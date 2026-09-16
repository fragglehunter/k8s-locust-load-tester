"""Load test for the CNCF OpenTelemetry Demo — the "Astronomy Shop".

Point `locust.targetHost` at the **frontend-proxy** Service on port **8080**, never at
`frontend` directly. `frontend-proxy` is the Envoy edge that fronts the whole demo, and
it routes `/images/` to the image provider and `/flagservice/` to flagd; only the
catch-all `/` prefix reaches Next.js. Aimed at `frontend` you would 404 every image.

    locust.targetHost: http://frontend-proxy:8080                          # same namespace
    locust.targetHost: http://frontend-proxy.otel-demo.svc.cluster.local:8080

**Namespace:** the upstream `opentelemetry-demo` chart sets no namespace of its own, so
the demo lands in whatever namespace Helm is pointed at — `default` unless you say
otherwise. The upstream docs use `otel-demo`, and so do this repo's example values, so
`helm install ... --namespace otel-demo` for both and the short name above resolves.

**A non-zero error rate is expected.** The demo exists to be broken: flagd ships sixteen
fault-injection flags (`paymentFailure`, `productCatalogFailure`, `adFailure`,
`paymentUnreachable`, `cartFailure`, `failedReadinessProbe`, ...) that turn healthy
routes into 5xx/422 on demand. They all default to *off*, so a clean install should sit
near 0% errors, but the moment anyone flips a flag in the `/feature` UI — which is the
entire point of the demo — this test will start reporting failures. That is the demo
working as designed, not a broken locustfile.

`catch_response` is used in exactly four places, and only where a non-2xx is the
*correct* answer rather than a fault:

  * `POST /api/checkout` — the `paymentFailure` flag makes the frontend return **422**
    `PAYMENT_FAILED`. Locust counts 422 as a failure by default, which would drown the
    run in red the instant that flag is on, so 422 is recorded as a success.
  * `DELETE /api/cart` — succeeds with **204**, and asserting the exact code catches a
    silent regression that a plain 2xx check would wave through.
  * the deliberate 404 probe — a 404 there means the error page rendered correctly.
  * the optional platform UIs — those subcharts may not be installed at all.

Injected **500s are deliberately left as failures**: an `adFailure` 500 on `/api/data`
is byte-for-byte identical to a genuinely broken ad service, and masking it would hide
real breakage. If a flag you turned on is the known cause, read the failures as expected.

Two things this test does *not* do, on purpose:

  * It never sends a wrong HTTP method to `/api/currency`, `/api/shipping` or
    `/api/cart`. Those three handlers `return res.status(405)` with no `.send()`, so the
    response is never terminated and the request hangs until the client times out,
    pinning a Locust connection open for nothing.
  * It never sets the `x-envoy-fault-delay-request` header. frontend-proxy enables the
    Envoy fault filter at 100%, so that header injects a real delay in milliseconds.

Only the ten real product IDs are used. An unknown ID returns gRPC `NotFound`, which the
frontend surfaces as a bare **500**, not a 404 — self-inflicted noise.
"""

import json
import random
import uuid
from urllib.parse import quote

from locust import HttpUser, between, task

# The ten rows seeded into catalog.products. Nothing else is a valid product ID.
PRODUCT_IDS = [
    "0PUK6V6EV0",
    "1YMWWN1N4O",
    "2ZYFJ3GM2N",
    "66VCHSJNUP",
    "6E92ZMYYFZ",
    "9SIQT8TOJO",
    "L9ECAV7KIM",
    "LS4PSXUNUM",
    "OLJCESPC7Z",
    "HQTGWGPNH4",
]

# Served by the image provider through Envoy's /images/ route, not by Next.js.
PRODUCT_PICTURES = [
    "NationalParkFoundationExplorascope.jpg",
    "StarsenseExplorer.jpg",
    "EclipsmartTravelRefractorTelescope.jpg",
    "LensCleaningKit.jpg",
    "RoofBinoculars.jpg",
    "SolarSystemColorImager.jpg",
    "RedFlashlight.jpg",
    "OpticalTubeAssembly.jpg",
    "SolarFilter.jpg",
    "TheCometBook.jpg",
]

# Ad context keys. None means "no contextKeys at all", which is a valid call that
# returns random ads — the upstream generator does the same thing.
AD_CONTEXT_KEYS = [
    "telescopes",
    "binoculars",
    "accessories",
    "assembly",
    "travel",
    "books",
    "flashlights",
    None,
]

# Everything the currency service will convert to, i.e. everything the switcher offers.
CURRENCY_CODES = [
    "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP",
    "HKD", "HRK", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN",
    "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "RUB", "SEK", "SGD", "THB",
    "TRY", "USD", "ZAR",
]

# The address the real cart page hard-codes into its shipping quote, so quotes here cost
# what they cost in the UI. It is also a US address, which keeps `intlShippingSlowdown`
# out of the picture unless you deliberately want it.
ADDRESS = {
    "streetAddress": "1600 Amphitheatre Parkway",
    "city": "Mountain View",
    "state": "CA",
    "country": "United States",
    "zipCode": "94043",
}

# The built-in Visa the payment service accepts. Any other number is declined and shows
# up as a 422 that the flags had nothing to do with.
CREDIT_CARD = {
    "creditCardNumber": "4432-8015-6152-0454",
    "creditCardExpirationMonth": 1,
    "creditCardExpirationYear": 2039,
    "creditCardCvv": 672,
}

EMAIL = "larry_sergei@example.com"


class AstronomyShopUser(HttpUser):
    # The upstream generator uses between(1, 10); this is a little busier so a five
    # minute run still covers every task at a sane user count.
    wait_time = between(1, 5)

    def on_start(self):
        # The browser mints one UUIDv4 in localStorage and uses it as both the cart's
        # userId and the sessionId query param, so one id here is the faithful thing.
        # It also keeps the valkey cart store from growing a key per request, which is
        # what a fresh id per add-to-cart would do — there is no TTL on those keys.
        self.session_id = str(uuid.uuid4())

        # Picking a currency per user *is* "set currency": the frontend keeps it in
        # localStorage and passes it as ?currencyCode= on every call. USD is the default
        # and short-circuits the currency RPC entirely, so a random pick out of 33 codes
        # means ~32 of 33 users actually exercise the currency service.
        self.currency = random.choice(CURRENCY_CODES)

        # The upstream generator gets this header for free from the OpenTelemetry
        # requests instrumentation. Stdlib-only, it has to be set by hand — without it
        # the frontend and the payment service never see the session, and nothing marks
        # this traffic as synthetic.
        self.client.headers["baggage"] = (
            f"session.id={self.session_id},synthetic_request=true"
        )

        # Mirror of the server-side cart, so shipping quotes and checkouts are asked
        # about items this user actually added.
        self.cart = []

        self.client.get("/", name="/")
        self.client.get("/api/currency", name="/api/currency")

    # -- browsing ---------------------------------------------------------------

    @task(10)
    def home_page(self):
        """Home page plus the XHRs and images a real browser fires behind it."""
        self.client.get("/", name="/")
        self.client.get(
            "/api/products",
            params={"currencyCode": self.currency},
            name="/api/products",
        )
        self.client.get("/images/Banner.png", name="/images/Banner.png")
        for picture in random.sample(PRODUCT_PICTURES, 3):
            self.client.get(
                f"/images/products/{picture}",
                name="/images/products/[picture]",
            )

    @task(14)
    def product_page(self):
        """Product detail page: the single busiest path in the demo."""
        product_id = random.choice(PRODUCT_IDS)
        self.client.get(
            f"/product/{product_id}",
            name="/product/[productId]",
        )
        self.client.get(
            f"/api/products/{product_id}",
            params={"currencyCode": self.currency},
            name="/api/products/[id]",
        )
        self.client.get(
            "/api/recommendations",
            params={
                "productIds": [product_id],
                "sessionId": self.session_id,
                "currencyCode": self.currency,
            },
            name="/api/recommendations",
        )
        self.client.get(
            "/api/data",
            params={"contextKeys": [random.choice(AD_CONTEXT_KEYS[:-1])]},
            name="/api/data",
        )
        self.client.get(
            f"/images/products/{random.choice(PRODUCT_PICTURES)}",
            name="/images/products/[picture]",
        )

    @task(3)
    def untargeted_ads(self):
        """/api/data with no contextKeys — a valid call that returns random ads."""
        context_key = random.choice(AD_CONTEXT_KEYS)
        params = {"contextKeys": [context_key]} if context_key else None
        # Note the missing trailing slash. The upstream generator calls /api/data/,
        # which is a 308 to /api/data and so costs two round trips per ad.
        self.client.get("/api/data", params=params, name="/api/data")

    @task(3)
    def change_currency(self):
        """What the currency switcher does: refetch the list, then reprice everything."""
        self.client.get("/api/currency", name="/api/currency")
        self.currency = random.choice(CURRENCY_CODES)
        self.client.get(
            "/api/products",
            params={"currencyCode": self.currency},
            name="/api/products",
        )
        self.client.get(
            "/api/cart",
            params={"sessionId": self.session_id, "currencyCode": self.currency},
            name="/api/cart",
        )

    @task(2)
    def static_assets(self):
        """Assets Next.js serves out of public/."""
        self.client.get("/favicon.ico", name="/favicon.ico")
        self.client.get("/icons/Cart.svg", name="/icons/[icon].svg")

    @task(1)
    def not_found(self):
        """Unmatched path, which renders the 404 page. A 404 here is the pass."""
        with self.client.get(
            "/does-not-exist",
            name="/[404]",
            catch_response=True,
        ) as response:
            if response.status_code == 404:
                response.success()
            else:
                response.failure(f"expected 404 from the error page, got {response.status_code}")

    # -- cart -------------------------------------------------------------------

    @task(5)
    def add_to_cart(self):
        product_id = random.choice(PRODUCT_IDS)
        quantity = random.choice([1, 2, 3, 4, 5, 10])
        # The UI always has the product loaded before the button exists.
        self.client.get(
            f"/api/products/{product_id}",
            params={"currencyCode": self.currency},
            name="/api/products/[id]",
        )
        self.client.post(
            "/api/cart",
            params={"currencyCode": self.currency},
            json={
                "userId": self.session_id,
                "item": {"productId": product_id, "quantity": quantity},
            },
            name="/api/cart",
        )
        self.cart.append({"productId": product_id, "quantity": quantity})

    @task(6)
    def cart_page(self):
        """Cart page and everything it loads, including the shipping quote."""
        self.client.get("/cart", name="/cart")
        self.client.get(
            "/api/cart",
            params={"sessionId": self.session_id, "currencyCode": self.currency},
            name="/api/cart",
        )
        self.shipping_quote()
        self.client.get(
            "/api/recommendations",
            params={"sessionId": self.session_id, "currencyCode": self.currency},
            name="/api/recommendations",
        )
        self.client.get(
            "/api/data",
            params={"contextKeys": [random.choice(AD_CONTEXT_KEYS[:-1])]},
            name="/api/data",
        )

    @task(1)
    def empty_cart(self):
        """DELETE /api/cart. Needs a JSON body and answers 204, not 200."""
        with self.client.delete(
            "/api/cart",
            json={"userId": self.session_id},
            name="/api/cart",
            catch_response=True,
        ) as response:
            if response.status_code == 204:
                response.success()
            else:
                response.failure(f"expected 204 from empty cart, got {response.status_code}")
        self.cart = []

    # -- checkout ---------------------------------------------------------------

    @task(2)
    def checkout(self):
        """The whole funnel: browse -> detail -> add -> cart -> order -> confirmation."""
        self.client.get("/", name="/")
        self.client.get(
            "/api/products",
            params={"currencyCode": self.currency},
            name="/api/products",
        )

        for _ in range(random.choice([1, 2, 3])):
            self.add_to_cart()

        self.client.get("/cart", name="/cart")
        self.client.get(
            "/api/cart",
            params={"sessionId": self.session_id, "currencyCode": self.currency},
            name="/api/cart",
        )
        self.shipping_quote()

        order = {
            "userId": self.session_id,
            "email": EMAIL,
            "address": ADDRESS,
            "userCurrency": self.currency,
            "creditCard": CREDIT_CARD,
        }
        with self.client.post(
            "/api/checkout",
            params={"currencyCode": self.currency},
            json=order,
            name="/api/checkout",
            catch_response=True,
        ) as response:
            if response.status_code == 422:
                # paymentFailure is on. The decline is the flag doing its job.
                response.success()
                return
            if response.status_code != 200:
                response.failure(f"HTTP {response.status_code}")
                return
            response.success()
            body = response.text

        # Checkout empties the cart server side, so drop ours too.
        self.cart = []

        try:
            order_id = json.loads(body)["orderId"]
        except (ValueError, KeyError, TypeError):
            return

        # The confirmation page JSON.parse()s the whole order out of ?order=, and 500s
        # without it, so the response body has to be handed straight back url-encoded.
        self.client.get(
            f"/cart/checkout/{order_id}?order={quote(body, safe='')}",
            name="/cart/checkout/[orderId]",
        )

    # -- helpers ----------------------------------------------------------------

    def shipping_quote(self):
        """GET /api/shipping. itemList and address go over as JSON *strings*, and the
        handler JSON.parse()s them unguarded — a malformed value is a 500 of our own
        making. An empty cart still gets quoted so the route keeps coverage; that is
        what the page would ask for as soon as one item lands in it."""
        item_list = self.cart or [{"productId": random.choice(PRODUCT_IDS), "quantity": 1}]
        self.client.get(
            "/api/shipping",
            params={
                "itemList": json.dumps(item_list),
                "address": json.dumps(ADDRESS),
                "currencyCode": self.currency,
            },
            name="/api/shipping",
        )


class PlatformUIUser(HttpUser):
    """Optional: the sibling UIs frontend-proxy also fronts.

    Jaeger, Grafana and the rest are separate subcharts that may not be installed, and
    answer 503 or 308 when they are not, so every response that came back at all counts
    as a success here. Inert at weight 0 — raise it if you want these loaded too.
    """

    weight = 0
    wait_time = between(2, 10)

    @task
    def platform_ui(self):
        path = random.choice(
            ["/loadgen/", "/feature", "/jaeger/", "/grafana/", "/telemetry/", "/profiles/", "/chatbot/"]
        )
        with self.client.get(path, name=path, catch_response=True) as response:
            response.success()

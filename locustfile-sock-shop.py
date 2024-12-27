import base64

import requests
requests.packages.urllib3.disable_warnings() 

from locust import HttpUser, TaskSet, task
from random import randint, choice
base64.encodestring = base64.encodebytes

class WebTasks(TaskSet):

    @task
    def load(self):
        self.client.verify = False
        base64string = base64.encodebytes(('%s:%s' % ('user', 'password')).encode('utf8')).decode('utf8').replace('\n', '')

        catalogue = self.client.get("/catalogue").json()
        category_item = choice(catalogue)
        item_id = category_item["id"]

        self.client.get("/")
        self.client.get("/login", headers={"Authorization":"Basic %s" % base64string})
        self.client.get("/category.html")
        self.client.get("/detail.html?id={}".format(item_id))
        self.client.delete("/cart")
        self.client.post("/cart", json={"id": item_id, "quantity": 1})
        self.client.get("/basket.html")
        self.client.post("/orders")


class Web(HttpUser):
    tasks = [WebTasks]
    min_wait = 0
    max_wait = 0

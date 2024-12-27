# Locust Load / Integration Tests

These tests simulate actual end user usage of the application. They are used to validate the overall functionality and can also be used to put simulated load on the system. The tests are written using [locust.io](http://locust.io)

## Building the Container

We want to make this container generic enough so we can just pass out Locust test to it, instead of building in a fixed test. This allows for the most flexibility when using Locust.

Build the container:

```bash
docker build -t locust-load-tester:v1 .
```

Push to your repo:

```bash
docker push locust-load-tester:v1
```

You now have an image to use for locust test as needed. 

## Running in Kubernetes Cluster

Once you have the image built and pushed to a image repository, you can use simple manifest to run the locust test:

### Sample Deployment Manifest

First configure the ConfigMap:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dotnet-8-locustfile-cm
data:
  hatchrate: "5"
  run-time: "5m"
  hostname: "http://dotnet-8-app:5000"
  locustfile.py: |
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
    
            self.client.get("/test")
            self.client.get("/health")
    
    class Web(HttpUser):
        tasks = [WebTasks]
        min_wait = 0
        max_wait = 0
```

Deploy the test against service:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dotnet-8-locust-load-test
  labels:
    name: dotnet-8-locust-load-test
spec:
  replicas: 1
  selector:
    matchLabels:
      name: dotnet-8-locust-load-test
  template:
    metadata:
      labels:
        name: dotnet-8-locust-load-test
    spec:
      containers:
      - name: locust-load-test
        image: locust-load-test:v1
        command: ["/bin/sh"]
        args: ["-c", "while true; do locust --host $HOSTNAME -f /config/locustfile.py --spawn-rate $HATCH_RATE --run-time $RUN_TIME --headless; done"]
        env:
        - name: MY_ENV_VAR
          value: "some_value"
        - name: HOSTNAME
          valueFrom:
            configMapKeyRef:
              name: dotnet-8-locustfile-cm
              key: hostname
        - name: HATCH_RATE
          valueFrom:
            configMapKeyRef:
              name: dotnet-8-locustfile-cm
              key: hatchrate
        - name: RUN_TIME
          valueFrom:
            configMapKeyRef:
              name: dotnet-8-locustfile-cm
              key: run-time
        volumeMounts:
        - name: dotnet-8-locustfile-cm
          mountPath: /config/locustfile.py
      volumes:
      - name: dotnet-8-locustfile-cm
        configMap:
          name: dotnet-8-locustfile-cm
```

You can update the `locustfile.py` and other parameters in the ConfigMap for your test as needed.

## Running locally

You can use the script to help run the test locally (it hasnt been touched or really updated in years though) or you can build the container and run in a Kubernetes cluster (preferred).

### Requirements 
* locust `pip install locust`

`./runLocust.sh -h [host] -c [number of clients] -r [number of requests]`

### Parameters
* `[host]` - The hostname (and port if applicable) where the application is exposed. (Required)
* `[number of clients]` - The nuber of concurrent end users to simulate. (Optional: Default is 2)
* `[number of requests]` - The total number of requests to run before terminating the tests. (Optional: Default is 10)


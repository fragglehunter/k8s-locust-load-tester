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
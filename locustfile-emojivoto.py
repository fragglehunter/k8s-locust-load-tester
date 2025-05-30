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

        self.client.get("/api/leaderboard")
        self.client.get("/api/list")
        self.client.get("/api/vote?choice=:joy:")
        self.client.get("/api/vote?choice=:sunglasses:")
        self.client.get("/api/vote?choice=:doughnut:")
        self.client.get("/api/vote?choice=:stuck_out_tongue_winking_eye:")
        self.client.get("/api/vote?choice=:money_mouth_face:")
        self.client.get("/api/vote?choice=:flushed:")
        self.client.get("/api/vote?choice=:mask:")
        self.client.get("/api/vote?choice=:nerd_face:")
        self.client.get("/api/vote?choice=:ghost:")
        self.client.get("/api/vote?choice=:skull_and_crossbones:")
        self.client.get("/api/vote?choice=:heart_eyes_cat:")
        self.client.get("/api/vote?choice=:hear_no_evil:")
        self.client.get("/api/vote?choice=:see_no_evil:")
        self.client.get("/api/vote?choice=:speak_no_evil:")
        self.client.get("/api/vote?choice=:boy:")
        self.client.get("/api/vote?choice=:girl:")
        self.client.get("/api/vote?choice=:man:")
        self.client.get("/api/vote?choice=:woman:")
        self.client.get("/api/vote?choice=:older_man:")
        self.client.get("/api/vote?choice=:policeman:")
        self.client.get("/api/vote?choice=:guardsman:")
        self.client.get("/api/vote?choice=:construction_worker_man:")
        self.client.get("/api/vote?choice=:prince:")
        self.client.get("/api/vote?choice=:princess:")
        self.client.get("/api/vote?choice=:man_in_tuxedo:")
        self.client.get("/api/vote?choice=:bride_with_veil:")
        self.client.get("/api/vote?choice=:mrs_claus:")
        self.client.get("/api/vote?choice=:santa:")
        self.client.get("/api/vote?choice=:turkey:")
        self.client.get("/api/vote?choice=:rabbit:")
        self.client.get("/api/vote?choice=:no_good_woman:")
        self.client.get("/api/vote?choice=:ok_woman:")
        self.client.get("/api/vote?choice=:raising_hand_woman:")
        self.client.get("/api/vote?choice=:bowing_man:")
        self.client.get("/api/vote?choice=:man_facepalming:")
        self.client.get("/api/vote?choice=:woman_shrugging:")
        self.client.get("/api/vote?choice=:massage_woman:")
        self.client.get("/api/vote?choice=:walking_man:")
        self.client.get("/api/vote?choice=:running_man:")
        self.client.get("/api/vote?choice=:dancer:")
        self.client.get("/api/vote?choice=:man_dancing:")
        self.client.get("/api/vote?choice=:dancing_women:")
        self.client.get("/api/vote?choice=:rainbow:")
        self.client.get("/api/vote?choice=:skier:")
        self.client.get("/api/vote?choice=:golfing_man:")
        self.client.get("/api/vote?choice=:surfing_man:")
        self.client.get("/api/vote?choice=:basketball_man:")
        self.client.get("/api/vote?choice=:biking_man:")
        self.client.get("/api/vote?choice=:point_up_2:")
        self.client.get("/api/vote?choice=:vulcan_salute:")
        self.client.get("/api/vote?choice=:metal:")
        self.client.get("/api/vote?choice=:call_me_hand:")
        self.client.get("/api/vote?choice=:thumbsup:")
        self.client.get("/api/vote?choice=:wave:")
        self.client.get("/api/vote?choice=:clap:")
        self.client.get("/api/vote?choice=:raised_hands:")
        self.client.get("/api/vote?choice=:pray:")
        self.client.get("/api/vote?choice=:dog:")
        self.client.get("/api/vote?choice=:cat2:")
        self.client.get("/api/vote?choice=:pig:")
        self.client.get("/api/vote?choice=:hatching_chick:")
        self.client.get("/api/vote?choice=:snail:")
        self.client.get("/api/vote?choice=:bacon:")
        self.client.get("/api/vote?choice=:pizza:")
        self.client.get("/api/vote?choice=:taco:")
        self.client.get("/api/vote?choice=:burrito:")
        self.client.get("/api/vote?choice=:ramen:")
        self.client.get("/api/vote?choice=:champagne:")
        self.client.get("/api/vote?choice=:tropical_drink:")
        self.client.get("/api/vote?choice=:beer:")
        self.client.get("/api/vote?choice=:tumbler_glass:")
        self.client.get("/api/vote?choice=:world_map:")
        self.client.get("/api/vote?choice=:beach_umbrella:")
        self.client.get("/api/vote?choice=:mountain_snow:")
        self.client.get("/api/vote?choice=:camping:")
        self.client.get("/api/vote?choice=:steam_locomotive:")
        self.client.get("/api/vote?choice=:flight_departure:")
        self.client.get("/api/vote?choice=:rocket:")
        self.client.get("/api/vote?choice=:star2:")
        self.client.get("/api/vote?choice=:sun_behind_small_cloud:")
        self.client.get("/api/vote?choice=:cloud_with_rain:")
        self.client.get("/api/vote?choice=:fire:")
        self.client.get("/api/vote?choice=:jack_o_lantern:")
        self.client.get("/api/vote?choice=:balloon:")
        self.client.get("/api/vote?choice=:tada:")
        self.client.get("/api/vote?choice=:trophy:")
        self.client.get("/api/vote?choice=:iphone:")
        self.client.get("/api/vote?choice=:pager:")
        self.client.get("/api/vote?choice=:fax:")
        self.client.get("/api/vote?choice=:bulb:")
        self.client.get("/api/vote?choice=:money_with_wings:")
        self.client.get("/api/vote?choice=:crystal_ball:")
        self.client.get("/api/vote?choice=:underage:")
        self.client.get("/api/vote?choice=:interrobang:")
        self.client.get("/api/vote?choice=:100:")
        self.client.get("/api/vote?choice=:checkered_flag:")
        self.client.get("/api/vote?choice=:crossed_swords:")
        self.client.get("/api/vote?choice=:floppy_disk:")
        self.client.get("/api/vote?choice=:poop:")

class Web(HttpUser):
    tasks = [WebTasks]
    min_wait = 0
    max_wait = 0
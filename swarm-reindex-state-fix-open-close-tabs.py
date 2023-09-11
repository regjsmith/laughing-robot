#!/usr/bin/python3

import requests
from requests.auth import HTTPBasicAuth
from requests.exceptions import HTTPError

# Hex encoded review states
states = {
    "approved": "617070726F766564",
    "needsReview": "6E65656473526576696577",
    "needsRevision": "6E656564735265766973696F6E",
    "archived": "6172636869766564"
}

# Perforce credentials and api endpoint to fetch list of reviews dislayed on open tab on review page
user="reg"
password="reg"
url='https://reg-swarm-vb/api/v9/reviews?state[]=needsReview&state[]=needsRevision&state[]=approved:isPending&fields=id,state,pending';

# Execute api call
response=requests.get(url, auth = HTTPBasicAuth(user, password))

if response.status_code == 200: 
    reviews=response.json() 
    for review in reviews["reviews"]:
        id=review["id"]
        pending=review["pending"]
        state=review["state"]
        reviewKeyname="swarm-review-" + hex(4294967295 - id)[3:]
        print("echo " , states[state] , " |p4 index -a 1308 " , reviewKeyname)



#!/usr/bin/bash

# Archive all reviews for deleted users
# Assumes there is a spec depot to find all the users spec deleted at head, and the jq json parsing uility
# is installed https://jqlang.github.io/jq/

# Enviroment specific variables for running curl commands, change to suit
curlUser="reg"
curlTicket="F281A10F170FF3632B9E0EF2085EBBBC"
swarmURL="https://reg-swarm-vb"

for deletedUser in $(p4 fstat -F headAction=delete -T depotFile //spec/user/... | cut -d/ -f5 | cut -d. -f1)
do
    echo \#Processing reviews for deleted user $deletedUser
    
    # List reviews authored by the deleted user that are not already archived
    for reviewID in $(curl -sq -u $curlUser:$curlTicket "$swarmURL/api/v9/reviews?author[]=$deletedUser&fields=id,author,state" | jq '.reviews[] | select(.state!="archived") | .id')
    do
        # Print curl command to transition to "archived" to teminal. To execute pipe to shell "./deleted-users-archive-reviews.sh |sh"
        echo curl -sq -u $curlUser:$curlTicket -X PATCH -d "state=archived" "$swarmURL/api/v9/reviews/$reviewID/state/" 
    done
done

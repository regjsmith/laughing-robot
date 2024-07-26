#!/usr/bin/bash

cat << COMMENT
Is there a reliable way to know when a review is finished being committed and all the updates to the review key are done 
(in particular the commit credit answer is finalised to author or submitter which happens after the submit itself has 
happened and a "change -f" is performed to update the change owner from the swarm admin that is initially the change owner).

We can do it if you're ok with looking at review keys rather than the actual submitted changes.
Looking at the review key avoids having to wait an indeterminate period on a change form which we are unsure of whether the 
owner has been finalised to the author or submitter (depending on 'commit_credit_author ' ) which occurs after the submit itself 
has happened and a "change -f" is performed to update the change owner from the swarm admin that is initially the change owner.
Following the swarm log, looking at the "p4 counter -u" commands to follow the stages of the the review key being updated during a commit,
we can inspect the review key to get the answer of who committed a change (assuming  'commit_credit_author ' is false so Swarm 
records the actual committer rather than the author).

1). Assuming we are starting with a particular change that has just been committed, first get the review change using the api to get the review id the change is associated with:
curl -u "user:password" "http://<swarm-url>/api/v9/reviews?change=<submitted CL>"

2). Get the review key using the review id we just got above:

curl -u "user:password" "http://<swarm-url>/api/v9/reviews/<REVIEWID>"


3). Looking at the review key, we can assume a commit has completed and the review key is up to date if the following conditions are all met :
- The "commitStatus" array is empty "[]" (this is populated on the fly as a commit proceeds but gets cleared when commit is completed)

- The "commits" array  contains the change that was committed

    "commits": [
        16977
    ],

- The "versions" array is populated with a block for the committed change we are checking (it contains the final commit credit user for that change which is what we are actually interested in, this doesn't go through the dance of the change owner being updated after the submit)

    "versions": [
        {
            "difference": 1,
            "stream": null,
            "streamSpecDifference": 0,
            "change": 16941,
            "user": "A",
            "time": 1718794044,
            "pending": true,
            "addChangeMode": "replace",
            "testRuns": [
                416,
                417
            ]
        },
        {
            "change": 16977,   <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< committed change
            "user": "A",       <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< commit credit user
            "time": 1721909071,
            "pending": false,  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< pending is false
            "difference": 2,
            "addChangeMode": "replace",
            "stream": null,
            "testRuns": [
                448,
                449
            ]
        }
    ],

COMMENT

# Combining all the above:

CHANGE=$1
USER="reg"
TICKET="2B48FE0F7FE451B999EDFB3BE82CF810"
SwarmURL="https://reg-swarm-vb"

REVIEWID=$(curl -s -u $USER:$TICKET $SwarmURL/api/v9/reviews?change=$CHANGE | jq '.reviews[].id') 

submitCreditUser=$(curl -s -u $USER:$TICKET $SwarmURL/api/v9/reviews/$REVIEWID | jq -r --argjson c "{\"c\": $CHANGE}" '.review | select(.commits[] == $c.c) | .versions[] | select(.pending==false and .change==$c.c) | .user')

echo $CHANGE associated with review $REVIEWID, submit credit user $submitCreditUser

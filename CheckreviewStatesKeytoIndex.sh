#!/usr/bin/bash

#############################################
# Site specific values, change as appropriate
#############################################
# Swarm url and curl user/password
swarmUrl="https://reg-swarm-vb"
curlUser="reg"
curlPass="reg"
###########################################

<<'###COMMENTS###'

https://github.com/regjsmith/laughing-robot/blob/master/CheckreviewStatesKeytoIndex.sh

Notes: Cross checking review state between review key (assume  this is the actual state) and the index, and if they differ then issue corrective command to fix the index.

1. NOT impemented: For efficiency only run search command once per state (needsReview, needsRevision, approved, archived, approved:iSPending etc.) and out in indivdual files
and put in file

2. NOT impemented: Loop over list of all review keys and extract state, and grep review key from state index files generated in 1. If found in same state then the index and key agree

3. If state is different between key and index, generate command to delete bad entry and to insert new entry with matching state to the key. 

This is a variation on Based on swarm-reindex-state-fix-open-close-tabs.sh, this one checks all review states between the key and the index.

Based on swarm-reindex-state-fix-open-close-tabs.sh
https://github.com/regjsmith/laughing-robot/blame/c67c3e3b5c827682a1c93c61e90f44b87cea32c8/swarm-reindex-state-fix-open-close-tabs.sh

Inclusing comments for that script as there is a lot of explaination pertinent to this script.

Script to cross check review state information held in the index against the state information in the review key.
They should agree but if not then reviews can appear in the wrong open or closed tab in the reviews list (either in both or the wrong one)
If any discrepancies are found it will print out an p4 index command to attempt to correct the index (the assumption is the key is correct)

There are 2 main points to mention regarding usage:

1. The machine where it is executed will need the "jq" command line processor installed.

   This is open source and can be obtained from  https://jqlang.github.io/jq/ ;

   The script will check for it and will not continue if it cannot be found.

2. There is a small section at the top where the user, password and url will need to be edited for curl:

   #############################################
   # Site specific values, change as appropriate
   #############################################
   # Swarm url and curl user/password
   swarmUrl="https://reg-swarm-vb"
   curlUser="reg"
   curlPass="reg"
   ###########################################


   All the output apart from the index commands is preceded with a #.
   It does not run any of the "p4 index" commands, it prints them to the terminal.

   ./swarm-reindex-state-fix-open-close-tabs.sh

   # Generating open-reviews.json using api call
   # swarm-review-ffffbf1a id 16613 found in index consistent with open
   # swarm-review-ffffbf1a id 16613 found in index consistent with closed
   # >>>> WARNING: Review  swarm-review-ffffbf1a index has both open and closed states in the index!!
   # Key has state=archived, but index has needsRevision
   # The following commands will delete the index entry
   echo 1308=6e656564735265766973696f6e | p4 index -a 1308 -d swarm-review-ffffbf1a
   # swarm-review-ffffbf20 id 16607 found in index consistent with open
   # swarm-review-ffffbf22 id 16605 found in index consistent with open
   ...and so on..

###############################################################################
General notes regarding indexing
###############################################################################

- Rules for which states will filter to open and closed tabs:

  Opened reviews state == (needsReview || needsRevision || approved:isPending)
  Closed reviews state == (approved:notPending || rejected || archived)

- Hex encodings and index attributes to use in p4 search queries:

  approved              1308=617070726F766564
  needsReview           1308=6E65656473526576696577
  needsRevision         1308=6e656564735265766973696f6e
  archived              1308=6172636869766564
  rejected              1308=72656a6563746564

  approved:isPending  (1308=617070726F766564 1310=31)
  approved:notPending (1308=617070726F766564 1310=30)

- To find reviews that should appear as closed according to the index, match the following states:
  (approved:notPending || rejected || archived)

  ..and reviews that should appear on the open tab according to the index
  (needsReview || needsRevision || approved:isPending)


- Specific p4 search queries to filter reviews for either the open or closed tab.

 Open
  needsReview | needsRevision | approved:isPending
  search (1308=6E65656473526576696577 | 1308=6E656564735265766973696F6E | (1308=617070726F766564 1310=31))

 Closed
  rejected | archived | approved:notPending
  search (1308=72656a6563746564 | 1308=6172636869766564 | (1308=617070726F766564 1310=30))

  (they should NOT overlap, but that's the point of this script, to find ones that do
  and are appearing in the wrong tab (either in both or the wrong one)
###############################################################################

###COMMENTS###


# Prerequisite is the jq json command line processor
# https://jqlang.github.io/jq/
$(which jq 2>&1>/dev/null)
if [[ $? > 0 ]] ;then
        echo "Please install [jq](https://jqlang.github.io/jq/) first."
        exit 1
fi

# Speed up grep as per
# http://www.inmotionhosting.com/support/website/ssh/speed-up-grep-searches-with-lc-all
GREP(){ LC_ALL=C fgrep "$@";}

# Add text colours to make it easier to read the output.
CLEAR=$'\e[0m'
MESSAGE=$'\033[3m'
INFO=$'\e[32m'
WARN=$'\e[31m'
ERROR=$'\e[41m'
PROMPT=$'\e[44m'

echoinfo()    { echo "${INFO}${1}${CLEAR}"   ;}
echomessage() { echo "${MESSAGE}${1}${CLEAR}";}
echowarn()    { echo "${WARN}${1}${CLEAR}"   ;}
echoerror()   { echo "${ERROR}${1}${CLEAR}"  ;}

# Set p4 search ixtext attributes + hex encodings for review states as variables
# for clarity when defining search queries later
approved='1308=617070726F766564'
needsReview='1308=6e65656473526576696577'
needsRevision='1308=6e656564735265766973696f6e'
archived='1308=6172636869766564'
rejected='1308=72656a6563746564'
pending='1310=31'
approved_isPending='(1308=617070726F766564 1310=31)'
approved_notPending=' (1308=617070726F766564 1310=30)'
no='30'
yes='31'


###############################################################################
# Let the processing begin!
###############################################################################

###############################################################################
# Loop over list of reviews from the index, one loop per state
###############################################################################
for checkState in approved needsReview needsRevision archived rejected
                  				  
do
for reviewKeyName in $(p4 search "${!checkState}")
do
    #echo "Processing review $reviewKeyName"
	
	# calculate review id from key name
    reviewHexKeyName=$(echo $reviewKeyName | cut -c14-21)
    reviewID=$(printf "%d" $((0xffffffff - 0x$reviewHexKeyName)))
    
	reviewKeyState=$(p4 keys -e "$reviewKeyName" | cut -d= -f2- | jq -r '.state')
	
	if [[ -z $reviewKeyState ]]
	then
	    echowarn "# No state found for key $reviewKeyName (review $reviewID), moving on to next review"
		continue
	fi
	
	#echo Index state for $reviewKeyName is needsReview
	#echo Key   state for $reviewKeyName is $reviewKeyState
	
	if [[ "$reviewKeyState" != "$checkState" ]]; then
        echowarn "# Key for review $reviewKeyName (review $reviewID) has state=$reviewKeyState, but index has $checkState"

        # Print p4 index command to delete the index entry
        echomessage "# The following command will delete the index entry"
        echomessage "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"
	
	    # Print p4 index command to correct the index entry
        echomessage "# The following commands will correct the index entry"
        echomessage "echo ${!reviewKeyState} | p4 index -a 1308 $reviewKeyName"
    else
	    echoinfo "# OK, review key $reviewKeyName (review $reviewID) state $reviewKeyState matches in key and index"
		
	fi
done
done


exit

# Looping over list of reviews from p4 keys, extracting the review key name and state from the key json value 
#Can store the output list of the key and value in an array directly:

#readarray -t reviewKeyValueArray < <(p4 keys -e "swarm-review-*" -m1 |tee >(cut -d= -f2-| jq -r '.state') | cut -d= -f1 )

#To refer to each element:

#printf '%s\n' "${reviewKeyValueArray[0]}"
#swarm-review-ffffbd7e 

printf '%s\n' "${reviewKeyValueArray[1]}"
needsReview###################################################################
# Fetch list of reviews from the index that have state/pending/approve:commit
# values consistent matching the rules for open
###################################################################

# Closed = rejected | archived | approved:notPending

#p4 search "($rejected | $archived | $approved_notPending)" > reviews-closed-per-index.txt


# Find reviews that appear in both open and closed lists
# (shouldn't happen, this is what we are wanting to find and correct)

#comm -12 reviews-open-per-index.txt reviews-closed-per-index.txt > reviews-open-and-closed-per-index.txt

# Inconsistencies found (reviews matching rules for both open and closed in index)
if [[ -s reviews-open-and-closed-per-index.txt ]] ; then

        echowarn ""
        echowarn "# The following reviews appear in the index with both open and closed attributes"
        echowarn "$(cat reviews-open-and-closed-per-index.txt)"
        echowarn ""

        # Now need to find out which of the index entries is inconsistent with key state
        # (initial compound search is probably better for overall efficiency if not many reviews inconsistent)

        # Loop over each review in reviews-open-and-closed-per-index.txt

        while read -r reviewKeyName || [[ -n $reviewKeyName ]]; do


                # calculate review id from key name
                reviewHexKeyName=$(echo $reviewKeyName | cut -c14-21)
                reviewID=$(printf "%d" $((0xffffffff - 0x$reviewHexKeyName)))
                echo ""
                echomessage "# Processing review $reviewID $reviewKeyName"

                # Grab review key directly using p4 key command
                read -r reviewKeyState reviewKeyPending<<<"$(p4 -ztag -F "%value%" keys -e swarm-review-ffffbf1a | jq -r '[.state,.pending] | join(" ")')"

                echo "# DEBUG reviewKeyState $reviewKeyState reviewKeyPending $reviewKeyPending"


                # Output example:
                # archived
                # 0
                # Appearing on open tab, so is one of
                # (needsReview || needsRevision || approved:isPending)

                #Check if review is in index as needsReview


                if [[ $(p4 search "$needsReview" | GREP $reviewKeyName) ]] ; then
                        echowarn "# Key for review $reviewId $reviewKeyName has state=$reviewKeyState, but index has needsReview"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following command will delete the index entry"
                        echomessage "echo $needsReview | p4 index -a 1308 -d $reviewKeyName"

                fi

                #Check if review is in index as needsRevision

                if [[ $(p4 search "$needsRevision" | GREP $reviewKeyName) ]] ; then
                        echowarn "# Key for review $reviewID $reviewKeyName has state=$reviewKeyState, but index has needsRevision"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following commands will delete the index entry"
                        echomessage "echo $needsRevision | p4 index -a 1308 -d $reviewKeyName"
                fi

                #Check if review is in index as approved:isPending

                if [[ $(p4 search "($approved_isPending)" | GREP $reviewKeyName) ]] ; then
                        echowarn "# Key for review $reviewID $reviewKeyName has pending=$reviewKeyPending, but index has approved:isPending"

                        # Print p4 index command to delete and correct the index entry
                        echomessage "# The following commands will correct the index entry"
                        echomessage "echo $yes | p4 index -a 1310 -d $reviewKeyName"
                        echomessage "echo $no | p4 index -a 1310 $reviewKeyName"
                fi
        done <reviews-open-and-closed-per-index.txt
else
        echomessage "No inconsistent review states found for open/closed in index"
fi

exit

#Review $keyID $keyReviewName index has both open and closed states in the index!!"

                # Now need to find out which of the index entries is inconsistent with key state
                # (initial compound search is probably better for overall efficiency if not many reviews inconsistent)

                # Appearing on open tab, so is one of
                # (needsReview || needsRevision || approved:isPending)

                #Check if review is in index as needsReview

                if [[ $(p4 search "$needsReview" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has state=$keyState, but index has needsReview"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following command will delete the index entry"
                        echomessage "echo $needsReview | p4 index -a 1308 -d $keyReviewName"

                fi

                #Check if review is in index as needsRevision

                if [[ $(p4 search "$needsRevision" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has state=$keyState, but index has needsRevision"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following commands will delete the index entry"
                        echomessage "echo $needsRevision | p4 index -a 1308 -d $keyReviewName"
                fi

                #Check if review is in index as approved:isPending

                if [[ $(p4 search "($approved_isPending)" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has pending=$keyPending, but index has approved:isPending"

                        # Print p4 index command to delete and correct the index entry
                        echomessage "# The following commands will correct the index entry"
                        echomessage "echo $yes | p4 index -a 1310 -d $keyReviewName"
                        echomessage "echo $no | p4 index -a 1310 $keyReviewName"
                fi
        fi

# ---------------------------------------------------------------------------#

# Fetch list of open reviews into file via api call (it gets this from the index)
# if not already created. Could check every review but probably faster if we know
# we are wanting to deal with reviews that are appearing unexpectedly on the open tab

if [[ ! -f open-reviews.json ]] ; then

        echoinfo "# Generating open-reviews.json using api call"
        curl -s -k -u ${curlUser}:${curlPass} "$swarmUrl/api/v9/reviews?state[]=needsReview&state[]=needsRevision&state[]=approved:isPending&fields=id,state,pending" > open-reviews.json
else
        echoinfo "# Found existing open-reviews.json, will use that"
fi

# Read each line of json (this is where we use jq for faster extraction of json fields)
cat open-reviews.json | jq -r ".reviews[] |.id,.state,.pending" | paste - - - | while read line
do
        # Extract and assign variables from $line which has "id state pending"
        read -r keyId keyState keyPending <<<"$(echo $line)"

        keyReviewName=$(printf "swarm-review-%08x\n" $((0xffffffff - $keyId)))

        # Reset boolean variables recording whether review matches open/closed rules
        unset indexStateOpen
        unset indexStateClosed


        ###################################################################
        # Does the review appear in the index matching the rules for open
        ###################################################################

        # Open = needsReview | needsRevision | approved:isPending

        if [[ $(p4 search "($needsReview | $needsRevision | $approved_isPending)" | GREP $keyReviewName) ]] ;then
                echoinfo "# $keyReviewName id $keyId found in index consistent with open"
                indexStateOpen=true
        fi

        #####################################################################
        # Does the review appear in the index matching the rules for closed
        #####################################################################

        # Closed = rejected | archived | approved:notPending

        if [[ $(p4 search "($rejected | $archived | $approved_notPending)" | GREP $keyReviewName) ]] ; then
                echoinfo "# $keyReviewName id $keyId found in index consistent with closed"
                indexStateClosed=true
        fi

        ###################################################################
        # Inconsistent state found
        ###################################################################
        if [[ $indexStateOpen && $indexStateClosed ]] ; then
                echowarn "# >>>> WARNING: Review $keyID $keyReviewName index has both open and closed states in the index!!"

                # Now need to find out which of the index entries is inconsistent with key state
                # (initial compound search is probably better for overall efficiency if not many reviews inconsistent)

                # Appearing on open tab, so is one of
                # (needsReview || needsRevision || approved:isPending)

                #Check if review is in index as needsReview

                if [[ $(p4 search "$needsReview" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has state=$keyState, but index has needsReview"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following command will delete the index entry"
                        echomessage "echo $needsReview | p4 index -a 1308 -d $keyReviewName"

                fi

                #Check if review is in index as needsRevision

                if [[ $(p4 search "$needsRevision" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has state=$keyState, but index has needsRevision"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following commands will delete the index entry"
                        echomessage "echo $needsRevision | p4 index -a 1308 -d $keyReviewName"
                fi

                #Check if review is in index as approved:isPending

                if [[ $(p4 search "($approved_isPending)" | GREP $keyReviewName) ]] ; then
                        echowarn "# Key has pending=$keyPending, but index has approved:isPending"

                        # Print p4 index command to delete and correct the index entry
                        echomessage "# The following commands will correct the index entry"
                        echomessage "echo $yes | p4 index -a 1310 -d $keyReviewName"
                        echomessage "echo $no | p4 index -a 1310 $keyReviewName"
                fi
        fi
done

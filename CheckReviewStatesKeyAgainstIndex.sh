#!/usr/bin/bash

# Reg Smith


<<'###COMMENTS###'

Notes: Cross checking review state between review key (assume key has the actual state) and the index, and if they differ then issue corrective command to fix the index.

If state is different between key and index, it will generate the commands command to delete index entry and to insert new entry with matching state to the key.

Prequesites:

1. The machine where it is executed will need the "jq" command line processor installed.

This is open source and can be obtained from  https://jqlang.github.io/jq/ ;

The script will check for it and will not continue if it cannot be found.

2. It is assumed the p4 command line tool is available and the P4USER/P4PASSWORD/P4PORT are set in the enviroment the script is executed in.

###COMMENTS###


# Prerequisite is the jq json command line processor
# https://jqlang.github.io/jq/
$(which jq 2>&1>/dev/null)
if [[ $? > 0 ]] ;then
        echo "Please install [jq](https://jqlang.github.io/jq/) first."
        exit 1
fi

# Options: currently have implemented -v option
while getopts "v" OPTION; do
     case $OPTION in
     v)
         verbose=1
      shift
         ;;
     esac
 done

# Add text colours to make it easier to read the output.
CLEAR=$'\e[0m'
MESSAGE=$'\033[3m'
INFO=$'\e[32m'
WARN=$'\e[31m'
ERROR=$'\e[41m'
PROMPT=$'\e[44m'

# Define prompt text colours & styles
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

# Following index searches not currently checked
pending='1310=31'
approved_isPending='(1308=617070726F766564 1310=31)'
approved_notPending=' (1308=617070726F766564 1310=30)'
no='30'
yes='31'

###############################################################################
# Loop over list of reviews from the index, one inner loop per state
###############################################################################
for checkState in approved needsReview needsRevision archived rejected
do
        # Keep a count of how many indexs we check for a status outptu at the end
        running_count=count_index_$checkState

        # Verbose output if opted for
        if [[ -n $verbose ]]; then echo info "# Checking state=$checkState indexes" ;fi


        # Using bash variable indirection to expand ${!checkState} to specific search attribute variable defined above
        for reviewKeyName in $(p4 search "${!checkState}")
        do
            ((++running_count))
            # echo index counter for $checkState $running_count

                # Calculate review id from key name to include in output for information (not needed in commands)
                reviewHexKeyName=$(echo $reviewKeyName | cut -c14-21)
                reviewID=$(printf "%d" $((0xffffffff - 0x$reviewHexKeyName)))

                # Extract state from the key (we are assuming this is correct and if the index is different it's the index that needs fixing)
                reviewKeyState=$(p4 keys -e "$reviewKeyName" | cut -d= -f2- | jq -r '.state')

                # If we didn't get the state from the key (for example if the key does not exist) then move to the next review
                if [[ -z $reviewKeyState ]]
                then
                        echowarn "# No state found for key $reviewKeyName (review $reviewID)"

                        # Print p4 index command to delete the index entry

                        echomessage "# The following command will delete the $checkState index entry for $reviewKeyName"
                        echomessage "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"

                        continue
                fi

                # If review key state is different from the state stored in the index, generate commands to fix the index
                if [[ "$reviewKeyState" != "$checkState" ]]; then

                        echowarn "# Key for review $reviewKeyName (review $reviewID) has state=$reviewKeyState, but index has $checkState"

                        # Print p4 index command to delete the index entry
                        echomessage "# The following command will delete the index entry"
                        echomessage "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"

                        # Print p4 index command to correct the index entry
                        echomessage "# The following commands will correct the index entry"
                        echomessage "echo ${!reviewKeyState} | p4 index -a 1308 $reviewKeyName"
                else
                        if  [[ -n $verbose ]]; then echo info "# OK, review key $reviewKeyName (review $reviewID) state $reviewKeyState matches in key and index" ;fi

                fi
        done
        declare count_index_summary_$checkState=$running_count
done


# Output stats of number of records processed
for checkState in approved needsReview needsRevision archived rejected
do
        summary_count=count_index_summary_$checkState
        echo -e "Number of $checkState indexes processed \t ${!summary_count}"

done

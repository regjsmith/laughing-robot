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

# Log file to save output to, create and make executable as it will contain p4 index commands to fix indexes  i
# (alternatively use -f option to fix immedately as the scrpt runs)

log=checkReviewStatesKeytoIndex-$(date +"%d-%m-%Y.%H.%M.%S")
touch $log
chmod +x $log

usage() { echo "Usage: $0 [-s <list of states> (One or more of approved needsReview needsRevision archived rejected, quoted if more than one state)]"
          echo "[-v (verbose)] [-q (quiet)] [-h detailed help] [-f (fix, run commands to fix index)]" 1>&2; exit 1; }

help(){ echo "The $0 script compares the state information of Swarm reviews stored in the index against the review key"
        echo "They should match, however if they have become out of sync the script will print or execute the p4 index commands required to update"
        echo "the index to match the key (the assumption is the key is correct and the index is out of sync)"
        echo ""
        echo "All output is copied into a log file named in the form checkReviewStatesKeytoIndex-<datetime>"
        echo "For example $log"
        echo ""
        echo "This can be run as a script to excute the index commands i.e. ./$log"
        echo ""
        echo "Options:"
        echo "-s <list of states to check>"
        echo "  - States should be one or more of approved needsReview needsRevision archived rejected"
        echo "  - List should be given as a space separated quoted list (if more than one), for example -s \"approved needsReview rejected\""
        echo "  - If -s not given then all states are checked"
        echo ""
        echo "-f (fix). Will execute to p4 index commands to update the index to match the key. If not given then prints commands"
        echo "-v (verbose). Output information about each review being processed"
        echo "-q (quiet). Only output information for reviews found with mismatched states"
        echo "-h (help). Output this help message"
}

# Prerequisite is the jq json command line processor
# https://jqlang.github.io/jq/
$(which jq 2>&1>/dev/null)
if [[ $? > 0 ]] ;then
        echo "Please install [jq](https://jqlang.github.io/jq/) first."
        exit 1
fi

# Options
while getopts "vqfhs:" OPTION; do
     case $OPTION in
     v)
      verbose=1
      ;;
     q)
      quiet=1
      ;;
     f)
      # -f to run the index commands rather then jsut print them to the teminal
      fix=1
      ;;
     h)
      help
      exit
      ;;
     s)
      checkStates=${OPTARG}
      for state in $checkStates
      do
          if [[ $(echo $state | egrep -v "(approved|needsReview|needsRevision|archived|rejected)" ) ]]
          then
                echo "State $state invalid! -s state options must be one or more of approved needsReview needsRevision archived rejected"
                echo ""
                usage
                exit
          fi
      # Remove any duplicated states keeping the order - being over caution probably
      # For the awk part see https://catonmat.net/awk-one-liners-explained-part-two
      checkStates=$(echo $checkStates | tr ' ' '\n'  | awk '!a[$0]++' | tr '\n' ' ')

      done
      ;;
     ?)
     usage
     exit
     ;;
     esac
 done

if [[ -n $verbose && -n $quiet ]]; then
    echo "Options -v (verbose and -q (quiet) are mutually exclusive!"
    exit
fi

# Final lsit of states to check, either from -s option or default to list of all valid states
checkStates=${checkStates:="approved needsReview needsRevision archived rejected"}

# Add text colours to make it easier to read the output.
CLEAR=$'\e[0m'
MESSAGE=$'\033[3m'
INFO=$'\e[32m'
WARN=$'\e[31m'
ERROR=$'\e[41m'
PROMPT=$'\e[44m'

# Define prompt text colours & styles
echoinfo()      { echo "#${INFO}${1}${CLEAR}"    | tee -a $log ;} # White text
echoplaintext() { echo "${1}"                    | tee -a $log ;} # No formatting characers so commands in log can be executed directly
echomessage()   { echo "#${MESSAGE}${1}${CLEAR}" | tee -a $log ;} # Green text
echowarn()      { echo "#${WARN}${1}${CLEAR}"    | tee -a $log ;} # Red text
echoerror()     { echo "#${ERROR}${1}${CLEAR}"   | tee -a $log ;} # Red block text

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


echo "###############################################################################################"
echo "# Output from this script run will be logged in $log"
echo "###############################################################################################"

echoinfo " $(date)"
echoinfo " Script executed as: $0 $*"

# Set counter for status report at the end
index_no_review_state_found=0

###############################################################################
# Loop over list of reviews from the index, one inner loop per state
###############################################################################
for checkState in $checkStates
do
        # Keep a count of how many indexs we check and mismatches for a status output at the end
        running_count=count_index_$checkState
        index_review_mismatch_state_found=index_review_mismatch_state_found_$checkState
        index_review_mismatch_state_found=0


        # Some feedback unless -q (quiet) option
        if [[ -z $quiet ]]; then echoinfo " Checking indexes for state $checkState" ;fi


        # Using bash variable indirection to expand ${!checkState} to specific search attribute variable defined above
        for reviewKeyName in $(p4 search "${!checkState}")
        do
            ((++running_count))

                # Calculate review id from key name to include in output for information (not needed in commands)
                reviewHexKeyName=$(echo $reviewKeyName | cut -c14-21)
                reviewID=$(printf "%d" $((0xffffffff - 0x$reviewHexKeyName)))

                # Extract state from the key (we are assuming this is correct and if the index is different it's the index that needs fixing)
                reviewKeyState=$(p4 keys -e "$reviewKeyName" | cut -d= -f2- | jq -r '.state')

                # If we didn't get the state from the key (for example if the key does not exist) then remove index entry and move to the next review
                if [[ -z $reviewKeyState ]]
                then
                        echowarn " No state found for key $reviewKeyName (review $reviewID)"

                        ((++index_no_review_state_found))

                        if [[ -n $fix ]]
                        then
                            echomessage " Executing the following command to delete the $checkState index entry for $reviewKeyName"
                            echoplaintext "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"
                            echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName
                        else
                            # Print p4 index command to delete the index entry
                            echomessage " The following command will delete the $checkState index entry for $reviewKeyName"
                            echoplaintext "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"
                        fi
                        continue
                fi

                # If review key state is different from the state stored in the index, generate commands to fix the index
                if [[ "$reviewKeyState" != "$checkState" ]]; then


                        echowarn " Key for review $reviewKeyName (review $reviewID) has state=$reviewKeyState, but index has $checkState"

                        ((++index_review_mismatch_state_found))

                        if [[ -n $fix ]]
                        then
                            # Execute p4 index commands to delete & correct the index entries
                            echomessage " Executing the following commands to delete & correct the index entries"
                            echoplaintext "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"
                            echoplaintext "echo ${!reviewKeyState} | p4 index -a 1308 $reviewKeyName"
                            echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName
                            echo ${!reviewKeyState} | p4 index -a 1308 $reviewKeyName
                        else
                            # Print  p4 index commands to delete & correct the index entries
                            echomessage " The following commands will delete & correct the index entries"
                            echoplaintext "echo ${!checkState} | p4 index -a 1308 -d $reviewKeyName"
                            echoplaintext "echo ${!reviewKeyState} | p4 index -a 1308 $reviewKeyName"
                        fi
                else
                        if  [[ -n $verbose ]]; then echoinfo "OK: review key $reviewKeyName (review $reviewID) state $reviewKeyState matches in key and index" ;fi

                fi
        done

        # Without these declare stements can't seem ot get at the counter variables later
        declare count_index_summary_$checkState=$running_count
        declare index_review_mismatch_state_found_$checkState=$index_review_mismatch_state_found
done


# Output stats of number of records processed
if [[ -z $quiet ]]; then

    echoinfo ""

    for checkState in $checkStates
    do
            summary_count=count_index_summary_$checkState
            index_review_mismatch_state_found=index_review_mismatch_state_found_$checkState

            printf '%-76s: %s\n' "# Number of $checkState index records processed "  "${!summary_count}" | tee -a $log
            printf '%-76s: %s\n\n' "# Number of $checkState index records with mismatched review key states"  "${!index_review_mismatch_state_found}" | tee -a $log

    done

    printf '%-76s: %s\n' "# Number of index records with no matching review key state"  "$index_no_review_state_found" | tee -a $log

    if [[ -z $fix ]]
        then
            echoinfo ""
            echoinfo " Commands to fix the indexes were not run as the -f (fix) option not given."
            echoinfo " You can run ./$log to execute them"
       fi
fi

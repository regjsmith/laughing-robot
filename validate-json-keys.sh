
#!/usr/bin/bash

# Validate Swarm keys as valid json by runing them through jq json paring utility
# Assumes the input file has been generated 'p4 keys -e "swarm-*"' so it contains both keynames and values like
# swarm-activity-ffea18d2 = {"type":"change","....rest of key}

# Didn't use the lines below as they mean script doesn't out to teminal at all butleaving as useful to know hown to do it
# As per https://stackoverflow.com/questions/314675/how-to-redirect-output-of-an-entire-shell-script-within-the-script-itself
# save stdout and stderr to file
# descriptors 3 and 4,
# then redirect them to "foo"
#exec 3>&1 4>&2 >foo 2>&1

if [ $# -eq 0 ]
  then
    echo Usage: $0 keyfile
    echo The script expects a single argument of the key file name, generated with something like 'p4 keys -e "swarm-*"'
    echo The script output with both stdout and stderr will be saved to a file named after the input file with the process id appended
    exit 2
fi

# Prerequisite is the jq json command line processor
# https://jqlang.github.io/jq/
$(which jq 2>&1>/dev/null)
if [[ $? > 0 ]] ;then
        echo "Please install [jq](https://jqlang.github.io/jq/) first." 
        exit 1
fi

inputfile=$1
outputfile=$inputfile.$$

{


        echo Input file is $inputfile
        echo Output will be saved to file $outputfile

        linenumber=0

        cat $inputfile |  while read line
        do
                echo -n "."
                linenumber=$[$linenumber +1]

                keyname=$(printf '%s' "$line" | cut -d '=' -f1)
                keyvalue=$(printf '%s' "$line" | cut -d '=' -f2)

                printf '%s' "$keyvalue" | jq '. | type' 1>/dev/null

                if [ $? -ne 0 ]; then
                        printf '\n%s\n' "$keyname invalid JSON line $linenumber"
                        printf '%s\n' "$keyvalue"
                fi
        done

} 2>&1 | tee $outputfile

# restore stdout and stderr, also close the FDs 3 and 4
#exec 1>&3 2>&4 3>&- 4>&-


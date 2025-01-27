#!/usr/bin/bash

# Loop over the users in the owners array (only if the array is not empty) of all the project keys not flagged as deleted and check if they exist in Perforce
for projectId in $(p4 -Ztag -F %value% keys -e "swarm-project-*" | jq  -r 'if .deleted != true and .owners !=[] then .id else empty end')
        do
                projectKey="swarm-project-${projectId}"

                echo "# Checking owners in project key for project id $projectId"

                for user in $(p4 keys -e $projectKey | cut -d= -f2- | jq -r '.owners[]')
                do
                        if p4 user -o --exists $user > /dev/null 2>&1; then
                        echo "#   OK $user exists in Perforce"
                        owners+=($user)
                else
                        echo "#   $user does not exist in Perforce"
                fi

                done

                # Check if the owners array has changed and if it has print out p4 counter command to update the key
                originalProjectKeyValue=$(p4 keys -e $projectKey | cut -d= -f2- | jq -r)
                modifiedProjectKeyValue=$(p4 keys -e $projectKey | cut -d= -f2- | jq -c  '.owners |= $ARGS.positional' --args "${owners[@]}" )

               if test "$(echo $originalProjectKeyValue |  jq -r '.owners')" != "$(echo $modifiedProjectKeyValue | jq -r '.owners')"
               then
                    echo ""
                    echo "#   p4 counter command to update owners in project key for project $projectId to existing Perforce id's"
                    echo ""
                    echo "#   IMPORTANT: the command should be run in a *NIX shell like bash and NOT windows cmd or Powershell terminals"
                    echo "#   as they strip off doube quotes in the json string"
                    echo ""
                    echo "p4 counter -u $projectKey '$modifiedProjectKeyValue'"
               fi

               # reset owners array for next project
               owners=()
               echo ""
done

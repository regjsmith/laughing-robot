#!/usr/bin/bash

# Reg Smith

# Example script to print out what Swarm projects changes are associate with (if any)
# Takes the approach of taking the list of files in the output from p4 changes and checking each element of the depot path
# for any redis path keys which are in the format Swarm^path:<md5sum> where the <md5sum> is taken of project branch paths (with any trailing ... removed)  
# No doubt could approach this a few diffferent ways (extracting project paths from api or keys to compare etc.)

# Example output for first 2 changes

#./changes-report-projects.sh 

#--------------------------------------
#Change 16955
#--------------------------------------
#File     //depot/Reg/file1.txt
#Checking //depot/Reg/file1.txt
#Checking //depot/Reg/
#    Project manhattan
#    Project reg
#  Checking //depot/
#
#--------------------------------------
#Change 16954
#--------------------------------------
#  File     //depot/Reg/file1.txt
#  Checking //depot/Reg/file1.txt
#  Checking //depot/Reg/
#    Project manhattan
#    Project reg
#  Checking //depot/
#
#  File     //depot/Reg/file2.txt
#  Checking //depot/Reg/file2.txt
#  Checking //depot/Reg/
#    Project manhattan
#    Project reg
#  Checking //depot/


# For testing only taking a few changes via -m option, adjust to a different number or omit to process all changes 
# for change in $(p4 -ztag -F "%change%" changes -m 5) ; do
for change in $(p4 -ztag -F "%change%" changes -m 9) ; do
    echo "--------------------------------------"
	echo Change $change
    echo "--------------------------------------"
    for file in $(p4 -ztag -F "%depotFile%" files @=$change); do
	    path=$file
        echo "  File     $file"

	    # Walk up depot path one directory element at time, when we reach the top it will simply be "/"
        while [ "$path" != "/" ]; do
           
            echo "  Checking $path"

            # Redis path key is stored in a php serialzed format, using php to deserializse and extract projects
            php -r 'if(empty($argv[1])) {exit;} foreach (array_keys(unserialize($argv[1])) as $project ){ echo "    Project $project" . "\n";}' \
            $(echo -n "$path" | md5sum | cut -d- -f1 | xargs printf "GET Swarm:path^%s \r\n quit\r\n" | /opt/perforce/swarm/sbin/redis-cli-swarm)

            ##debug
            #echo -n "$path" | md5sum | cut -d- -f1 
            #echo -n "$path" | md5sum | cut -d- -f1 | xargs printf "GET Swarm:path^%s \r\n quit\r\n" | /opt/perforce/swarm/sbin/redis-cli-swarm
            ##debug

            # Go up path one level
            path=$(dirname $path)

            # Append / to dirname result as that's what redis is keyed off
            # Do it here at the bottom of the loop so first run through which is always a file doesn't get the / above
            if [[ "$path" != */ ]]; then
                path="$path/"
            fi

        done
        echo ""
    done
done

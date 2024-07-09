#!/usr/bin/bash

# Download and update Linux p4v

# Reg Smith

now=$(date)

# Fetch list of availble versions that can be dpwnloaded in local file

if [ -f ./P4V.json ]; then
    mv P4V.json P4V.json.bak

    set -o pipefail

    curl -qs https://updates.perforce.com/static/P4V/P4V.json | jq  -r '.versions[] | select(.platform=="linux26x86_64")| .major+"."+.minor+"."+.build' > P4V.json

    if [ $? -ne 0 ]; then
        echo Download of https://updates.perforce.com/static/P4V/P4V.json failed
        exit 1
    fi
fi

# List in file is already sorted with the latest being the last line
latest=$(tail -1 P4V.json | cut -d. -f1-2 | sed 's/^..//')

# Check the version is supplied as argument in short form like 23.2
# if [[ "$#" -ne 1 ]] || ! [[ "$1" =~ [1-9][0-9]\.[1-9]|latest ]] || ! [[ "$1" == "latest" ]]; then
if [[ "$#" -ne 1 ]] || ! [[ "$1" =~ [1-9][0-9]\.[1-9]|latest ]] ; then
    echo "Please provide version in short form like $latest"
    echo ""
    echo "As of $now:"
    echo ""
    echo " - Latest version is $latest"
    echo " - Currently availble versions are availble for download from https://ftp.perforce.com/perforce/, with an "r" prefix like r23.2"
    echo " - Full list with build numbers extracted from https://updates.perforce.com/static/P4V/P4V.json are as follows:"
    echo ""
    cat P4V.json

    # Notes for later improvements
    # - To get a list of availble versionsin short form run one of these
    #   (the grep  comes out faster according t "time")

    #   curl -s https://ftp.perforce.com/perforce/ | sed -n 's#.* href="r\([1-9][0-9]\.[1-9]\)/.*#\1#p'
    #   curl -s https://ftp.perforce.com/perforce/ | grep -Po '(?<= href="r)[1-9]{2}\.[1-9](?=/)'

    # - To look for p4v.tgz files under any of the returned version numbers, e.g. 24.1 (useful for checking for latest)
    #   curl -s  https://ftp.perforce.com/perforce/r24.1/bin.linux26x86_64/ -o - | grep -Po '(?<= href=")p4v.tgz(?=")'

    # Interactvie select menu
    # select i in $(echo latest;cat P4V.json) ; do case $i in latest) echo latest;; $i) echo $i ;; esac; done
    # Output:
    #1) latest            4) 2017.3.1654916   7) 2018.3.1719707  10) 2019.2.1965058  13) 2020.3.2060285  16) 2021.3.2186916  19) 2022.2.2336701  22) 2023.2.2467475  25) 2024.1.2591061
    #2) 2017.1.1491634    5) 2018.1.1637591   8) 2018.4.1753667  11) 2020.1.1966006  14) 2021.1.2125979  17) 2021.4.2263543  20) 2022.3.2408367  23) 2023.3.2495381  26) 2024.2.2619912
    #3) 2017.2.1573260    6) 2018.2.1687764   9) 2019.1.1865170  12) 2020.2.2028073  15) 2021.2.2138880  18) 2022.1.2286077  21) 2023.1.2431464  24) 2023.4.2558838


    exit
else
    version=$1
fi

# testing code thus far
#exit

# Run a command using sudo so it only asks for password at the start and won't
# ask again while rest of script runs, default for sudo is to store password for 15 minutes

sudo echo Installing/updating P4V


if [ -f /opt/perforce/bin/p4v/bin/p4v ];then
    installedVersion=$(/opt/perforce/bin/p4v/bin/p4v -V | grep "^Rev"| cut -d/ -f3,4 | sed 's#/#.#')
    echo Currently installed version of P4V $installedVersion
else
    echo "No currently installed P4V found at /opt/perforce/bin/p4v/bin/p4v"
fi

# Look for already downloaded p4v.tgz in current directory, else determine online version

if [ -f ./p4v.tgz ]; then
    localtarVersion=$(tar -ztf p4v.tgz | head -1 | sed 's#/$##' | cut -d- -f2-)
    echo "Found p4v.tgz in current directory for P4V version $localtarVersion, using that for install"

    if [ "$localtarVersion" = "$installedVersion" ]; then
        echo "Local p4v.tgz version matches currently installed P4V $installedVersion ... exiting"
        exit
    fi
else
    # Check if we already have the same version as availble for download installed.
    # Download a small amount of the tar file to check version, clumsy (it's a zipped tar file and we only get
    # the first 256 bytes and it does give errors about not being valid archive, but seems to work
    # Determine version in tarfile by inspecting first line of tar file listing

    downloadableVersion=$(curl -s -r 0-256 https://ftp.perforce.com/perforce/r$version/bin.linux26x86_64/p4v.tgz -o - | tar -ztf - 2>/dev/null | head -1 | sed 's#/$##' | cut -d- -f2-)

    if [[ "$downloadableVersion" = "$installedVersion" ]]; then
        echo "Downloadable version P4V $downloadableVersion matches currently installed version ...exiting"
        exit
    fi

    # Clean up our partial download if it exists
    if [ -f ./p4v.tgz ]; then
        rm p4v.tgz
    fi


    # Installed version not the available download version so download full tgz to current directory
    # Currently hardwired to a particluar version (23.4 below), wonder if there is a /latest link?

    echo "Downloading https://ftp.perforce.com/perforce/r$version/bin.linux26x86_64/p4v.tgz"
    curl https://ftp.perforce.com/perforce/r$version/bin.linux26x86_64/p4v.tgz -o p4v.tgz

fi

# Untar into /opt/perforce/bin/p4v, saving previous install first if present
if [ -d /opt/perforce/bin/p4v ]; then
        echo Renaming /opt/perforce/bin/p4v to /opt/perforce/bin/p4v_prev
        sudo mv -f /opt/perforce/bin/p4v /opt/perforce/bin/p4v_prev
fi

sudo mkdir /opt/perforce/bin/p4v
sudo tar -xvf p4v.tgz -C /opt/perforce/bin/p4v --strip-components=1

# Create or replace link to /usr/local/bin/p4v
if [ -f /usr/local/bin/p4v ]; then
    sudo rm /usr/local/bin/p4v
fi

sudo ln -s /opt/perforce/bin/p4v/bin/p4v /usr/local/bin/p4v

echo Created link /opt/perforce/bin/p4v/bin/p4v to /usr/local/bin/p4v
echo Updated P4V to following version:
p4v -V

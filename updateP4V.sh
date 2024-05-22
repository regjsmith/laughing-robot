#!/usr/bin/bash
<< 'COMMENT'
Notes
Future enhancements for quickly determining latest downloadable version and checking if requested version exists

// In production the latest versions json content comes from
// https://updates.perforce.com/static/P4V/P4V.json

Defined in //qt/p4v/p24.2/src/gui/web/UpdateWebRequestManager.cpp

List of linux26x86_64 

curl -qs https://updates.perforce.com/static/P4V/P4V.json | jq '.versions[] | select(.platform=="linux26x86_64")'

Example output (truncated):

{"platform": "linux26x86_64",
  "minor": "4",
  "major": "2023",
  "build": "2558838"
}
{
  "platform": "linux26x86_64",
  "minor": "1",
  "major": "2024",
  "build": "2591061"
}
COMMENT

# Download and update Linux p4v

# Check the version is supplied as argument in short form like 23.2 

if [[ "$#" -ne 1 ]] || ! [[ "$1" =~ [1-9][0-9]\.[1-9] ]]; then

    echo "Please provide version in short form like 23.2"
    echo "Availble versions are listed at https://ftp.perforce.com/perforce/, with an "r" prefix like r23.2"
    
    # Notes for later improvements

    # - To get a list of availble versions in short form run one of these
    #   (the grep  comes out faster according t "time")
    #   curl -s https://ftp.perforce.com/perforce/ | sed -n 's#.* href="r\([1-9][0-9]\.[1-9]\)/.*#\1#p'
    #   curl -s https://ftp.perforce.com/perforce/ | grep -Po '(?<= href="r)[1-9]{2}\.[1-9](?=/)'

    # - To look for p4v.tgz files under any of the returned version numbers, e.g. 24.1 (useful for checking for latest)
    #   curl -s  https://ftp.perforce.com/perforce/r24.1/bin.linux26x86_64/ -o - | grep -Po '(?<= href=")p4v.tgz(?=")'
    
    exit
else
    version=$1
fi

# Run a command using sudo so it only asks for password at the start and won't 

# ask again while rest of script runs, default for sudo is to store password for 15 minutes

sudo echo Installing/updating P4V

if [ -f /opt/perforce/bin/p4v/bin/p4v ];then
    installedVersion=$(/opt/perforce/bin/p4v/bin/p4v -V | grep "^Rev"| cut -d/ -f3,4 | sed 's#/#.#')
    echo Currently installed version P4V $installedVersion
else
    echo "No currently installed P4V found at /opt/perforce/bin/p4v/bin/p4v"
fi

# Look for already downloaded p4v.tgz in current directory, else determine online version

if [ -f ./p4v.tgz ]; then
    echo "Found p4v.tgz in current directory, using that"
    
    localtarVersion=$(tar -ztf p4v.tgz | head -1 | sed 's#/$##' | cut -d- -f2-)

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

    # clean up our partial download
    rm p4v.tgz

# Installed version not the available download version so download full tgz to current directory
# Currently hardwired to a particluar version (23.4 below), wonder if there is a /latest link?
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


#!/bin/bash

#
# Copyright (C) 2016 RTAndroid Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# OpenGApps installation script
# Author: Igor Kalkov
# https://github.com/RTAndroid/android_device_brcm_rpi3/blob/aosp-7.1/scripts/gapps.sh
#

TIMESTAMP="20170117"
VERSION="7.1"
VARIANT="pico"

SHOW_HELP=false
ADB_ADDRESS=""
ARCHITECTURE=""
PACKAGE_NAME=""
INIT_FILE="/etc/init.d/gapps"

# ------------------------------------------------
# Helping functions
# ------------------------------------------------

show_help()
{
cat << EOF
USAGE:
  $0 [-h] -a ARCH -i IP
OPTIONS:
  -a  Device architecture: x86, x86_64, arm, arm64
  -h  Show help
  -i  IP address for ADB
EOF
}

check_dependency()
{
    which $1 > /dev/null
    if (($? != 0));then
        echo "ERR: $1 not found. Please install: \"$2\""
        exit 1
    fi
}

reboot_device()
{
    adb reboot bootloader > /dev/null &
    sleep 10
}

is_booted()
{
    [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
}

wait_for_adb()
{
    while true; do
        sleep 1
        adb kill-server > /dev/null
        sleep 1
        adb connect $ADB_ADDRESS > /dev/null
        sleep 1
        if is_booted; then
            break
        fi
    done
}

prepare_device()
{
    echo " * Checking available devices..."
    ping -c 1 $ADB_ADDRESS > /dev/null 2>&1
    reachable="$?"
    if [ "$reachable" -ne "0" ]; then
        echo "ERR: no device with address $ADB_ADDRESS found"
        echo ""
        show_help
        exit 1
    fi

    echo " * Enabling root access..."
    wait_for_adb
    adb root

    echo " * Remounting system partition..."
    wait_for_adb
    adb remount
}

prepare_gapps()
{
    mkdir -p gapps

    if [ ! -d "gapps/pkg" ]; then
        echo " * Downloading OpenGApps package..."
        echo ""
        wget https://github.com/opengapps/$ARCHITECTURE/releases/download/$TIMESTAMP/$PACKAGE_NAME -O gapps/$PACKAGE_NAME
    fi

    if [ ! -f "gapps/$PACKAGE_NAME" ]; then
        echo "ERR: package download failed!"
    fi

    if [ ! -d "gapps/pkg" ]; then
        echo " * Unzipping package..."
        echo ""
        unzip "gapps/$PACKAGE_NAME" -d "gapps/pkg"
        echo ""
    fi

    if [ ! -d "gapps/pkg" ]; then
        echo "ERR: unzipping the package failed!"
        exit 1
    fi
}

create_partition()
{
    echo " * Extracting supplied packages..."
    rm -rf gapps/tmp > /dev/null 2>&1
    mkdir -p gapps/tmp
    find . -name "*.tar.[g|l|x]z" -exec tar -xf {} -C gapps/tmp/ \;

    echo " * Creating local system partition..."
    rm -rf gapps/sys > /dev/null 2>&1
    mkdir -p gapps/sys
    for dir in gapps/tmp/*/
    do
      pkg=${dir%*/}
      dpi=$(ls -1 $pkg | head -1)

      echo "  - including $pkg/$dpi"
      rsync -aq $pkg/$dpi/ gapps/sys/
    done

    # no leftovers
    rm -rf gapps/tmp
}

install_package()
{
    echo " * Waiting for ADB..."
    wait_for_adb

    echo " * Pushing system files..."
    adb push gapps/sys/. /system/.

    echo " * Setting up the package installer..."
    count=$(adb shell ls -al /system/priv-app/ | grep -o Installer | wc -l)
    if [ "$count" == 1 ]; then
        echo "  - only one package installer found, leaving it as it is..."
    elif [ "$count" == 2 ]; then
        echo "  - two package installers found, removing the stock one..."
        adb shell "rm -rf /system/priv-app/PackageInstaller"
    else
        echo "  - $count package installers found, something is very wrong!"
    fi
}

write_script()
{
    adb shell echo "$1" >> $INIT_FILE
}

create_script()
{
    echo " * Waiting for ADB..."
    wait_for_adb

    echo " * Creating initialization script..."

    echo "  - creating a new init file"
    adb shell rm -rf $INIT_FILE
    adb shell touch $INIT_FILE

    echo "  - adding required permissions"
    write_script "#!/system/bin/sh"
    write_script ""
    write_script "### BEGIN INIT INFO"
    write_script "# Exec: ready"
    write_script "# Type: onetime"
    write_script "### END INIT INFO"
    write_script ""
    write_script "pm grant com.google.android.gms android.permission.ACCESS_COARSE_LOCATION"
    write_script "pm grant com.google.android.gms android.permission.ACCESS_FINE_LOCATION"
}


# ------------------------------------------------
# Script entry point
# ------------------------------------------------


# save the passed options
while getopts ":i:a:h" flag; do
case $flag in
    "i") ADB_ADDRESS="$OPTARG" ;;
    "a") ARCHITECTURE="$OPTARG" ;;
    "h") SHOW_HELP=true ;;
    *)
         echo ""
         echo "ERR: invalid option (-$flag $OPTARG)"
         echo ""
         show_help
         exit 1
esac
done

if [[ "$ARCHITECTURE" != "x86" && "$ARCHITECTURE" != "x86_64" && "$ARCHITECTURE" != "arm" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "ERR: $ARCHITECTURE is not a valid architecture!";
    show_help
    exit 1
fi

if [[ "$SHOW_HELP" = true ]]; then
    show_help
    exit 1
fi

# create the full package name
PACKAGE_NAME="open_gapps-$ARCHITECTURE-$VERSION-$VARIANT-$TIMESTAMP.zip"

echo "GApps installation script"
echo "Used package: $PACKAGE_NAME"
echo "ADB version: $(adb version)"
echo "ADB IP address: $ADB_ADDRESS"
echo ""

check_dependency adb phablet-tools
check_dependency lzip lzip

prepare_device
prepare_gapps
create_partition
install_package
create_script

echo " * Waiting for ADB..."
wait_for_adb

echo ""
echo "All done. The device will be rebooted."

echo ""
echo "NOTE: Please be patient and give it time to initialize the installed packages."
echo "It can take up to 10 minutes for the system to get responsive after boot."

reboot_device
adb kill-server

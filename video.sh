#!/bin/bash

#
# Copyright (C) 2017 RTAndroid Project
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
# Android video configuration script for Raspberry Pi 3
# Author: Igor Kalkov, Maximilian Schander
# https://github.com/RTAndroid/android_device_brcm_rpi3/blob/aosp-n/scripts/video.sh
#

GITHUB_API="https://api.github.com/repos"
GITHUB_RAW="https://raw.githubusercontent.com"

REPO_NAME="RTAndroid/android_device_brcm_rpi3"
REPO_BRANCH="aosp-7.1"
REPO_LISTING="$GITHUB_API/$REPO_NAME/contents/video?ref=$REPO_BRANCH"
REPO_FILES="$GITHUB_RAW/$REPO_NAME/$REPO_BRANCH/video"

SHOW_HELP=false
SHOW_CONFIGS=false
DEVICE_LOCATION=""
DEVICE_SUFFIX=""
PATCHES=""
SCREEN_CONFIG=""
MOUNT_DIR="rpi-sd"

# ------------------------------------------------
# Helping functions
# ------------------------------------------------

show_help()
{
cat << EOF
USAGE:
  $0 [-h] [-a] [-c CONFIG] /dev/NAME
OPTIONS:
  -a  Show all available configurations
  -c  Use CONFIG as screen configuration
  -h  Show this help and exit
EOF
}

show_configs()
{
    echo "Available configurations:"
    curl -fq $REPO_LISTING 2> /dev/null | grep \"name\" | sed 's/[",]//g' | sed 's/    name: / * /g'
    exit 0
}

check_device()
{
    echo " * Checking access permissions..."

    if [ "$(sudo id -u)" != "0" ]; then
        echo "ERR: please make sure you are allowed to run 'sudo'!"
        exit 1
    fi

    echo " * Checking the device in $DEVICE_LOCATION..."

    if [[ -z "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: device location not valid."
        exit 1
    fi

    if [[ ! -b "$DEVICE_LOCATION" ]]; then
        echo ""
        echo "ERR: no block device was found in $DEVICE_LOCATION!"
        exit 1
    fi

    # some card readers mount the sdcard as /dev/mmcblkXp? instead of /dev/sdX?
    DEVICE_NAME=${DEVICE_LOCATION##*/}
    if [[ $DEVICE_NAME == "mmcblk"* ]]; then
        echo " * Using device suffix 'p' (mmcblk device)"
        DEVICE_SUFFIX="p"
    fi
}

mount_partitions()
{
    echo " * Mounting required partitions..."
    mkdir $MOUNT_DIR
    mkdir -p $MOUNT_DIR/boot
    mkdir -p $MOUNT_DIR/system

    echo "  - boot partition"
    sudo mount -t vfat -o rw ${DEVICE_LOCATION}${DEVICE_SUFFIX}1 ${MOUNT_DIR}/boot

    echo "  - system partition"
    sudo mount -o rw ${DEVICE_LOCATION}${DEVICE_SUFFIX}2 ${MOUNT_DIR}/system
}

patch_partitions()
{
    URL="$REPO_FILES/$SCREEN_CONFIG"

    echo " * Downloading configuration..."
    echo "  - name: $SCREEN_CONFIG"
    echo "  - url: $URL"

    sudo curl -fs $URL > $MOUNT_DIR/$SCREEN_CONFIG
    if [ $? -ne 0 ]; then
        echo "ERR: Download failed!"
        exit 1
    fi

    echo " * Applying the configuration..."

    cd $MOUNT_DIR
    sudo patch -p0 < $SCREEN_CONFIG
    RESULT=$?
    cd - > /dev/null

    if [ $RESULT -ne 0 ]; then
        echo "ERR: Patching failed!"
        exit 1
    fi
}

unmount_partitions()
{
    echo " * Unmounting mounted partitions..."
    sync

    sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}1 > /dev/null 2>&1
    sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}2 > /dev/null 2>&1
    sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}3 > /dev/null 2>&1
    sudo umount -l ${DEVICE_LOCATION}${DEVICE_SUFFIX}4 > /dev/null 2>&1

    sudo umount $MOUNT_DIR/* 2> /dev/null
    sudo rm -rf $MOUNT_DIR
}


# --------------------------------------
# Script entry point
# --------------------------------------


# save the passed options
while getopts ":ac:h" flag; do
case $flag in
    "a") SHOW_CONFIGS=true ;;
    "c") SCREEN_CONFIG="$OPTARG" ;;
    "h") SHOW_HELP=true ;;
    *)
         echo ""
         echo "ERR: invalid option (-$flag $OPTARG)"
         echo ""
         show_help
         exit 1
esac
done

# don't do anything else
if [[ "$SHOW_HELP" = true ]]; then
    show_help
    exit 1
fi

# don't do anything else
if [[ "$SHOW_CONFIGS" = true ]]; then
    show_configs
    exit 1
fi

# what left after the parameters has to be the device
shift $(($OPTIND - 1))
DEVICE_LOCATION="$1"

# no target provided
if [[ -z "$DEVICE_LOCATION" ]]; then
    echo ""
    echo "ERR: missing the path to the sdcard!"
    echo ""
    show_help
    exit 1
fi

echo "Video configuration script for RPi started."
echo "Target device: $DEVICE_LOCATION"
echo "Screen config: $SCREEN_CONFIG"
echo ""

check_device
unmount_partitions
mount_partitions
patch_partitions
unmount_partitions

echo ""
echo "Configuration successful. You can now put your sdcard in the RPi."


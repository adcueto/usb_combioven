#!/bin/bash

# usb_combioven
#
# Description:
# This script updates or rolls back the application on the Forlinx board using files from a GitHub repository.
# It automates the process of copying application files, setting permissions, and configuring system services to ensure a seamless update or rollback.
#
# Usage:
# ./app_from_github.sh update
# ./app_from_github.sh rollback <software_version>
#
# Examples:
# ./app_from_github.sh update                # Updates to the latest version available on GitHub
# ./app_from_github.sh rollback 1.5.2        # Rolls back to version 1.5.2
#
# Note:
# Ensure the script has execution permissions.
# This script requires 'sudo' privileges to execute certain commands.
#
# Dependencies:
# - sudo: To execute commands with superuser privileges
# - unzip: To extract application archives
# - curl or wget: To download files from the GitHub repository
#
# Author:
# Jose Adrian Perez Cueto
# adrianjpca@gmail.com
##

# Variables
LOG_FILE="/var/log/usboven.log"
REPO_URL="https://github.com/adcueto/usb_combioven/archive/refs/heads/master.zip"
TEMP_DIR="/tmp/github_repo"
DOWNLOAD_FILE="/tmp/github_repo.zip"
APP_PATH="$TEMP_DIR/usb_combioven-master/app"
APP_DEST="/usr/crank/apps/ProServices"

# Function to log messages to the log file
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Clear the log file at the start
> "$LOG_FILE"

# Check arguments
if [[ $# -eq 0 ]]; then
    log_message "Error: You must specify 'update' or 'rollback <software_version>' as an argument."
    log_message "Usage: $0 update | rollback <software_version>"
    exit 1
fi

operation=$1
version=$2

if [[ "$operation" != "update" && "$operation" != "rollback" ]]; then
    echo "Error: Invalid operation. Use 'update' or 'rollback <software_version>'."
    exit 1
fi

if [[ "$operation" == "rollback" && -z "$version" ]]; then
    echo "Error: You must specify the software version for rollback."
    echo "Usage: $0 rollback <software_version>"
    exit 1
fi

log_message "Starting the application transfer..."

# Download the GitHub repository zip file
log_message "Downloading the repository zip file from GitHub..."
if [[ -f "$DOWNLOAD_FILE" ]]; then
    rm -f "$DOWNLOAD_FILE"
fi

curl -L "$REPO_URL" -o "$DOWNLOAD_FILE"
if [[ $? -ne 0 ]]; then
    log_message "Error: Failed to download repository zip file."
    exit 1
fi

# Extract the downloaded zip file
log_message "Extracting the repository zip file..."
if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"
unzip -o "$DOWNLOAD_FILE" -d "$TEMP_DIR"
if [[ $? -ne 0 ]]; then
    log_message "Error: Failed to extract repository zip file."
    exit 1
fi

# Check if the required directories exist in the extracted repository
if [[ ! -d "$APP_PATH" ]]; then
    log_message "Error: Directory '$APP_PATH' does not exist."
    exit 1
fi

LATEST_VERSION=$(ls -v "$APP_PATH" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1)

# Create necessary directories
log_message "Creating directory structure..."
sudo mkdir -p /usr/crank/apps /usr/crank/runtimes /usr/crank/apps/ProServices

# Unzip file into runtimes
log_message "Unzipping linux-imx8yocto-armle-opengles file..."
if [[ ! -f "$TEMP_DIR/usb_combioven-master/linux/linux-imx8yocto-armle-opengles_2.0-7.0-40118.zip" ]]; then
    log_message "Error: ZIP file not found."
    exit 1
fi
sudo unzip -o "$TEMP_DIR/usb_combioven-master/linux/linux-imx8yocto-armle-opengles_2.0-7.0-40118.zip" -d /usr/crank/runtimes/

# Set permissions
log_message "Setting 0775 permissions for runtimes and apps..."
sudo chmod -R 775 /usr/crank/runtimes /usr/crank/apps

# Copy scripts
log_message "Copying scripts to /usr/crank..."
if [[ ! -d "$TEMP_DIR/usb_combioven-master/scripts" ]]; then
    log_message "Error: Scripts directory not found."
    exit 1
fi
sudo cp -f -r "$TEMP_DIR/usb_combioven-master/scripts/"* /usr/crank/
sudo chmod 775 /usr/crank/*

# Copy and configure services
log_message "Copying and configuring services..."
if [[ ! -d "$TEMP_DIR/usb_combioven-master/services" ]]; then
    log_message "Error: Services directory not found."
    exit 1
fi

SERVICES=(
    "$TEMP_DIR/usb_combioven-master/services/storyboard_splash.service:/etc/systemd/system/"
    "$TEMP_DIR/usb_combioven-master/services/storyboard.service:/etc/systemd/system/"
    "$TEMP_DIR/usb_combioven-master/services/combi_backend.service:/lib/systemd/system/"
    "$TEMP_DIR/usb_combioven-master/services/wired.network:/etc/systemd/network/"
    "$TEMP_DIR/usb_combioven-master/services/wireless.network:/etc/systemd/network/"
    "$TEMP_DIR/usb_combioven-master/services/wpa_supplicant@wlan0.service:/etc/systemd/system/"
)

for service in "${SERVICES[@]}"; do
    IFS=":" read src dest <<< "$service"
    sudo cp -f "$src" "$dest"
    sudo chmod 0755 "$dest"
done

# Remove connection handlers
log_message "Removing connection handlers..."
sudo rm -f /etc/resolv.conf /etc/tmpfiles.d/connman_resolvconf.conf
sudo systemctl stop connman connman-env
sudo systemctl disable connman connman-env

# Enable services
log_message "Enabling services..."
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl stop wpa_supplicant
sudo systemctl disable wpa_supplicant
sudo systemctl daemon-reload

SERVICES_TO_ENABLE=(
    "storyboard_splash.service"
    "storyboard.service"
    "combi_backend.service"
    "wpa_supplicant@wlan0.service"
    "systemd-resolved.service"
)

for service in "${SERVICES_TO_ENABLE[@]}"; do
    sudo systemctl enable "$service"
    sudo systemctl start "$service"
done

# Rename weston service
log_message "Renaming weston service..."
if [[ -e "/lib/systemd/system/weston.service" ]]; then
    sudo mv /lib/systemd/system/weston.service /lib/systemd/system/weston_Pro_S.service
    log_message "The weston service was renamed successfully."
else
    log_message "The weston service file was already renamed."
fi

# Update or rollback the application
log_message "Copying version $version to the apps directory..."
if [[ "$operation" == "update" ]]; then
    log_message "Updating the application..."
    if [[ -z "$LATEST_VERSION" ]]; then
        log_message "No versions found in $APP_PATH"
        exit 1
    else
        sudo cp -f -r "$APP_PATH/$LATEST_VERSION/"* "$APP_DEST"
        log_message "Software version $LATEST_VERSION updated"
    fi
else
    log_message "Rolling back to version $version..."
    sudo cp -f -r "$APP_PATH/$version/"* "$APP_DEST"
fi

# Change boot logo
log_message "Changing the system boot logo..."
if [[ ! -f "$TEMP_DIR/usb_combioven-master/img/logo.bmp" ]]; then
    log_message "Error: Boot logo file not found."
    exit 1
fi
sudo cp -f "$TEMP_DIR/usb_combioven-master/img/logo.bmp" /run/media/mmcblk2p1/logo.bmp

# Remove temporary files
log_message "Removing temporary files..."
sudo rm -rf "$TEMP_DIR" "$DOWNLOAD_FILE"

# Reboot
log_message "Rebooting..."
sudo reboot
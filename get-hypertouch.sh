#!/bin/bash

# One-Line Bootstrap Installer for HyperTouch 4.0

REPO_URL="https://github.com/lutzh86/hypertouch"
INSTALL_DIR="/usr/src/hypertouch40"

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo bash ...)"
  exit
fi

echo "Updating System & Installing Git..."
apt-get update
apt-get install -y git

if [ -d "$INSTALL_DIR" ]; then
    echo "Existing directory found at $INSTALL_DIR. Updating..."
    cd $INSTALL_DIR
    git pull
else
    echo "Cloning repository..."
    git clone $REPO_URL $INSTALL_DIR
    cd $INSTALL_DIR
fi

# Run the main installer
chmod +x install.sh
./install.sh

#!/bin/bash
# HyperTouch 4.0 Master Installer

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

DRIVER_DIR="driver"
OVERLAY_DIR="overlays"
SRC_DIR="/usr/src/hypertouch40-1.0"

echo -e "${GREEN}HyperTouch 4.0 Installer (2025)${NC}"
echo "================================"

# --- 1. Dependencies ---
echo -e "${YELLOW}Installing Dependencies...${NC}"
apt-get update

# Try to find the correct kernel headers
HEADERS_PKG="raspberrypi-kernel-headers"
if ! apt-cache show "$HEADERS_PKG" >/dev/null 2>&1; then
    echo "raspberrypi-kernel-headers not found, trying linux-headers-$(uname -r)..."
    HEADERS_PKG="linux-headers-$(uname -r)"
fi

# Install basics first
apt-get install -y dkms device-tree-compiler i2c-tools git $HEADERS_PKG

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to install required packages.$NC"
    echo "Please ensure you have internet access and your package lists are up to date."
    exit 1
fi

# --- 2. Driver Installation (DKMS) ---
echo -e "${YELLOW}Installing/Updating Kernel Module (DKMS)...${NC}"

# Remove old DKMS if exists
dkms remove hypertouch40/1.0 --all >/dev/null 2>&1

# Copy source
rm -rf $SRC_DIR
mkdir -p $SRC_DIR
cp $DRIVER_DIR/* $SRC_DIR/

# Build and Install
dkms add hypertouch40/1.0
if [ $? -ne 0 ]; then echo -e "${RED}DKMS Add failed${NC}"; exit 1; fi

dkms build hypertouch40/1.0
if [ $? -ne 0 ]; then echo -e "${RED}DKMS Build failed${NC}"; exit 1; fi

dkms install hypertouch40/1.0
if [ $? -ne 0 ]; then echo -e "${RED}DKMS Install failed${NC}"; exit 1; fi

# --- 3. Overlay Selection ---
echo ""
echo "Select Display Driver Mode:"
echo -e "1) ${GREEN}KMS/DRM (Recommended)${NC} - Modern graphics stack, better performance."
echo -e "2) ${YELLOW}Legacy${NC} - Old-school Framebuffer mode."
echo ""
read -p "Select [1]: " choice < /dev/tty
choice=${choice:-1}

CONFIG="/boot/config.txt"
if [ -f "/boot/firmware/config.txt" ]; then
    CONFIG="/boot/firmware/config.txt"
fi

if [ -f "$CONFIG" ]; then
    cp $CONFIG $CONFIG.bak
else
    echo -e "${RED}Error: config.txt not found!${NC}"
    exit 1
fi

# Disable conflicting config.txt entries
# dtparam=i2c_arm=on conflicts with DPI (GPIO 2/3)
sed -i '/^dtparam=i2c_arm=on/s/^/#/' $CONFIG
# enable_uart=1 conflicts with DPI (GPIO 14/15)
sed -i '/^enable_uart=1/s/^/#/' $CONFIG

# Cleanup config.txt
sed -i '/dtoverlay=hypertouch40/d' $CONFIG
sed -i '/dtoverlay=vc4-kms-v3d/d' $CONFIG
sed -i '/gpio=27=pu/d' $CONFIG
# Legacy cleanup
sed -i '/enable_dpi_lcd/d' $CONFIG
sed -i '/dpi_group/d' $CONFIG
sed -i '/dpi_mode/d' $CONFIG
sed -i '/dpi_output_format/d' $CONFIG
sed -i '/dpi_timings/d' $CONFIG
sed -i '/max_framebuffers/d' $CONFIG

# Common Fix (Hardware I2C Stability)
echo "" >> $CONFIG
echo "# HyperTouch 4.0" >> $CONFIG
echo "gpio=27=pu # Fix for Touch Controller Address" >> $CONFIG

if [ "$choice" -eq "1" ]; then
    echo -e "${GREEN}Installing KMS Overlay...${NC}"
    dtc -I dts -O dtb -o $OVERLAY_DIR/hypertouch40-kms.dtbo $OVERLAY_DIR/hypertouch40-kms.dts
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: DTC Compilation failed.${NC}"
        exit 1
    fi
    
    cp $OVERLAY_DIR/hypertouch40-kms.dtbo /boot/overlays/
    
    echo "dtoverlay=vc4-kms-v3d" >> $CONFIG
    echo "dtoverlay=hypertouch40-kms" >> $CONFIG
else
    echo -e "${YELLOW}Installing Legacy Overlay...${NC}"
    dtc -I dts -O dtb -o $OVERLAY_DIR/hypertouch40.dtbo $OVERLAY_DIR/hypertouch40.dts
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: DTC Compilation failed.${NC}"
        exit 1
    fi

    cp $OVERLAY_DIR/hypertouch40.dtbo /boot/overlays/
    
    cat <<EOT >> $CONFIG
dtoverlay=hypertouch40
enable_dpi_lcd=1
dpi_group=2
dpi_mode=87
dpi_output_format=0x7f216
dpi_timings=480 0 10 16 59 800 0 15 113 15 0 0 0 60 0 32000000 6
max_framebuffers=2 
# dtparam=touchscreen-swapped-x-y
# dtparam=touchscreen-inverted-x
EOT
fi

echo ""
echo -e "${GREEN}Installation Complete.${NC}"
echo "Please reboot your Raspberry Pi."

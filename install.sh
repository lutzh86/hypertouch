#!/bin/bash
# HyperTouch 4.0 Master Installer

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

KERNEL_RELEASE="$(uname -r)"
KERNEL_ARCH="$(uname -m)"
USERSPACE_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

DRIVER_DIR="driver"
OVERLAY_DIR="overlays"
SRC_DIR="/usr/src/hypertouch40-1.0"

echo -e "${GREEN}HyperTouch 4.0 Installer (2025)${NC}"
echo "================================"

case "$USERSPACE_ARCH" in
  armhf)
    if [ "$KERNEL_ARCH" = "aarch64" ]; then
      echo -e "${RED}Unsupported mixed Raspberry Pi OS setup detected.${NC}"
      echo "Userspace is 32-bit (${USERSPACE_ARCH}) but the running kernel is 64-bit (${KERNEL_ARCH})."
      echo "DKMS cannot build a module reliably for this combination."
      echo "Use a matching Raspberry Pi OS variant instead:"
      echo "  - 32-bit OS + 32-bit kernel, or"
      echo "  - 64-bit OS + 64-bit kernel"
      echo "If you want to stay on 32-bit Raspberry Pi OS, set 'arm_64bit=0' in config.txt and reboot."
      exit 1
    fi
    ;;
  arm64)
    if [ "$KERNEL_ARCH" != "aarch64" ]; then
      echo -e "${RED}Unsupported mixed Raspberry Pi OS setup detected.${NC}"
      echo "Userspace is 64-bit (${USERSPACE_ARCH}) but the running kernel is ${KERNEL_ARCH}."
      echo "Use a matching Raspberry Pi OS image/kernel pair and run the installer again."
      exit 1
    fi
    ;;
  "")
    echo -e "${YELLOW}Warning:${NC} Could not determine Debian userspace architecture via dpkg."
    ;;
  *)
    echo -e "${RED}Unsupported architecture: ${USERSPACE_ARCH}${NC}"
    echo "This installer targets Raspberry Pi OS on armhf and arm64."
    exit 1
    ;;
esac

# --- 1. Dependencies ---
echo -e "${YELLOW}Installing Dependencies...${NC}"
apt-get update

# Prefer the exact headers for the running kernel, then fall back to the meta package.
HEADERS_PKG=""
for pkg in "linux-headers-${KERNEL_RELEASE}" "raspberrypi-kernel-headers"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        HEADERS_PKG="$pkg"
        break
    fi
done

if [ -z "$HEADERS_PKG" ]; then
    echo -e "${RED}Error: Could not find a kernel headers package for ${KERNEL_RELEASE}.${NC}"
    echo "Tried: linux-headers-${KERNEL_RELEASE}, raspberrypi-kernel-headers"
    echo "Please update apt sources or install matching headers manually."
    exit 1
fi

echo "Using kernel headers package: ${HEADERS_PKG}"

# Install basics first
apt-get install -y build-essential dkms device-tree-compiler i2c-tools git "$HEADERS_PKG"

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
BOOT_OVERLAY_DIR="/boot/overlays"
if [ -f "/boot/firmware/config.txt" ]; then
    CONFIG="/boot/firmware/config.txt"
    BOOT_OVERLAY_DIR="/boot/firmware/overlays"
elif [ ! -d "$BOOT_OVERLAY_DIR" ] && [ -d "/boot/firmware/overlays" ]; then
    BOOT_OVERLAY_DIR="/boot/firmware/overlays"
fi

if [ ! -d "$BOOT_OVERLAY_DIR" ]; then
    echo -e "${RED}Error: overlays directory not found at ${BOOT_OVERLAY_DIR}.${NC}"
    exit 1
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

# Shared section
echo "" >> $CONFIG
echo "# HyperTouch 4.0" >> $CONFIG

if [ "$choice" -eq "1" ]; then
    echo -e "${GREEN}Installing KMS Overlay...${NC}"
    dtc -I dts -O dtb -o $OVERLAY_DIR/hypertouch40-kms.dtbo $OVERLAY_DIR/hypertouch40-kms.dts
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: DTC Compilation failed.${NC}"
        exit 1
    fi
    
    cp $OVERLAY_DIR/hypertouch40-kms.dtbo "$BOOT_OVERLAY_DIR/"
    
    echo "dtoverlay=vc4-kms-v3d" >> $CONFIG
    echo "dtoverlay=hypertouch40-kms" >> $CONFIG
else
    echo -e "${YELLOW}Installing Legacy Overlay...${NC}"
    dtc -I dts -O dtb -o $OVERLAY_DIR/hypertouch40.dtbo $OVERLAY_DIR/hypertouch40.dts
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: DTC Compilation failed.${NC}"
        exit 1
    fi

    cp $OVERLAY_DIR/hypertouch40.dtbo "$BOOT_OVERLAY_DIR/"
    
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
echo "Touch address autodetect is enabled for both 0x14 and 0x5d."
echo "Please reboot your Raspberry Pi."

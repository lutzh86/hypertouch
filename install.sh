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
ROTATION_HELPER="/usr/local/bin/hypertouch-apply-desktop-rotation"

rotation_wayland_transform() {
    case "$1" in
        0) echo "normal" ;;
        90) echo "90" ;;
        180) echo "180" ;;
        270) echo "270" ;;
        *) return 1 ;;
    esac
}

rotation_x11_transform() {
    case "$1" in
        0) echo "normal" ;;
        90) echo "right" ;;
        180) echo "inverted" ;;
        270) echo "left" ;;
        *) return 1 ;;
    esac
}

desktop_user_home() {
    local user_name="$1"
    local passwd_entry

    if [ -n "$user_name" ]; then
        passwd_entry="$(getent passwd "$user_name" || true)"
        [ -n "$passwd_entry" ] || return 1
        printf '%s\n' "$passwd_entry" | cut -d: -f6
        return 0
    fi

    return 1
}

install_kms_rotation_autostart() {
    local user_name="$1"
    local user_home="$2"
    local rotation_deg="$3"
    local x11_transform wayland_transform autostart_dir desktop_file

    x11_transform="$(rotation_x11_transform "$rotation_deg")" || return 1
    wayland_transform="$(rotation_wayland_transform "$rotation_deg")" || return 1

    install -m 0755 /dev/null "$ROTATION_HELPER"
    cat > "$ROTATION_HELPER" <<EOF
#!/bin/sh
set -eu

ROTATION_DEG="${rotation_deg}"
WAYLAND_TRANSFORM="${wayland_transform}"
X11_TRANSFORM="${x11_transform}"
OUTPUTS="DPI-1 DSI-1"

apply_wayland() {
    command -v wlr-randr >/dev/null 2>&1 || return 1

    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
        for output in \$OUTPUTS; do
            wlr-randr --output "\$output" --transform "\$WAYLAND_TRANSFORM" >/dev/null 2>&1 && return 0
        done
        sleep 2
    done

    return 1
}

apply_x11() {
    command -v xrandr >/dev/null 2>&1 || return 1
    [ -n "\${DISPLAY:-}" ] || return 1

    for _attempt in 1 2 3 4 5 6 7 8 9 10; do
        for output in \$OUTPUTS; do
            xrandr --output "\$output" --rotate "\$X11_TRANSFORM" >/dev/null 2>&1 && return 0
        done
        sleep 2
    done

    return 1
}

case "\${XDG_SESSION_TYPE:-}" in
    wayland)
        apply_wayland || true
        ;;
    x11)
        apply_x11 || true
        ;;
    *)
        apply_wayland || apply_x11 || true
        ;;
esac
EOF

    autostart_dir="${user_home}/.config/autostart"
    desktop_file="${autostart_dir}/hypertouch-rotation.desktop"
    mkdir -p "$autostart_dir"

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=HyperTouch Rotation
Comment=Apply HyperTouch desktop rotation after login
Exec=${ROTATION_HELPER}
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

    chown root:root "$ROTATION_HELPER"
    chown "$user_name:$user_name" "$autostart_dir" "$desktop_file"
}

remove_kms_rotation_autostart() {
    local user_home="$1"

    rm -f "$ROTATION_HELPER"
    rm -f "${user_home}/.config/autostart/hypertouch-rotation.desktop"
}

detect_touch_address() {
    local model="$1"

    case "$model" in
        *"Raspberry Pi Zero 2 W"*|*"Raspberry Pi 3"*|*"Compute Module 3"*)
            echo "0x5d"
            return 0
            ;;
        *"Raspberry Pi 4"*|*"Pi 400"*|*"Compute Module 4"*)
            echo "0x14"
            return 0
            ;;
        *)
            echo "0x14"
            return 1
            ;;
    esac
}

detect_touch_address_from_binding() {
    local driver_dir driver_name devpath suffix

    for driver_dir in /sys/bus/i2c/drivers/*; do
        [ -d "$driver_dir" ] || continue
        driver_name="$(basename "$driver_dir" | tr '[:upper:]' '[:lower:]')"

        case "$driver_name" in
            *goodix*)
                for devpath in "$driver_dir"/*-0014 "$driver_dir"/*-005d; do
                    [ -e "$devpath" ] || continue
                    suffix="${devpath##*-}"
                    case "$suffix" in
                        0014) echo "0x14"; return 0 ;;
                        005d) echo "0x5d"; return 0 ;;
                    esac
                done
                ;;
        esac
    done

    return 1
}

detect_touch_address_from_i2c_gpio() {
    local name_file bus bus_name scan

    command -v i2cdetect >/dev/null 2>&1 || return 1

    for name_file in /sys/class/i2c-dev/i2c-*/name; do
        [ -r "$name_file" ] || continue
        bus="${name_file%/name}"
        bus="${bus##*/i2c-}"
        bus_name="$(cat "$name_file")"

        case "$bus_name" in
            *i2c-gpio*)
                ;;
            *)
                continue
                ;;
        esac

        scan="$(i2cdetect -y "$bus" 2>/dev/null || true)"
        [ -n "$scan" ] || continue

        if printf '%s\n' "$scan" | awk '/^10:/{exit !(($6 == "14") || ($6 == "UU"))} END{if (NR == 0) exit 1}'; then
            echo "0x14"
            return 0
        fi

        if printf '%s\n' "$scan" | awk '/^50:/{exit !(($15 == "5d") || ($15 == "UU"))} END{if (NR == 0) exit 1}'; then
            echo "0x5d"
            return 0
        fi
    done

    return 1
}

touch_gpio_config_for_addr() {
    case "$1" in
        0x14) echo "gpio=27=pu" ;;
        0x5d) echo "gpio=27=pd" ;;
        *) return 1 ;;
    esac
}

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

echo ""
PI_MODEL="Unknown Raspberry Pi"
if [ -r "/proc/device-tree/model" ]; then
    PI_MODEL="$(tr -d '\0' < /proc/device-tree/model)"
fi

DETECTED_TOUCH_SOURCE=""
if DETECTED_TOUCH_ADDR="$(detect_touch_address_from_binding)"; then
    DETECTED_TOUCH_SOURCE="current Goodix binding"
    DETECTED_TOUCH_STATUS=0
elif DETECTED_TOUCH_ADDR="$(detect_touch_address_from_i2c_gpio)"; then
    DETECTED_TOUCH_SOURCE="active i2c-gpio scan"
    DETECTED_TOUCH_STATUS=0
else
    DETECTED_TOUCH_ADDR="$(detect_touch_address "$PI_MODEL")"
    DETECTED_TOUCH_STATUS=$?
    if [ "$DETECTED_TOUCH_STATUS" -eq 0 ]; then
        DETECTED_TOUCH_SOURCE="board profile"
    else
        DETECTED_TOUCH_SOURCE="default fallback"
    fi
fi

if [ "$DETECTED_TOUCH_STATUS" -eq 0 ]; then
    echo "Detected board: ${PI_MODEL}"
    echo "Auto-detected touch address: ${DETECTED_TOUCH_ADDR} (${DETECTED_TOUCH_SOURCE})"
else
    echo "Detected board: ${PI_MODEL}"
    echo -e "${YELLOW}Warning:${NC} No live touch address could be detected. Defaulting to ${DETECTED_TOUCH_ADDR} (${DETECTED_TOUCH_SOURCE})."
fi

echo ""
echo "Select Touch Address Mode:"
echo "1) Auto (${DETECTED_TOUCH_ADDR})"
echo "2) Force 0x14"
echo "3) Force 0x5d"
echo ""
read -p "Select [1]: " touch_choice < /dev/tty
touch_choice=${touch_choice:-1}

case "$touch_choice" in
    1)
        TOUCH_ADDR="${DETECTED_TOUCH_ADDR}"
        ;;
    2)
        TOUCH_ADDR="0x14"
        ;;
    3)
        TOUCH_ADDR="0x5d"
        ;;
    *)
        echo -e "${RED}Invalid touch address mode selection.${NC}"
        exit 1
        ;;
esac

TOUCH_GPIO_CFG="$(touch_gpio_config_for_addr "${TOUCH_ADDR}")"
if [ -z "$TOUCH_GPIO_CFG" ]; then
    echo -e "${RED}Failed to derive GPIO boot configuration for touch address ${TOUCH_ADDR}.${NC}"
    exit 1
fi

echo ""
echo "Select Screen Rotation:"
echo "1) 0°   - Portrait, header on the right (default)"
echo "2) 90°  - Landscape, header on the bottom"
echo "3) 180° - Portrait, header on the left"
echo "4) 270° - Landscape, header on the top"
echo ""
read -p "Select [1]: " rotation_choice < /dev/tty
rotation_choice=${rotation_choice:-1}

case "$rotation_choice" in
    1)
        ROTATION_DEG=0
        KMS_ROTATION=0
        TOUCH_SWAP="on"
        TOUCH_INVX="off"
        TOUCH_INVY="on"
        LEGACY_ROTATE=0
        ;;
    2)
        ROTATION_DEG=90
        KMS_ROTATION=270
        TOUCH_SWAP="off"
        TOUCH_INVX="on"
        TOUCH_INVY="on"
        LEGACY_ROTATE=1
        ;;
    3)
        ROTATION_DEG=180
        KMS_ROTATION=180
        TOUCH_SWAP="on"
        TOUCH_INVX="on"
        TOUCH_INVY="off"
        LEGACY_ROTATE=2
        ;;
    4)
        ROTATION_DEG=270
        KMS_ROTATION=90
        TOUCH_SWAP="off"
        TOUCH_INVX="off"
        TOUCH_INVY="off"
        LEGACY_ROTATE=3
        ;;
    *)
        echo -e "${RED}Invalid rotation selection.${NC}"
        exit 1
        ;;
esac

DESKTOP_USER="${SUDO_USER:-}"
DESKTOP_HOME=""
if [ -n "$DESKTOP_USER" ]; then
    DESKTOP_HOME="$(desktop_user_home "$DESKTOP_USER")"
fi

if [ -z "$DESKTOP_HOME" ]; then
    echo -e "${YELLOW}Warning:${NC} Could not determine the desktop user home from SUDO_USER."
fi

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
sed -i '/gpio=27=pd/d' $CONFIG
sed -i '/^display_lcd_rotate=/d' $CONFIG
sed -i '/^dtparam=addr=/d' $CONFIG
sed -i '/^dtparam=rotate=/d' $CONFIG
sed -i '/^dtparam=touchscreen-swapped-x-y=/d' $CONFIG
sed -i '/^dtparam=touchscreen-inverted-x=/d' $CONFIG
sed -i '/^dtparam=touchscreen-inverted-y=/d' $CONFIG
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
echo "${TOUCH_GPIO_CFG}" >> $CONFIG
echo "# Touch address: ${TOUCH_ADDR}" >> $CONFIG
echo "# Rotation: ${ROTATION_DEG} degrees clockwise" >> $CONFIG

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
    echo "dtparam=addr=${TOUCH_ADDR}" >> $CONFIG
    echo "dtparam=rotate=${KMS_ROTATION}" >> $CONFIG
    echo "dtparam=touchscreen-swapped-x-y=${TOUCH_SWAP}" >> $CONFIG
    echo "dtparam=touchscreen-inverted-x=${TOUCH_INVX}" >> $CONFIG
    echo "dtparam=touchscreen-inverted-y=${TOUCH_INVY}" >> $CONFIG

    if [ -n "$DESKTOP_HOME" ] && [ -d "$DESKTOP_HOME" ]; then
        install_kms_rotation_autostart "$DESKTOP_USER" "$DESKTOP_HOME" "$ROTATION_DEG"
        echo "Desktop autostart rotation installed for user ${DESKTOP_USER}."
    fi
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
dtparam=addr=${TOUCH_ADDR}
display_lcd_rotate=${LEGACY_ROTATE}
dtparam=touchscreen-swapped-x-y=${TOUCH_SWAP}
dtparam=touchscreen-inverted-x=${TOUCH_INVX}
dtparam=touchscreen-inverted-y=${TOUCH_INVY}
enable_dpi_lcd=1
dpi_group=2
dpi_mode=87
dpi_output_format=0x7f216
dpi_timings=480 0 10 16 59 800 0 15 113 15 0 0 0 60 0 32000000 6
max_framebuffers=2 
EOT

    if [ -n "$DESKTOP_HOME" ] && [ -d "$DESKTOP_HOME" ]; then
        remove_kms_rotation_autostart "$DESKTOP_HOME"
    fi
fi

echo ""
echo -e "${GREEN}Installation Complete.${NC}"
echo "Touch address is fixed to ${TOUCH_ADDR}."
echo "Display rotation is set to ${ROTATION_DEG} degrees clockwise."
echo "Please reboot your Raspberry Pi."

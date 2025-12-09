# HyperTouch 4.0 Drivers & Utilities

Welcome to the official repository for the **HyperTouch 4.0** display for Raspberry Pi.

This repository contains:
*   **Kernel Drivers** (DKMS based) for Backlight and LCD Initialization.
*   **Device Tree Overlays** for both Modern (KMS) and Legacy systems.
*   **Documentation** and Datasheets.

## Quick Installation (One-Line)

Run this command on your Raspberry Pi to install the driver automatically:

```bash
curl https://raw.githubusercontent.com/lutzh86/hypertouch/main/get-hypertouch.sh | sudo bash
```

*Note: Replace `main` with the correct branch name if necessary.*

## Manual Installation

1.  Clone this repository:
    ```bash
    git clone https://github.com/lutzh86/hypertouch hypertouch40
    cd hypertouch40
    ```
2.  Run the installer:
    ```bash
    sudo ./install.sh
    ```
3.  Choose your driver version (KMS is recommended for Pi 4/5/Zero2W).
4.  Reboot.

## Important Hardware Note (I2C Address)

The Touch Controller on this display chooses its I2C address (`0x14` or `0x5d`) based on the state of the Interrupt Pin (GPIO 27) at power-on.
Since the Reset Pin is **hardwired to 3.3V**, software cannot reset the chip to fix a wrong address.

The installer applies a fix in `/boot/config.txt` (`gpio=27=pu`) to force the pin HIGH during boot, ensuring address `0x14` is selected.

## Directory Structure

*   **`driver/`**: Source code for the `hypertouch40_bl` kernel module. Uses DKMS for automatic updates.
*   **`overlays/`**: Device Tree Sources (`.dts`) for KMS and Legacy modes.
*   **`docs/`**: Manuals and datasheets (including `TXW397017S4-AS_SPEC.pdf`).
*   **`install.sh`**: Main installation script.

## Backlight Control

You can adjust the backlight brightness via the Linux sysfs interface. The valid range is typically 0 to 31.

To set the brightness (e.g., to maximum):
```bash
echo 31 | sudo tee /sys/class/backlight/soc:backlight/brightness
```
*Note: If the path `soc:backlight` does not exist, check `ls /sys/class/backlight/` for the correct device name.*

## Troubleshooting

If the touch does not work:
1.  Check the I2C address: `i2cdetect -y 11`
2.  It should be `14`. If it is `5d`, the pull-up fix might not be active or the cable is loose.
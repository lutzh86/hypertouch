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
3.  Choose your driver version (`KMS/DRM via DKMS` is recommended. On Pi 5 this path is currently beta).
4.  Reboot.

## Important Hardware Note (I2C Address)

The Touch Controller on this display chooses its I2C address (`0x14` or `0x5d`) based on the state of the Interrupt Pin (GPIO 27) at power-on.
Since the Reset Pin is **hardwired to 3.3V**, software cannot reset the chip to fix a wrong address.

The installer configures **exactly one** Goodix touchscreen node and also sets a boot-time pull on GPIO 27 to force the selected address:

*   `0x14` via `gpio=27=pu`
*   `0x5d` via `gpio=27=pd`

This avoids duplicate probing, I2C errors on the non-existent address, and IRQ conflicts during boot.

## Supported Raspberry Pi OS Variants

The installer supports both native Raspberry Pi OS variants:

*   **32-bit Raspberry Pi OS** (`armhf` userspace with a 32-bit kernel)
*   **64-bit Raspberry Pi OS** (`arm64` userspace with a 64-bit kernel)

Mixed installations are **not supported**:

*   32-bit userspace with a 64-bit kernel
*   64-bit userspace with a 32-bit kernel

The installer detects these mismatches and stops with an explicit error before DKMS runs.

## Touch Address Selection

During installation, the script auto-detects the touch address in this order:

*   existing bound Goodix device in `sysfs`
*   active `i2c-gpio` bus scan
*   Raspberry Pi model fallback

The board-model fallback is:

*   Pi 4 / Pi 400 / CM4: defaults to `0x14`
*   Pi 3 / Zero 2 W / CM3: defaults to `0x5d`

You can still override the result and force either `0x14` or `0x5d` manually.

This keeps the installer independent from hardcoded bus numbers such as `11` or `22`.

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

## Rotation

The installer now offers four built-in rotation presets:

*   `0°` - Portrait, header on the right
*   `90°` - Landscape, header on the bottom
*   `180°` - Portrait, header on the left
*   `270°` - Landscape, header on the top

For **KMS**, the installer keeps the touchscreen at its base orientation, writes a Wayfire output/input mapping for `DPI-1`, and installs a desktop autostart helper as a fallback for sessions that need `wlr-randr` or `xrandr`.
The KMS display timing and DPI data format are aligned with the Raspberry Pi / HyperPixel4 KMS DPI reference values.

For **Legacy**, the installer writes `display_lcd_rotate=` plus matching touchscreen axis settings.

## Troubleshooting

### Dependency Errors / Kernel/Header Mismatch
If you encounter errors during installation regarding kernel headers, `gcc`, or "unmet dependencies", verify that your Raspberry Pi OS userspace and running kernel match.

DKMS builds against the running kernel, so mixed 32/64-bit installations will fail.

**Solution:**
Use a matching Raspberry Pi OS image/kernel pair.

If you are intentionally using **32-bit Raspberry Pi OS**, switch to the 32-bit kernel:
1. Edit `/boot/config.txt`:
   ```bash
   sudo nano /boot/config.txt
   ```
2. Add the following line to the end of the file:
   ```ini
   arm_64bit=0
   ```
3. Reboot your Pi:
   ```bash
   sudo reboot
   ```
4. Run the installer again.

### "Pin already requested" Errors
The installer automatically disables conflicting interfaces in `/boot/config.txt`.
- `dtparam=i2c_arm=on` is disabled (conflicts with DPI Pins 2 & 3).
- `enable_uart=1` is disabled (conflicts with DPI Pins 14 & 15).

If you manually re-enable these, the display or touch might fail.

### Touch Not Detected
The software I2C bus number can vary between systems. First list the available buses:

```bash
i2cdetect -l
```

Then scan the `i2c-gpio` bus shown in that list:

```bash
i2cdetect -y <bus-number>
```

The detected address must match the `dtparam=addr=` value written by the installer.

## License

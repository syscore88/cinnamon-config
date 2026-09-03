# 🎨 Cinnamon Visual Configuration Script

An automated Bash shell script designed for full visual and environmental configuration of the **Cinnamon** desktop environment on popular Linux distributions. The script automatically detects the system package manager, installs required configuration tools, copies user settings (`.config`, `.local`, `.icons`), sets wallpapers (desktop and LightDM/Slick-Greeter login screen), loads `dconf` settings, and automatically downloads and installs extensions and applets (Cinnamon Spices).

---

## 🚀 Main Features

- **Automatic distribution detection**: Full support for Debian, Ubuntu, Fedora, Arch Linux, openSUSE, and their derivatives.
- **Cinnamon tools installation**: The script automatically installs `cinnamon-settings`, `cinnamon-control-center`, and necessary dependencies (`curl`, `unzip`).
- **Configuration files synchronization**:
  - Copies the contents of the `.config/`, `.local/`, and `.icons/` folders to the user's home directory.
- **Wallpaper management**:
  - Sets the desktop wallpaper from the `wallpaper.jpg` file.
  - Configures the **LightDM / Slick-Greeter** login screen background using the `login-wallpaper.png` file.
- **dconf settings import**: Automatically loads exported user preferences from the `dconf-settings.ini` file directly into the dconf database.
- **Cinnamon Spices management**: Downloads and extracts selected applets and extensions directly from Linux Mint servers:
  - **Applets**: *Download/Upload Speed* (`download-and-upload-speed@cardsurf`), *ScreenShot* (`ScreenShot@tech71`), *Sticky Notes* (`sticky@scollins`), *Weather* (`weather@mockturtl`).
  - **Extensions**: *Burn My Windows* (`CinnamonBurnMyWindows@klangman`), *Compiz Windows Effect* (`compiz-windows-effect@hermes83.github.com`), *Transparent Panels* (`transparent-panels@germanfr`).
- **User Avatar**: Automatically sets the user's profile picture in AccountsService using the `piwo.png` file.
- **Multilingualism**: Displays clear progress bars in Polish or English depending on the system's regional settings.

---

## 🐧 Supported Distributions

The script identifies the system using `/etc/os-release` and selects the appropriate package manager:

| Distribution | Package Manager | Installed Packages |
| :--- | :--- | :--- |
| **Debian / Ubuntu / Mint** | `apt` | `cinnamon-settings`, `cinnamon-control-center`, `curl`, `unzip` |
| **Fedora** | `dnf` | `cinnamon-settings`, `cinnamon-control-center`, `curl`, `unzip` |
| **Arch Linux / Manjaro** | `pacman` | `cinnamon-control-center`, `curl`, `unzip` |
| **openSUSE** | `zypper` | `cinnamon-settings`, `cinnamon-control-center`, `curl`, `unzip` |

---

## 🔍 Module Details

### 1. Configuration Copying
Copies the contents of local configuration files (`.config`, `.local`, `.icons`) to the user's home directory, preserving the directory structure and permissions.

### 2. Desktop and Login Wallpapers
- The desktop wallpaper is copied to the `Pictures` directory (detected by `xdg-user-dir PICTURES`) and set using `gsettings`.
- The LightDM login background is copied to `/usr/share/backgrounds/custom/login-wallpaper.png`. The `/etc/lightdm/slick-greeter.conf` file is dynamically updated to apply the new background and disable the default drawing of the user background.

### 3. Loading dconf Settings
The `dconf-settings.ini` file is cleaned of Windows formatting (CRLF) and loaded via:

dconf load / < dconf-settings.ini

This ensures the immediate application of the panel layout, keyboard shortcuts, and environment behavior.

### 4. User Avatar (AccountsService)
The `piwo.png` image is copied to `/var/lib/AccountsService/icons/$USER`, and the account configuration file in `/var/lib/AccountsService/users/$USER` is updated.

---

## 🛠️ How to Use

### 1. Clone the repository or download the files
```bash
git clone https://github.com/syscore88/cinnamon-config.git
```

### 2. Enter the downloaded folder
```bash
cd cinnamon-config
```

### 3. Make the script executable
```bash
chmod +x install.sh
```

### 4. Run the script
> ⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo). The script will ask for the administrator password at the start to configure temporary elevated privileges.

```bash
./install.sh
```
<img width="1280" height="800" alt="Screenshot_debian13_2026-09-03_21:55:25" src="https://github.com/user-attachments/assets/41f23ae9-a5ba-4660-9378-6cc374b68f8f" />

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

If you find this project useful, leave a star! ⭐

## ⚠️ Troubleshooting and Notes

- **System restart**: The script includes a `systemctl reboot` command at the very end to ensure that all visual changes, permissions, and session variables are properly applied. **Save your work before running!**
- **Add-ons (Spices) not activating automatically?** If downloaded applets or extensions do not appear immediately, open *Cinnamon Settings* > *Applets/Extensions* and make sure they are enabled.

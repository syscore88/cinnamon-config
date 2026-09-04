# 🌿 Cinnamon Visual Configuration Script

An automated Bash shell script designed for complete visual and environment configuration of the **Cinnamon** desktop across popular Linux distributions. The script automatically detects the system package manager, installs required Cinnamon utility packages, downloads Cinnamon Spices applets/extensions, copies user configurations, sets the desktop wallpaper, loads `dconf` settings, sets the user avatar, and configures the LightDM/Slick-Greeter login screen wallpaper.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL` locale and prints all status messages accordingly.

---

## 🚀 Script Features

- **Automatic Linux Distribution Detection**: Support for Debian/Ubuntu-based, Fedora-based, Arch/Manjaro-based, and openSUSE/SUSE-based systems, detected via `/etc/os-release`.
- **Temporary Passwordless Sudo**: Requests the admin password once at the start, then configures a temporary `NOPASSWD` rule (via `/etc/sudoers.d/`, or a `polkit`/`run0` rule on systems without `visudo`) so the rest of the script can run unattended. The rule is automatically removed at the end of the script.
- **Cinnamon Tools Installation**: Installs `cinnamon-settings`, `cinnamon-control-center`, and `dconf`/`dconf-cli` depending on the distribution.
- **Cinnamon Spices (Applets & Extensions)**: Downloads and installs selected items directly from `cinnamon-spices.linuxmint.com` into `~/.local/share/cinnamon/`:
  - **Applets**: *Download & Upload Speed* (`download-and-upload-speed@cardsurf`), *ScreenShot* (`ScreenShot@tech71`), *Sticky Notes* (`sticky@scollins`), *Weather* (`weather@mockturtl`)
  - **Extensions**: *Burn My Windows* (`CinnamonBurnMyWindows@klangman`), *Compiz Windows Effect* (`compiz-windows-effect@hermes83.github.com`), *Transparent Panels* (`transparent-panels@germanfr`)
- **Configuration Files Sync**:
  - Copies `.config/`, `.local/`, `.icons/`, and `.themes/` folder contents into the corresponding folders in the user's home directory.
- **Wallpaper Management**:
  - Desktop wallpaper copied from `wallpaper.jpg` into the user's Pictures folder (`xdg-user-dir PICTURES`) and applied via `gsettings` (`org.cinnamon.desktop.background`).
  - Login screen wallpaper applied from `login-wallpaper.png` for LightDM's Slick Greeter, via `/etc/lightdm/slick-greeter.conf`.
- **Import dconf Settings**: Loads a full set of Cinnamon, GTK, Nemo, GNOME Terminal, and xed/xapp preferences directly into the user's `dconf` database via `dconf load /`.
- **User Avatar Setup**: Automatically sets the user profile picture in `AccountsService` using `piwo.png`.
- **Progress Bar & Logging**: Displays a live progress bar across 5 phases / 12 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.

---

## 🐧 Supported Distributions

The script identifies the OS using `/etc/os-release` (`ID` / `ID_LIKE`) and selects the corresponding package manager:

| Distribution | Package Manager | Installed Packages |
| :--- | :--- | :--- |
| **Debian / Ubuntu** and derivatives | `apt` | `cinnamon-settings`, `cinnamon-control-center`, `dconf-cli` |
| **Fedora** and derivatives | `dnf` | `cinnamon-settings`, `cinnamon-control-center`, `dconf` |
| **Arch Linux / Manjaro** | `pacman` | `cinnamon-control-center`, `dconf` |
| **openSUSE / SUSE** | `zypper` | `cinnamon-settings`, `cinnamon-control-center`, `dconf` |

`curl` and `unzip` are additionally installed on all distributions as dependencies for downloading Cinnamon Spices.

---

## 🔍 Module Details

### 1. Permissions & Distribution Detection
Verifies the script is **not** run as root, requests the sudo password once, and grants a temporary `NOPASSWD` rule for the duration of the run (via sudoers, or a `polkit`/`run0` rule on systems that lack `visudo`).

### 2. Cinnamon Spices Installation
For each applet/extension UUID, the script downloads `https://cinnamon-spices.linuxmint.com/files/<applets|extensions>/<uuid>.zip` with `curl` and extracts it into `~/.local/share/cinnamon/<applets|extensions>/`.

### 3. Configuration Copy & Wallpaper
Copies `.config`, `.local`, `.icons`, and `.themes` from the script directory into the user's home directory, copies `wallpaper.jpg` into the Pictures folder, and applies it as the desktop background via `gsettings`.

### 4. Loading dconf Settings
A large predefined block of Cinnamon/GNOME/GTK/Nemo settings (panel layout, enabled applets/extensions, theme, keyboard layout, gestures, terminal profile, file manager preferences, etc.) is loaded with `dconf load /` under the current user's permissions.

### 5. User Avatar (AccountsService)
`piwo.png` is copied to `/var/lib/AccountsService/icons/$USER`, and `/var/lib/AccountsService/users/$USER` is created or updated with the matching `Icon=` entry.

### 6. Login Screen Wallpaper (LightDM / Slick Greeter)
`login-wallpaper.png` is copied to `/usr/share/backgrounds/custom/`, and — if LightDM is detected — `/etc/lightdm/slick-greeter.conf` is updated with `background=` and `draw-user-backgrounds=false` under the `[Greeter]` section.

### 7. Finalization
The temporary sudo/polkit rule is removed and the system automatically **reboots** (`systemctl reboot`) to apply all changes.

---

## 🛠️ How to Use

### 1. Clone the repository or download the files
```bash
git clone https://gitlab.com/syscore88/cinnamon-config.git
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

#!/bin/bash
# ==========================================================
# SKRYPT KONFIGURACJI WIZUALNEJ CINNAMON
# ==========================================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/sbin:/sbin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PHASE_1="[1/5] Wykrywanie dystrybucji i konfiguracja uprawnień..."
    MSG_PHASE_2="[2/5] Instalacja i weryfikacja pakietów Cinnamon..."
    MSG_PHASE_3="[3/5] Instalacja apletów i rozszerzeń Cinnamon Spices..."
    MSG_PHASE_4="[4/5] Konfiguracja środowiska, tapety i ustawień wizualnych..."
    MSG_PHASE_5="[5/5] Konfiguracja tapety ekranu logowania..."
else
    MSG_PHASE_1="[1/5] Detecting distribution and configuring permissions..."
    MSG_PHASE_2="[2/5] Installing and verifying Cinnamon packages..."
    MSG_PHASE_3="[3/5] Installing Cinnamon Spices applets and extensions..."
    MSG_PHASE_4="[4/5] Configuring environment, wallpaper, and visual settings..."
    MSG_PHASE_5="[5/5] Configuring login screen wallpaper..."
fi

TOTAL_STEPS=12

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
USER_PICTURES="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallpaper_PATH="$USER_PICTURES/wallpaper.jpg"

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    exit 1
fi

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

sudo -v

if [[ "$USE_RUN0" -eq 1 ]]; then
    printf 'polkit._run0_nopasswd.push("%s");\n' "$CURRENT_USER" | sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    SUDOERS_TMP="$(mktemp)"
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" &>/dev/null; then
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
    else
        rm -f "$SUDOERS_TMP"
        log_err "Nieprawidłowa składnia reguły sudoers." "Invalid sudoers rule syntax."
        exit 1
    fi
    rm -f "$SUDOERS_TMP"
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

printf '\033[?7h' >&3

printf '\033[?7l' >&3

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

# ==========================================================
# 2. WYKRYWANIE DYSTRYBUCJI I INSTALACJA PAKIETÓW
# ==========================================================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="${ID:-}"
        OS_LIKE="${ID_LIKE:-}"
    else
        OS="unknown"
        OS_LIKE=""
    fi
}

install_cinnamon_packages() {
    if [[ "$OS" == *"ubuntu"* || "$OS" == *"debian"* || "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
        sudo apt-get update -yq || true
        for pkg in cinnamon-settings cinnamon-control-center; do
            sudo apt-get install -yq "$pkg" || true
        done
    elif [[ "$OS" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
        for pkg in cinnamon-settings cinnamon-control-center; do
            sudo dnf install -yq "$pkg" || true
        done
    elif [[ "$OS" == "arch" || "$OS_LIKE" == *"arch"* || "$OS" == "manjaro" ]]; then
        for pkg in cinnamon-control-center; do
            sudo pacman -S --noconfirm --needed "$pkg" || true
        done
    elif [[ "$OS" == *"opensuse"* || "$OS" == *"suse"* || "$OS_LIKE" == *"suse"* ]]; then
        for pkg in cinnamon-settings cinnamon-control-center; do
            sudo zypper install -yqn "$pkg" || true
        done
    fi
}

# ==========================================================
# 2b. ZALEŻNOŚCI I INSTALACJA APLETÓW/ROZSZERZEŃ (CINNAMON SPICES)
# ==========================================================
install_spices_dependencies() {
    if [[ "$OS" == *"ubuntu"* || "$OS" == *"debian"* || "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
        sudo apt-get install -yq curl unzip || true
    elif [[ "$OS" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
        sudo dnf install -yq curl unzip || true
    elif [[ "$OS" == "arch" || "$OS_LIKE" == *"arch"* || "$OS" == "manjaro" ]]; then
        sudo pacman -S --noconfirm --needed curl unzip || true
    elif [[ "$OS" == *"opensuse"* || "$OS" == *"suse"* || "$OS_LIKE" == *"suse"* ]]; then
        sudo zypper install -yqn curl unzip || true
    fi
}

CINNAMON_APPLETS=(
    "download-and-upload-speed@cardsurf"
    "ScreenShot@tech71"
    "sticky@scollins"
    "weather@mockturtl"
)

CINNAMON_EXTENSIONS=(
    "CinnamonBurnMyWindows@klangman"
    "compiz-windows-effect@hermes83.github.com"
    "transparent-panels@germanfr"
)

install_cinnamon_spice() {
    local spice_type="$1"
    local uuid="$2"
    local dest_dir="$HOME/.local/share/cinnamon/${spice_type}"
    local tmp_zip
    tmp_zip="$(mktemp --suffix=".zip")"
    local url="https://cinnamon-spices.linuxmint.com/files/${spice_type}/${uuid}.zip"

    mkdir -p "$dest_dir"

    if curl -fsSL "$url" -o "$tmp_zip"; then
        unzip -oq "$tmp_zip" -d "$dest_dir" || true
    fi

    rm -f "$tmp_zip"
}

install_all_cinnamon_spices() {
    install_spices_dependencies

    for uuid in "${CINNAMON_APPLETS[@]}"; do
        install_cinnamon_spice "applets" "$uuid"
    done

    for uuid in "${CINNAMON_EXTENSIONS[@]}"; do
        install_cinnamon_spice "extensions" "$uuid"
    done
}

detect_os
show_progress 2 $TOTAL_STEPS "$MSG_PHASE_2"

install_cinnamon_packages
show_progress 3 $TOTAL_STEPS "$MSG_PHASE_2"

install_spices_dependencies
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_3"

for uuid in "${CINNAMON_APPLETS[@]}"; do
    install_cinnamon_spice "applets" "$uuid"
done
for uuid in "${CINNAMON_EXTENSIONS[@]}"; do
    install_cinnamon_spice "extensions" "$uuid"
done
show_progress 5 $TOTAL_STEPS "$MSG_PHASE_3"

# ==========================================================
# 3. KONFIGURACJA WIZUALNA CINNAMON
# ==========================================================
show_progress 6 $TOTAL_STEPS "$MSG_PHASE_4"

if [[ -d "$SCRIPT_DIR/.config" ]]; then cp -af "$SCRIPT_DIR/.config/." ~/.config/ || true; fi
if [[ -d "$SCRIPT_DIR/.local" ]]; then cp -af "$SCRIPT_DIR/.local/." ~/.local/ || true; fi

if [[ -d "$SCRIPT_DIR/.icons" ]]; then
    mkdir -p ~/.icons
    cp -af "$SCRIPT_DIR/.icons/." ~/.icons/ || true
fi

if [[ -d "$SCRIPT_DIR/.themes" ]]; then
    mkdir -p ~/.themes
    cp -af "$SCRIPT_DIR/.themes/." ~/.themes/ || true
fi

if [[ -f "$SCRIPT_DIR/wallpaper.jpg" ]]; then
    mkdir -p "$(dirname "$wallpaper_PATH")"
    cp -af "$SCRIPT_DIR/wallpaper.jpg" "$wallpaper_PATH" || true
fi

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_4"

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.cinnamon.desktop.background picture-uri "file://$wallpaper_PATH" 2>/dev/null \
        && gsettings set org.cinnamon.desktop.background picture-options "zoom" 2>/dev/null || true
fi

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_4"

if command -v dconf &>/dev/null; then
    mkdir -p "$HOME/.config/dconf"

    dconf load / <<'DCONF_EOF' || true
[org/cinnamon]
alttab-switcher-delay=100
desktop-effects-close='fly'
desktop-effects-map='traditional'
desktop-effects-minimize='fade'
enabled-applets=['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:1:separator@cinnamon.org:1', 'panel1:left:2:grouped-window-list@cinnamon.org:2', 'panel1:right:4:systray@cinnamon.org:3', 'panel1:right:5:xapp-status@cinnamon.org:4', 'panel1:right:6:notifications@cinnamon.org:5', 'panel1:right:7:printers@cinnamon.org:6', 'panel1:right:8:removable-drives@cinnamon.org:7', 'panel1:right:9:keyboard@cinnamon.org:8', 'panel1:right:10:favorites@cinnamon.org:9', 'panel1:right:11:network@cinnamon.org:10', 'panel1:right:12:sound@cinnamon.org:11', 'panel1:right:13:power@cinnamon.org:12', 'panel1:right:15:calendar@cinnamon.org:13', 'panel1:right:16:cornerbar@cinnamon.org:14', 'panel1:right:14:weather@mockturtl:15', 'panel1:right:2:sticky@scollins:16', 'panel1:right:0:download-and-upload-speed@cardsurf:17', 'panel1:right:1:ScreenShot@tech71:18']
enabled-extensions=['transparent-panels@germanfr', 'compiz-windows-effect@hermes83.github.com', 'CinnamonBurnMyWindows@klangman']
next-applet-id=19
no-adjacent-panel-barriers=true
panel-edit-mode=false
panel-zone-icon-sizes='[{"panelId": 1, "left": 48, "center": 0, "right": 24}]'
panel-zone-symbolic-icon-sizes='[{"panelId": 1, "left": 28, "center": 28, "right": 16}]'
panel-zone-text-sizes='[{"panelId": 1, "left": 9.5, "center": 0.0, "right": 0.0}]'
panels-height=['1:29']
window-effect-speed=1

[org/cinnamon/desktop/input-sources]
sources=[('xkb', 'pl')]

[org/cinnamon/desktop/interface]
clock-show-date=true
clock-show-seconds=true
cursor-theme='McMojave-Cursors'
gtk-theme='Mojave-Dark'
icon-theme='Mkos-Big-Sur-Night'
toolkit-accessibility=false

[org/cinnamon/desktop/sound]
event-sounds=false

[org/cinnamon/desktop/wm/preferences]
min-window-opacity=30

[org/cinnamon/gestures]
swipe-down-2='PUSH_TILE_DOWN::end'
swipe-down-3='TOGGLE_OVERVIEW::end'
swipe-down-4='VOLUME_DOWN::end'
swipe-left-2='PUSH_TILE_LEFT::end'
swipe-left-3='WORKSPACE_NEXT::end'
swipe-left-4='WINDOW_WORKSPACE_PREVIOUS::end'
swipe-right-2='PUSH_TILE_RIGHT::end'
swipe-right-3='WORKSPACE_PREVIOUS::end'
swipe-right-4='WINDOW_WORKSPACE_NEXT::end'
swipe-up-2='PUSH_TILE_UP::end'
swipe-up-3='TOGGLE_EXPO::end'
swipe-up-4='VOLUME_UP::end'
tap-3='MEDIA_PLAY_PAUSE::end'

[org/cinnamon/launcher]
check-frequency=300
memory-limit=2048

[org/cinnamon/muffin]
draggable-border-width=10

[org/cinnamon/settings-daemon/plugins/color]
night-light-last-coordinates=(52.25, 21.0)

[org/cinnamon/theme]
name='Mojave-Dark'

[org/gnome/desktop/a11y/applications]
screen-reader-enabled=false

[org/gnome/desktop/a11y/mouse]
dwell-click-enabled=false
dwell-threshold=10
dwell-time=1.2
secondary-click-enabled=false
secondary-click-time=1.2

[org/gnome/desktop/input-sources]
sources=[('xkb', 'pl')]

[org/gnome/desktop/interface]
can-change-accels=false
clock-format='24h'
clock-show-date=true
clock-show-seconds=true
cursor-blink=true
cursor-blink-time=1200
cursor-blink-timeout=10
cursor-size=24
cursor-theme='Yaru'
enable-animations=true
font-name='Ubuntu 10'
gtk-color-palette='black:white:gray50:red:purple:blue:light blue:green:yellow:orange:lavender:brown:goldenrod4:dodger blue:pink:light green:gray10:gray30:gray75:gray90'
gtk-color-scheme=''
gtk-enable-primary-paste=true
gtk-im-module=''
gtk-im-preedit-style='callback'
gtk-im-status-style='callback'
gtk-key-theme='Default'
gtk-theme='Mojave-Dark'
gtk-timeout-initial=200
gtk-timeout-repeat=20
icon-theme='WhiteSur-dark'
menubar-accel='F10'
menubar-detachable=false
menus-have-tearoff=false
scaling-factor=uint32 0
text-scaling-factor=1.0
toolbar-detachable=false
toolbar-icons-size='large'
toolbar-style='both-horiz'
toolkit-accessibility=false

[org/gnome/desktop/peripherals/mouse]
accel-profile='default'
double-click=400
drag-threshold=8
left-handed=false
middle-click-emulation=false
natural-scroll=false
speed=0.0

[org/gnome/desktop/privacy]
disable-camera=false
disable-microphone=false
disable-sound-output=false
old-files-age=uint32 30
recent-files-max-age=7
remember-recent-files=true
remove-old-temp-files=false
remove-old-trash-files=false

[org/gnome/desktop/sound]
event-sounds=false
input-feedback-sounds=false
theme-name='LinuxMint'

[org/gnome/desktop/wm/preferences]
action-double-click-titlebar='toggle-maximize'
action-middle-click-titlebar='lower'
action-right-click-titlebar='menu'
audible-bell=false
auto-raise=false
auto-raise-delay=500
button-layout=':minimize,maximize,close'
disable-workarounds=false
focus-mode='click'
focus-new-windows='smart'
mouse-button-modifier='<Alt>'
num-workspaces=4
raise-on-click=true
resize-with-right-button=true
theme='Mint-Y'
titlebar-font='Ubuntu Medium 10'
titlebar-uses-system-font=false
visual-bell=false
visual-bell-type='fullscreen-flash'
workspace-names=@as []

[org/gnome/evolution-data-server]
migrated=true

[org/gnome/file-roller/listing]
show-path=false

[org/gnome/settings-daemon/plugins/xsettings]
disabled-gtk-modules=@as []
enabled-gtk-modules=@as []
overrides=@a{sv} {}

[org/gnome/terminal/legacy/profiles:]
list=['b1dcc9dd-5262-4d8d-a863-c897e6d979b9']

[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]
audible-bell=true
background-transparency-percent=21
bold-color='rgb(104,16,16)'
bold-color-same-as-fg=false
cursor-background-color='rgb(112,229,0)'
cursor-blink-mode='on'
cursor-colors-set=true
cursor-foreground-color='rgb(212,255,0)'
cursor-shape='block'
foreground-color='rgb(19,109,207)'
highlight-colors-set=true
highlight-foreground-color='rgb(193,49,184)'
palette=['rgb(0,0,0)', 'rgb(205,0,0)', 'rgb(0,205,0)', 'rgb(205,205,0)', 'rgb(0,0,238)', 'rgb(172,37,172)', 'rgb(0,205,205)', 'rgb(229,229,229)', 'rgb(127,127,127)', 'rgb(255,0,0)', 'rgb(0,255,0)', 'rgb(255,255,0)', 'rgb(92,92,255)', 'rgb(255,0,255)', 'rgb(0,255,255)', 'rgb(255,255,255)']
use-theme-colors=false
use-theme-transparency=false
use-transparent-background=true
visible-name='xd'

[org/gtk/settings/color-chooser]
custom-colors=[(0.4387943262411349, 0.89666666666666672, 0.0, 1.0), (0.82978723404255317, 1.0, 0.0, 1.0), (0.23921568627450981, 0.792156862745098, 0.090196078431372548, 1.0), (0.240156634304207, 0.79333333333333333, 0.089911111111111081, 1.0), (0.20392156862745098, 0.52156862745098043, 0.11764705882352941, 1.0), (0.1803921568627451, 0.20392156862745098, 0.21176470588235294, 1.0), (0.80392156862745101, 0.80392156862745101, 0.0, 1.0), (0.67333333333333334, 0.1458888888888889, 0.67333333333333334, 1.0)]
selected-color=(true, 0.4387943262411349, 0.89666666666666672, 0.0, 1.0)

[org/gtk/settings/file-chooser]
date-format='regular'
location-mode='path-bar'
show-hidden=false
show-size-column=true
show-type-column=true
sidebar-width=167
sort-column='name'
sort-directories-first=true
sort-order='ascending'
type-format='category'
window-position=(0, 0)
window-size=(1096, 745)

[org/nemo/preferences]
confirm-trash=false
disable-menu-warning=true
enable-delete=false
show-hidden-files=true

[org/nemo/window-state]
geometry='800x556+263+73'
maximized=false
side-pane-view='places'
sidebar-bookmark-breakpoint=5
start-with-menu-bar=false
start-with-sidebar=true

[org/x/apps/portal]
color-scheme='default'

[org/x/editor/plugins]
active-plugins=['sort', 'bracketcompletion', 'textsize', 'spell', 'filebrowser', 'joinlines', 'docinfo', 'modelines', 'time', 'open-uri-context-menu']

[org/x/editor/preferences/ui]
statusbar-visible=true

[org/x/editor/state/window]
bottom-panel-size=140
side-panel-active-page=-1725528251
side-panel-size=200
size=(650, 500)
state=87168

[org/x/warpinator/preferences]
ask-for-send-permission=true
autostart=false
connect-id=':0'
no-overwrite=true
DCONF_EOF
fi

show_progress 9 $TOTAL_STEPS "$MSG_PHASE_4"

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    AVATAR_DEST="/var/lib/AccountsService/icons/$CURRENT_USER"
    sudo mkdir -p "$(dirname "$AVATAR_DEST")" || true
    sudo cp -af "$SCRIPT_DIR/piwo.png" "$AVATAR_DEST" || true
    sudo chmod 644 "$AVATAR_DEST" || true

    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"
    if [[ -f "$ACCOUNTS_FILE" ]]; then
        if sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
            sudo sed -i "s|^Icon=.*|Icon=$AVATAR_DEST|" "$ACCOUNTS_FILE" || true
        elif sudo grep -q "^\[User\]" "$ACCOUNTS_FILE"; then
            sudo sed -i "/^\[User\]/a Icon=$AVATAR_DEST" "$ACCOUNTS_FILE" || true
        else
            echo "Icon=$AVATAR_DEST" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null
        fi
    else
        echo -e "[User]\nIcon=$AVATAR_DEST" | sudo tee "$ACCOUNTS_FILE" > /dev/null
    fi
fi

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_4"

# ==========================================================
# 3b. TAPETA EKRANU LOGOWANIA (LIGHTDM / SLICK-GREETER)
# ==========================================================
if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    show_progress 11 $TOTAL_STEPS "$MSG_PHASE_5"

    LOGIN_BG_DIR="/usr/share/backgrounds/custom"
    LOGIN_BG_DEST="$LOGIN_BG_DIR/login-wallpaper.png"

    sudo mkdir -p "$LOGIN_BG_DIR" || true
    sudo cp -af "$SCRIPT_DIR/login-wallpaper.png" "$LOGIN_BG_DEST" || true
    sudo chmod 644 "$LOGIN_BG_DEST" || true

    if [[ -d /etc/lightdm ]] || command -v lightdm &>/dev/null; then
        sudo mkdir -p /etc/lightdm/slick-greeter.conf.d || true
        SLICK_CONF="/etc/lightdm/slick-greeter.conf"
        sudo touch "$SLICK_CONF"

        if sudo grep -q "^\[Greeter\]" "$SLICK_CONF" 2>/dev/null; then
            if sudo grep -q "^background=" "$SLICK_CONF"; then
                sudo sed -i "s|^background=.*|background=$LOGIN_BG_DEST|" "$SLICK_CONF" || true
            else
                sudo sed -i "/^\[Greeter\]/a background=$LOGIN_BG_DEST" "$SLICK_CONF" || true
            fi
            if sudo grep -q "^draw-user-backgrounds=" "$SLICK_CONF"; then
                sudo sed -i "s|^draw-user-backgrounds=.*|draw-user-backgrounds=false|" "$SLICK_CONF" || true
            else
                sudo sed -i "/^\[Greeter\]/a draw-user-backgrounds=false" "$SLICK_CONF" || true
            fi
        else
            {
                echo "[Greeter]"
                echo "background=$LOGIN_BG_DEST"
                echo "draw-user-backgrounds=false"
            } | sudo tee -a "$SLICK_CONF" > /dev/null
        fi
    fi
fi

# ==========================================================
# 4. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo rm -f "$RUN0_NOPASSWD_FILE"
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    sudo rm -f /etc/sudoers.d/99-temp-installer
fi

show_progress 12 $TOTAL_STEPS "$MSG_PHASE_5"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA WIZUALNA ZAKOŃCZONA!${NC}" >&3
else
    echo -e "${SUCCESS}✔ VISUAL CONFIGURATION COMPLETED!${NC}" >&3
fi

systemctl reboot

#!/usr/bin/env bash
# ==========================================================
# SKRYPT KONFIGURACJI WIZUALNEJ CINNAMON
# ==========================================================

set -Eeuo pipefail

FAILED_PACKAGES=()
FAILED_SPICES=()
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
    set +e
    trap - ERR
    declare -F restore_packagekit >/dev/null && restore_packagekit || true
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ] || [ "${#FAILED_PACKAGES[@]}" -gt 0 ] || [ "${#FAILED_SPICES[@]}" -gt 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [ "$exit_code" -ne 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}[X] Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${ERR}[X] An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
            fi
        elif [ "${#FAILED_PACKAGES[@]}" -gt 0 ] && [ "${#FAILED_SPICES[@]}" -gt 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}[!] Niektóre pakiety oraz aplety/rozszerzenia nie zostały zainstalowane. Log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${WARN}[!] Some packages and applets/extensions failed to install. Log saved to: $LOG_FILE${NC}" >&3
            fi
        elif [ "${#FAILED_PACKAGES[@]}" -gt 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}[!] Niektóre pakiety nie zostały zainstalowane. Log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${WARN}[!] Some packages failed to install. Log saved to: $LOG_FILE${NC}" >&3
            fi
        else
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}[!] Niektóre aplety/rozszerzenia nie zostały pobrane. Log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${WARN}[!] Some applets/extensions failed to download. Log saved to: $LOG_FILE${NC}" >&3
            fi
        fi
    fi
    rm -f "$TMP_LOG"
    local do_reboot=0
    [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ] && do_reboot=1
    if [ "${SUDO_READY:-0}" = "1" ]; then
        sudo sh -c 'rm -f "$1" "$2"; systemctl try-restart polkit 2>/dev/null || true; if [ "$3" = 1 ]; then systemctl reboot 2>/dev/null || reboot; fi' _ \
            "${RUN0_NOPASSWD_FILE:-/etc/polkit-1/rules.d/51-run0-nopasswd.rules}" \
            "/etc/sudoers.d/99-temp-installer" \
            "$do_reboot" || true
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() {
    echo -e "$1"
    printf '\r\033[K%b\n' "$1" >&3
    cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
}
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}[OK] $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}[X] ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}[!] WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

# ==========================================================
# PACKAGEKIT + BLOKADA MENEDŻERA PAKIETÓW
# ==========================================================
PACKAGEKIT_MASKED=0
PACKAGEKIT_UNITS=(packagekit.service packagekit-offline-update.service)

disable_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] && return 0
    sudo systemctl stop "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    if command -v killall >/dev/null 2>&1; then
        sudo killall -q packagekitd 2>/dev/null || true
    else
        sudo pkill -x packagekitd 2>/dev/null || true
    fi
    sudo systemctl mask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=1
}

restore_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] || return 0
    sudo systemctl unmask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=0
}

_pkg_lock_busy() {
    local f
    for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock \
             /run/zypp.pid /var/run/zypp.pid /var/lib/pacman/db.lck \
             /var/cache/dnf/metadata_lock.pid /var/lib/rpm/.rpm.lock; do
        [[ -e "$f" ]] || continue
        sudo fuser "$f" >/dev/null 2>&1 && return 0
    done
    pgrep -x 'apt|apt-get|dpkg|zypper|pacman|dnf|dnf5|xbps-install|packagekitd' >/dev/null 2>&1 && return 0
    return 1
}

wait_for_pkg_lock() {
    local timeout="${1:-300}" waited=0
    disable_packagekit
    while _pkg_lock_busy; do
        if (( waited >= timeout )); then
            log_warn "Blokada menedżera pakietów trwa ponad ${timeout}s - kontynuuję mimo to." \
                     "Package manager lock held for over ${timeout}s - continuing anyway."
            break
        fi
        sleep 3
        waited=$(( waited + 3 ))
    done
}

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(stty size </dev/tty 2>/dev/null || true)
    cols="${cols##* }"
    [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 )) || cols=80

    local bar_width=50
    local reserved=14
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 3))}..."
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
    MSG_PREP="[1/4] Przygotowywanie..."
    MSG_INSTALL="[2/4] Instalacja..."
    MSG_OPTIMIZE="[3/4] Optymalizacja..."
    MSG_FINALIZE="[4/4] Finalizowanie..."
else
    MSG_PREP="[1/4] Preparing..."
    MSG_INSTALL="[2/4] Installation..."
    MSG_OPTIMIZE="[3/4] Optimization..."
    MSG_FINALIZE="[4/4] Finalizing..."
fi

TOTAL_STEPS=12

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
USER_PICTURES="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallpaper_PATH="$USER_PICTURES/wallpaper.jpg"

if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}[X] Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    else
        echo -e "${ERR}[X] Do not run this script as root. Run as a normal user with sudo.${NC}" >&3
    fi
    exit 1
fi

# ==========================================================
# 1. WSTĘPNE SPRAWDZENIA I UPRAWNIENIA
# ==========================================================
RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if command -v run0 >/dev/null 2>&1; then
    if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
        USE_RUN0=1
    fi
fi

printf '\033[?7h' >&3
SUDO_READY=0
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo mkdir -p "$(dirname "$RUN0_NOPASSWD_FILE")"
    sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null <<POLKIT_RULE_EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$CURRENT_USER") {
        return polkit.Result.YES;
    }
});
POLKIT_RULE_EOF
    sudo systemctl try-restart polkit 2>/dev/null || true
    SUDO_READY=1
else
    sudo -v

    (
        set +e
        trap - ERR
        while true; do
            sudo -n true
            sleep 60
            kill -0 "$$" 2>/dev/null || exit
        done
    ) &
    SUDO_KEEPALIVE_PID=$!

    if command -v visudo >/dev/null 2>&1; then
        SUDOERS_TMP="$(mktemp)"
        echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
        if sudo visudo -cf "$SUDOERS_TMP" &>/dev/null; then
            sudo mkdir -p /etc/sudoers.d
            sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
        else
            rm -f "$SUDOERS_TMP"
            log_err "Nieprawidłowa składnia reguły sudoers." "Invalid sudoers rule syntax."
            exit 1
        fi
        rm -f "$SUDOERS_TMP"
    fi
    SUDO_READY=1
fi

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"

# ==========================================================
# 2. WYKRYWANIE DYSTRYBUCJI I INSTALACJA PAKIETÓW
# ==========================================================
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_LIKE="${ID:-} ${ID_LIKE:-}"
        OS_LIKE="${OS_LIKE,,}"
    else
        OS="unknown"
        OS_LIKE=""
    fi
}

install_cinnamon_packages() {
    wait_for_pkg_lock
    if [[ "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
        sudo apt-get update -yq || true
        for pkg in cinnamon-control-center dconf-cli; do
            sudo apt-get install -yq "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"fedora"* ]]; then
        for pkg in cinnamon-control-center dconf; do
            sudo dnf install -yq "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"arch"* ]]; then
        for pkg in cinnamon-control-center dconf; do
            sudo pacman -S --noconfirm --needed "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"suse"* ]]; then
        for pkg in cinnamon-control-center dconf; do
            sudo zypper -nq install -y "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"void"* ]]; then
        sudo xbps-install -Suy xbps || true
        for pkg in dbus elogind NetworkManager network-manager-applet pulseaudio-utils rtkit btop xorg-minimal mesa-dri xorg-server-xwayland gnome-terminal lightdm lightdm-gtk3-greeter cinnamon cinnamon-control-center fontconfig font-adobe-source-sans-pro font-util liberation-fonts-ttf ttf-ubuntu-font-family font-awesome dejavu-fonts-ttf noto-fonts-ttf noto-fonts-emoji adwaita-icon-theme xdg-user-dirs pavucontrol pix xed xreader xviewer ffmpegthumbnailer poppler-glib tumbler engrampa gvfs gvfs-afc gvfs-smb udisks2 polkit-gnome dconf; do
            sudo xbps-install -y "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    else
        log_warn "Nierozpoznana dystrybucja ($OS) - pomijam instalację pakietów Cinnamon. Zainstaluj ręcznie: cinnamon-control-center, dconf-cli/dconf." \
                 "Unrecognized distribution ($OS) - skipping Cinnamon package installation. Install manually: cinnamon-control-center, dconf-cli/dconf."
        FAILED_PACKAGES+=(cinnamon-control-center dconf)
    fi
}

# ==========================================================
# 2b. ZALEŻNOŚCI I INSTALACJA APLETÓW/ROZSZERZEŃ (CINNAMON SPICES)
# ==========================================================
install_spices_dependencies() {
    wait_for_pkg_lock
    local pkg
    if [[ "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
        for pkg in curl unzip; do
            sudo apt-get install -yq "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"fedora"* ]]; then
        for pkg in curl unzip; do
            sudo dnf install -yq "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"arch"* ]]; then
        for pkg in curl unzip; do
            sudo pacman -S --noconfirm --needed "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"suse"* ]]; then
        for pkg in curl unzip; do
            sudo zypper -nq install -y "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    elif [[ "$OS_LIKE" == *"void"* ]]; then
        for pkg in curl unzip; do
            sudo xbps-install -y "$pkg" || FAILED_PACKAGES+=("$pkg")
        done
    fi
}

CINNAMON_APPLETS=(
    "download-and-upload-speed@cardsurf"
    "ScreenShot@tech71"
    "sticky@scollins"
    "weather@mockturtl"
    "spicy-clipboard-applet@Twilight0"
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

    if curl -fsSL "$url" -o "$tmp_zip" && unzip -oq "$tmp_zip" -d "$dest_dir"; then
        :
    else
        FAILED_SPICES+=("$uuid")
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
disable_packagekit
show_progress 1 $TOTAL_STEPS "$MSG_INSTALL"

install_cinnamon_packages
show_progress 2 $TOTAL_STEPS "$MSG_INSTALL"

install_all_cinnamon_spices
show_progress 3 $TOTAL_STEPS "$MSG_INSTALL"

# ==========================================================
# 3. KONFIGURACJA WIZUALNA CINNAMON
# ==========================================================
show_progress 4 $TOTAL_STEPS "$MSG_OPTIMIZE"

restore_packagekit

safe_copy_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]] && [[ "$(realpath "$src" 2>/dev/null)" != "$(realpath "$dst" 2>/dev/null)" ]]; then
        mkdir -p "$dst" 2>/dev/null || return 0
        cp -af "$src/." "$dst/" 2>/dev/null || true
    fi
    return 0
}

safe_copy_dir "$SCRIPT_DIR/.config" "$HOME/.config"
safe_copy_dir "$SCRIPT_DIR/.local" "$HOME/.local"
safe_copy_dir "$SCRIPT_DIR/.icons" "$HOME/.icons"
safe_copy_dir "$SCRIPT_DIR/.themes" "$HOME/.themes"

if [[ -f "$SCRIPT_DIR/wallpaper.jpg" ]]; then
    mkdir -p "$(dirname "$wallpaper_PATH")" 2>/dev/null || true
    cp -af "$SCRIPT_DIR/wallpaper.jpg" "$wallpaper_PATH" 2>/dev/null || true
fi
chmod 644 "$wallpaper_PATH" 2>/dev/null || true

show_progress 5 $TOTAL_STEPS "$MSG_OPTIMIZE"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    SESSION_PID=$(pgrep -u "$CURRENT_USER" cinnamon-session | head -n 1 || true)
    if [[ -n "$SESSION_PID" ]]; then
        DBUS_ADDR_FROM_ENVIRON="$(grep -z DBUS_SESSION_BUS_ADDRESS "/proc/$SESSION_PID/environ" 2>/dev/null | tr '\0' '\n' | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2- || true)"
        [[ -n "$DBUS_ADDR_FROM_ENVIRON" ]] && export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR_FROM_ENVIRON"
    fi
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    RUNTIME_DIR="/run/user/$(id -u "$CURRENT_USER" 2>/dev/null || id -u)"
    if [[ -S "$RUNTIME_DIR/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"
    fi
fi

DBUS_WRAP=()
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v dbus-run-session >/dev/null 2>&1; then
    DBUS_WRAP=(dbus-run-session --)
fi

if command -v gsettings >/dev/null 2>&1; then
    ${DBUS_WRAP[@]+"${DBUS_WRAP[@]}"} gsettings set org.cinnamon.desktop.background picture-uri "file://$wallpaper_PATH" 2>/dev/null \
        && ${DBUS_WRAP[@]+"${DBUS_WRAP[@]}"} gsettings set org.cinnamon.desktop.background picture-options "zoom" 2>/dev/null || true
fi

show_progress 6 $TOTAL_STEPS "$MSG_OPTIMIZE"

ENABLED_APPLETS_LIST=(
    "'panel1:left:0:menu@cinnamon.org:0'"
    "'panel1:left:1:separator@cinnamon.org:1'"
    "'panel1:left:2:grouped-window-list@cinnamon.org:2'"
    "'panel1:right:3:systray@cinnamon.org:3'"
    "'panel1:right:4:xapp-status@cinnamon.org:4'"
    "'panel1:right:5:notifications@cinnamon.org:5'"
    "'panel1:right:6:printers@cinnamon.org:6'"
    "'panel1:right:7:removable-drives@cinnamon.org:7'"
    "'panel1:right:8:keyboard@cinnamon.org:8'"
    "'panel1:right:9:favorites@cinnamon.org:9'"
    "'panel1:right:10:network@cinnamon.org:10'"
    "'panel1:right:11:sound@cinnamon.org:11'"
    "'panel1:right:12:power@cinnamon.org:12'"
    "'panel1:right:14:calendar@cinnamon.org:13'"
    "'panel1:right:18:cornerbar@cinnamon.org:14'"
)
[[ -d "$HOME/.local/share/cinnamon/applets/weather@mockturtl" ]] && ENABLED_APPLETS_LIST+=("'panel1:right:15:weather@mockturtl:15'")
[[ -d "$HOME/.local/share/cinnamon/applets/sticky@scollins" ]] && ENABLED_APPLETS_LIST+=("'panel1:right:2:sticky@scollins:16'")
[[ -d "$HOME/.local/share/cinnamon/applets/download-and-upload-speed@cardsurf" ]] && ENABLED_APPLETS_LIST+=("'panel1:right:13:download-and-upload-speed@cardsurf:17'")
[[ -d "$HOME/.local/share/cinnamon/applets/ScreenShot@tech71" ]] && ENABLED_APPLETS_LIST+=("'panel1:right:17:ScreenShot@tech71:18'")
[[ -d "$HOME/.local/share/cinnamon/applets/spicy-clipboard-applet@Twilight0" ]] && ENABLED_APPLETS_LIST+=("'panel1:right:0:spicy-clipboard-applet@Twilight0:20'")

ENABLED_EXTENSIONS_LIST=()
for ext_uuid in "transparent-panels@germanfr" "compiz-windows-effect@hermes83.github.com" "CinnamonBurnMyWindows@klangman"; do
    [[ -d "$HOME/.local/share/cinnamon/extensions/$ext_uuid" ]] && ENABLED_EXTENSIONS_LIST+=("'$ext_uuid'")
done

join_dconf_array() {
    local out="" item
    for item in "$@"; do
        [[ -n "$out" ]] && out+=", "
        out+="$item"
    done
    printf '[%s]' "$out"
}

ENABLED_APPLETS_DCONF="$(join_dconf_array "${ENABLED_APPLETS_LIST[@]}")"
if [[ ${#ENABLED_EXTENSIONS_LIST[@]} -gt 0 ]]; then
    ENABLED_EXTENSIONS_DCONF="$(join_dconf_array "${ENABLED_EXTENSIONS_LIST[@]}")"
else
    ENABLED_EXTENSIONS_DCONF="@as []"
fi

if command -v dconf &>/dev/null; then
    mkdir -p "$HOME/.config/dconf"

    sed \
        -e "s|__ENABLED_APPLETS__|${ENABLED_APPLETS_DCONF}|g" \
        -e "s|__ENABLED_EXTENSIONS__|${ENABLED_EXTENSIONS_DCONF}|g" \
        <<'DCONF_EOF' | ${DBUS_WRAP[@]+"${DBUS_WRAP[@]}"} dconf load / || true
[org/cinnamon]
alttab-switcher-delay=100
desktop-effects-close='fly'
desktop-effects-map='traditional'
desktop-effects-minimize='fade'
enabled-applets=__ENABLED_APPLETS__
enabled-extensions=__ENABLED_EXTENSIONS__
next-applet-id=21
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
icon-theme='kora'
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
cursor-theme='McMojave-Cursors'
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
icon-theme='kora'
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
theme='Mojave-Dark'
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

[org/gnome/terminal/legacy]
theme-variant='dark'
default-show-menubar=false

[org/gnome/terminal/legacy/profiles:]
default='b1dcc9dd-5262-4d8d-a863-c897e6d979b9'
list=['b1dcc9dd-5262-4d8d-a863-c897e6d979b9']

[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]
audible-bell=true
background-color='rgb(0,0,0)'
background-transparency-percent=21
bold-color='rgb(104,16,16)'
bold-color-same-as-fg=false
cursor-background-color='rgb(112,229,0)'
cursor-blink-mode='on'
cursor-colors-set=true
cursor-foreground-color='rgb(12,18,234)'
cursor-shape='block'
foreground-color='rgb(20,219,138)'
highlight-colors-set=true
highlight-foreground-color='rgb(193,49,184)'
palette=['rgb(0,0,0)', 'rgb(205,0,0)', 'rgb(0,205,0)', 'rgb(205,205,0)', 'rgb(0,0,238)', 'rgb(172,37,172)', 'rgb(0,205,205)', 'rgb(229,229,229)', 'rgb(127,127,127)', 'rgb(255,0,0)', 'rgb(0,255,0)', 'rgb(255,255,0)', 'rgb(92,92,255)', 'rgb(255,0,255)', 'rgb(0,255,255)', 'rgb(255,255,255)']
use-theme-colors=false
use-theme-transparency=false
use-transparent-background=true
visible-name='user'

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

show_progress 7 $TOTAL_STEPS "$MSG_OPTIMIZE"

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    install -m 644 "$SCRIPT_DIR/piwo.png" "$HOME/.face" 2>/dev/null || true

    AVATAR_DEST="/var/lib/AccountsService/icons/$CURRENT_USER"
    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"

    sudo mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users || true
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/piwo.png" "$AVATAR_DEST" || true

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        printf '[User]\nIcon=%s\n' "$AVATAR_DEST" | sudo tee "$ACCOUNTS_FILE" > /dev/null
    elif sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
        sudo sed -i "s|^Icon=.*|Icon=$AVATAR_DEST|" "$ACCOUNTS_FILE" || true
    elif sudo grep -q "^\[User\]" "$ACCOUNTS_FILE"; then
        sudo sed -i "/^\[User\]/a Icon=$AVATAR_DEST" "$ACCOUNTS_FILE" || true
    else
        printf '\n[User]\nIcon=%s\n' "$AVATAR_DEST" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null
    fi

    sudo systemctl restart accounts-daemon 2>/dev/null || true
fi

show_progress 8 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================================
# 3b. TAPETA EKRANU LOGOWANIA (LIGHTDM: SLICK-GREETER / GTK-GREETER)
# ==========================================================
detect_lightdm_greeter() {
    local conf_files=("/etc/lightdm/lightdm.conf")
    if [[ -d /etc/lightdm/lightdm.conf.d ]]; then
        while IFS= read -r -d '' f; do
            conf_files+=("$f")
        done < <(find /etc/lightdm/lightdm.conf.d -maxdepth 1 -name '*.conf' -print0 2>/dev/null | LC_ALL=C sort -z)
    fi

    local greeter_session=""
    local f
    for f in "${conf_files[@]}"; do
        [[ -f "$f" ]] || continue
        local line
        line="$(sudo grep -E '^[[:space:]]*greeter-session[[:space:]]*=' "$f" 2>/dev/null | tail -n1 || true)"
        if [[ -n "$line" ]]; then greeter_session="${line#*=}"; fi
    done
    greeter_session="$(echo "$greeter_session" | xargs 2>/dev/null || true)"

    if [[ "$greeter_session" == *slick* ]]; then
        echo "slick"; return 0
    elif [[ "$greeter_session" == *gtk* ]]; then
        echo "gtk"; return 0
    fi

    local has_slick=0
    local has_gtk=0
    command -v slick-greeter &>/dev/null && has_slick=1 || true
    [[ -x /usr/lib/lightdm/lightdm-slick-greeter ]] && has_slick=1 || true
    command -v lightdm-gtk-greeter &>/dev/null && has_gtk=1 || true
    [[ -x /usr/lib/lightdm/lightdm-gtk-greeter ]] && has_gtk=1 || true

    if [[ "$OS_LIKE" == *"ubuntu"* || "$OS_LIKE" == *"debian"* ]]; then
        if command -v dpkg-query &>/dev/null; then
            dpkg-query -W -f='${Status}' lightdm-slick-greeter 2>/dev/null | grep -q "install ok installed" && has_slick=1 || true
            dpkg-query -W -f='${Status}' lightdm-gtk-greeter 2>/dev/null | grep -q "install ok installed" && has_gtk=1 || true
        fi
    elif [[ "$OS_LIKE" == *"fedora"* ]]; then
        if command -v rpm &>/dev/null; then
            { rpm -q slick-greeter &>/dev/null || rpm -q lightdm-settings-slick-greeter &>/dev/null; } && has_slick=1 || true
            { rpm -q lightdm-gtk &>/dev/null || rpm -q lightdm-gtk-greeter &>/dev/null; } && has_gtk=1 || true
        fi
    elif [[ "$OS_LIKE" == *"suse"* ]]; then
        if command -v rpm &>/dev/null; then
            rpm -q lightdm-slick-greeter &>/dev/null && has_slick=1 || true
            rpm -q lightdm-gtk-greeter &>/dev/null && has_gtk=1 || true
        fi
    elif [[ "$OS_LIKE" == *"arch"* ]]; then
        if command -v pacman &>/dev/null; then
            pacman -Qq lightdm-slick-greeter &>/dev/null && has_slick=1 || true
            pacman -Qq lightdm-gtk-greeter &>/dev/null && has_gtk=1 || true
        fi
    elif [[ "$OS_LIKE" == *"void"* ]]; then
        if command -v xbps-query &>/dev/null; then
            xbps-query lightdm-slick-greeter &>/dev/null && has_slick=1 || true
            xbps-query lightdm-gtk3-greeter &>/dev/null && has_gtk=1 || true
        fi
    fi

    if [[ "$has_slick" -eq 1 && "$has_gtk" -eq 0 ]]; then
        echo "slick"
    elif [[ "$has_gtk" -eq 1 && "$has_slick" -eq 0 ]]; then
        echo "gtk"
    elif [[ "$has_slick" -eq 1 && "$has_gtk" -eq 1 ]]; then
        echo "slick"
    else
        echo ""
    fi
}

set_ini_key() {
    local file="$1" section="$2" key="$3" value="$4"
    local tmp_ini
    tmp_ini="$(mktemp)"
    sudo mkdir -p "$(dirname "$file")"
    sudo touch "$file"

    sudo awk -v sec="$section" -v k="$key" -v v="$value" '
        BEGIN { in_sec = 0; found_sec = 0; updated = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            if (in_sec && !updated) {
                print k "=" v
                updated = 1
            }
            line_sec = $0
            sub(/^[[:space:]]*\[/, "", line_sec)
            sub(/\][[:space:]]*$/, "", line_sec)
            if (line_sec == sec) {
                in_sec = 1
                found_sec = 1
            } else {
                in_sec = 0
            }
            print
            next
        }
        {
            if (in_sec && $0 ~ "^[[:space:]]*" k "[[:space:]]*=") {
                if (!updated) {
                    print k "=" v
                    updated = 1
                }
                next
            }
            print
        }
        END {
            if (!found_sec) {
                if (NR > 0) print ""
                print "[" sec "]"
                print k "=" v
            } else if (in_sec && !updated) {
                print k "=" v
            }
        }
    ' "$file" > "$tmp_ini"

    sudo install -m 644 -o root -g root "$tmp_ini" "$file"
    rm -f "$tmp_ini"
}

show_progress 9 $TOTAL_STEPS "$MSG_OPTIMIZE"

if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    LOGIN_BG_DIR="/usr/share/backgrounds/custom"
    LOGIN_BG_DEST="$LOGIN_BG_DIR/login-wallpaper.png"

    sudo mkdir -p "$LOGIN_BG_DIR" || true
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/login-wallpaper.png" "$LOGIN_BG_DEST" || true

    if [[ -d /etc/lightdm ]] || command -v lightdm &>/dev/null; then
        LIGHTDM_GREETER="$(detect_lightdm_greeter)"

        configure_slick_greeter() {
            set_ini_key "/etc/lightdm/slick-greeter.conf" "Greeter" "background" "$LOGIN_BG_DEST"
            set_ini_key "/etc/lightdm/slick-greeter.conf" "Greeter" "draw-user-backgrounds" "false"
            if [[ -d /etc/lightdm/slick-greeter.conf.d ]]; then
                set_ini_key "/etc/lightdm/slick-greeter.conf.d/99-custom-wallpaper.conf" "Greeter" "background" "$LOGIN_BG_DEST"
                set_ini_key "/etc/lightdm/slick-greeter.conf.d/99-custom-wallpaper.conf" "Greeter" "draw-user-backgrounds" "false"
            fi
        }

        configure_gtk_greeter() {
            set_ini_key "/etc/lightdm/lightdm-gtk-greeter.conf" "greeter" "background" "$LOGIN_BG_DEST"
            set_ini_key "/etc/lightdm/lightdm-gtk-greeter.conf" "greeter" "user-background" "false"
        }

        case "$LIGHTDM_GREETER" in
            slick)
                configure_slick_greeter
                ;;
            gtk)
                configure_gtk_greeter
                ;;
            *)
                configure_slick_greeter
                configure_gtk_greeter
                ;;
        esac
    fi
fi

show_progress 10 $TOTAL_STEPS "$MSG_OPTIMIZE"

rm -rf "$HOME/.cache/thumbnails" 2>/dev/null || true
rm -rf "$HOME/.cache/icon-cache.kcache" 2>/dev/null || true
if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d "$HOME/.icons" ]]; then
    for theme_dir in "$HOME/.icons/"*/; do
        [[ -f "${theme_dir}index.theme" ]] && gtk-update-icon-cache -f -t "$theme_dir" >/dev/null 2>&1 || true
    done
fi

show_progress 11 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================================
# 4. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================

show_progress 12 $TOTAL_STEPS "$MSG_FINALIZE"
printf '\n\n' >&3

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    log_warn "Nie udało się zainstalować: ${FAILED_PACKAGES[*]}. Sprawdź log: $LOG_FILE" \
             "Failed to install: ${FAILED_PACKAGES[*]}. Check the log: $LOG_FILE"
fi

if [[ ${#FAILED_SPICES[@]} -gt 0 ]]; then
    log_warn "Nie udało się pobrać apletów/rozszerzeń: ${FAILED_SPICES[*]}. Sprawdź log: $LOG_FILE" \
             "Failed to download applets/extensions: ${FAILED_SPICES[*]}. Check the log: $LOG_FILE"
fi

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}[OK] KONFIGURACJA WIZUALNA ZAKOŃCZONA!${NC}" >&3
else
    echo -e "${SUCCESS}[OK] VISUAL CONFIGURATION COMPLETED!${NC}" >&3
fi

if [[ "$OS_LIKE" == *"void"* ]]; then
    for svc in dhcpcd wpa_supplicant; do
        if [[ -L "/var/service/$svc" ]]; then
            sudo rm -f "/var/service/$svc" || true
        fi
    done
    for svc in dbus elogind NetworkManager lightdm; do
        if [[ -d "/etc/sv/$svc" && ! -e "/var/service/$svc" ]]; then
            sudo ln -s "/etc/sv/$svc" "/var/service/$svc" || true
        fi
    done
fi

DO_REBOOT=1
exit 0

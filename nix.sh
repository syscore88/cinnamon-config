#!/usr/bin/env bash
# ==========================================
# SKRYPT KONFIGURACJI WIZUALNEJ CINNAMON (NixOS)
# ==========================================

set -Eeuo pipefail

FAILED_SPICES=()

# ==========================================
# 1. WYKRYWANIE JĘZYKA SYSTEMU I ZMIENNE
# ==========================================
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
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ] || [ "${#FAILED_SPICES[@]}" -gt 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [ "$exit_code" -ne 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
            fi
        else
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${WARN}⚠ Niektóre aplety/rozszerzenia nie zostały pobrane. Log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${WARN}⚠ Some applets/extensions failed to download. Log saved to: $LOG_FILE${NC}" >&3
            fi
        fi
    fi
    rm -f "$TMP_LOG"
    local do_reboot=0
    [ "$exit_code" -eq 0 ] && [ "${DO_REBOOT:-0}" = "1" ] && do_reboot=1
    if [ "${SUDO_READY:-0}" = "1" ]; then
        sudo sh -c 'rm -f "$1" "$2"; systemctl try-restart polkit 2>/dev/null; [ "$3" = 1 ] && systemctl reboot' _ \
            "${RUN0_NOPASSWD_FILE:-/etc/polkit-1/rules.d/51-run0-nopasswd.rules}" \
            "/etc/sudoers.d/99-temp-installer" \
            "$do_reboot"
    fi
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() {
    echo -e "$1"
    echo -e "$1" >&3
}
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}⚠ WARN: $m${NC}"; }

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
    MSG_PREP="Przygotowywanie..."
    MSG_INSTALL="Instalacja..."
    MSG_OPTIMIZE="Optymalizacja..."
    MSG_FINALIZE="Finalizowanie..."
else
    MSG_PREP="Preparing..."
    MSG_INSTALL="Installation..."
    MSG_OPTIMIZE="Optimization..."
    MSG_FINALIZE="Finalizing..."
fi

TOTAL_STEPS=8

CURRENT_USER=$(whoami)
USER_PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallpaper_PATH="$USER_PICTURES_DIR/wallpaper.jpg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# WALIDACJA UŻYTKOWNIKA
if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    else
        echo -e "${ERR}✘ Do not run this script as root. Run as a normal user with sudo.${NC}" >&3
    fi
    exit 1
fi

# ==========================================
# 2. UPRAWNIENIA TYMCZASOWE (SUDO / POLKIT)
# ==========================================
RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1; then
    USE_RUN0=1
elif command -v run0 >/dev/null 2>&1 && sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

printf '\033[?7h' >&3
SUDO_READY=0
if [[ "$USE_RUN0" -eq 1 ]]; then
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

    SUDOERS_TMP="$(mktemp)"
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
        sudo mkdir -p /etc/sudoers.d
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
    else
        rm -f "$SUDOERS_TMP"
        log_err "Nieprawidłowa składnia reguły sudoers - przerywam." "Invalid sudoers rule syntax - aborting."
        exit 1
    fi
    rm -f "$SUDOERS_TMP"
    SUDO_READY=1
fi

printf '\033[?7l' >&3

show_progress 0 $TOTAL_STEPS "$MSG_PREP"

# ==========================================
# 3. KONFIGURACJA SYSTEMOWA (NIXOS)
# ==========================================
NIXOS_DIR="/etc/nixos"
NIXOS_CONF="$NIXOS_DIR/configuration.nix"
CINNAMON_MODULE="$NIXOS_DIR/cinnamon-visual.nix"

if [[ ! -f "$NIXOS_CONF" ]]; then
    log_err "Nie znaleziono $NIXOS_CONF." "$NIXOS_CONF not found."
    exit 1
fi

if [[ -f "$SCRIPT_DIR/piwo.png" ]]; then
    cp -af "$SCRIPT_DIR/piwo.png" "$HOME/.face" 2>/dev/null || true
    chmod 644 "$HOME/.face" 2>/dev/null || true

    AVATAR_DEST="/var/lib/AccountsService/icons/$CURRENT_USER"
    ACCOUNTS_FILE="/var/lib/AccountsService/users/$CURRENT_USER"

    sudo mkdir -p /var/lib/AccountsService/icons/ /var/lib/AccountsService/users/ || true
    sudo cp -f "$SCRIPT_DIR/piwo.png" "$AVATAR_DEST" || true
    sudo chmod 644 "$AVATAR_DEST" || true

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        echo -e "[User]\nIcon=$AVATAR_DEST" | sudo tee "$ACCOUNTS_FILE" > /dev/null
    elif sudo grep -q "^Icon=" "$ACCOUNTS_FILE"; then
        sudo sed -i "s|^Icon=.*|Icon=$AVATAR_DEST|" "$ACCOUNTS_FILE" || true
    elif sudo grep -q "^\[User\]" "$ACCOUNTS_FILE"; then
        sudo sed -i "/^\[User\]/a Icon=$AVATAR_DEST" "$ACCOUNTS_FILE" || true
    else
        echo "Icon=$AVATAR_DEST" | sudo tee -a "$ACCOUNTS_FILE" > /dev/null
    fi

    sudo systemctl restart accounts-daemon 2>/dev/null || true
fi

LOGIN_WALLPAPER_NIX="# brak"
if [[ -f "$SCRIPT_DIR/login-wallpaper.png" ]]; then
    sudo install -m 644 -o root -g root "$SCRIPT_DIR/login-wallpaper.png" "$NIXOS_DIR/login-wallpaper.png"
    LOGIN_WALLPAPER_NIX='services.xserver.displayManager.lightdm.background = lib.mkForce ./login-wallpaper.png;

  services.xserver.displayManager.lightdm.greeters.slick.extraConfig = '"''"'
    background=${./login-wallpaper.png}
    draw-user-backgrounds=false
  '"''"';'
fi

CINNAMON_MODULE_TMP="$(mktemp)"
cat > "$CINNAMON_MODULE_TMP" <<NIX_EOF
{ config, pkgs, lib, ... }:

let
  packageNames = [
    "cinnamon-control-center"
    "dconf"
    "curl"
    "unzip"
  ];
  try = v: let r = builtins.tryEval v; in if r.success then r.value else null;
  lookup = n:
    let
      top = try (pkgs.\${n} or null);
      sub = try (pkgs.cinnamon.\${n} or null);
    in
      if lib.isDerivation top then top
      else if lib.isDerivation sub then sub
      else null;
  usable = p: p != null && !(p.meta.broken or false);
in
{
  environment.systemPackages = lib.filter usable (map lookup packageNames);

  programs.dconf.enable = lib.mkDefault true;

  $LOGIN_WALLPAPER_NIX
}
NIX_EOF

sudo install -m 644 -o root -g root "$CINNAMON_MODULE_TMP" "$CINNAMON_MODULE"
rm -f "$CINNAMON_MODULE_TMP"

sudo cp -f "$NIXOS_CONF" "$NIXOS_CONF.bak"
if ! sudo grep -q "cinnamon-visual.nix" "$NIXOS_CONF"; then
    if sudo grep -q "\./hardware-configuration\.nix" "$NIXOS_CONF"; then
        sudo sed -i 's|\./hardware-configuration\.nix|& ./cinnamon-visual.nix|' "$NIXOS_CONF"
    else
        log_err "Nie można dodać ./cinnamon-visual.nix do imports w $NIXOS_CONF - dodaj ręcznie." \
                "Cannot add ./cinnamon-visual.nix to imports in $NIXOS_CONF - add it manually."
        exit 1
    fi
fi

show_progress 1 $TOTAL_STEPS "$MSG_INSTALL"

if ! sudo nixos-rebuild switch; then
    sudo cp -f "$NIXOS_CONF.bak" "$NIXOS_CONF"
    log_err "nixos-rebuild nie powiódł się - przywrócono configuration.nix." "nixos-rebuild failed - configuration.nix restored."
    exit 1
fi

show_progress 2 $TOTAL_STEPS "$MSG_INSTALL"

# ==========================================================
# 3b. INSTALACJA APLETÓW/ROZSZERZEŃ (CINNAMON SPICES)
# ==========================================================
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

for uuid in "${CINNAMON_APPLETS[@]}"; do
    install_cinnamon_spice "applets" "$uuid"
done

for uuid in "${CINNAMON_EXTENSIONS[@]}"; do
    install_cinnamon_spice "extensions" "$uuid"
done

if [[ ${#FAILED_SPICES[@]} -gt 0 ]]; then
    log_warn "Nie udało się pobrać apletów/rozszerzeń: ${FAILED_SPICES[*]}. Sprawdź log: $LOG_FILE" \
             "Failed to download applets/extensions: ${FAILED_SPICES[*]}. Check the log: $LOG_FILE"
fi

show_progress 3 $TOTAL_STEPS "$MSG_INSTALL"

# ==========================================
# 4. KOPIOWANIE PLIKÓW KONFIGURACYJNYCH
# ==========================================
safe_copy_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]] && [[ "$(realpath "$src" 2>/dev/null)" != "$(realpath "$dst" 2>/dev/null)" ]]; then
        mkdir -p "$dst" 2>/dev/null || return 0
        cp -af "$src/." "$dst/" 2>/dev/null || true
    fi
    return 0
}

safe_copy_dir "$SCRIPT_DIR/.config" ~/.config
safe_copy_dir "$SCRIPT_DIR/.local" ~/.local
safe_copy_dir "$SCRIPT_DIR/.icons" ~/.icons
safe_copy_dir "$SCRIPT_DIR/.themes" ~/.themes

if [[ -f "$SCRIPT_DIR/wallpaper.jpg" ]]; then
    mkdir -p "$(dirname "$wallpaper_PATH")" 2>/dev/null
    cp -af "$SCRIPT_DIR/wallpaper.jpg" "$wallpaper_PATH" 2>/dev/null || true
fi

show_progress 4 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================
# 5. KONFIGURACJA WIZUALNA CINNAMON
# ==========================================
chmod 644 "$wallpaper_PATH" 2>/dev/null || true

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    SESSION_PID=$(pgrep -u "$CURRENT_USER" cinnamon-session | head -n 1 || true)
    if [[ -n "$SESSION_PID" ]]; then
        DBUS_ADDR_FROM_ENVIRON="$(grep -z DBUS_SESSION_BUS_ADDRESS "/proc/$SESSION_PID/environ" 2>/dev/null | tr '\0' '\n' | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2- || true)"
        export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR_FROM_ENVIRON"
    fi
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    RUNTIME_DIR="/run/user/$(id -u "$CURRENT_USER" 2>/dev/null || id -u)"
    if [[ -S "$RUNTIME_DIR/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"
    fi
fi

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.cinnamon.desktop.background picture-uri "file://$wallpaper_PATH" 2>/dev/null \
        && gsettings set org.cinnamon.desktop.background picture-options "zoom" 2>/dev/null || true
fi

show_progress 5 $TOTAL_STEPS "$MSG_OPTIMIZE"

if command -v dconf >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/dconf"

    dconf load / <<'DCONF_EOF' || true
[org/cinnamon]
alttab-switcher-delay=100
desktop-effects-close='fly'
desktop-effects-map='traditional'
desktop-effects-minimize='fade'
enabled-applets=['panel1:left:0:menu@cinnamon.org:0', 'panel1:left:1:separator@cinnamon.org:1', 'panel1:left:2:grouped-window-list@cinnamon.org:2', 'panel1:right:3:systray@cinnamon.org:3', 'panel1:right:4:xapp-status@cinnamon.org:4', 'panel1:right:5:notifications@cinnamon.org:5', 'panel1:right:6:printers@cinnamon.org:6', 'panel1:right:7:removable-drives@cinnamon.org:7', 'panel1:right:8:keyboard@cinnamon.org:8', 'panel1:right:9:favorites@cinnamon.org:9', 'panel1:right:10:network@cinnamon.org:10', 'panel1:right:11:sound@cinnamon.org:11', 'panel1:right:12:power@cinnamon.org:12', 'panel1:right:14:calendar@cinnamon.org:13', 'panel1:right:18:cornerbar@cinnamon.org:14', 'panel1:right:15:weather@mockturtl:15', 'panel1:right:2:sticky@scollins:16', 'panel1:right:13:download-and-upload-speed@cardsurf:17', 'panel1:right:17:ScreenShot@tech71:18', 'panel1:right:0:spicy-clipboard-applet@Twilight0:20']
enabled-extensions=['transparent-panels@germanfr', 'compiz-windows-effect@hermes83.github.com', 'CinnamonBurnMyWindows@klangman']
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

[org/gnome/terminal/legacy]
theme-variant='dark'
default-show-menubar=false

[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]
background-color='rgb(0,0,0)'
cursor-colors-set=true
cursor-foreground-color='rgb(12,18,234)'
foreground-color='rgb(20,219,138)'
use-theme-colors=false
visible-name='user'

[org/x/warpinator/preferences]
ask-for-send-permission=true
autostart=false
connect-id=':0'
no-overwrite=true
DCONF_EOF
fi

show_progress 6 $TOTAL_STEPS "$MSG_OPTIMIZE"

rm -rf "$HOME/.cache/thumbnails" 2>/dev/null || true
rm -rf "$HOME/.cache/icon-cache.kcache" 2>/dev/null || true
if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d "$HOME/.icons" ]]; then
    for theme_dir in "$HOME/.icons/"*/; do
        [[ -f "${theme_dir}index.theme" ]] && gtk-update-icon-cache -f -t "$theme_dir" >/dev/null 2>&1 || true
    done
fi

show_progress 7 $TOTAL_STEPS "$MSG_OPTIMIZE"

# ==========================================
# 6. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================
show_progress 8 $TOTAL_STEPS "$MSG_FINALIZE"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA WIZUALNA ZAKOŃCZONA!${NC}" >&3
else
    echo -e "${SUCCESS}✔ VISUAL CONFIGURATION COMPLETED!${NC}" >&3
fi

DO_REBOOT=1
exit 0

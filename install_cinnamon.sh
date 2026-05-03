#!/bin/sh
# ==============================================================================
# PROJECT MODERN-BSD : FreeBSD 15 + Cinnamon + NVIDIA (Master Auto-Installer)
# EDITION      : Ultimate (English/Universal)
# INCLUDES     : ZFS Boot Environments, Doas, Qt/GTK Bridge, CPU Microcodes
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

BACKTITLE="FreeBSD 15 Universal Workstation Installer"

# ==============================================================================
# BLOCK 1: DISCLAIMER & INTERACTIVE MENUS
# ==============================================================================

show_disclaimer() {
    local msg="DISCLAIMER OF LIABILITY\n\n\
This script deeply modifies the configuration of your FreeBSD system. \
It is provided 'as is', without any express or implied warranty. \
By using it, you agree that the author cannot be held responsible \
for any data loss, system failure, or other damage.\n\n\
Do you accept these terms to continue?"

    if ! bsddialog --backtitle "$BACKTITLE" --title "Warning & Disclaimer" --yesno "$msg" 14 75; then
        clear
        echo "Installation cancelled by the user. No changes were made."
        exit 1
    fi
}

# Run the disclaimer first
show_disclaimer

SYS_KBD=$(sysrc -n keymap 2>/dev/null | grep -Eo '^[a-z]{2}' || echo "us")
DEFAULT_LANG="en_US.UTF-8"
DEFAULT_X11_KBD="us"

case "$SYS_KBD" in
    fr) DEFAULT_LANG="fr_FR.UTF-8"; DEFAULT_X11_KBD="fr" ;;
    ch) DEFAULT_LANG="fr_CH.UTF-8"; DEFAULT_X11_KBD="ch-fr" ;;
    de) DEFAULT_LANG="de_DE.UTF-8"; DEFAULT_X11_KBD="de" ;;
esac

USER_LOCALE=$(bsddialog --backtitle "$BACKTITLE" --title "Language & Region" --default-item "$DEFAULT_LANG" --menu "Select System Language:" 15 60 8 \
    "en_US.UTF-8" "English (US)" \
    "en_GB.UTF-8" "English (UK)" \
    "fr_FR.UTF-8" "French (France)" \
    "fr_CH.UTF-8" "French (Switzerland)" \
    "de_DE.UTF-8" "German (Germany)" \
    "de_CH.UTF-8" "German (Switzerland)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; exit 1; fi

X11_KBD=$(bsddialog --backtitle "$BACKTITLE" --title "Keyboard (X11)" --default-item "$DEFAULT_X11_KBD" --menu "Select Keyboard Layout:" 15 60 8 \
    "us" "US English" \
    "gb" "UK English" \
    "fr" "French (AZERTY)" \
    "ch-fr" "Swiss French (QWERTZ)" \
    "ch-de" "Swiss German (QWERTZ)" \
    "de" "German (QWERTZ)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; exit 1; fi

case "$X11_KBD" in
    *-*) XKBLAYOUT="${X11_KBD%%-*}"; XKBVARIANT="${X11_KBD##*-}" ;;
    *)   XKBLAYOUT="$X11_KBD"; XKBVARIANT="" ;;
esac

while true; do
    TARGET_USER=$(bsddialog --backtitle "$BACKTITLE" --title "Target User" --inputbox "Enter the target username (e.g., admin):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$TARGET_USER" ]; then clear; exit 1; fi
    if id "$TARGET_USER" >/dev/null 2>&1; then break; else bsddialog --title "Error" --msgbox "User '$TARGET_USER' does not exist." 8 50; fi
done
USER_HOME=$(eval echo "~$TARGET_USER")

CPU_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "CPU Selection" --menu "Select Processor for Microcode Updates:" 12 55 3 \
    1 "Intel CPU" 2 "AMD CPU" 3 "Skip (Virtual Machine)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; exit 1; fi

GPU_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "GPU Selection" --menu "Select Graphics Card Vendor:" 12 50 3 \
    1 "AMD" 2 "NVIDIA" 3 "Intel" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; exit 1; fi

if [ "$GPU_CHOICE" = "2" ]; then
    NV_VER=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Version" --menu "Select NVIDIA Driver Branch:" 12 60 3 \
        1 "Latest (595+)" 2 "Legacy 580" 3 "Legacy 470" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then clear; exit 1; fi
fi

clear
step_start() { 
    printf "\n\033[1;36m================================================================================\033[0m\n"
    printf "\033[1;36m %s \033[0m\n" "$1"
    printf "\033[1;36m================================================================================\033[0m\n"
}

# ==============================================================================
# BLOCK 2: INFRASTRUCTURE & FREEBSD FIXES
# ==============================================================================
step_start "1/8: Core Services & FreeBSD Fixes"

sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc cupsd_enable="YES"
sysrc autofs_enable="YES"

if ! grep -q "procfs" /etc/fstab; then echo "proc    /proc    procfs    rw    0    0" >> /etc/fstab; mount -t procfs proc /proc 2>/dev/null; fi
if ! grep -q "fdescfs" /etc/fstab; then echo "fdesc   /dev/fd   fdescfs   rw   0   0" >> /etc/fstab; mount -t fdescfs fdesc /dev/fd 2>/dev/null; fi
if [ ! -s /etc/machine-id ]; then dbus-uuidgen > /etc/machine-id; fi
if ! grep -q "localhost $(hostname)" /etc/hosts; then echo "127.0.0.1 localhost $(hostname)" >> /etc/hosts; fi

env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap -f
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg update -f

# ==============================================================================
# BLOCK 3: CPU MICROCODE & PACKAGE INSTALLATION
# ==============================================================================
step_start "2/8: CPU Microcode & System Packages"

if [ "$CPU_CHOICE" = "1" ]; then
    env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y devcpu-data-intel
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/intel-ucode.bin"
    sysrc microcode_update_enable="YES"
elif [ "$CPU_CHOICE" = "2" ]; then
    env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y devcpu-data-amd
    sysrc -f /boot/loader.conf cpu_microcode_load="YES"
    sysrc -f /boot/loader.conf cpu_microcode_name="/boot/firmware/amd-ucode.bin"
    sysrc microcode_update_enable="YES"
fi

env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y \
    xorg xprop xorg-apps sddm pulseaudio pavucontrol cups system-config-printer automount fusefs-ntfs fusefs-exfat gvfs \
    cinnamon cinnamon-screensaver doas unzip wget alacritty flameshot htop neofetch firefox vlc \
    gtk-arc-themes papirus-icon-theme qt5-style-plugins qt5ct qt6ct

# ==============================================================================
# BLOCK 4: GPU CONFIGURATION
# ==============================================================================
step_start "3/8: GPU Configuration"
case $GPU_CHOICE in
    2)
        KMOD_DRIVER="nvidia-modeset"
        case $NV_VER in 2) NV_BASE="nvidia-driver-580" ;; 3) NV_BASE="nvidia-driver-470" ;; *) NV_BASE="nvidia-driver" ;; esac
        env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y "$NV_BASE" nvidia-xconfig nvidia-settings
        if [ -f /usr/local/bin/nvidia-xconfig ]; then nvidia-xconfig; fi
        ;;
    3) KMOD_DRIVER="i915kms"; env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod libva-intel-driver ;;
    *) KMOD_DRIVER="amdgpu"; env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod ;;
esac

CURRENT_KMODS=$(sysrc -n kld_list)
case "$CURRENT_KMODS" in *"$KMOD_DRIVER"*) ;; *) sysrc kld_list+="$KMOD_DRIVER" ;; esac

# ==============================================================================
# BLOCK 5: SECURITY (DOAS), KEYBOARD & PERMISSIONS
# ==============================================================================
step_start "4/8: Pure Philosophy: Doas, Keyboard & Device Permissions"

mkdir -p /usr/local/etc
if ! grep -q "permit persist :wheel" /usr/local/etc/doas.conf 2>/dev/null; then
    echo "permit persist :wheel" > /usr/local/etc/doas.conf
    echo "permit nopass :operator cmd /sbin/shutdown" >> /usr/local/etc/doas.conf
fi
ln -sf /usr/local/bin/doas /usr/local/bin/sudo

sysrc sddm_lang="${USER_LOCALE%%.*}"
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$XKBLAYOUT"
        Option "XkbVariant" "$XKBVARIANT"
EndSection
EOF

XSETUP="/usr/local/share/sddm/scripts/Xsetup"
if [ -f "$XSETUP" ]; then
    sed -i '' '/setxkbmap/d' "$XSETUP" 2>/dev/null
    echo "setxkbmap -layout $XKBLAYOUT ${XKBVARIANT:+-variant $XKBVARIANT}" >> "$XSETUP"
fi

sysrc -f /etc/sysctl.conf vfs.usermount=1; sysctl vfs.usermount=1 >/dev/null
cat > /etc/devfs.rules << 'EOF'
[localrules=5]
add path 'da*' mode 0660 group operator
add path 'cd*' mode 0660 group operator
add path 'usb/*' mode 0660 group operator
add path 'lpt*' mode 0660 group cups
add path 'ulpt*' mode 0660 group cups
add path 'unlpt*' mode 0660 group cups
EOF
sysrc devfs_system_ruleset="localrules"; service devfs restart 2>/dev/null || true

CLASS_NAME="custom_${USER_LOCALE%%.*}"
sed -i '' "/^${CLASS_NAME}|/,/:tc=default:/d" /etc/login.conf 2>/dev/null
printf "%s|Custom User Class:\n\t:charset=UTF-8:\n\t:lang=%s:\n\t:tc=default:\n" "$CLASS_NAME" "$USER_LOCALE" >> /etc/login.conf
cap_mkdb /etc/login.conf
pw usermod "$TARGET_USER" -G wheel,operator,video,cups -L "$CLASS_NAME" 2>/dev/null

# ==============================================================================
# BLOCK 6: ULTIMATE WRAPPER & SDDM CONFIGURATION
# ==============================================================================
step_start "5/8: SDDM Configuration, Wrapper & Wallpapers"

mkdir -p /usr/local/etc/sddm.conf.d
printf "[Theme]\nCurrent=maldives\n" > /usr/local/etc/sddm.conf.d/10-theme.conf

mkdir -p /usr/local/share/backgrounds

# SDDM Background Setup
if [ -f /usr/local/share/sddm/themes/maldives/background.jpg ]; then
    cp -f /usr/local/share/sddm/themes/maldives/background.jpg /usr/local/share/backgrounds/maldives-beach.jpg
    chmod 644 /usr/local/share/backgrounds/maldives-beach.jpg
fi

# Veligandu Island Download for Cinnamon Desktop
fetch -o /usr/local/share/backgrounds/veligandu-island.jpg "https://raw.githubusercontent.com/msartor99/FreeBSD15/a14e0129b3fcfbe40901ce20c2ffaefe674e5201/veligandu-island.jpg"
chmod 644 /usr/local/share/backgrounds/veligandu-island.jpg

# The Master Cinnamon Launcher
cat > /usr/local/bin/start-cinnamon << EOF
#!/bin/sh
export LANG="$USER_LOCALE"
export LC_ALL="$USER_LOCALE"
export LANGUAGE="$USER_LOCALE"
export QT_QPA_PLATFORMTHEME="gtk3"

exec dbus-launch --exit-with-session /usr/local/bin/cinnamon-session
EOF
chmod +x /usr/local/bin/start-cinnamon

mkdir -p /usr/local/share/xsessions
cat > /usr/local/share/xsessions/cinnamon.desktop << 'EOF'
[Desktop Entry]
Name=Cinnamon
Comment=FreeBSD Custom Cinnamon Launcher
Exec=/usr/local/bin/start-cinnamon
TryExec=/usr/local/bin/start-cinnamon
Icon=
Type=Application
EOF

# ==============================================================================
# BLOCK 7: USER PROFILE & ALACRITTY
# ==============================================================================
step_start "6/8: Local Profile & Terminal Configuration"

mkdir -p "$USER_HOME/.config/dconf"
mkdir -p "$USER_HOME/.config/alacritty"

cat > "$USER_HOME/.config/alacritty/alacritty.toml" << 'EOF'
[window]
opacity = 0.85
padding = { x = 12, y = 12 }
dynamic_padding = true
[font]
size = 11.0
[colors.primary]
background = "#0f1c2e"
foreground = "#d8e2eb"
[colors.normal]
black   = "#0f1c2e"
red     = "#e06c75"
green   = "#98c379"
yellow  = "#e5c07b"
blue    = "#61afef"
magenta = "#c678dd"
cyan    = "#56b6c2"
white   = "#d8e2eb"
EOF

# ==============================================================================
# BLOCK 8: THEMATIC AUTOSTART INJECTION
# ==============================================================================
step_start "7/8: Preparing Theme Injection (Autostart)"

mkdir -p "$USER_HOME/.config/autostart"

cat > "$USER_HOME/.config/autostart/apply-cinnamon-theme.sh" << 'EOF'
#!/bin/sh
sleep 3
gsettings set org.cinnamon.desktop.background picture-uri "'file:///usr/local/share/backgrounds/veligandu-island.jpg'"
gsettings set org.cinnamon.desktop.background picture-options "'zoom'"
gsettings set org.cinnamon.desktop.interface gtk-theme "'Arc'"
gsettings set org.cinnamon.desktop.wm.preferences theme "'Arc'"
gsettings set org.cinnamon.theme name "'Arc'"
gsettings set org.cinnamon.desktop.interface icon-theme "'Papirus'"
gsettings set org.cinnamon.desktop.default-applications.terminal exec "'alacritty'"
rm -f "$HOME/.config/autostart/apply-cinnamon-theme.desktop"
rm -f "$0"
EOF
chmod +x "$USER_HOME/.config/autostart/apply-cinnamon-theme.sh"

cat > "$USER_HOME/.config/autostart/apply-cinnamon-theme.desktop" << EOF
[Desktop Entry]
Type=Application
Name=ThemeInjector
Exec=$USER_HOME/.config/autostart/apply-cinnamon-theme.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

chown -R "$TARGET_USER" "$USER_HOME"

# ==============================================================================
# BLOCK 9: ZFS INDESTRUCTIBILITY
# ==============================================================================
step_start "8/8: ZFS Securing"

if mount | grep -q 'on / (zfs,'; then
    printf "ZFS system detected. Creating Boot Environment 'sys_cinnamon_clean'...\n"
    bectl destroy sys_cinnamon_clean 2>/dev/null || true
    bectl create sys_cinnamon_clean
    printf "👉 ZFS Snapshot successfully created.\n"
else
    printf "System is not on ZFS. Skipping step.\n"
fi

printf "\n\033[1;32m[ SUCCESS ] Ultimate UNIX/Cinnamon installation completed successfully.\033[0m\n"
printf "Please reboot the machine (/sbin/shutdown -r now).\n"
printf "On first login, let the script apply the magic of the Maldives!\n\n"

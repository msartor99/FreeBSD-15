#!/bin/sh

# --- CONFIGURATION AND VERIFICATION ---
TITLE="FreeBSD 15 Post-Installation (Idempotent)"
BACKTITLE="Workstation Configuration by Gemini"

if ! command -v bsddialog >/dev/null 2>&1; then
    echo "Installing bsddialog..."
    pkg update && pkg install -y bsddialog
fi

# Utility function to add a line to a file only if it doesn't already exist
add_line_if_missing() {
    grep -qF -- "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

# Check if running inside a VirtualBox VM
is_vbox_guest() {
    kenv smbios.system.product | grep -iq "VirtualBox"
}

# --- DISCLAIMER AND CREDITS ---
show_disclaimer() {
    local msg="DISCLAIMER OF LIABILITY\n\n\
This script deeply modifies your FreeBSD system configuration. \
It is provided 'as is', without any express or implied warranty. \
By using it, you agree that the author cannot be held responsible \
for any data loss, system breakage, or other damage.\n\n\
ACKNOWLEDGEMENTS\n\n\
A huge thanks to NASA (National Aeronautics and Space Administration) \
for providing their beautiful public domain images.\n\n\
Do you accept these conditions to continue?"

    if ! bsddialog --backtitle "$BACKTITLE" --title "Warning & Credits" --yesno "$msg" 18 75; then
        clear
        echo "Installation cancelled."
        exit 1
    fi
}

# --- FUSED INITIAL SETUP (Option 1) ---

initial_setup() {
    bsddialog --infobox "Starting System, CPU, Hardware and Language Setup..." 5 60
    
    # 1. Base System & PKG
    pkg update -y && pkg install -y sudo doas unzip libzip wget git linux-rl9 htop neofetch python3 bashtop ImageMagick7 smartmontools
    
    bsddialog --msgbox "Visudo will now open. Please add '%wheel ALL=(ALL:ALL) ALL'." 8 50
    visudo

    sed -i '' 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    add_line_if_missing "PermitRootLogin yes" /etc/ssh/sshd_config
    service sshd restart
    freebsd-update fetch install

    # Boot & Kernel Tuning
    sysrc -f /boot/loader.conf boot_mute=YES splash_changer_enable=YES autoboot_delay=3
    sed -i '' 's/run_rc_script ${_rc_elem} ${_boot}/run_rc_script ${_rc_elem} ${_boot} > \/dev\/null/g' /etc/rc
    sysrc rc_startmsgs=NO
    add_line_if_missing "kern.sched.preempt_thresh=224" /etc/sysctl.conf
    add_line_if_missing "kern.ipc.shm_allow_removed=1" /etc/sysctl.conf
    sysrc -f /boot/loader.conf tmpfs_load=YES aio_load=YES
    sysctl net.local.stream.recvspace=65536 net.local.stream.sendspace=65536
    
    # Linux Compat
    sysrc linux_enable=YES linux64_enable=YES
    service linux restart 2>/dev/null || service linux start

    # Smartd
    sysrc smartd_enable=YES
    [ ! -f /usr/local/etc/smartd.conf ] && cp /usr/local/etc/smartd.conf.sample /usr/local/etc/smartd.conf
    service smartd restart 2>/dev/null || service smartd start

    # 2. CPU Management
    CPU_TYPE=$(bsddialog --menu "Select CPU Type:" 12 50 2 "Intel" "Coretemp/Ucode" "AMD" "Amdtemp/Ucode" 3>&1 1>&2 2>&3)
    case $CPU_TYPE in
        Intel) pkg install -y cpu-microcode sensors; sysrc -f /boot/loader.conf coretemp_load="YES" cpu_microcode_name="/boot/firmware/intel-ucode.bin" ;;
        AMD) pkg install -y sensors cpu-microcode; sysrc -f /boot/loader.conf amdtemp_load="YES" cpu_microcode_load="YES" cpu_microcode_name="/boot/firmware/amd-ucode.bin" ;;
    esac

    # 3. Hardware Base
    pkg install -y pulseaudio pipewire wireplumber audio/freedesktop-sound-theme xorg dbus avahi signal-cli seatd sddm cups gutenprint cups-filters hplip system-config-printer fusefs-ntfs fusefs-ext2 fusefs-hfsfuse
    sysrc sound_load="YES" snd_hda_load="YES"
    add_line_if_missing "hw.snd.default_unit=1" /etc/sysctl.conf
    sysrc dbus_enable=YES avahi_enable=YES seatd_enable=YES sddm_enable=YES sddm_lang="ch_FR"
    sysrc cupsd_enable=YES devfs_system_ruleset=localrules
    sysrc kld_list+=fusefs kld_list+=ext2fs
    add_line_if_missing "vfs.usermount=1" /etc/sysctl.conf
    add_line_if_missing "proc /proc procfs rw 0 0" /etc/fstab
    add_line_if_missing "fdesc /dev/fd fdescfs rw 0 0" /etc/fstab

    # X11 Keyboard (Swiss French) - Always applied
    mkdir -p /usr/local/etc/X11/xorg.conf.d/
    cat >/usr/local/etc/X11/xorg.conf.d/20-keyboards.conf <<EOF
Section "InputClass"
    Identifier "All Keyboards"
    MatchIsKeyboard "yes"
    Option "XkbLayout" "ch"
    Option "XkbVariant" "fr"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

    # 4. Localization Menu (French Swiss vs English)
    LOC_CHOICE=$(bsddialog --menu "Select System Language:" 12 55 2 \
        "French" "Swiss French Locales (UTF-8)" \
        "English" "Default English (Clean up French if present)" 3>&1 1>&2 2>&3)

    case $LOC_CHOICE in
        French)
            if ! grep -q "french|French Users Accounts" /etc/login.conf; then
                cat >> /etc/login.conf <<EOF

french|French Users Accounts:\\
    :charset=UTF-8:\\
    :lang=fr_FR.UTF-8:\\
    :lc_all=fr_FR:\\
    :lc_collate=fr_FR:\\
    :lc_ctype=fr_FR:\\
    :lc_messages=fr_FR:\\
    :tc=default:
EOF
                cap_mkdb /etc/login.conf
            fi
            echo 'defaultclass=french' > /etc/adduser.conf
            USER_CLASS="french"
            ;;
        English)
            if grep -q "french|French Users Accounts" /etc/login.conf; then
                sed -i '' '/french|French Users Accounts:/,+8d' /etc/login.conf
                cap_mkdb /etc/login.conf
            fi
            echo 'defaultclass=default' > /etc/adduser.conf
            USER_CLASS="default"
            ;;
    esac

    # User creation/modification
    USER_NAME=$(bsddialog --inputbox "User Configuration:\nEnter main user name:" 9 50 3>&1 1>&2 2>&3)
    if [ -n "$USER_NAME" ]; then
        export USER_NAME
        pw usermod "$USER_NAME" -G wheel,operator,video -L "$USER_CLASS"
    fi
    pw usermod root -L "$USER_CLASS"
    bsddialog --msgbox "Initial Setup Complete." 6 40
}

# --- GPU / DRM FUNCTIONS ---

nvidia_config() {
    GPU_INFO=$(pciconf -lv | grep -i -B 1 -A 2 "vendor.*NVIDIA" | grep "device.*=" | cut -d "'" -f 2)
    [ -z "$GPU_INFO" ] && GPU_INFO="Unknown Nvidia GPU"
    REC_DRIVER="nvidia-driver"
    if echo "$GPU_INFO" | grep -iqE "Quadro P|GTX 10|Pascal"; then REC_DRIVER="nvidia-driver-580"
    elif echo "$GPU_INFO" | grep -iqE "Quadro M|GTX 9|Maxwell"; then REC_DRIVER="nvidia-driver-470"
    elif echo "$GPU_INFO" | grep -iqE "Quadro K|GTX 7|Kepler"; then REC_DRIVER="nvidia-driver-390"; fi

    CHOICE=$(bsddialog --title "Nvidia Config" --menu "Detected: $GPU_INFO\nRecommended: $REC_DRIVER" 17 85 5 \
        "nvidia-driver" "Latest" "nvidia-driver-580" "Legacy 580" "nvidia-driver-470" "Legacy 470" "nvidia-driver-390" "Legacy 390" "Back" "Cancel" 3>&1 1>&2 2>&3)
    [ "$CHOICE" = "Back" ] || [ -z "$CHOICE" ] && return
    DRIVER_PKG="$CHOICE"
    [ "$DRIVER_PKG" = "nvidia-driver" ] && LINUX_LIBS="linux-nvidia-libs" || LINUX_LIBS="linux-nvidia-libs-$(echo $DRIVER_PKG | cut -d'-' -f3)"
    pkg install -y "$DRIVER_PKG" "$LINUX_LIBS" libc6-shim nvidia-settings nvidia-xconfig
    sysrc kld_list+="nvidia-modeset"
    add_line_if_missing "hw.nvidiadrm.modeset=\"1\"" /boot/loader.conf
    nvidia-xconfig
}

drm_config() {
    VGA_VENDOR=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "vendor" | cut -d "'" -f 2)
    VGA_DEVICE=$(pciconf -lv | grep -i -A 2 "vgapci" | grep "device" | cut -d "'" -f 2)
    DRM_DRIVER=""
    
    if is_vbox_guest; then
        bsddialog --infobox "VirtualBox VM detected. Installing Guest Additions..." 5 50
        pkg install -y virtualbox-ose-additions
        sysrc vboxguest_enable="YES"
        sysrc vboxservice_enable="YES"
        add_line_if_missing "vboxvideo_load=\"YES\"" /boot/loader.conf
        add_line_if_missing "hw.efi.poweroff=0" /boot/loader.conf
        DRM_DRIVER="vboxvideo"
    else
        case "$VGA_VENDOR" in
            *Intel*) DRM_DRIVER="i915kms" ;;
            *AMD*|*ATI*)
                if echo "$VGA_DEVICE" | grep -iqE "Radeon HD|Radeon R[579]|FirePro"; then DRM_DRIVER="radeonkms"; else DRM_DRIVER="amdgpu"; fi
                ;;
            *) bsddialog --msgbox "No supported Intel/AMD GPU or VM detected." 8 50; return ;;
        esac
        pkg install -y drm-kmod
    fi

    pkg install -y wayland xwayland
    if ! sysrc -n kld_list | grep -q "$DRM_DRIVER"; then sysrc kld_list+="$DRM_DRIVER"; fi
    bsddialog --msgbox "DRM/VM Setup complete: $DRM_DRIVER configured." 6 60
}

# --- DESKTOPS & APPS ---

plasma_config() { 
    bsddialog --infobox "Installing Plasma 6 (KDE) and native tools..." 5 60
    pkg install -y --g "plasma6-*" "kf6*"
    pkg install -y pavucontrol kate konsole ark remmina dolphin Kvantum octopkg
}

mate_config() { 
    bsddialog --infobox "Installing MATE Desktop..." 5 50
    pkg install -y mate mate-desktop octopkg 
}

samba_config() { 
    pkg install -y samba416
    mkdir -p /home/share && chmod 777 /home/share
    if [ ! -f /usr/local/etc/smb4.conf ]; then
        cat > /usr/local/etc/smb4.conf <<EOF
[global]
    workgroup = HOMELAB
    map to guest = bad user
[Share]
    path = /home/share
    writable = yes
    guest ok = yes
EOF
    fi
    sysrc samba_server_enable="YES"; service samba_server restart 2>/dev/null || service samba_server start
}

xrdp_config() { 
    pkg install -y xrdp xorgxrdp
    sysrc xrdp_enable="YES" xrdp_sesman_enable="YES"
    [ ! -f /usr/local/etc/xrdp/startwm.sh.backup ] && mv /usr/local/etc/xrdp/startwm.sh /usr/local/etc/xrdp/startwm.sh.backup
    echo 'export LANG=fr_FR.UTF-8' > /usr/local/etc/xrdp/startwm.sh
    echo 'exec startplasma-x11' >> /usr/local/etc/xrdp/startwm.sh
    chmod 555 /usr/local/etc/xrdp/startwm.sh
}

vbox_host_config() {
    if is_vbox_guest; then
        bsddialog --title "Error" --msgbox "You are running FreeBSD inside a VirtualBox VM.\n\nInstallation of VirtualBox 7.2 (Host) is blocked to prevent nested virtualization issues." 10 60
        return
    fi
    pkg install -y virtualbox-ose-72
    sysrc -f /boot/loader.conf vboxdrv_load="YES" vboxnet_load="YES"
    sysrc vboxnet_enable="YES"
    pw groupmod vboxusers -m root
    [ -n "$USER_NAME" ] && pw groupmod vboxusers -m "$USER_NAME"
    add_line_if_missing 'own vboxnetctl root:vboxusers' /etc/devfs.conf
    add_line_if_missing 'perm vboxnetctl 0660' /etc/devfs.conf
}

nasa_theme() { 
    git clone https://github.com/msartor99/FreeBSD14 /tmp/fb14_assets
    mkdir -p /usr/local/share/sddm/themes/nasa
    cp -r /usr/local/share/sddm/themes/maldives/* /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/Main.qml /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/metadata.desktop /usr/local/share/sddm/themes/nasa/
    cp -f /tmp/fb14_assets/nasa2560login.jpg /usr/local/share/sddm/themes/nasa/background.jpg
    cat > /usr/local/etc/sddm.conf <<EOF
[Theme]
Current=nasa
EOF
    mkdir -p /boot/images
    cp -f /tmp/fb14_assets/freebsd-brand-rev.png /boot/images/
    cp -f /tmp/fb14_assets/freebsd-logo-rev.png /boot/images/
    cp -f /tmp/fb14_assets/nasa1920.png /boot/images/splash.png
    sysrc -f /boot/loader.conf splash="/boot/images/splash.png"
}

apps_config() { 
    bsddialog --infobox "Installing general applications and fonts..." 5 60
    pkg install -y firefox chromium thunderbird vlc ffmpeg kdenlive webcamd win98se-icon-theme ImageMagick7
    pkg install -y cantarell-fonts droid-fonts-ttf inconsolata-ttf noto-basic noto-emoji roboto-fonts-ttf ubuntu-font webfonts terminus-font terminus-ttf
    sysrc webcamd_enable=YES
}

switch_latest() { sed -i '' 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf; pkg update -f && pkg upgrade -y; }

# --- MAIN MENU ---

show_disclaimer

while true; do
    MAIN_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "$TITLE" \
        --menu "Select Installation Step:" 20 85 11 \
        "1" "Initial Setup (System, CPU, Hardware, Language, User)" \
        "2" "GPU: NVIDIA (Auto-Detect Legacy/Latest)" \
        "3" "GPU/VM: DRM-KMOD & VirtualBox Guest Auto-Setup" \
        "4" "Desktop: Plasma 6" \
        "5" "Desktop: MATE" \
        "6" "Samba Server" \
        "7" "XRDP Remote Desktop" \
        "8" "VirtualBox 7.2 (Host - Blocked in VM)" \
        "9" "Applications & Fonts" \
        "10" "NASA Theme (SDDM & Boot)" \
        "11" "Upgrade to LATEST Branch" \
        "Q" "Quit" 3>&1 1>&2 2>&3)

    case $MAIN_CHOICE in
        1) initial_setup ;;
        2) nvidia_config ;;
        3) drm_config ;;
        4) plasma_config ;;
        5) mate_config ;;
        6) samba_config ;;
        7) xrdp_config ;;
        8) vbox_host_config ;;
        9) apps_config ;;
        10) nasa_theme ;;
        11) switch_latest ;;
        Q|q|*) break ;;
    esac
done
clear
echo "Script finished. Please reboot your system."

#!/bin/sh
# ==============================================================================
# PROJECT PURE-IRIX : SGI Desktop Clone for FreeBSD 15 (100% NATIVE / SH)
# VERSION: V16 MASTER NATIVE (The Indestructible Edition)
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required. Please execute this script as root."
    exit 1
fi

BACKTITLE="Pure-IRIX SGI - FreeBSD 15 Native Installer"

# --- AUTO-DETECT SYSTEM DEFAULTS ---
SYS_KBD=$(sysrc -n keymap 2>/dev/null | grep -Eo '^[a-z]{2}' || echo "us")

DEFAULT_LANG="en_US.UTF-8"
DEFAULT_X11_KBD="us"

case "$SYS_KBD" in
    fr) DEFAULT_LANG="fr_FR.UTF-8"; DEFAULT_X11_KBD="fr" ;;
    ch) DEFAULT_LANG="fr_CH.UTF-8"; DEFAULT_X11_KBD="ch-fr" ;;
    de) DEFAULT_LANG="de_DE.UTF-8"; DEFAULT_X11_KBD="de" ;;
    uk|gb) DEFAULT_LANG="en_GB.UTF-8"; DEFAULT_X11_KBD="gb" ;;
    es) DEFAULT_LANG="es_ES.UTF-8"; DEFAULT_X11_KBD="es" ;;
    it) DEFAULT_LANG="it_IT.UTF-8"; DEFAULT_X11_KBD="it" ;;
esac

# --- INTERACTIVE PHASES (bsddialog) ---
USER_LOCALE=$(bsddialog --backtitle "$BACKTITLE" --title "Language & Region" --default-item "$DEFAULT_LANG" --menu "Select your system language and region:" 15 60 8 \
    "en_US.UTF-8" "English (US)" \
    "en_GB.UTF-8" "English (UK)" \
    "fr_FR.UTF-8" "French (France)" \
    "fr_CH.UTF-8" "French (Switzerland)" \
    "de_DE.UTF-8" "German (Germany)" \
    "de_CH.UTF-8" "German (Switzerland)" \
    "es_ES.UTF-8" "Spanish (Spain)" \
    "it_IT.UTF-8" "Italian (Italy)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; echo "Installation cancelled."; exit 1; fi

X11_KBD=$(bsddialog --backtitle "$BACKTITLE" --title "Keyboard Layout" --default-item "$DEFAULT_X11_KBD" --menu "Select your X11 Keyboard Layout:" 15 60 8 \
    "us" "US English" \
    "gb" "UK English" \
    "fr" "French (AZERTY)" \
    "ch-fr" "Swiss French (QWERTZ)" \
    "ch-de" "Swiss German (QWERTZ)" \
    "de" "German (QWERTZ)" \
    "es" "Spanish (QWERTY)" \
    "it" "Italian (QWERTY)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; echo "Installation cancelled."; exit 1; fi

case "$X11_KBD" in
    *-*) XKBLAYOUT="${X11_KBD%%-*}"; XKBVARIANT="${X11_KBD##*-}" ;;
    *)   XKBLAYOUT="$X11_KBD"; XKBVARIANT="" ;;
esac

while true; do
    TARGET_USER=$(bsddialog --backtitle "$BACKTITLE" --title "Target User" --inputbox "Enter the target username (e.g., administrator):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$TARGET_USER" ]; then
        clear; echo "Installation cancelled."; exit 1
    fi
    if id "$TARGET_USER" >/dev/null 2>&1; then
        break
    else
        bsddialog --backtitle "$BACKTITLE" --title "Error" --msgbox "User '$TARGET_USER' does not exist. Please create it first." 8 50
    fi
done

GPU_CHOICE=$(bsddialog --backtitle "$BACKTITLE" --title "GPU Selection" --menu "Select your graphics card vendor:" 12 50 3 \
    1 "AMD" \
    2 "NVIDIA" \
    3 "Intel" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then clear; echo "Installation cancelled."; exit 1; fi

if [ "$GPU_CHOICE" = "2" ]; then
    NV_VER=$(bsddialog --backtitle "$BACKTITLE" --title "NVIDIA Driver Version" --menu "Select the NVIDIA driver branch (FreeBSD 15):" 12 60 3 \
        1 "Latest (595+ for Pascal and newer)" \
        2 "Legacy 580 Series" \
        3 "Legacy 470 (Kepler)" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then clear; echo "Installation cancelled."; exit 1; fi
fi

clear

step_start() { 
    printf "\n\033[1;36m================================================================================\033[0m\n"
    printf "\033[1;36m %s \033[0m\n" "$1"
    printf "\033[1;36m================================================================================\033[0m\n"
}

# --- STEP 1 : CORE PACKAGES ---
step_start "1/8: Bootstrap pkg & Install Native Core"

sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc cupsd_enable="YES"

env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap -f
hash -r
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg update -f

printf "\n👉 Installing Base X11 Server & Motif...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y xorg xprop xorg-apps open-motif xorg-fonts-100dpi xorg-fonts-75dpi

printf "\n👉 Installing Display Manager, Audio & Printing...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y sddm pulseaudio pavucontrol cups arandr

printf "\n👉 Installing SGI-like Native Utilities, Screensavers & Demos...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y sudo unzip git htop neofetch ImageMagick7 xscreensaver xscreensaver-gl mesa-demos wget tk86

printf "\n👉 Installing Applications (Office, Media, MATE Utilities)...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y xfe firefox thunderbird xterm xpdf nedit scrot vlc feh xosview apache-openoffice \
    mate-system-monitor mate-calc engrampa atril

# --- STEP 2 : GPU CONFIGURATION ---
step_start "2/8: GPU Drivers Configuration"
case $GPU_CHOICE in
    2)
        GPU_NAME="NVIDIA"; KMOD_DRIVER="nvidia-modeset"
        case $NV_VER in
            2) NV_BASE="nvidia-driver-580" ;;
            3) NV_BASE="nvidia-driver-470" ;;
            *) NV_BASE="nvidia-driver" ;;
        esac
        env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y "$NV_BASE" nvidia-xconfig nvidia-settings
        if [ -f /usr/local/bin/nvidia-xconfig ]; then nvidia-xconfig; fi
        ;;
    3) GPU_NAME="Intel"; KMOD_DRIVER="i915kms"; env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod libva-intel-driver ;;
    *) GPU_NAME="AMD"; KMOD_DRIVER="amdgpu"; env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y drm-kmod ;;
esac

CURRENT_KMODS=$(sysrc -n kld_list)
case "$CURRENT_KMODS" in
    *"$KMOD_DRIVER"*) ;;
    *) sysrc kld_list+="$KMOD_DRIVER" ;;
esac

# --- STEP 3 : GRAPHICS STACK & KEYBOARD ---
step_start "3/8: Unified Keyboard Configuration"

SDDM_LANG="${USER_LOCALE%%.*}"
sysrc sddm_lang="$SDDM_LANG"

mkdir -p /usr/local/etc/X11/xorg.conf.d

cat > /usr/local/etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$XKBLAYOUT"
        Option "XkbVariant" "$XKBVARIANT"
EndSection
EOF

cat > /usr/local/etc/X11/xorg.conf.d/20-keyboards.conf << EOF
Section "ServerFlags"
                 Option "DontZap" "false"
EndSection
Section     "InputClass"
           Identifier     "All Keyboards"
           MatchIsKeyboard    "yes"
           Option     "XkbLayout" "$XKBLAYOUT"
           Option     "XkbVariant" "$XKBVARIANT"
           Option     "XkbOptions" "terminate:ctrl_alt_bksp" 
EndSection
EOF

XSETUP="/usr/local/share/sddm/scripts/Xsetup"
if [ -f "$XSETUP" ]; then
    sed -i '' '/setxkbmap/d' "$XSETUP" 2>/dev/null
    if [ -n "$XKBVARIANT" ]; then
        echo "setxkbmap -layout $XKBLAYOUT -variant $XKBVARIANT" >> "$XSETUP"
    else
        echo "setxkbmap -layout $XKBLAYOUT" >> "$XSETUP"
    fi
fi

# --- STEP 4 : SECURITY & POWER ---
step_start "4/8: Security, Localization & Power Management"

mkdir -p /usr/local/etc/sudoers.d
echo "%wheel ALL=(ALL) ALL" > /usr/local/etc/sudoers.d/wheel
chmod 0440 /usr/local/etc/sudoers.d/wheel

echo "%operator ALL=(ALL) NOPASSWD: /sbin/shutdown" > /usr/local/etc/sudoers.d/power_management
chmod 0440 /usr/local/etc/sudoers.d/power_management

CLASS_NAME="custom_${USER_LOCALE%%.*}"
sed -i '' "/^${CLASS_NAME}|/,/:tc=default:/d" /etc/login.conf 2>/dev/null
printf "%s|Custom User Class:\n\t:charset=UTF-8:\n\t:lang=%s:\n\t:tc=default:\n" "$CLASS_NAME" "$USER_LOCALE" >> /etc/login.conf
cap_mkdb /etc/login.conf
echo "defaultclass=$CLASS_NAME" > /etc/adduser.conf
pw usermod "$TARGET_USER" -G wheel,operator,video -L "$CLASS_NAME" 2>/dev/null

# --- STEP 5 : SDDM SGI THEME ---
step_start "5/8: Generating SGI Boot Logo and SDDM Theme"

IMG_DIR="/boot/images"
mkdir -p "$IMG_DIR"
SGI_WALLPAPER_URL="https://raw.githubusercontent.com/msartor99/FreeBSD15-Maxxdesktop/main/sgi_desktop.jpg"

cd "$IMG_DIR" || exit 1
fetch -q -o "sgi_desktop.jpg" "$SGI_WALLPAPER_URL"
if [ -f "sgi_desktop.jpg" ]; then
    PATH="/usr/local/bin:$PATH"
    SDDM_BASE="/usr/local/share/sddm/themes"
    if [ -d "$SDDM_BASE/maldives" ]; then
        rm -rf "$SDDM_BASE/sgi_irix"
        cp -R "$SDDM_BASE/maldives" "$SDDM_BASE/sgi_irix"
        cp "sgi_desktop.jpg" "$SDDM_BASE/sgi_irix/sgi_desktop.jpg"
        sed -i '' "s|^background=.*|background=sgi_desktop.jpg|" "$SDDM_BASE/sgi_irix/theme.conf"
        mkdir -p /usr/local/etc/sddm.conf.d
        cat > /usr/local/etc/sddm.conf.d/10-theme.conf << 'EOF'
[Theme]
Current=sgi_irix
EOF
    fi
fi
cd - >/dev/null

# --- STEP 6 : SGI COLOR PALETTE, GTK & MWM FOCUS ---
step_start "6/8: Forging the SGI Aesthetics & MWM Config"

# 'explicit' keyboardFocusPolicy avoids GTK3 BadMatch crashes with xscreensaver
cat > /usr/share/skel/dot.Xdefaults << 'EOF'
Mwm*useClientIcon: True
Mwm*interactivePlacement: False
Mwm*keyboardFocusPolicy: explicit
Mwm*focusAutoRaise: True

Mwm*background: #AFAFAF
Mwm*foreground: #000000
Mwm*activeBackground: #8B8B8B
Mwm*activeForeground: #FFFFFF
Mwm*cleanText: True
Mwm*fontList: -*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*,fixed

xterm*faceName: Monospace
xterm*faceSize: 10
xterm*background: #D8D8CF
xterm*foreground: #000000
xterm*scrollBar: true
xterm*rightScrollBar: true
xterm*saveLines: 5000
EOF

# Default screensaver config (to be edited via nedit)
cat > /usr/share/skel/dot.xscreensaver << 'EOF'
timeout:	10
cycle:		10
lock:		False
lockTimeout:	0
splash:		False
mode:		random
EOF

mkdir -p /usr/share/skel/dot.config/gtk-3.0
cat > /usr/share/skel/dot.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=0
gtk-enable-animations=0
gtk-font-name=Helvetica 10
EOF

cp -f /usr/share/skel/dot.Xdefaults /root/.Xdefaults
cp -f /usr/share/skel/dot.xscreensaver /root/.xscreensaver
mkdir -p /root/.config/gtk-3.0
cp -f /usr/share/skel/dot.config/gtk-3.0/settings.ini /root/.config/gtk-3.0/

for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        cp -f /usr/share/skel/dot.Xdefaults "$user_home/.Xdefaults"
        cp -f /usr/share/skel/dot.xscreensaver "$user_home/.xscreensaver"
        mkdir -p "$user_home/.config/gtk-3.0"
        cp -f /usr/share/skel/dot.config/gtk-3.0/settings.ini "$user_home/.config/gtk-3.0/"
        
        user_id=$(stat -f "%u:%g" "$user_home")
        chown "$user_id" "$user_home/.Xdefaults"
        chown "$user_id" "$user_home/.xscreensaver"
        chown -R "$user_id" "$user_home/.config"
    fi
done

# --- STEP 7 : DYNAMIC IRIXCHEST & CONTROL PANEL ---
step_start "7/8: Crafting Bulletproof IrixChest & Control Panel"

cat > /usr/local/bin/irixcontrol << 'EOF'
#!/usr/local/bin/wish8.6
option add *background "#AFAFAF"
option add *foreground "#000000"
option add *activeBackground "#8B8B8B"
option add *activeForeground "#FFFFFF"
option add *font "-*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*"
option add *borderWidth 2

# The ultimate indestructible launch function with full FreeBSD PATH
proc launch {cmd} {
    catch {
        exec /bin/sh -c "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:\$PATH; $cmd" &
    }
}

wm title . "Irix Control Panel"
wm geometry . "+200+150"
wm resizable . 0 0

label .title -text "System Control Panel" -font "-*-helvetica-bold-r-normal-*-16-*-*-*-*-*-*-*" -pady 10
pack .title -side top -fill x

frame .grid
pack .grid -padx 15 -pady 15

button .grid.disp -text "Display Settings" -width 22 -command {launch "arandr"}
button .grid.snd -text "Audio Control" -width 22 -command {launch "pavucontrol"}
button .grid.prt -text "Printers (CUPS)" -width 22 -command {launch "firefox http://localhost:631"}
button .grid.bg -text "Change Wallpaper" -width 22 -command {
    set img [tk_getOpenFile -title "Select Wallpaper" -filetypes {{{Images} {.jpg .png .bmp .jpeg}}}]
    if {$img ne ""} { launch "feh --bg-fill \"$img\"" }
}
button .grid.theme -text "Appearance (.Xdefaults)" -width 22 -command {launch "nedit $env(HOME)/.Xdefaults"}
button .grid.scr -text "Screensaver" -width 22 -command {launch "nedit $env(HOME)/.xscreensaver"}
button .grid.close -text "Close Panel" -width 22 -command {exit}

grid .grid.disp .grid.snd -pady 8 -padx 8
grid .grid.prt .grid.bg -pady 8 -padx 8
grid .grid.theme .grid.scr -pady 8 -padx 8

if {[auto_execok nvidia-settings] ne ""} {
    button .grid.nv -text "NVIDIA Settings" -width 22 -command {launch "nvidia-settings"}
    grid .grid.nv .grid.close -pady 8 -padx 8
} else {
    grid .grid.close -columnspan 2 -pady 8 -padx 8
}
EOF
chmod +x /usr/local/bin/irixcontrol

cat > /usr/local/bin/irixchest << 'EOF'
#!/usr/local/bin/wish8.6
option add *background "#AFAFAF"
option add *foreground "#000000"
option add *activeBackground "#8B8B8B"
option add *activeForeground "#FFFFFF"
option add *font "-*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*"
option add *borderWidth 2

proc launch {cmd} {
    catch {
        exec /bin/sh -c "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:\$PATH; $cmd" &
    }
}

wm title . "IrixChest"
wm geometry . "+20+20"
wm resizable . 0 0

proc rebuild_xdg_menu {} {
    .apps.m delete 0 end
    foreach cat {Network Office Multimedia Graphics Utilities System Games Other} {
        catch {destroy .apps.m.[string tolower $cat]}
        menu .apps.m.[string tolower $cat] -tearoff 0
    }
    set files [glob -nocomplain /usr/local/share/applications/*.desktop]
    set app_data {}

    foreach f $files {
        if {[catch {set fp [open $f r]}]} continue
        set name ""; set exec ""; set cat "Other"; set nodisp 0
        while {[gets $fp line] >= 0} {
            if {[string match "Name=*" $line] && $name eq ""} { set name [string range $line 5 end] }
            if {[string match "Exec=*" $line] && $exec eq ""} { set exec [string range $line 5 end] }
            if {[string match "NoDisplay=true*" $line]} { set nodisp 1 }
            if {[string match "Categories=*" $line]} {
                if {[string match "*Network*" $line] || [string match "*WebBrowser*" $line]} { set cat "Network" }
                if {[string match "*Office*" $line]} { set cat "Office" }
                if {[string match "*AudioVideo*" $line] || [string match "*Audio*" $line] || [string match "*Video*" $line]} { set cat "Multimedia" }
                if {[string match "*Graphics*" $line]} { set cat "Graphics" }
                if {[string match "*Utility*" $line]} { set cat "Utilities" }
                if {[string match "*System*" $line]} { set cat "System" }
                if {[string match "*Game*" $line]} { set cat "Games" }
            }
        }
        close $fp
        
        # Filtre anti-GTK3 pour bloquer l'interface capricieuse de xscreensaver dans le menu Applications
        if {[string match "*xscreensaver*" [string tolower $exec]]} { set nodisp 1 }

        if {$name ne "" && $exec ne "" && $nodisp == 0} {
            regsub -all { %[a-zA-Z]} $exec "" exec
            lappend app_data [list $cat $name $exec]
        }
    }

    set app_data [lsort -index 1 $app_data]
    set cat_counts [dict create Network 0 Office 0 Multimedia 0 Graphics 0 Utilities 0 System 0 Games 0 Other 0]
    
    foreach item $app_data {
        set c [lindex $item 0]; set n [lindex $item 1]; set e [lindex $item 2]
        .apps.m.[string tolower $c] add command -label "  $n" -command "launch {$e}"
        dict incr cat_counts $c
    }

    foreach c {Network Office Multimedia Graphics Utilities System Games Other} {
        if {[dict get $cat_counts $c] > 0} {
            .apps.m add cascade -label "  $c" -menu .apps.m.[string tolower $c]
        }
    }
}

menubutton .desktop -text "  Desktop" -menu .desktop.m -relief raised -anchor w -width 18
menu .desktop.m -tearoff 0
.desktop.m add command -label "  Unix Shell" -command {launch "xterm -name Winterm -title 'Unix Shell'"}
.desktop.m add command -label "  File Manager" -command {launch "xfe"}
.desktop.m add command -label "  Text Editor" -command {launch "nedit"}

menubutton .apps -text "  Applications" -menu .apps.m -relief raised -anchor w -width 18
menu .apps.m -tearoff 0 -postcommand {rebuild_xdg_menu}

menubutton .demos -text "  Demos (GL)" -menu .demos.m -relief raised -anchor w -width 18
menu .demos.m -tearoff 0
.demos.m add command -label "  GL Gears" -command {launch "/usr/local/bin/xscreensaver-hacks/gears -window"}
.demos.m add command -label "  3D Pipes" -command {launch "/usr/local/bin/xscreensaver-hacks/pipes -window"}
.demos.m add command -label "  GL Planet" -command {launch "/usr/local/bin/xscreensaver-hacks/glplanet -window"}
.demos.m add command -label "  Moebius" -command {launch "/usr/local/bin/xscreensaver-hacks/moebius -window"}
.demos.m add command -label "  Molecule" -command {launch "/usr/local/bin/xscreensaver-hacks/molecule -window"}

menubutton .system -text "  System" -menu .system.m -relief raised -anchor w -width 18
menu .system.m -tearoff 0
.system.m add command -label "  Screensaver Config" -command {launch "nedit $env(HOME)/.xscreensaver"}
.system.m add command -label "  Control Panel" -command {launch "/usr/local/bin/irixcontrol"}
if {[auto_execok nvidia-settings] ne ""} {
    .system.m add command -label "  NVIDIA Settings" -command {launch "nvidia-settings"}
}
.system.m add separator
.system.m add command -label "  System Monitor" -command {launch "mate-system-monitor"}
.system.m add command -label "  Audio Mixer" -command {launch "pavucontrol"}

menubutton .power -text "  Power" -menu .power.m -relief raised -anchor w -width 18
menu .power.m -tearoff 0
.power.m add command -label "  Lock Screen" -command {launch "xscreensaver-command -lock"}
.power.m add separator
.power.m add command -label "  Restart System" -command {launch "/sbin/shutdown -r now"}
.power.m add command -label "  Shutdown System" -command {launch "/sbin/shutdown -p now"}
.power.m add separator
.power.m add command -label "  Log Out" -command {launch "killall mwm"}

pack .desktop .apps .demos .system .power -side top -fill x
EOF
chmod +x /usr/local/bin/irixchest

# 3. Motif Bindings
mkdir -p /usr/local/etc/X11/mwm
cat > /usr/local/etc/X11/mwm/system.mwmrc << 'EOF'
Buttons DefaultButtonBindings
{
    <Btn1Down>      frame|icon      f.raise
    <Btn3Down>      frame|icon      f.post_wmenu
}
Keys DefaultKeyBindings
{
    Shift<Key>Escape        window|icon             f.post_wmenu
    Meta<Key>space          window|icon             f.post_wmenu
    Meta<Key>Tab            root|icon|window        f.next_key
    Shift Meta<Key>Tab      root|icon|window        f.prev_key
    Meta<Key>Escape         root|icon|window        f.next_key
    Shift Meta<Key>Escape   root|icon|window        f.prev_key
}
Menu DefaultWindowMenu
{
    "Restore"      _R  Alt<Key>F5      f.normalize
    "Move"         _M  Alt<Key>F7      f.move
    "Size"         _S  Alt<Key>F8      f.resize
    "Minimize"     _n  Alt<Key>F9      f.minimize
    "Maximize"     _x  Alt<Key>F10     f.maximize
    "Lower"        _L  Alt<Key>F3      f.lower
    no-label                           f.separator
    "Close"        _C  Alt<Key>F4      f.kill
}
EOF

# --- STEP 8 : NATIVE IRIX SESSION MANAGER ---
step_start "8/8: Creating Session Script & SDDM Configuration"

cat > /usr/local/bin/start_pure_irix << EOF
#!/bin/sh
export LANG="$USER_LOCALE"
export LC_ALL="$USER_LOCALE"

if [ -f "\$HOME/.Xdefaults" ]; then
    xrdb -merge "\$HOME/.Xdefaults"
fi

# Wallpaper loading
if [ -x "\$HOME/.fehbg" ]; then
    "\$HOME/.fehbg" &
elif [ -f "/boot/images/sgi_desktop.jpg" ]; then
    feh --bg-fill /boot/images/sgi_desktop.jpg &
else
    xsetroot -solid "#395E79" &
fi
xset b off 2>/dev/null

pulseaudio --kill 2>/dev/null || true
pulseaudio --start --exit-idle-time=-1 2>/dev/null &

xscreensaver -nosplash &

/usr/local/bin/irixchest &

exec /usr/local/bin/mwm -xrm "Mwm*configFile: /usr/local/etc/X11/mwm/system.mwmrc"
EOF
chmod +x /usr/local/bin/start_pure_irix

mkdir -p /usr/local/share/xsessions
cat > /usr/local/share/xsessions/pure-irix.desktop << 'EOF'
[Desktop Entry]
Name=Pure IRIX (FreeBSD Native)
Exec=/usr/local/bin/start_pure_irix
Type=Application
EOF

printf "\n\033[1;32m[ DONE ] Pure-IRIX 100%% Native installation complete.\033[0m\n"
printf "Please reboot your system.\n"

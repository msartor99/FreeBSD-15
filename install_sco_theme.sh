#!/bin/sh
# ==============================================================================
# PROJECT PURE-SCO : SCO OpenDesktop / System V Clone for FreeBSD 15
# VERSION: V3.0 MASTERPIECE NATIVE (SDDM Qt6 + Volume Mixer)
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Root privileges required. Please execute this script as root."
    exit 1
fi

BACKTITLE="Pure-SCO OpenDesktop - FreeBSD 15 Native Installer"

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
    printf "\n\033[1;34m================================================================================\033[0m\n"
    printf "\033[1;34m %s \033[0m\n" "$1"
    printf "\033[1;34m================================================================================\033[0m\n"
}

# --- STEP 1 : CORE PACKAGES ---
step_start "1/8: Bootstrap pkg & Install System V Core Tools"

sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc cupsd_enable="YES"

env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap -f
hash -r
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg update -f

printf "\n👉 Installing Base X11 Server, Motif & System V Korn Shell...\n"
# Ajout de xcb-util-cursor pour le support Qt6 sous FreeBSD 15
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y xorg xprop xorg-apps open-motif xorg-fonts-100dpi xorg-fonts-75dpi ksh93 xcb-util-cursor

printf "\n👉 Installing Display Manager, Audio & Printing...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y sddm pulseaudio pavucontrol cups arandr

printf "\n👉 Installing Commercial-like Utilities...\n"
env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install -y sudo unzip wget tk86 xfe firefox xterm xpdf nedit scrot ImageMagick7 xosview

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

# --- STEP 5 : SDDM "PURE-SCO" THEME & Qt6 FIXES ---
step_start "5/8: Generating the Authentic SCO Login Screen"

THEME_DIR="/usr/local/share/sddm/themes/pure-sco"
# Pointer vers la branche main garantit de télécharger la dernière image corrigée
LOGO_URL="https://raw.githubusercontent.com/msartor99/FreeBSD15/main/SCO_open_desktop_logo.jpg"

mkdir -p "$THEME_DIR"
fetch -q -o "$THEME_DIR/sco_logo.jpg" "$LOGO_URL"

# Carte d'identité indispensable pour éviter le rejet du thème sous Qt6
cat > "$THEME_DIR/metadata.desktop" << 'EOF'
[SddmGreeterTheme]
Name=Pure-SCO
Description=SCO OpenDesktop Classic Login
Type=sddm-theme
Version=1.0
MainScript=Main.qml
ConfigFile=theme.conf
EOF

cat > "$THEME_DIR/theme.conf" << 'EOF'
[Theme]
Current=pure-sco
Description=SCO OpenDesktop Classic Login
Author=Pure-SCO Project
Type=sddm-theme
EOF

cat > "$THEME_DIR/Main.qml" << 'EOF'
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    width: 1024
    height: 768
    color: "black"

    Rectangle {
        width: 500
        height: 550
        anchors.centerIn: parent
        color: "#2B2024"
        
        Rectangle { width: parent.width; height: 3; color: "#5A4A50" }
        Rectangle { width: 3; height: parent.height; color: "#5A4A50" }
        Rectangle { width: parent.width; height: 3; color: "#100B0D"; anchors.bottom: parent.bottom }
        Rectangle { width: 3; height: parent.height; color: "#100B0D"; anchors.right: parent.right }

        Rectangle {
            width: parent.width - 20
            height: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: buttonRow.top
            anchors.bottomMargin: 20
            color: "#100B0D"
            Rectangle { width: parent.width; height: 1; color: "#5A4A50"; anchors.top: parent.bottom }
        }

        Rectangle {
            id: logoArea
            width: 460
            height: 260
            anchors.top: parent.top
            anchors.topMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            color: "black"

            Image {
                anchors.fill: parent
                source: "sco_logo.jpg"
                fillMode: Image.PreserveAspectCrop
            }

            Rectangle { width: parent.width; height: 3; color: "#100B0D" }
            Rectangle { width: 3; height: parent.height; color: "#100B0D" }
            Rectangle { width: parent.width; height: 3; color: "#5A4A50"; anchors.bottom: parent.bottom }
            Rectangle { width: 3; height: parent.height; color: "#5A4A50"; anchors.right: parent.right }
        }

        Column {
            id: inputArea
            anchors.top: logoArea.bottom
            anchors.topMargin: 30
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15

            Row {
                spacing: 15
                Text {
                    text: "scosysv login "
                    color: "#D8B888"
                    font.pixelSize: 18
                    font.family: "serif"
                    font.bold: true
                    width: 140
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 250
                    height: 30
                    color: "#8E7557"
                    Rectangle { width: parent.width; height: 2; color: "#4A3B2A" }
                    Rectangle { width: 2; height: parent.height; color: "#4A3B2A" }
                    Rectangle { width: parent.width; height: 2; color: "#C4AA8C"; anchors.bottom: parent.bottom }
                    Rectangle { width: 2; height: parent.height; color: "#C4AA8C"; anchors.right: parent.right }

                    TextInput {
                        id: nameInput
                        anchors.fill: parent
                        anchors.margins: 5
                        font.pixelSize: 16
                        font.family: "serif"
                        color: "white"
                        focus: true
                        KeyNavigation.tab: passwordInput
                    }
                }
            }

            Row {
                spacing: 15
                Text {
                    text: "Password "
                    color: "#D8B888"
                    font.pixelSize: 18
                    font.family: "serif"
                    font.bold: true
                    width: 140
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 250
                    height: 30
                    color: "#8E7557"
                    Rectangle { width: parent.width; height: 2; color: "#4A3B2A" }
                    Rectangle { width: 2; height: parent.height; color: "#4A3B2A" }
                    Rectangle { width: parent.width; height: 2; color: "#C4AA8C"; anchors.bottom: parent.bottom }
                    Rectangle { width: 2; height: parent.height; color: "#C4AA8C"; anchors.right: parent.right }

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: 5
                        font.pixelSize: 16
                        font.family: "serif"
                        color: "white"
                        echoMode: TextInput.Password
                        KeyNavigation.tab: btnLogin
                        Keys.onPressed: {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                sddm.login(nameInput.text, passwordInput.text, sessionIndex.index)
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: sessionIndex
            property int index: 0
        }

        Row {
            id: buttonRow
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 70

            Component {
                id: motifButton
                Rectangle {
                    property string btnText: ""
                    property var action: null
                    width: 80
                    height: 35
                    color: "#2B2024"
                    
                    Rectangle { width: parent.width; height: 2; color: "#5A4A50" }
                    Rectangle { width: 2; height: parent.height; color: "#5A4A50" }
                    Rectangle { width: parent.width; height: 2; color: "#100B0D"; anchors.bottom: parent.bottom }
                    Rectangle { width: 2; height: parent.height; color: "#100B0D"; anchors.right: parent.right }

                    Text {
                        anchors.centerIn: parent
                        text: parent.btnText
                        color: "#D8B888"
                        font.pixelSize: 16
                        font.family: "serif"
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: parent.action()
                        onPressed: { parent.color = "#100B0D" }
                        onReleased: { parent.color = "#2B2024" }
                    }
                }
            }

            Loader { 
                id: btnLogin
                sourceComponent: motifButton; 
                onLoaded: { item.btnText = "Login"; item.action = function() { sddm.login(nameInput.text, passwordInput.text, sessionIndex.index) } } 
            }
            Loader { 
                sourceComponent: motifButton; 
                onLoaded: { item.btnText = "Restart"; item.action = function() { sddm.reboot() } } 
            }
            Loader { 
                sourceComponent: motifButton; 
                onLoaded: { item.btnText = "Help"; item.action = function() { nameInput.text = "Help unavailable"; passwordInput.text = ""; } } 
            }
        }
    }
}
EOF

# Verrouillage des permissions pour que SDDM lise le thème sans encombre
chmod -R 755 "$THEME_DIR"
if [ -f "$THEME_DIR/sco_logo.jpg" ]; then
    chmod 644 "$THEME_DIR/sco_logo.jpg"
fi

# Le Hack Magistral : Créer l'illusion pour contourner le bug Qt6 de SDDM
if [ -f "/usr/local/bin/sddm-greeter-qt6" ]; then
    ln -sf /usr/local/bin/sddm-greeter-qt6 /usr/local/bin/sddm-greeter
fi

mkdir -p /usr/local/etc/sddm.conf.d
cat > /usr/local/etc/sddm.conf.d/10-theme.conf << 'EOF'
[Theme]
Current=pure-sco
EOF

# --- STEP 6 : SCO OPEN DESKTOP MWM & XDEFAULTS ---
step_start "6/8: Forging the SCO Industrial Aesthetics"

cat > /usr/share/skel/dot.Xdefaults << 'EOF'
Mwm*useClientIcon: True
Mwm*interactivePlacement: False
Mwm*keyboardFocusPolicy: explicit
Mwm*focusAutoRaise: True

! SCO OpenDesktop Colors
Mwm*background: #C0C0C0
Mwm*foreground: #000000
Mwm*activeBackground: #000080
Mwm*activeForeground: #FFFFFF
Mwm*cleanText: True
Mwm*fontList: -*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*,fixed

! Scoterm emulation
xterm*faceName: Monospace
xterm*faceSize: 10
xterm*background: #FFFFFF
xterm*foreground: #000000
xterm*scrollBar: true
xterm*rightScrollBar: true
xterm*saveLines: 5000
EOF

cp -f /usr/share/skel/dot.Xdefaults /root/.Xdefaults

for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        cp -f /usr/share/skel/dot.Xdefaults "$user_home/.Xdefaults"
        user_id=$(stat -f "%u:%g" "$user_home")
        chown "$user_id" "$user_home/.Xdefaults"
    fi
done

# --- STEP 7 : SCO DESKTOP & SYSTEM ADMINISTRATION ---
step_start "7/8: Crafting SCO Desktop Interface"

# Outil Audio Natif "SCO Volume"
cat > /usr/local/bin/scovolume << 'EOF'
#!/usr/local/bin/wish8.6
option add *background "#C0C0C0"
option add *foreground "#000000"
option add *activeBackground "#A0A0A0"
option add *font "-*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*"
option add *borderWidth 2

wm title . "Volume"
wm geometry . "+300+250"
wm resizable . 0 0

frame .pad -padx 20 -pady 20
pack .pad

label .pad.title -text "Master Audio Level" -font "-*-helvetica-bold-r-normal-*-16-*-*-*-*-*-*-*"
pack .pad.title -pady 10

scale .pad.vol -orient horizontal -from 0 -to 100 -length 250 -command set_vol -relief sunken -borderwidth 3
pack .pad.vol -pady 10

catch {
    set current [exec pactl get-sink-volume @DEFAULT_SINK@ | grep -Eo "[0-9]+%" | head -n 1 | tr -d "%"]
    .pad.vol set $current
}

proc set_vol {val} {
    catch { exec pactl set-sink-volume @DEFAULT_SINK@ $val% }
}

button .pad.close -text "Close" -width 15 -command exit -relief raised -borderwidth 3
pack .pad.close -pady 15
EOF
chmod +x /usr/local/bin/scovolume

# The System Administration Control Panel
cat > /usr/local/bin/scoadmin << 'EOF'
#!/usr/local/bin/wish8.6
option add *background "#C0C0C0"
option add *foreground "#000000"
option add *activeBackground "#A0A0A0"
option add *activeForeground "#000000"
option add *font "-*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*"
option add *borderWidth 2

proc launch {cmd} {
    catch {
        exec /bin/sh -c "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:\$PATH; $cmd" &
    }
}

wm title . "System Administration"
wm geometry . "+250+150"
wm resizable . 0 0

label .title -text "SCO System Administration" -font "-*-helvetica-bold-r-normal-*-16-*-*-*-*-*-*-*" -pady 10
pack .title -side top -fill x

frame .grid
pack .grid -padx 15 -pady 15

button .grid.disp -text "Display/X11" -width 22 -command {launch "arandr"}
button .grid.snd -text "Audio Hardware" -width 22 -command {launch "pavucontrol"}
button .grid.prt -text "Printers (CUPS)" -width 22 -command {launch "firefox http://localhost:631"}
button .grid.theme -text "Desktop Resources" -width 22 -command {launch "nedit $env(HOME)/.Xdefaults"}
button .grid.close -text "Exit Admin" -width 22 -command {exit}

grid .grid.disp .grid.snd -pady 8 -padx 8
grid .grid.prt .grid.theme -pady 8 -padx 8
grid .grid.close -columnspan 2 -pady 8 -padx 8
EOF
chmod +x /usr/local/bin/scoadmin

# The Main SCO Desktop Launcher (Now including Volume Mixer)
cat > /usr/local/bin/scodesktop << 'EOF'
#!/usr/local/bin/wish8.6
option add *background "#C0C0C0"
option add *foreground "#000000"
option add *activeBackground "#A0A0A0"
option add *activeForeground "#000000"
option add *font "-*-helvetica-bold-r-normal-*-14-*-*-*-*-*-*-*"
option add *borderWidth 3

proc launch {cmd} {
    catch {
        exec /bin/sh -c "export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:\$PATH; $cmd" &
    }
}

wm title . "Desktop"
wm geometry . "+50+50"
wm resizable . 0 0

frame .main -padx 20 -pady 20
pack .main

# Function to create large blocky buttons
proc make_btn {parent name text cmd row col} {
    button $parent.$name -text $text -width 18 -height 3 -command "launch {$cmd}" -relief raised -borderwidth 3
    grid $parent.$name -row $row -column $col -padx 10 -pady 10
}

make_btn .main unix "UNIX\n(Korn Shell)" "xterm -name scoterm -title 'UNIX System V' -e ksh93" 0 0
make_btn .main files "Files\n(Directory)" "xfe" 0 1
make_btn .main edit "Edit\n(Text Editor)" "nedit" 1 0
make_btn .main sysadmin "System Admin\n(Controls)" "/usr/local/bin/scoadmin" 1 1
make_btn .main net "Network\n(Browser)" "firefox" 2 0
make_btn .main perf "Performance\n(xosview)" "xosview" 2 1
make_btn .main vol "Volume\n(Mixer)" "/usr/local/bin/scovolume" 3 0

frame .power -pady 10
pack .power -side bottom -fill x

button .power.logout -text "Log Out" -width 15 -command {launch "killall mwm"}
button .power.reboot -text "Reboot" -width 15 -command {launch "/sbin/shutdown -r now"}
button .power.halt -text "Halt System" -width 15 -command {launch "/sbin/shutdown -p now"}

grid .power.logout .power.reboot .power.halt -padx 5
EOF
chmod +x /usr/local/bin/scodesktop

# Motif Bindings
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

# --- STEP 8 : NATIVE SYSTEM V SESSION MANAGER ---
step_start "8/8: Creating System V Session Script"

cat > /usr/local/bin/start_pure_sco << EOF
#!/bin/sh
export LANG="$USER_LOCALE"
export LC_ALL="$USER_LOCALE"

if [ -f "\$HOME/.Xdefaults" ]; then
    xrdb -merge "\$HOME/.Xdefaults"
fi

# The Legendary SCO Solid Blue Desktop
xsetroot -solid "#0000AA" &
xset b off 2>/dev/null

pulseaudio --kill 2>/dev/null || true
pulseaudio --start --exit-idle-time=-1 2>/dev/null &

# Launch the SCO Desktop Interface
/usr/local/bin/scodesktop &

exec /usr/local/bin/mwm -xrm "Mwm*configFile: /usr/local/etc/X11/mwm/system.mwmrc"
EOF
chmod +x /usr/local/bin/start_pure_sco

mkdir -p /usr/local/share/xsessions
cat > /usr/local/share/xsessions/pure-sco.desktop << 'EOF'
[Desktop Entry]
Name=Pure SCO (OpenDesktop System V)
Exec=/usr/local/bin/start_pure_sco
Type=Application
EOF

printf "\n\033[1;32m[ DONE ] Pure-SCO OpenDesktop installation complete.\033[0m\n"
printf "Please reboot your system to enter the System V era.\n"

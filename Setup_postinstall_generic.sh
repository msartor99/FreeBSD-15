#!/bin/sh

# ==============================================================================
# SCRIPT DE POST-INSTALLATION FREEBSD 15
# Version: 3.9 - Localisation Complète + Pack Polices Microsoft
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

pkg install -y bsddialog > /dev/null 2>&1

# 1. SÉLECTION DE LA LOCALISATION ET DU CLAVIER
CHOIX_KBD=$(bsddialog --title "Configuration Régionale" \
    --menu "Choisissez votre langue et disposition clavier :" 18 70 8 \
    "ch_fr" "Suisse Romand (Keyboard: ch fr / Lang: fr_CH)" \
    "ch_de" "Suisse Allemand (Keyboard: ch de / Lang: de_CH)" \
    "fr"    "France (Keyboard: fr / Lang: fr_FR)" \
    "de"    "Allemagne (Keyboard: de / Lang: de_DE)" \
    "it"    "Italie (Keyboard: it / Lang: it_IT)" \
    "pt"    "Portugal (Keyboard: pt / Lang: pt_PT)" \
    "us"    "USA (Keyboard: us / Lang: en_US)" \
    "uk"    "United Kingdom (Keyboard: gb / Lang: en_GB)" 3>&1 1>&2 2>&3)

case $CHOIX_KBD in
    "ch_fr") K_LAYOUT="ch"; K_VARIANT="fr"; L_CODE="fr_CH"; CLASS="swiss_fr" ;;
    "ch_de") K_LAYOUT="ch"; K_VARIANT="de"; L_CODE="de_CH"; CLASS="swiss_de" ;;
    "fr")    K_LAYOUT="fr"; K_VARIANT="";   L_CODE="fr_FR"; CLASS="french"   ;;
    "de")    K_LAYOUT="de"; K_VARIANT="";   L_CODE="de_DE"; CLASS="german"   ;;
    "it")    K_LAYOUT="it"; K_VARIANT="";   L_CODE="it_IT"; CLASS="italian"  ;;
    "pt")    K_LAYOUT="pt"; K_VARIANT="";   L_CODE="pt_PT"; CLASS="portuguese" ;;
    "us")    K_LAYOUT="us"; K_VARIANT="";   L_CODE="en_US"; CLASS="english"  ;;
    "uk")    K_LAYOUT="gb"; K_VARIANT="";   L_CODE="en_GB"; CLASS="english_uk" ;;
    *) exit 1 ;;
esac

# 2. GESTION DE L'UTILISATEUR
TYPE_USER=$(bsddialog --title "Gestion Utilisateur" \
    --menu "Option :" 12 60 2 \
    "NEW" "Créer un nouvel utilisateur complet" \
    "EXISTING" "Utiliser un utilisateur existant" 3>&1 1>&2 2>&3)

case $TYPE_USER in
    "NEW")
        USER_NAME=$(bsddialog --title "Login" --inputbox "Nom de login :" 10 50 3>&1 1>&2 2>&3)
        REAL_NAME=$(bsddialog --title "Nom Réel" --inputbox "Nom complet :" 10 50 3>&1 1>&2 2>&3)
        USER_PASS=$(bsddialog --title "Mot de passe" --passwordbox "Entrez le mot de passe :" 10 50 3>&1 1>&2 2>&3)
        echo "$USER_PASS" | pw useradd "$USER_NAME" -m -G wheel,operator,video -s /bin/sh -c "$REAL_NAME" -h 0
        ;;
    "EXISTING")
        USER_NAME=$(bsddialog --title "Existant" --inputbox "Nom de l'utilisateur :" 10 50 3>&1 1>&2 2>&3)
        pw usermod "$USER_NAME" -G wheel,operator,video 2>/dev/null
        ;;
esac

# 3. MATÉRIEL (CPU / GPU)
CHOIX_CPU=$(bsddialog --title "CPU" --menu "Type de processeur :" 12 60 2 "AMD" "AMD" "INTEL" "Intel" 3>&1 1>&2 2>&3)
CHOIX_GPU=$(bsddialog --title "GPU" --menu "Carte graphique :" 12 60 2 "AMD" "Wayland/X11" "NVIDIA" "X11 Uniquement" 3>&1 1>&2 2>&3)

# 4. MISE À JOUR ET RÉSEAU
sed -i '' -e 's/quarterly/latest/g' /etc/pkg/FreeBSD.conf
pkg update -f && pkg upgrade -y
pkg install -y realtek-re-kmod
sysrc kld_list+="if_re"

# 5. CONFIGURATION LOGIN.CONF (Dynamique)
if ! grep -q "$CLASS" /etc/login.conf; then
    cat >> /etc/login.conf <<EOF

$CLASS|Custom User Class:\\
    :charset=UTF-8:\\
    :lang=${L_CODE}.UTF-8:\\
    :tc=default:
EOF
    cap_mkdb /etc/login.conf
fi
echo "defaultclass=$CLASS" > /etc/adduser.conf
pw usermod "$USER_NAME" -L "$CLASS"

# 6. CONFIGURATION CPU (Microcode)
case $CHOIX_CPU in
    "AMD")   pkg install -y cpu-microcode-amd ; sysrc -f /boot/loader.conf amdtemp_load="YES" ; echo 'cpu_microcode_name="/boot/firmware/amd-ucode.bin"' >> /boot/loader.conf ;;
    "INTEL") pkg install -y cpu-microcode-intel ; sysrc -f /boot/loader.conf coretemp_load="YES" ; echo 'cpu_microcode_name="/boot/firmware/intel-ucode.bin"' >> /boot/loader.conf ;;
esac
echo 'cpu_microcode_load="YES"' >> /boot/loader.conf

# 7. POLICES DE CARACTÈRES (MICROSOFT & WEB)
# On accepte la licence des webfonts automatiquement
pkg install -y webfonts dejavu noto-basic liberation-fonts-ttf
mkdir -p /usr/local/etc/fonts/conf.d
ln -s /usr/local/etc/fonts/conf.avail/70-no-bitmaps.conf /usr/local/etc/fonts/conf.d/ 2>/dev/null || true

# 8. CLAVIER X11
mkdir -p /usr/local/etc/X11/xorg.conf.d
cat > /usr/local/etc/X11/xorg.conf.d/20-keyboard.conf <<EOF
Section "InputClass"
    Identifier "KeyboardDefaults"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$K_LAYOUT"
    Option "XkbVariant" "$K_VARIANT"
EndSection
EOF

# 9. PLASMA 6, SDDM ET LOGICIELS
pkg install -y xorg dbus avahi-app seatd sddm plasma6-plasma firefox vlc ffmpeg
sysrc dbus_enable="YES"
sysrc sddm_enable="YES"
sysrc sddm_lang="${L_CODE}.UTF-8"

cat > /usr/local/etc/sddm.conf <<EOF
[X11]
Layout=$K_LAYOUT
Variant=$K_VARIANT
[Wayland]
GreeterEnvironment=XKB_DEFAULT_LAYOUT=$K_LAYOUT,XKB_DEFAULT_VARIANT=$K_VARIANT
EOF

# 10. CONFIGURATION GPU
case $CHOIX_GPU in
    "AMD")
        pkg install -y drm-kmod wayland xwayland wayfire wf-shell
        sysrc kld_list+="amdgpu"
        USER_HOME="/home/$USER_NAME"
        if [ -d "$USER_HOME" ]; then
            mkdir -p "$USER_HOME/.config/wayfire"
            cp /usr/local/share/examples/wayfire/wayfire.ini "$USER_HOME/.config/wayfire/"
            cat >> "$USER_HOME/.config/wayfire/wayfire.ini" <<EOF
[input]
xkb_layout = $K_LAYOUT
xkb_variant = $K_VARIANT
[core]
xwayland = true
EOF
            chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"
        fi
        ;;
    "NVIDIA")
        pkg install -y nvidia-driver nvidia-settings nvidia-xconfig
        sysrc kld_list+="nvidia-modeset"
        nvidia-xconfig
        ;;
esac

# 11. SAMBA ET VIRTUALBOX
pkg install -y samba416 virtualbox-ose-72
mkdir -p /home/share && chmod 777 /home/share
printf "[global]\n\tworkgroup = MAISON\n\tmap to guest = bad user\n[Share]\n\tpath = /home/share\n\tguest ok = yes\n\twritable = yes\n" > /usr/local/etc/smb4.conf
sysrc samba_server_enable="YES"
echo 'vboxdrv_load="YES"' >> /boot/loader.conf
pw groupmod vboxusers -m "$USER_NAME" 2>/dev/null || true

bsddialog --msgbox "Post-installation terminée !\n\nLangue : $L_CODE\nPolices Microsoft : Installées\nUtilisateur : $USER_NAME\n\nRedémarrez le système." 15 60
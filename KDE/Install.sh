#!/bin/bash

# Install Apps from pacman
sudo pacman -S bcachefs-tools btrfs-progs dosfstools exfatprogs f2fs-tools e2fsprogs jfsutils mtd-utils nilfs-utils ntfs-3g udftools xfsprogs plymouth fwupd adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts adobe-source-sans-fonts adobe-source-serif-fonts android-tools android-udev darktable flameshot qbittorrent gamemode gimp krita partitionmanager kdenlive libreoffice-fresh mangohud noto-fonts-emoji obs-studio prismlauncher steam ttf-dejavu ttf-liberation vlc vlc-plugins-all nfs-utils pcsclite ccid opensc ttf-firacode-nerd cups freecad audacity solaar element-desktop syncthing lact wine nodejs qt6-multimedia-ffmpeg jre-openjdk lib32-vulkan-radeon sbctl chromium btop fastfetch zsh noto-fonts exa ttf-jetbrains-mono-nerd otf-codenewroman-nerd grim discord yubikey-manager pam-u2f libfido2 yubikey-full-disk-encryption ghostscript skanlite sane-airscan --needed

# Install yay
git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si && cd && rm -rf /home/$USER/yay

# Install Apps from yay
yay -S onthespot-git github-desktop eid-mw feishin-bin heroic-games-launcher-bin jdownloader2 protonup-qt orca-slicer-bin auto-cpufreq mangojuice-bin librewolf-bin localsend-bin opendeck imsprog ubports-installer vscodium-bin vscodium-bin-marketplace yubico-authenticator --needed

# Remove leftover install files
sudo pacman -Rscnu $(pacman -Qdtq) --noconfirm && sudo pacman -Sc --noconfirm && yay -Sc --noconfirm && yay -Yc --noconfirm

# Enable Services
sudo systemctl enable --now pcscd.service && sudo systemctl enable --now cups && sudo systemctl enable --now auto-cpufreq && sudo systemctl enable --now syncthing@$USER.service && sudo systemctl enable --now fwupd-refresh.timer && sudo systemctl enable greetd && sudo systemctl enable --now lactd && sudo systemctl enable --now avahi-daemon

# Create directories for mounting disks
sudo mkdir /media && sudo mkdir /media/TrueNAS && sudo mkdir /media/Games && sudo mkdir /media/Recordings && sudo mkdir /media/Data

# Make all folder in /media writable
sudo chmod 777 /media /media/Games /media/Recordings /media/Data

# Copy .zshrc
cp "VK-Dotfiles/KDE/.zshrc" -r /home/$USER/
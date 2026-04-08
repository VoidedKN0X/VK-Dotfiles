#!/bin/bash

# Install Apps from pacman
sudo pacman -S bcachefs-tools btrfs-progs dosfstools exfatprogs f2fs-tools e2fsprogs jfsutils mtd-utils nilfs-utils ntfs-3g udftools xfsprogs plymouth fwupd adobe-source-han-sans-otc-fonts adobe-source-han-serif-otc-fonts adobe-source-sans-fonts adobe-source-serif-fonts android-tools android-udev darktable flameshot qbittorrent gamemode gimp krita wget partitionmanager kdenlive libreoffice-fresh mangohud noto-fonts-emoji obs-studio prismlauncher steam ttf-dejavu ttf-liberation mpv nfs-utils pcsclite ccid opensc ttf-firacode-nerd cups freecad audacity rhythmbox solaar greetd greetd-tuigreet gnome-keyring unzip papers element-desktop syncthing ark unrar qt6-multimedia-ffmpeg jre-openjdk lib32-vulkan-intel sbctl ollama ollama-rocm intel-compute-runtime chromium xdg-user-dirs hyprland hyprlock hypridle hyprpolkitagent btop fastfetch awww thunar foot nano git base-devel zsh rofi waybar swaync noto-fonts ristretto exa ttf-jetbrains-mono-nerd pavucontrol nwg-look orchis-theme papirus-icon-theme otf-codenewroman-nerd qt5ct breeze-icons breeze grim --needed

# Install yay
git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si && cd && rm -rf /home/$USER/yay

# Install Apps from yay
yay -S cnijfilter2 eid-mw feishin-bin heroic-games-launcher-bin jdownloader2 protonplus scangearmp2-sane-git orca-slicer-bin auto-cpufreq mangojuice-bin librewolf-bin localsend-bin obs-aitum-multistream-bin obs-plugin-browser imsprog ubports-installer vscodium-bin vscodium-bin-marketplace bibata-cursor-theme-bin waybar-module-music-git qt6ct-kde --noconfirm

# Remove leftover install files
sudo pacman -Rscnu $(pacman -Qdtq) --noconfirm && sudo pacman -Sc --noconfirm && yay -Sc --noconfirm && yay -Yc --noconfirm

# Enable Services
sudo systemctl enable --now pcscd.service && sudo systemctl enable --now cups && sudo systemctl enable --now auto-cpufreq && sudo systemctl enable --now syncthing@$USER.service && sudo systemctl enable --now fwupd-refresh.timer && sudo systemctl enable greetd && sudo systemctl enable --now ollama

# Create directories for mounting disks
sudo mkdir /media && sudo mkdir /media/TrueNAS

# Add home directories
xdg-user-dirs-update

# Copy .config folder
cp "VK-Dotfiles/Asus Laptop/.config" -r /home/$USER/

# Copy .zshrc
cp "VK-Dotfiles/Asus Laptop/.zshrc" -r /home/$USER/
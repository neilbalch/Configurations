#!/bin/bash

# https://stackoverflow.com/a/36273740/3339274
set -x

# Clone git repo or just fetch relevant files
clone_repo = true

# Install most-used packages
sudo apt install -y \
  vim git cmake make ant openjdk-17-jre-headless \
  proot qemu-user-static qemu-utils \
  stlink-tools \
  neofetch gnome-system-monitor top htop bmon iotop \
  iperf3 qdirstat rsync screen x11-apps

# Install vscode
wget "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O vscode.deb
sudo dpkg -i vscode.deb
rm vscode.deb

# Clone configurations repo
if [ $clone_repo == true ]; then
  cd ~
  if [ ! -d ~/Configurations ]; then
    git clone https://github.com/neilbalch/Configurations.git
  fi
fi

# Add all dotfiles to the right places
if [ ! -d ~/.ssh ]; then
   mkdir ~/.ssh
fi
if [ $clone_repo == true ]; then
  cp ~/Configurations/Linux/.sshconfig ~/.ssh/config
  cp ~/Configurations/Linux/.bashrc ~/
  cp ~/Configurations/Linux/.vimrc ~/
  cp ~/Configurations/Linux/.gitconfig ~/
else
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.sshConfig -O ~/.ssh/config
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.bashrc -O ~/.bashrc
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.vimrc -O ~/.vimrc
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.gitconfig -O ~/.gitconfig
fi

# Install vscode extensions
wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extension_installer.py
wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extensions_list.txt
./extension_installer.py
rm extension_installer.py extensions_list.txt

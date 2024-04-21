#!/bin/bash

# https://stackoverflow.com/a/36273740/3339274
set -x

# Clone git repo or just fetch relevant files
clone_repo = true

# Install most-used packages and update all others
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y \
  vim git cmake make ant openjdk-17-jre-headless \
  python3 python3-pip \
  proot qemu-user-static qemu-utils \
  stlink-tools openocd \
  neofetch gnome-system-monitor htop bmon iotop qdirstat \
  iperf3 qdirstat rsync screen tmux x11-apps xcowsay \
  unattended-upgrades smartmontools \
  zoxide
sudo pip3 install black pyserial

# Install Bazel
# https://bazel.build/install/ubuntu
sudo apt install apt-transport-https curl gnupg -y
curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor >bazel-archive-keyring.gpg
sudo mv bazel-archive-keyring.gpg /usr/share/keyrings
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
sudo apt update
sudo apt install bazel -y

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
   ssh-keygen -f ~/.ssh/id_rsa -N ""
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
if [ $clone_repo == true ]; then
  cp ~/Configurations/VSCode/extensions_list.txt .
  ~/Configurations/VSCode/extension_installer.py
  rm extensions_list.txt
else
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extension_installer.py
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extensions_list.txt
  ./extension_installer.py
  rm extension_installer.py extensions_list.txt
fi

# If WSL2, then do the legwork to enable usbipd
# https://github.com/dorssel/usbipd-win/wiki/WSL-support
if uname -a | grep "WSL2" > /dev/null || uname -a | grep "Microsoft" > /dev/null; then
  sudo apt install linux-tools-virtual hwdata
  sudo update-alternatives --install /usr/local/bin/usbip usbip `ls /usr/lib/linux-tools/*/usbip | tail -n1` 20
fi

# Enable mDNS (NOTE: a specific interface must still be attached manually!)
sudo systemctl enable systemd-resolved.service
sudo systemctl start systemd-resolved.service

# Just for fun :)
neofetch

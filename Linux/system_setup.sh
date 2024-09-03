#!/bin/bash

# ------------------------------------------------------------------------------
# Flags
# ------------------------------------------------------------------------------
# Clone git repo or just fetch relevant files
clone_repo=true
# Set which package categories to install
install_apt_utilities=true
install_apt_programming=true
install_apt_rpi=true
install_apt_install_deps=true
# ------------------------------------------------------------------------------
# Settings
# ------------------------------------------------------------------------------
# TODO: onboard desktop tools (Firefox, kdenlive, obs, spotify, discord,
# blender, resolve?, keepassxc, steam, notion, filezilla?, GIMP, GitHub Desktop,
# Google Drive?, GPX viewer, Inkscape, KiCad, Legion toolkit?, Logitech client?,
# Libreoffice/openoffice, vlc, Nvidia/AMD/Intel driver, OpenRocket, OpenVPN?,
# Prusaslicer, Pulseview, qBittorrent, RPi imager, VNC, STM32Cube?, Teamviewer,
# TI Connect?, etc.)
apt_utilities="bmon ffmpeg fio gnome-system-monitor gparted htop iotop iperf3 \
               neofetch qdirstat rsync screen smartmontools tmux \
               unattended-upgrades vim x11-apps xcowsay zoxide"
# TODO: onboard FPGA toolchains (Vivado, @sifferman/tangnano_example)
# TODO: onboard Rust toolchains?
apt_programming="ant cmake code git make openjdk-17-jre-headless openocd \
                 stlink-tools"
apt_rpi="proot qemu-user-static qemu-utils"
# Required by:    Bazel,  Global Python Packages,
apt_install_deps="golang pipx python3 python3-pip"

pip_packages=("black" "pyserial" "youtube_dl")
# ------------------------------------------------------------------------------

apt_packages="" # Filled in later
# https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Conditional_Expressions
[[ $install_apt_utilities = true ]] && apt_packages="${apt_packages} ${apt_utilities}"
[[ $install_apt_programming = true ]] && apt_packages="${apt_packages} ${apt_programming}"
[[ $install_apt_rpi = true ]] && apt_packages="${apt_packages} ${apt_rpi}"
[[ $install_apt_install_deps = true ]] && apt_packages="${apt_packages} ${apt_install_deps}"

# https://stackoverflow.com/a/36273740/3339274
set -x

# Install most-used packages and update all others
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y $apt_packages
# Patch for Zoxide installation (not yet in apt sources)
# https://github.com/ajeetdsouza/zoxide
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
# https://stackoverflow.com/a/8880625/3339274
for i in "${pip_packages[@]}"; do
  # :rolling_eyes: https://stackoverflow.com/a/75722775/3339274
  pipx install "$i"
done

# ------------------------------------------------------------------------------
# Platform-specific installations
# ------------------------------------------------------------------------------
if uname -m | grep "x86_64" > /dev/null; then
  echo "Installing x86 apps..."
  # Install Bazel
  # https://bazel.build/install/ubuntu
  sudo apt install apt-transport-https curl gnupg -y
  curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor >bazel-archive-keyring.gpg
  sudo mv bazel-archive-keyring.gpg /usr/share/keyrings
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
  sudo apt update
  sudo apt install bazel -y

  # If WSL2, then do the legwork to enable usbipd
  # https://github.com/dorssel/usbipd-win/wiki/WSL-support
  echo "Installing WSL2 usbipd tools..."
  if uname -a | grep "WSL2" > /dev/null || uname -a | grep "Microsoft" > /dev/null; then
    sudo apt install linux-tools-virtual hwdata
    sudo update-alternatives --install /usr/local/bin/usbip usbip `ls /usr/lib/linux-tools/*/usbip | tail -n1` 20
  fi
elif uname -m | grep "aarch64" > /dev/null; then
  echo "Installing aarch64 apps..."
  # Install Bazel through Bazelisk, then use `bazelisk ...` instead of `bazel ...`
  # https://bazel.build/versions/6.4.0/install/bazelisk
  # https://github.com/bazelbuild/bazelisk?tab=readme-ov-file#requirements
  go install github.com/bazelbuild/bazelisk@latest
fi

# Generate SSH keys
if [ ! -d ~/.ssh ]; then
   mkdir ~/.ssh
   ssh-keygen -f ~/.ssh/id_rsa -N ""
fi

# ------------------------------------------------------------------------------
# Apply customizations from @neilbalch/Configurations repo
# ------------------------------------------------------------------------------
if [ $clone_repo = true ]; then
  if [ ! -d ~/Configurations ]; then
    git clone https://github.com/neilbalch/Configurations.git ~/Configurations
  fi

  # Apply dotfiles
  cp ~/Configurations/Linux/.sshConfig ~/.ssh/config
  cp ~/Configurations/Linux/.bashrc ~/
  cp ~/Configurations/Linux/.vimrc ~/
  mkdir -p $HOME/.cache/vim/swapfiles
  mkdir -p /root
  sudo cp ~/Configurations/Linux/.vimrc /root/
  sudo mkdir -p /root/.cache/vim/swapfiles
  cp ~/Configurations/Linux/.gitconfig ~/

  # Install vscode extensions
  cp ~/Configurations/VSCode/extensions_list.txt .
  python3 ~/Configurations/VSCode/extension_installer.py
  rm extensions_list.txt
else
  # Apply dotfiles
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.sshConfig -O ~/.ssh/config
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.bashrc -O ~/.bashrc
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.vimrc -O ~/.vimrc
  mkdir -p $HOME/.cache/vim/swapfiles
  mkdir -p /root
  sudo wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.vimrc -O /root/.vimrc
  sudo mkdir -p /root/.cache/vim/swapfiles
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/Linux/.gitconfig -O ~/.gitconfig

  # Install vscode extensions
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extension_installer.py
  wget https://raw.githubusercontent.com/neilbalch/Configurations/master/VSCode/extensions_list.txt
  ./extension_installer.py
  rm extension_installer.py extensions_list.txt
fi

# Just for fun :)
neofetch

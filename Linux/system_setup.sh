#!/bin/bash

# ------------------------------------------------------------------------------
# Flags and Settings
# ------------------------------------------------------------------------------
# Clone git repo or just fetch relevant files
clone_repo=true
# Set which package categories to install
install_apt_desktop=false       # Packages for Desktop Linux
install_apt_utilities=true      # CLI utilities
install_apt_programming=true    # Programming tools
install_fpga=true               # FPGA programming tools
install_apt_rpi=true            # Raspberry Pi config tools
install_apt_install_deps=true   # Install dependencies for other packages
                                #  should really never be turned off
# Thread count for Make builds
# Consider only using 1/2 threads on Raspberry Pi to prevent >1G RAM usage from
# hitting the swapfile and TANKING build performance
build_threads=$(nproc)
# ------------------------------------------------------------------------------
# Package Lists
# ------------------------------------------------------------------------------
# TODO: add desktop tools (Resolve, Legion toolkit, Nvidia/AMD/Intel driver,
#  OpenRocket, RealVNC Viewer, Teamviewer, TI Connect CE)
# Fusion 360? https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux
apt_desktop="blender filezilla firefox gh gimp gpxsee inkscape kdenlive \
             keepassxc kicad libreoffice obs-studio openvpn prusa-slicer \
             pulseview qbittorrent rpi-imager spotify-client steam-installer \
             vlc"
apt_utilities="bmon ffmpeg fio flatpak gnome-system-monitor gparted htop iotop \
               iperf3 neofetch pv qdirstat rsync screen smartmontools tmux \
               unattended-upgrades vim x11-apps xcowsay zoxide"
# TODO: add desktop FPGA toolchains (Vivado) and STM32Cube
apt_programming="ant cmake code git make openjdk-17-jre-headless openocd \
                 rustup stlink-tools"
apt_fpga="cmake libboost-dev libboost-filesystem-dev libboost-thread-dev \
          libboost-program-options-dev libboost-iostreams-dev libboost-dev \
          libeigen3-dev"
apt_rpi="proot qemu-user-static qemu-utils"
# Required by:    Bazel,  Global Python Packages,
apt_install_deps="golang pipx python3 python3-pip"

# https://flathub.org
# TODO: Any of these important? https://flathub.org/apps/category/System/1
flatpak_desktop="com.discordapp.Discord com.hunterwittenborn.Celeste \
                 io.github.brunofin.Cohesion io.github.nokse22.Exhibit \
                 io.github.pwr_solaar.solaar io.github.shiftey.Desktop \
                 org.stellarium.Stellarium"

pip_packages=("black" "pyserial" "youtube_dl")
# OSS Gowin bitstream tools: https://github.com/YosysHQ/apicula
pip_fpga=("fusesoc" "apycula")
# ------------------------------------------------------------------------------

apt_packages="" # Filled in later
# https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Conditional_Expressions
[ $install_apt_desktop = true ] && apt_packages="${apt_packages} ${apt_desktop}"
[ $install_apt_utilities = true ] && apt_packages="${apt_packages} ${apt_utilities}"
[ $install_apt_programming = true ] && apt_packages="${apt_packages} ${apt_programming}"
[ $install_fpga = true ] && apt_packages="${apt_packages} ${apt_fpga}"
[ $install_apt_rpi = true ] && apt_packages="${apt_packages} ${apt_rpi}"
[ $install_apt_install_deps = true ] && apt_packages="${apt_packages} ${apt_install_deps}"
# https://linuxsimply.com/bash-scripting-tutorial/array/array-operations/array-append
[ $install_fpga = true ] && pip_packages=(${pip_packages[@]} ${pip_fpga[@]})

# https://stackoverflow.com/a/36273740/3339274
set -x

# Install most-used packages and update all others
if [ $install_desktop ]; then
  # https://www.spotify.com/us/download/linux
  curl -sS https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
  echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
  # https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  # https://software.opensuse.org/download.html?project=home%3Atumic%3AGPXSee&package=gpxsee
  echo 'deb http://download.opensuse.org/repositories/home:/tumic:/GPXSee/xUbuntu_24.04/ /' | sudo tee /etc/apt/sources.list.d/home:tumic:GPXSee.list
  curl -fsSL https://download.opensuse.org/repositories/home:tumic:GPXSee/xUbuntu_24.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_tumic_GPXSee.gpg > /dev/null
fi
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y $apt_packages
if [ $install_desktop ]; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y $flatpak_desktop
fi
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

# ------------------------------------------------------------------------------
# Tools init
# ------------------------------------------------------------------------------

# FPGAs?
if [ $install_fpga ]; then
  echo "Installing OSS FPGA toolchain"
  # fusesoc init # Deprecated at some point?

  # Install OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build
  if ! which yosys > /dev/null; then
    # Download the right binary!
    if uname -m | grep "x86_64" > /dev/null; then
      echo "Installing x86 oss-cad-suite..."
      wget -O oss-cad-suite.tgz "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-09-04/oss-cad-suite-linux-x64-20240904.tgz"
    elif uname -m | grep "aarch64" > /dev/null; then
      echo "Installing aarch64 oss-cad-suite..."
      wget -O oss-cad-suite.tgz "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-09-04/oss-cad-suite-linux-arm64-20240904.tgz"
    fi

    # https://superuser.com/a/1601085/342885
    pv oss-cad-suite.tgz | tar -xz
    rm oss-cad-suite.tgz
    # TODO: Should more directories be copied over?
    sudo cp oss-cad-suite/bin/* /usr/local/bin/
    sudo cp -r oss-cad-suite/lib/* /usr/local/lib/
    sudo mkdir -p /usr/local/libexec
    sudo cp -r oss-cad-suite/libexec/* /usr/local/libexec
    sudo cp -r oss-cad-suite/share/* /usr/local/share
    rm -rf oss-cad-suite
  else
    echo "Skipping OSS Cad Suite install, it already exists!"
  fi

  # Install nextpnr-gowin (not yet packaged with OSS CAD Suite)
  git clone https://github.com/YosysHQ/nextpnr
  cd nextpnr
  cmake . -DARCH=gowin
  make -j${build_threads}
  sudo make install
  cd ..
  rm -rf nextpnr
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

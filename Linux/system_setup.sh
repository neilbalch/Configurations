#!/bin/bash

# ------------------------------------------------------------------------------
# Default Flags and Settings
# ------------------------------------------------------------------------------
# Clone git repo or just fetch relevant files
clone_repo=true
# Set which package categories to install
install_desktop=false       # Packages for Desktop Linux
install_utilities=false     # CLI utilities
install_programming=false   # Programming tools
install_fpga=false          # FPGA programming tools
install_rpi=false           # Raspberry Pi config tools
install_install_deps=true   # Install dependencies for other packages

# Thread count for Make builds
# Consider only using 1/2 threads on Raspberry Pi to prevent >1G RAM usage from
# hitting the swapfile and TANKING build performance
build_threads=$(nproc)
# OSS CAD Suite build date
oss_build="2024-09-04"
# ------------------------------------------------------------------------------
# Package Lists
# ------------------------------------------------------------------------------
# TODO: add GPU driver instlalls? (Nvidia/AMD/Intel)
# TODO: add desktop tools (Resolve, OpenRocket)
# TODO: Fusion 360? https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux
apt_desktop="blender filezilla firefox gh gimp gpxsee inkscape kdenlive \
             keepassxc kicad libreoffice obs-studio openvpn prusa-slicer \
             pulseview qbittorrent rpi-imager spotify-client steam-installer \
             vlc"
apt_utilities="bmon ffmpeg fio flatpak gnome-system-monitor gparted htop iotop \
               iperf3 neofetch pv qdirstat rsync screen smartmontools tmux \
               unattended-upgrades vim x11-apps xcowsay zoxide"
apt_programming="ant cmake code git make openjdk-17-jre-headless openocd \
                 stlink-tools"
apt_teamviewer="libminizip1"
apt_sdrpp="g++ make cmake libfftw3-dev libglfw3 libvolk2-dev zstd"
apt_openhantek="g++ make cmake fakeroot qttools5-dev libfftw3-dev binutils-dev \
                libusb-1.0-0-dev libqt5opengl5-dev mesa-common-dev \
                libgl1-mesa-dev libgles2-mesa-dev rpm"
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

# https://github.com/ytdl-org/youtube-dl
# https://github.com/dlenski/python-vipaccess
pip_packages=("black" "pyserial" "youtube_dl" "python-vipaccess")
# OSS Gowin bitstream tools: https://github.com/YosysHQ/apicula
pip_fpga=("fusesoc" "apycula")
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# apt and flatpak installs
# ------------------------------------------------------------------------------
apt_and_flatpak() {
  apt_packages="" # Filled in later
  # https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Conditional_Expressions
  [ $install_desktop = true ] && apt_packages="${apt_packages} ${apt_desktop} ${apt_teamviewer}"
  [ $install_utilities = true ] && apt_packages="${apt_packages} ${apt_utilities}"
  [ $install_programming = true ] && apt_packages="${apt_packages} ${apt_programming} ${apt_sdrpp} ${apt_openhantek}"
  [ $install_fpga = true ] && apt_packages="${apt_packages} ${apt_fpga}"
  [ $install_rpi = true ] && apt_packages="${apt_packages} ${apt_rpi}"
  [ $install_install_deps = true ] && apt_packages="${apt_packages} ${apt_install_deps}"
  # https://linuxsimply.com/bash-scripting-tutorial/array/array-operations/array-append
  [ $install_fpga = true ] && pip_packages=(${pip_packages[@]} ${pip_fpga[@]})

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

  # https://stackoverflow.com/a/8880625/3339274
  for i in "${pip_packages[@]}"; do
    # :rolling_eyes: https://stackoverflow.com/a/75722775/3339274
    pipx install "$i"
  done

  # Patch for Zoxide installation (not yet in apt sources)
  # https://github.com/ajeetdsouza/zoxide
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

  if [ $install_programming ]; then
    # Rustup is not in apt, only in snap 🤮
    # https://rust-lang.github.io/rustup/installation/other.html
    curl --proto '=https' --tlsv1.3 https://sh.rustup.rs -sSf | sh -s -- -y
    echo "# Init Rust environment\nsource \"$HOME/.cargo/env\"\n" >> $HOME/.bashrc
  fi
}

# ------------------------------------------------------------------------------
# Platform-specific installations
# ------------------------------------------------------------------------------
platform() {
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
}

# ------------------------------------------------------------------------------
# Tools init
# ------------------------------------------------------------------------------
tools() {
  # FPGAs?`
  if [ $install_fpga ]; then
    echo "Installing OSS FPGA toolchain"
    # fusesoc init # Deprecated at some point?

    # Install OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build
    if ! which yosys > /dev/null; then
      # Download the right binary!
      # https://stackoverflow.com/a/23909383/3339274
      if uname -m | grep "x86_64" > /dev/null; then
        echo "Installing x86 oss-cad-suite..."
        wget -O oss-cad-suite.tgz "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${oss_build}/oss-cad-suite-linux-x64-$(date -d ${oss_build} +'%Y%m%d').tgz"
      elif uname -m | grep "aarch64" > /dev/null; then
        echo "Installing aarch64 oss-cad-suite..."
        wget -O oss-cad-suite.tgz "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${oss_build}/oss-cad-suite-linux-arm64-$(date -d ${oss_build} +'%Y%m%d').tgz"
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

    if ! which nextpnr-gowin > /dev/null; then
      # Install nextpnr-gowin (not yet packaged with OSS CAD Suite)
      git clone https://github.com/YosysHQ/nextpnr
      cd nextpnr
      cmake . -DARCH=gowin
      make -j${build_threads}
      sudo make install
      cd ..
      rm -rf nextpnr
    else
      echo "Skipping nextpnr-gowin install, it already exists!"
    fi

  fi

  if [ $install_desktop ] && ! which teamviewer > /dev/null; then
    # Teamviewer install
    if uname -m | grep "x86_64" > /dev/null; then
      echo "Installing x86 Teamviewer..."
      wget -O teamviewer.deb "https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"
    elif uname -m | grep "aarch64" > /dev/null; then
      echo "Installing aarch64 Teamviewer..."
      wget -O teamviewer.deb "https://download.teamviewer.com/download/linux/teamviewer_arm64.deb"
    fi

    sudo dpkg -i teamviewer.deb
    rm teamviewer.deb
  fi

  if [ $install_programming ] && ! which sdrpp > /dev/null; then
    # Install SDR++
    # https://github.com/AlexandreRouma/SDRPlusPlus?tab=readme-ov-file#building-on-linux--bsd
    git clone https://github.com/AlexandreRouma/SDRPlusPlus
    mkdir SDRPlusPlus/build
    cd SDRPlusPlus/build
    cmake ..
    make -j${build_threads}
    sudo make install
    cd ../..
    rm -rf SDRPlusPlus
  fi

  if [ $install_programming ] && ! which OpenHantek > /dev/null; then
    # Install OpenHantek
    # https://github.com/OpenHantek/OpenHantek6022
    git clone https://github.com/OpenHantek/OpenHantek6022
    mkdir OpenHantek6022/build
    cd OpenHantek6022/build
    cmake ..
    make -j${build_threads}
    sudo make install
    cd ../..
    rm -rf OpenHantek6022
  fi

  # Generate SSH keys
  if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
    ssh-keygen -f ~/.ssh/id_rsa -N ""
  fi
}

# ------------------------------------------------------------------------------
# Apply customizations from @neilbalch/Configurations repo
# ------------------------------------------------------------------------------
configurations() {
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
}

# Debug mode: https://stackoverflow.com/a/36273740/3339274
# set -x

# ------------------------------------------------------------------------------
# Parse CLI args
# ------------------------------------------------------------------------------
# https://linuxconfig.org/bash-script-flags-usage-with-arguments-examples
while getopts 'Cn:dupfrD' OPTION; do
  case "$OPTION" in
    C) clone_repo=false;;
    n) build_threads=$OPTARG;;
    d) install_desktop=true;;
    u) install_utilities=true;;
    p) install_programming=true;;
    f) install_fpga=true;;
    r) install_rpi=true;;
    D) install_install_deps=false;;
    ?)
      echo -e "$(basename $0) [-C] [-n] [-d] [-u] [-p] [-f] [-r] [-D]" >&2
      echo -e "-C\tDON'T clone the @neilbalch/Configurations repository to $HOME" >&2
      echo -e "-n\tSet number of make build threads (defaults to $(nproc))" >&2
      echo -e "-d\tInstall packages for Desktop Linux" >&2
      echo -e "-u\tInstall CLI utilities" >&2
      echo -e "-p\tInstall programming tools" >&2
      echo -e "-f\tInstall FPGA programming tools" >&2
      echo -e "-r\tInstall Raspberry Pi config tools" >&2
      echo -e "-D\tDON'T install dependencies for other packages (why?)" >&2
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

# Invoke all the things
apt_and_flatpak
platform
tools
configurations

# Just for fun :)
neofetch

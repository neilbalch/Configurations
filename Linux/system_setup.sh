# !/bin/bash

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
install_bento4=false        # Install bento4's MP4 and DASH/HLS/CMAF tools

# Thread count for Make builds
# Consider only using 1/2 threads on Raspberry Pi to prevent >1G RAM usage from
# hitting the swapfile and TANKING build performance
build_threads=$(nproc)
# OSS CAD Suite build date
oss_build="2024-09-04"
# ------------------------------------------------------------------------------
# Package Lists
# ------------------------------------------------------------------------------
# TODO: add GPU driver installs? (Nvidia/AMD/Intel)
# TODO: add desktop tools (Resolve, OpenRocket)
# TODO: Fusion 360? https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux
apt_desktop="blender filezilla firefox gh gimp inkscape kdenlive \
             keepassxc kicad obs-studio openvpn prusa-slicer pulseview \
             qbittorrent rpi-imager steam-installer vlc"
# devscripts included *only* for `annotate-output` lol
# https://unix.stackexchange.com/a/186570/75035
apt_utilities="bmon btop devscripts ffmpeg fio flatpak gnome-system-monitor \
               gparted htop iotop iperf3 screenfetch pv qdirstat rsync screen \
               smartmontools tmux unattended-upgrades vim x11-apps xcowsay \
               zoxide"
apt_programming="ant cmake git make openjdk-17-jre-headless openocd \
                 stlink-tools"
apt_teamviewer="libminizip1"
apt_sdrpp="g++ make cmake libfftw3-dev libglfw3-dev libzstd-dev libvolk-dev \
           zstd libhackrf-dev libairspy-dev librtaudio-dev libiio-dev \
           libairspyhf-dev libad9361-dev librtlsdr-dev"
apt_openhantek="g++ make cmake fakeroot qttools5-dev libfftw3-dev binutils-dev \
                libusb-1.0-0-dev libqt5opengl5-dev mesa-common-dev \
                libgl1-mesa-dev libgles2-mesa-dev rpm \
                qt6-base-dev qt6-base-dev-tools qt6-tools-dev \
                qt6-tools-dev-tools libgl-dev libgl1-mesa-dev"
apt_fpga="cmake libboost-dev libboost-filesystem-dev libboost-thread-dev \
          libboost-program-options-dev libboost-iostreams-dev libboost-dev \
          libeigen3-dev python3-apycula"
apt_rpi="proot qemu-user qemu-utils"
# Required by:    Bazel,  Global Python Packages,
apt_install_deps="golang pipx python3 python3-pip"

# https://flathub.org
# TODO: Any of these important? https://flathub.org/apps/category/System/1
flatpak_desktop="com.discordapp.Discord com.hunterwittenborn.Celeste \
                 com.spotify.Client org.gpxsee.GPXSee \
                 io.github.brunofin.Cohesion io.github.nokse22.Exhibit \
                 io.github.pwr_solaar.solaar io.github.shiftey.Desktop \
                 org.onlyoffice.desktopeditors org.stellarium.Stellarium"

# https://github.com/yt-dlp/yt-dlp
# https://github.com/dlenski/python-vipaccess
pip_packages=("black" "pyserial" "yt-dlp" "python-vipaccess")
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
    # https://github.com/cli/cli/blob/trunk/docs/install_linux.md
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    # Add Firefox's userChrome.css and enable it
    # Determine absolute source path relative to script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_CSS="$(cd "$SCRIPT_DIR/../Firefox" 2>/dev/null && pwd)/userChrome.css"

    if [ ! -f "$SOURCE_CSS" ]; then
      echo "Warning: Skipping Firefox setup. Could not find source CSS at: $SCRIPT_DIR/../Firefox/userChrome.css"
    else
      SNAP_FF_DIR="$HOME/snap/firefox/common/.mozilla/firefox"

      # Match any profile directory matching *.default or *.default*
      PROFILE_DIR=$(find "$SNAP_FF_DIR" -maxdepth 1 -type d -name "*.default*" 2>/dev/null | head -n 1)

      if [ -z "$PROFILE_DIR" ] || [ ! -d "$PROFILE_DIR" ]; then
        echo "Warning: Skipping Firefox setup. Snap user profile directory not found under $SNAP_FF_DIR."
      else
        echo "Configuring Firefox profile at: $PROFILE_DIR"

        # Create chrome directory
        mkdir -p "$PROFILE_DIR/chrome"

        # Copy source userChrome.css
        cp "$SOURCE_CSS" "$PROFILE_DIR/chrome/userChrome.css"

        # Function to safely append a user_pref if it doesn't already exist in user.js
        set_user_pref() {
          local pref="$1"
          local val="$2"
          local line="user_pref(\"$pref\", $val);"

          if ! grep -q "user_pref(\"$pref\"," "$PROFILE_DIR/user.js" 2>/dev/null; then
            echo "$line" >> "$PROFILE_DIR/user.js"
            echo "Added preference: $pref"
          fi
        }

        # Apply all required Firefox preferences safely
        # Enable CSS customization
        set_user_pref "toolkit.legacyUserProfileCustomizations.stylesheets" "true"
        # Enable the menu bar, since the CSS hides the tab bar that usually 
        # contains the window control buttons
        set_user_pref "ui.menu.autohide" "false"
        # Enable CSS edits to the sidebar feature
        set_user_pref "sidebar.revamp" "false"
        # Disable native sidebar header
        set_user_pref "sidebar.visibility" '"hide-header"'
      fi
    fi
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

  if [ "$install_programming" ]; then
    # Rustup is not in apt, only in snap 🤮
    # https://rust-lang.github.io/rustup/installation/other.html
    curl --proto '=https' --tlsv1.3 https://sh.rustup.rs -sSf | sh -s -- -y

    # Source environment in current script execution context
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

    # Check if rustc is still not available on PATH after installation
    if ! command -v rustc > /dev/null 2>&1; then
      # Ensure Cargo bin dir is added to ~/.bashrc if not already present
      if ! grep -q '\$HOME/\.cargo/bin' "$HOME/.bashrc" && ! grep -q "$HOME/.cargo/bin" "$HOME/.bashrc"; then
        printf '\n# Init Rust environment\nexpxort PATH="$HOME/.cargo/bin:$PATH"\n[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"\n' >> "$HOME/.bashrc"
      fi
    fi

    if ! which code > /dev/null; then
      # Install VSCode, per official guidance
      echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
      sudo apt install wget gpg && wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
      wget "https://go.microsoft.com/fwlink/?LinkID=760868" -O vscode.deb
      sudo apt install -y ./vscode.deb
      rm vscode.deb
    fi
  fi
}

# ------------------------------------------------------------------------------
# Platform-specific installations
# ------------------------------------------------------------------------------
platform() {
  if uname -m | grep "x86_64" > /dev/null; then
    echo "Installing x86 apps..."
    # Install Bazel through Bazelisk, then use `bazelisk ...` instead of `bazel ...`
    # https://bazel.build/versions/6.4.0/install/bazelisk
    # https://github.com/bazelbuild/bazelisk?tab=readme-ov-file#requirements
    go install github.com/bazelbuild/bazelisk@latest

    # If WSL2, then do the legwork to enable usbipd
    # https://github.com/dorssel/usbipd-win/wiki/WSL-support
    if uname -a | grep "WSL2" > /dev/null || uname -a | grep "Microsoft" > /dev/null; then
      echo "Installing WSL2 usbipd tools..."
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
  # FPGAs?
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

      sudo mkdir -p /opt/oss-cad-suite
      # https://superuser.com/a/1601085/342885
      pv oss-cad-suite.tgz | tar -x -C /opt/oss-cad-suite --strip-components=1
      rm oss-cad-suite.tgz
      # Expose executables system-wide via symlinks
      sudo ln -sf /opt/oss-cad-suite/bin/* /usr/local/bin/ 2>/dev/null || true
    else
      echo "Skipping OSS Cad Suite install, it already exists!"
    fi

    if ! which nextpnr-himbaechel > /dev/null; then
      # Nextpnr expects an updated version of Apycula that doesn't come by 
      # default
      pip3 install --upgrade --break-system-packages apycula

      # Install nextpnr-gowin (not yet packaged with OSS CAD Suite)
      git clone https://github.com/YosysHQ/nextpnr
      mkdir -p nextpnr/build
      cd nextpnr/build
      # Current versions of Apycula don't ship with files for the newer "GW5A"
      # product series. Exclude it for now
      cmake .. -DARCH="himbaechel" -DHIMBAECHEL_UARCH="gowin" -DHIMBAECHEL_GOWIN_DEVICES="GW1N-9;GW2A-18"
      make -j${build_threads}
      sudo make install
      cd ../..
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
    mkdir -p SDRPlusPlus/build
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

bento4() {
  if [ $install_bento4 ] && ! which mp4info > /dev/null; then
    # TODO: Find a way to make this URL pull the latest version, and be
    # supported on non-x86_64 platforms. Hopefully this doesn't involve
    # building from source!
    # https://github.com/axiomatic-systems/Bento4#cmakemake
    wget https://www.bok.net/Bento4/binaries/Bento4-SDK-1-6-0-641.x86_64-unknown-linux.zip -O BENTO4-TEMP.zip
    unzip BENTO4-TEMP.zip
    sudo cp Bento4-SDK-1-6-0-641.x86_64-unknown-linux/bin/* /usr/local/bin/
    rm -rf Bento4-SDK-1-6-0-641.x86_64-unknown-linux
    rm BENTO4-TEMP.zip
  fi
}

# Debug mode: https://stackoverflow.com/a/36273740/3339274
# set -x

# ------------------------------------------------------------------------------
# Parse CLI args
# ------------------------------------------------------------------------------
# https://linuxconfig.org/bash-script-flags-usage-with-arguments-examples
while getopts 'Cn:dupfrDb' OPTION; do
  case "$OPTION" in
    C) clone_repo=false;;
    n) build_threads=$OPTARG;;
    d) install_desktop=true;;
    u) install_utilities=true;;
    p) install_programming=true;;
    f) install_fpga=true;;
    r) install_rpi=true;;
    D) install_install_deps=false;;
    b) install_bento4=true;;
    ?)
      echo -e "$(basename $0) [-C] [-n] [-d] [-u] [-p] [-f] [-r] [-D] [b]" >&2
      echo -e "-C\tDON'T clone the @neilbalch/Configurations repository to $HOME" >&2
      echo -e "-n\tSet number of make build threads (defaults to $(nproc))" >&2
      echo -e "-d\tInstall packages for Desktop Linux" >&2
      echo -e "-u\tInstall CLI utilities" >&2
      echo -e "-p\tInstall programming tools" >&2
      echo -e "-f\tInstall FPGA programming tools" >&2
      echo -e "-r\tInstall Raspberry Pi config tools" >&2
      echo -e "-D\tDON'T install dependencies for other packages (why?)" >&2
      echo -e "-b\tInstall Bento4's MP4 and DASH/HLS/CMAF tools" >&2
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
bento4

# Just for fun :)
screenfetch


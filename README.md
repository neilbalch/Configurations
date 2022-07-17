# Configurations

This repository covers my software configurations for the following applications: (*each heading is its own directory*)

## 3D Printing

- Cura
  - `Ender 3 PETG.curaprofile` Cura profile for PETG on Ender 3
  - `Ender 3 PLA.curaprofile` Cura profile for PLA on Ender 3
  - `Ender 3 TPU.curaprofile` Cura profile for TPU on Ender 3
- `Ender 3 Marlin 1.1.x — Melzi Mainboard` Customized [MarlinFW](http://www.marlinfw.org) v1.1 firmware for Ender 3
- `Ender 3 Marlin 2.x.x — SKR Mini E3 Mainboard` Customized [MarlinFW](http://www.marlinfw.org) v2.0.0 firmware for Ender 3 with BLTouch mesh bed-leveling sensor
  - `_Bootscreen.h`, `_Statusscreen.h`, `Configuration.h`, `Configuration_adv.h` Marlin config files for drop-in replacement into `MARLIN_PATH/Marlin` folder
    - ***NOTE:*** also apply [EEPROM emulation fix](https://github.com/MarlinFirmware/Marlin/issues/15254#issuecomment-535755449)
    - [Useful Reddit Config guide](https://www.reddit.com/r/ender3/comments/dojh3v/guide_for_those_upgrading_to_an_skr_e3_mini_v12/)
    - [Useful TeachingTech Youtube video on v1.2](https://www.youtube.com/watch?v=ikHhzOIlHPg), [v1.0, but applicable to both v1.0 and v1.2](https://www.youtube.com/watch?v=-XUQKQnUNig)
  - `firmware-bltouch-for-z-homing.bin` Bigtreetech pre-compiled firmware with BLTouch
  - `firmware-printer-stock.bin` Bigtreetech pre-compiled firmware, comes stock with printer
  - `firmware-self-compiled-bltouch.bin` Self-compiled and tested firmware from config files in this folder
  - `SKR-MINI-E3-V1.2-test.gcode` Test GCODE file which came with the SKR Mini E3 mainboard
- OctoPrint
  - `backup-yyyymmdd-xxxx.zip` Configuration backups for the OctoPrint 3D printer tool
  - `RPi-Fan-Control.py` Fan Control script for OctoPrint to only turn on a fan connected to BOARD pin 7 (*via a BJT amplifier transistor*) when the CPU core temp >=60C.
  - `RPi-Fan-Control.service` Fan control `systemctl` service script (*located in `/etc/systemd/system`*) and started on boot by `systemctl` once service is enabled
- `SuperSlicer_config_bundle.ini` [SuperSlicer](https://github.com/supermerill/SuperSlicer) configuration file

## Adobe

- Workspace for Premiere Pro CS6
- "Adobe Bloat" (media cache) deletion batch script
- After Effects Move Anchor Point Script

## Drones

- `Betaflight F405-CTR Dumps` Dated Betaflight FC config dumps on [Matek F405-CTR](http://www.mateksys.com/?portfolio=f405-ctr)
- `MultiWii_Flip` [Customised MultiWii](http://www.multiwii.com/wiki/?title=Main_Page) FC firmware for [RTFQ Flip MWC](https://readytoflyquads.com/flip-mwc-flight-controller)

## Firefox

- `sidebery-data-XXXX.XX.XX-XX.XX.XX.json`: [Sidebery](https://addons.mozilla.org/en-US/firefox/addon/sidebery)
- `Tree Tabs CUSTOMIZED.tt_theme` [Tree Tabs](https://addons.mozilla.org/en-US/firefox/addon/tree-tabs) theme
- `[profile]/chrome/userChrome.css` Hides the tab bar and sidebar header for use with [Tree Tab](https://addons.mozilla.org/en-US/firefox/addon/tree-tabs)

## Games

- FlightGear
  - Mad-Katz-F.L.Y 5 Joystick map
- WarThunder
  - Mad-Katz-F.L.Y 5 Joystick map for Aircraft
- `WoWs Modstation Config.txt`

## Intellij Idea Settings

- `settings.jar`

## Linux Stuff

- Samba Raspberry Pi NAS Configuration
- Raspberry Pi Scripts
  - `wifi-to-eth-route.service` Wireless bridge `systemctl` service script (*located in `/etc/systemd/system`*) and started on boot by `systemctl` once service is enabled
  - `wifi-to-eth-route.sh` Bash script that reconfigures the RPi `eth0` LAN port as a wireless bridge from the WiFi connection. Forked from [arpitjindal97/raspbian-recipes](https://github.com/arpitjindal97/raspbian-recipes)
- `.bashrc`
- `.gitconfig`
- `.vimrc`
  - With *Vundle* support
  - Without *Vundle* support
- `debian-restart-network.sh`: Bash script to reset the network interfaces in a Debian VM (*Used briefly for VirtualBox @ FRC971*)
- `system_setup.sh`: Bash script to automate personal first-time setup of a Linux installation

## TI84 Plus CE Apps (*Use TI Connect to transfer onto calculator*)

Various apps in each subfolder.

## Visual Studio

- `VisualStudio2017-XXXXXXXX.vssettings`

## Visual Studio Code

- Keybindings
- Global Settings
- Snippets
  - `cpp.json`
- C++ Workspace Settings (Windows with MinGW)
  - C++ Properties
  - Local Settings
  - `launch.json`
  - `tasks.json`
- `extension_installer.py` Utility script to automate re-installing a pre-defined set of VSCode extensions. Useful for initializing a new development environment in the image of another.
- `extensions_list.txt` My current list of universally-used extensions

## Windows

- `E-YOOSO X-7 Mouse/*` Utilities related to configuring the [E-YOOSO X-7 mouse](https://smile.amazon.com/dp/B083NSD4CG)'s macro keys
  - `2791Driverprogram.exe` Vendor-provided configuration utility
  - `F23andF24.ahk` AutoHotKey script that "presses" F23 and F24 to help bind the mouse's macro keys (*enter record mode in the configuration utility and then run the AHK script*)
  - `SPCP199-Macro.bin` Unknown binary file generated by the configuration utility
- `Ctrl+Backspace Support.ahk` AutoHotkey Script that enables `Ctrl`+`Backspace` to delete the previous word in Windows Explorer
- `Ctrl+Shift+QaW Remover.ahk` AutoHotkey Script that blocks `Ctrl+Shift+Q` and `Ctrl+Shift+W` from Chrome and Firefox
- `Launch SymWin.xml` Windows Task Scheduler task to launch [SymWin](https://www.github.com/mjvh80/SymWin) on system startup
- `RoboticsIPChanger.bat` (Windows IP Switcher for Robot Network)
- `SMBShares.cmd` SMB Share populator/depopulator for home network
- `AudioService-Restart.cmd` Restarts the audio service to refresh audio driver issues
- `Windows Terminal profiles.json` Config file for the UWP Windows Terminal app

# Configurations

This repository covers my software configurations for the following applications:

- 3D Printing
  - Cura
    - `CHEP_Cura_Profiles_4.0/*` [CHEPclub](https://www.chepclub.com/startend-gcode.html) Ender 3 Cura profiles for Cura 4.0
    - `CHEP_Cura_Profiles_4.4/*` [CHEPclub](https://www.chepclub.com/startend-gcode.html) Ender 3 Cura profiles for Cura 4.4
    - `Ender 3 PETG.curaprofile` Cura profile for PETG on Ender 3
    - `Ender 3 PLA.curaprofile` Cura profile for PLA on Ender 3
    - `Ender 3 TPU.curaprofile` Cura profile for TPU on Ender 3
  - `Ender 3 Marlin 1.1.x — Melzi Mainboard` Customized [MarlinFW](http://www.marlinfw.org) v1.1 firmware for Ender 3
  - `Ender 3 Marlin 2.x.x — SKR Mini E3 Mainboard` Customized [MarlinFW](http://www.marlinfw.org) v2.0.0 firmware for Ender 3 with BLTouch mesh bed-leveling sensor
    - `_Bootscreen.h`, `_Statusscreen.h`, ` Configuration.h`, `Configuration_adv.h` Marlin config files for drop-in replacement into `MARLIN_PATH/Marlin` folder, ***NOTE:*** also apply [EEPROM emulation fix](https://github.com/MarlinFirmware/Marlin/issues/15254#issuecomment-535755449)
    - `firmware-bltouch-for-z-homing.bin` Bigtreetech pre-compiled firmware with BLTouch
    - `firmware-printer-stock.bin` Bigtreetech pre-compiled firmware, comes stock with printer
    - `firmware-self-compiled-bltouch.bin` Self-compiled and tested firmware from config files in this folder
    - `SKR-MINI-E3-V1.2-test.gcode` Test GCODE file which came with the SKR Mini E3 mainboard
- Adobe
  - Workspace for Premiere Pro CS6
  - "Adobe Bloat" (media cache) deletion batch script
  - After Effects Move Anchor Point Script
- Drones
  - `Betaflight F405-CTR Dumps` Dated Betaflight FC config dumps on [Matek F405-CTR](http://www.mateksys.com/?portfolio=f405-ctr)
  - `MultiWii_Flip` [Customised MultiWii](http://www.multiwii.com/wiki/?title=Main_Page) FC firmware for [RTFQ Flip MWC](https://readytoflyquads.com/flip-mwc-flight-controller)
- Firefox
  - `[profile]/chrome/userChrome.css` Hides the tabbar and sidebar header for use with [Tree Tab](https://addons.mozilla.org/en-US/firefox/addon/tree-tabs/)
  - `Tree Tabs CUSTOMISED.tt_theme` [Tree Tabs](https://addons.mozilla.org/en-US/firefox/addon/tree-tabs/) theme
- Games
  - FlightGear
    - Mad-Katz-F.L.Y 5 Joystick map
  - WarThunder
    - Mad-Katz-F.L.Y 5 Joystick map for Aircrft
- Intellij Idea Settings
- Linux Stuff
  - Samba NAS Configuration
  - `.bashrc`
  - `.gitconfig`
  - `.vimrc`
    - With *Vundle* support
    - Without *Vundle* support
- OctoPrint
  - `backup-yyyymmdd-xxxx.zip` Configuration backups for the OctoPrint 3D printer tool
  - `RPi-Fan-Control.py` Fan Control script for OctoPrint to only turn on a fan connected to BOARD pin 7 (*via a BJT amplifier transistor*) when the CPU core temp >=60C. Script is mentioned in `/etc/rc.local` for run on startup
- Quick Reference
  - `screen`
  - `sed`
- TI84 Plus CE Apps (*Use TI Connect to transfer onto calculator*)
- Visual Studio
  - Settings
- Visual Studio Code
  - Keybindings
  - Global Settings
  - Snippets
    - `cpp.json`
  - C++ Workspace Settings (Windows with MinGW)
    - C++ Properties
    - Local Settings
    - `launch.json`
    - `tasks.json`
- Windows
  - `Ctrl+Backspace Support.ahk` AutoHotkey Script that enables `Ctrl`+`Backspace` to delete the previous word in Windows Explorer
  - `Ctrl+Shift+QaW Remover.ahk` AutoHotkey Script that blocks `Ctrl+Shift+Q` and `Ctrl+Shift+W` from Chrome and Firefox
  - `Launch SymWin.xml` Windows Task Scheduler task to launch [SymWin](https://www.github.com/mjvh80/SymWin) on system startup
  - `RoboticsIPChanger.bat` (Windows IP Switcher for Robot Network)
  - `SMBShares.cmd` SMB Share populator/depopulator for home network
  - `AudioService-Restart.cmd` Restarts the audio service to refresh audio driver issues
  - `Windows Terminal profiles.json` Config file for the UWP Windows Terminal app

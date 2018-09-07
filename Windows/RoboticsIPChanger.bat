@echo off
REM  --> Check for permissions
    IF "%PROCESSOR_ARCHITECTURE%" EQU "amd64" (
>nul 2>&1 "%SYSTEMROOT%\SysWOW64\cacls.exe" "%SYSTEMROOT%\SysWOW64\config\system"
) ELSE (
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
)

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c ""%~s0"" %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

REM BEGIN!!!!
@echo off
echo Choose: Home or Robotics
echo [SW] Set Robotics Static IP: WiFi
echo [SE] Set Robotics Static IP: Ethernet
echo [DW] Set Home DHCP IP: WiFi
echo [DE] Set Home DHCP IP: Ethernet
echo.

SET /P C=[SW,SE,DW,DE]?
for %%? in (SW) do if /I "%C%"=="%%?" goto SWiFi
for %%? in (SE) do if /I "%C%"=="%%?" goto SEthernet
for %%? in (DW) do if /I "%C%"=="%%?" goto DWiFi
for %%? in (DE) do if /I "%C%"=="%%?" goto DEthernet

REM Set SEthernet
:SEthernet
set Eth_IP=10.9.71.55
echo "Ethernet Static IP Address:" %Eth_IP%

REM Might be 10.0.0.1
set Gate=10.9.71.1
echo "Default Gateway:" %Gate%

set Mask=255.0.0.0
echo "Subnet Mask:" %Mask%

echo "Setting: Ethernet (Static IP)"
netsh interface ipv4 set address "LAN" static %Eth_IP% %Mask% %Gate%
netsh int ip show config
pause
goto end

REM Set SWiFi
:SWiFi
set WiFi_IP=10.9.71.56
echo "WiFi Static IP Address:" %&WiFi_IP%

REM Might be 10.0.0.1
set Gate=10.9.71.1
echo "Default Gateway:" %Gate%

set Mask=255.0.0.0
echo "Subnet Mask:" %Mask%

echo "Setting: Wifi (Static IP)"
netsh interface ipv4 set address "WiFi" static %WiFi_IP% %Mask% %Gate%
netsh int ip show config
pause
goto end

REM Set WiFi Home DHCP
:DWiFi
@ECHO OFF
ECHO "Setting: WiFi (DHCP)"
netsh int ipv4 set address name = "WiFi" source = dhcp

ipconfig /renew

ECHO Here are the new settings for %computername%:
netsh int ip show config

pause
goto end

REM Set Ethernet Home DHCP
:DEthernet
@ECHO OFF
ECHO "Setting: Ethernet (DHCP)"
netsh int ipv4 set address name = "LAN" source = dhcp

ipconfig /renew

ECHO Here are the new settings for %computername%:
netsh int ip show config

pause
goto end
:end
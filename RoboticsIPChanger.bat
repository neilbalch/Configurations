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
echo [R] Set Robotics Static IP 
echo [H] Set Home DHCP IP 
echo. 

:choice 
SET /P C=[R,H]? 
for %%? in (R) do if /I "%C%"=="%%?" goto Robotics
for %%? in (H) do if /I "%C%"=="%%?" goto Home

goto choice 

REM Set Robotics
:Robotics
set Eth_IP_Addr=10.9.71.55
echo "Ethernet Static IP Address: "%&IPAddr%

set WiFi_IP_Addr=10.9.71.56
echo "WiFi Static IP Address: "%&IPAddr%

REM Might actually be 10.0.0.1
set D_Gate=10.9.71.1
echo "Default Gateway: "%D_Gate%

set Sub_Mask=255.0.0.0
echo "Subnet Mask: "%Sub_Mask%

echo "Setting: Robotics (Static IP)" 
netsh interface ipv4 set address "WiFi" static %WiFi_IP_Addr% %Sub_Mask% %D_Gate% 1 
netsh interface ipv4 set address "LAN" static %Eth_IP_Addr% %Sub_Mask% %D_Gate% 1 
netsh int ip show config 
pause 
goto end

REM Set Home DHCP
:Home
@ECHO OFF 
ECHO "Setting: Home (DHCP)" 
netsh int ipv4 set address name = "WiFi" source = dhcp
netsh int ipv4 set address name = "LAN" source = dhcp

ipconfig /renew

ECHO Here are the new settings for %computername%: 
netsh int ip show config

pause 
goto end 
:end
@echo off
REM IPs:
REM M: 192.168.1.16/Balch NAS
REM N: 192.168.1.10/d
REM Q: 192.168.1.10/Users

if /i "%1" EQU "/1" goto ToggleOn
if /i "%1" EQU "/0" goto ToggleOff

@echo off
echo.
echo Choose SMB Share Action:
echo [on] Turn Share Connections On
echo [off] Turn Share Connections Off
echo.

SET /P choice=Choice:
echo.
if /i "%choice:~%" EQU "on" goto ToggleOn
if /i "%choice:~%" EQU "off" goto ToggleOff

REM Toggle Connections On
:ToggleOn
echo Toggling Share Connections ON
net use M: "\\192.168.1.16\Balch NAS" /persistent:Yes
net use N: "\\192.168.1.10\d" /persistent:Yes
net use O: "\\192.168.1.10\Users" /persistent:Yes
pause
goto end

REM Toggle Connections Off
:ToggleOff
echo Toggling Share Connections OFF
net use M: /delete
net use N: /delete
net use O: /delete
pause
goto end

:end
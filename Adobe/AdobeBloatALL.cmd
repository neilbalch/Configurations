rem Removes all files on drive with .pek, .xmp, and .cfa extensions

@ECHO OFF
SET interactive=0

ECHO %CMDCMDLINE% | FINDSTR /L %COMSPEC% >NUL 2>&1
IF %ERRORLEVEL% == 0 SET interactive=1

@echo cdING into the %1 Drive  
%1:

del /s *.pek
@echo ".pek" files Deleted on the %1 Drive...

del /s *.xmp
@echo ".xmp" files Deleted on the %1 Drive...

del /s *.cfa
@echo ".cfa" files Deleted on the %1 Drive...

@pause

IF "%interactive%"=="0" PAUSE
EXIT /B 0
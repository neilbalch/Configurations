rem Removes files from the standatd Adobe Cache locations

@ECHO OFF
SET interactive=0

ECHO %CMDCMDLINE% | FINDSTR /L %COMSPEC% >NUL 2>&1
IF %ERRORLEVEL% == 0 SET interactive=1

del /q C:\Users\%USERNAME%\AppData\Roaming\Adobe\Common\"Media Cache"\*
@echo "Media Cache" Deleted...

del /q C:\Users\%USERNAME%\AppData\Roaming\Adobe\Common\"Media Cache Files"\*
@echo "Media Cache Files" Deleted...

del /q C:\Users\%USERNAME%\AppData\Roaming\Adobe\Common\"Peak Files"\*
@echo "Peak Files" Deleted...

@pause

IF "%interactive%"=="0" PAUSE
EXIT /B 0
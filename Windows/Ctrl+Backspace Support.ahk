; how to write scripts: http://www.autohotkey.com/docs/

#IfWinActive ahk_class CabinetWClass ; File Explorer
	^Backspace::
#IfWinActive ahk_class Progman ; Desktop
        ^Backspace::
#IfWinActive ahk_class Notepad
	^Backspace::
	Send ^+{Left}{Backspace}
#IfWinActive

; source and context: http://superuser.com/a/636973/124606

; relevant documentation links:
; writing hotkeys
; http://www.autohotkey.com/docs/Hotkeys.htm
; list of key codes (including Backspace)
; http://www.autohotkey.com/docs/KeyList.htm
; the #IfWinActive directive
; http://www.autohotkey.com/docs/commands/_IfWinActive.htm
; the Send command
; http://www.autohotkey.com/docs/commands/Send.htm
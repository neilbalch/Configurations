SetTitleMatchMode, Regex

#IfWinActive, ahk_class Chrome_WidgetWin_1
    ^+w::
        ;do nothing
        return
    ^+q::
        ;do nothing
        return

#IfWinActive

#IfWinActive, ahk_class MozillaWindowClass
    ^+w::
        ;do nothing
        return
    ^+q::
        ;do nothing
        return

#IfWinActive
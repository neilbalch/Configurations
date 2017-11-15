# `screen` Quick Reference

## Launching from the terminal

- `screen`: To startup a new instance
- `screen -r [PID]`: To restore a detatched instance (PID is displayed upon detaching from a `screen` instance anc can be obtained from the *PID* collumn of `top`)

## Command reference

| Command (`C-a` means `Ctrl+A`) |       | Description |
|--------------------------------|-------|-------------|
|`C-a c` | (new) | Make a new window. |
|`C-a n` | (next) | Switch to next window. |
|`C-a p` | (previous) | Switch to next previous window. |
|`C-a M` | (alert) | Alert me (bottom of screen) if this window has activity. |
|`C-a _` | (alert) | Alert me (bottom of screen) if this window has no activity. |
|`C-a k` | (kill) | Kill screen. |
|`C-a '` | (select) | Prompt for a window name or number to switch to. |
| `C-a "` | (windowlist -b) |Present a list of all windows for selection. |
| `C-a 0` ... `C-a 9` | (select 0) ... (select 9) |Switch to window number 0 - 9, or to the blank window. |
| `C-a A` | (title) | Allow the user to enter a name for the current window. |
| `C-a d` ***OR*** `C-a C-d` | (detach) | Detach screen from this terminal. |
| `C-a N` | (number) | Show the number (and title) of the current window. |
| `C-a ?` | (help) | Show key bindings.|

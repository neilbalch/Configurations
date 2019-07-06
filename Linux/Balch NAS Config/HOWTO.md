# How to create

## Resources

http://www.penguintutor.com/linux/file-permissions-reference
https://www.samba.org/samba/docs/old/Samba3-HOWTO/speed.html
https://www.jeremymorgan.com/tutorials/raspberry-pi/how-to-raspberry-pi-file-server/
https://askubuntu.com/questions/79078/how-to-restart-samba-server

## Commands

- `sudo apt install samba samba-common-bin ntfs-3g`
- `git clone https://github.com/neilbalch/Configurations`
- `sudo mkdir /home/NAS`
- `sudo mount -t ntfs-3g -o uid=pi,gid=pi /dev/sda1 /home/NAS`
- `sudo chmod -R 775 /home/NAS`
- `sudo useradd -g users media && sudo smbpasswd -a media`
- Modify `/etc/samba/smb.conf` with contents from cloned repo
- `testparm`
- `sudo service smbd start`
- All is working okay?
  - `sudo vim /etc/rc.local` (Add to bottom, but before `exit 0`)
  - `sudo mount -t ntfs-3g -o uid=pi,gid=pi /dev/sda1 /home/NAS`

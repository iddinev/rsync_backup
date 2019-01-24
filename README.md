# Raspberry rsync script
## Rudimentary script + systemd timer/service to do incremental rsync rootfs backups to a mounted storage.

The script keeps and rotates several backups. It can be configured to keep a preset amount of backups, and when it reaches that number it starts using the oldest backup as the incremental base for the new one - this is done to minimize the backup creation time and read/writes needed. Automatically deletes the new backup dir if the backup fails for some reason.
Script is configured through internal variables.

### Usage
```
rsync_backup {-b | --backup} {-r | --restore <num>}
```
* `-b | --backup` Create a backup as per configurations (requires sudo).
* `-r | --restore <num>` Restore backup <num>: 1 - latest backup (requires sudo).
  
### Install
1. Copy .service/.timer files to a systemd sytem path, e.g. - `/etc/systemd/system`
2. Copy the script inside root's path, e.g. - `/usr/local/sbin`
3. Change/modify configs/paths inside the script/timer/service files to liking.
4. Enable & start the timer service:
```
sudo systemctl enable rsync_backup.timer; sudo systemctl start rsync_backup.timer
```

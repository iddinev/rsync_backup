# Rudimentary rsync backup/restore scripts
## Scripts + systemd timer/service to do incremental rsync rootfs backups to a mounted storage or a remote machine.

The script keeps and rotates several backups on local storage. It can be configured to keep a preset amount of backups, and when it reaches that number it starts using the oldest backup as the incremental base for the new one - this is done to minimize the backup creation time and read/writes needed. Automatically deletes the new backup dir if the backup fails for some reason (BEWARE: this scenario can effectively remove the last backup if the creation of the new one fails). The archive option can tar.gz, encrypt (via gpg2) and copy the backups to another machine via SSH, it also rotates the tar.gz, encrypted and remote backups.\
Scripts are configured through a config file stored in the same dir. Scripts need to be used only through
symlinks as they need to be able to reach their config file and function library, or keep everything in
one dir.\

### Usage

#### rsync_backup - main script

Used to create backups stored on a locally accessible mounted storage.

```
rsync_backup {-b | --backup} {-r | --restore <num>} {-h | --help}
```
* `-b | --backup` Create a backup as per configurations (requires sudo).
* `-r | --restore <num>` Restore backup <num>: 1 - latest backup (requires sudo).
* `-l | --list` Lists and numbers the available backups: 1 - latest backup.
* `--archive`   Archive, encrypt and possibly send over ssh.
* `-h | --help` Show this help message.

If you want to keep a particular backup, rename it so the script won't be able to list it,
or copy it to another dir.\
NOTE:
If you need to copy a backup, use the same rsync command as the script
to preserve the attributes.\
For restoring, the file name should start with the backup prefix,
so the script can list/use it.

### Install
1. Copy .service/.timer files to a systemd sytem path, e.g. - `/etc/systemd/system`
2. Symlink the script(s) inside root's path, e.g. - `/usr/local/sbin`.\
   It is advisable to keep the script itself outside of the backup tree, so any\
   modifications of it do not get overwritten by restores.
3. Change/modify configs/paths in the config/timer/service files to liking.
4. Create the desired storage paths (configured in step 3).
5. Enable & start the timer service:
```
sudo systemctl enable rsync_backup.timer; sudo systemctl start rsync_backup.timer
```

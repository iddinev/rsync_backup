#!/usr/bin/env bash


# The source & storage path should always end with '/'.
SOURCE_PATH="/"
RESTORE_TARGET_PATH="$SOURCE_PATH"
STORAGE_PATH="/mnt/backup/backup_root/"
RSYNC_BACKUP_PREFIX="rsync_monthly"
RSYNC_BACKUP_MAIN_PATH="$STORAGE_PATH""$RSYNC_BACKUP_PREFIX"
RSYNC_BACKUP_OPTIONS=("-aAHX" "--delete" "--numeric-ids" "--exclude=/lost+found"
"--exclude=/proc/*" "--exclude=/sys/*" "--exclude=/dev/*" "--exclude=/home/*"
"--exclude=/tmp/*" "--exclude=/run/*" "--exclude=/mnt/*" "--exclude=/media/*")
DATE_FORMAT="%Y-%b-%d-%H-%M-%S"
TIMESTAMP="$(date +$DATE_FORMAT)"
BACKUP_PATH="$RSYNC_BACKUP_MAIN_PATH"-"$TIMESTAMP"
TIMESTAMP_FILE="BACKUP-TIMESTAMP"
MAX_BAKUPS=1



function create_rsync_backup()
{
	rc_code=1

	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ]; then
		if [ "$num_backups" -ge 0 ] && [ "$num_backups" -lt "$MAX_BAKUPS" ]; then
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_PATH" "$BACKUP_PATH"; then
				rc_code=0
				# Touch the new backup to update it's modify time.
				touch "$BACKUP_PATH"
			else
				if [ -d "$BACKUP_PATH" ]; then
					rm -r "$BACKUP_PATH"
				fi
			fi
		elif [ "$num_backups" -ge "$MAX_BAKUPS" ]; then
			base_backup="$(get_oldest_rsync_backup)"
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_PATH" "$base_backup"; then
				if mv "$base_backup" "$BACKUP_PATH"; then
					rc_code=0
					# Touch the new backup to update it's modify time.
					touch "$BACKUP_PATH"
				fi
			else
				if [ -d "$base_backup" ]; then
					rm -r "$base_backup"
				fi
			fi
		fi
	fi

	if [ "$rc_code" -eq 0 ] && [ -d "$BACKUP_PATH" ]; then
		echo "$TIMESTAMP" > "$BACKUP_PATH"/"$TIMESTAMP_FILE"
	fi

	return "$rc_code"
}

function get_oldest_rsync_backup()
{
	ret_val=-1

	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ] && [ "$num_backups" -ge "$MAX_BAKUPS" ]; then
		mapfile -t arr < <(ls -dqtr "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
		ret_val="${arr[0]}"
	fi

	echo "$ret_val"
}

function count_rsync_backup()
{
	rc_val=-1

	num_backups=$(ls -1dq "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null | wc -l)
	if [ -n "$num_backups" ]; then
		rc_val="$num_backups"
	fi

	echo "$rc_val"
}

function list_rsync_backup()
{
	echo "Found the following backups:"
	ls -dqtF "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null | nl
}

function rotate_rsync_backup()
{
	rc_code=1

	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ] && [ "$num_backups" -ge 0 ]; then
		if [ "$num_backups" -gt "$MAX_BAKUPS" ]; then
			mapfile -t backup_list < <(ls -dqt "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
			for i in $(eval "echo {$MAX_BAKUPS..$num_backups}"); do
				rm -rf "${backup_list[i]}"
			done
			rc_code=0
		else
			rc_code=0
		fi
	fi

	return "$rc_code"
}

function restore_rsync_backup()
{
	rc_code=1
	which_backup=${1:-0}
	
	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ]; then
		if [ "$num_backups" -ge "$which_backup" ] && [ "$which_backup" -gt 0 ]; then
			mapfile -t arr < <(ls -dqtF "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
			backup="${arr[$((which_backup-1))]}"
			echo "Restoring $backup"
			sleep 5
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "-v" "$backup" "$RESTORE_TARGET_PATH"; then
				rc_code=0
			fi
		fi	
	fi

	return "$rc_code"
}

function help_text
{
cat << _EOF_
Usage:
rsync_backup {-b | --backup} {-r | --restore <num>} {-l | --list} {-h | --help}

-b | --backup           Create a backup as per configurations (requires sudo).
-r | --restore <num>    Restore backup <num>: 1 - latest backup (requires sudo).
-l | --list             Lists and numbers the available backups: 1 - latest backup.
-h | --help             Show this help message.

If you want to keep a particular backup, rename it so the script won't be able to list it,
or copy it to another dir. If you need to copy a backup, use the same rsync command as
the script to preserve the attributes. For restoring, the file name should start with
the backup prefix, so the script can list/use it.
_EOF_
}



# MAIN

m_exit=1
m_action=0
m_opt="$1"

case $m_opt in
	-b|--backup)
	m_action=1
	;;
	-r|--restore)
	m_action=2
	m_restore="$2"
	;;
	-l|--list)
	m_action=3
	;;
	-h|--help)
	m_action=4
	;;
	*)
	m_action=5
	;;

esac

case $m_action in
	1)
	create_rsync_backup
	rc_code=$?
	if [ "$rc_code" -eq 0 ]; then
		if rotate_rsync_backup; then
			m_exit=0
		fi
	fi
	;;
	2)
	if restore_rsync_backup "$m_restore"; then
		m_exit=0
	fi
	;;
	3)
	list_rsync_backup
	;;
	4)
	help_text
	m_exit=0
	;;
	5)
	help_text
	m_exit=1
	;;
esac

exit "$m_exit"

# END

#!/usr/bin/env bash



#SOURCE_PATH="/"
RESTORE_TARGET_PATH="$SOURCE_PATH"
STORAGE_PATH="/mnt/storage/pi_backups/"
RSYNC_BACKUP_PREFIX="rsync_weekly"
RSYNC_BACKUP_MAIN_PATH="$STORAGE_PATH""$RSYNC_BACKUP_PREFIX"
RSYNC_BACKUP_OPTIONS=("-aHv" "--delete"
"--exclude=/proc/*" "--exclude=/sys/*" "--exclude=/dev/*" "--exclude=/boot/*"
"--exclude=/tmp/*" "--exclude=/run/*" "--exclude=/mnt/*" "--exclude=/media/*")
DATE_FORMAT="%Y-%B-%d"
MAX_BAKUPS=2



function create_rsync_backup()
{
	rc_code=1

	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ]; then
		backup_path="$RSYNC_BACKUP_MAIN_PATH"-"$(date +$DATE_FORMAT)"
		if [ "$num_backups" -ge 0 ] && [ "$num_backups" -lt "$MAX_BAKUPS" ]; then
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_PATH" "$backup_path"; then
				rc_code=0
			fi
		elif [ "$num_backups" -ge "$MAX_BAKUPS" ]; then
			base_backup="$(get_oldest_rsync_backup)"
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_PATH" "$base_backup"; then
				if mv "$base_backup" "$backup_path"; then
					rc_code=0
				fi
			fi
		fi
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

	num_backups=$(ls -1dqt "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null | wc -l)
	if [ -n "$num_backups" ]; then
		rc_val="$num_backups"
	fi

	echo "$rc_val"
}

function rotate_rsync_backup()
{
	rc_code=1

	num_backups="$(count_rsync_backup)"
	ret_code=$?

	if [ "$ret_code" -eq 0 ] && [ "$num_backups" -gt "$MAX_BAKUPS" ]; then
		mapfile -t backup_list < <(ls -dqt "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
		for i in $(eval "echo {$MAX_BAKUPS..$num_backups}"); do
			rm -rf "${backup_list[i]}"
		done
		rc_code=0
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
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$backup" "$RESTORE_TARGET_PATH"; then
				rc_code=0
			fi
		fi	
	fi

	return "$rc_code"
}



# MAIN

m_exit=1
m_backup=0
m_opt="$1"

case $m_opt in
	-b|--backup)
	m_backup=1
	;;
	-r|--restore)
	m_restore="$2"
	;;
esac


if [ "$m_backup" -eq 1 ]; then
	create_rsync_backup
	rc_code=$?
	if [ "$rc_code" -eq 0 ] && rotate_rsync_backup; then
		m_exit=0
	fi
elif [ -n "$m_restore" ] && restore_rsync_backup "$m_restore"; then
	m_exit=0
fi

exit "$m_exit"

# END

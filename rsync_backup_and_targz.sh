#!/usr/bin/env bash


BACKUP_SCRIPT="/mnt/backup/code/rsync_backup.sh"
TIMESTAMP_FILE="BACKUP-TIMESTAMP"
BACKUP_TARGZ_DIR="/mnt/backup/backup_targz/"
REMOTE_BACKUP_DIR="/mnt/storage/backups/pc_backup/"
BACKUP_TARGZ_PREFIX="backup-"
BACKUP_TARGZ_SUFFIX=".tar.gz"
SSH_USER="root"
SSH_HOST="mypi"


function create_rsync_backup()
{
	rc_code=1
	if "$BACKUP_SCRIPT" --backup; then
		rc_code=0
		log_systemd "Backup created."
	fi
	return "$rc_code"
}

function get_latest_rsync_backup()
{
	rc_val=-1
	mapfile -t backup_list < <("$BACKUP_SCRIPT" --list 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 2 ]; then
		latest_backup="$(echo ${backup_list[1]} | cut -d ' ' -f 2)"
		ret_val="$latest_backup"
	fi
	echo "$ret_val"
}

function targz_and_scp_backup()
{
	rc_code=1
	latest_backup="$(get_latest_rsync_backup)"
	echo "Found new backup $latest_backup ." | systemd -t backup -p info
	if [ "$latest_backup" != "-1" ] && [ "$latest_backup" != "" ] ; then
		read timestamp < "$latest_backup"/"$TIMESTAMP_FILE"
		targz_file="${BACKUP_TARGZ_DIR}/backup-${timestamp}.tar.gz"
		if tar -zcf "$targz_file" "$latest_backup"; then
			echo "Created $targz_file ." | systemd-cat -t backup -p info
			# Overwrite previous backup.
			if scp "$targz_file" "$SSH_USER"@"$SSH_USER":"$REMOTE_BACKUP_PATH"; then
				echo "scp successfull." | systemd -t backup -p info
				rc_code=0
			fi
		fi
	fi

	return "$rc_code"
}

function gpg_encrypt()
{
	true
}

function targz_backup()
{
	rc_code=1
	latest_backup="$(get_latest_rsync_backup)"
	log_systemd "Found new backup $latest_backup ."
	if [ "$latest_backup" != "-1" ] && [ "$latest_backup" != "" ] ; then
		read timestamp < "$latest_backup""$TIMESTAMP_FILE"
		targz_file="${BACKUP_TARGZ_DIR}${BACKUP_TARGZ_PREFIX}${timestamp}${BACKUP_TARGZ_SUFFIX}"
		if tar -zcf "$targz_file" "$latest_backup"; then
			log_systemd "Created $targz_file ."
			rc_code=0
		fi
	fi

	return "$rc_code"
}

function scp_backup()
{
	rc_code=1
	mapfile -t backup_list < <(ls -dqtr "$BACKUP_TARGZ_DIR"* 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 1 ]; then
		backup_file="${backup_list[0]}"
		if scp "$backup_file" "$SSH_USER"@"$SSH_USER":"$REMOTE_BACKUP_PATH"; then
			log_systemd "scp $backup_file successfull."
			rc_code=0
		fi
	fi

	return "$rc_code"
}

function log_systemd()
{
	l_prio={2:-"info"}
	l_tag={3:-"backup"}

	echo "$1" | systemd-cat -p "$l_prio" -t "$l_tag"
}



### MAIN

m_exit=1

log_systemd "Starting Monthly backup."
create_rsync_backup
rc=$?
if [ "$rc" -eq 0 ]; then
	if targz_and_scp_backup; then
		m_exit=0
	fi
fi

exit "$m_exit"

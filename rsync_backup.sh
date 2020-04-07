#!/usr/bin/env bash

SCRIPTNAME="$(basename "$0")"
SCRIPTPATH="$(dirname "$(readlink -f "$0")")"

source "${SCRIPTPATH}/backup.conf"
source "${SCRIPTPATH}/common_lib.sh"

function create_rsync_backup()
{
	local ret_code=1
	local num_backup
	local cmd_code
	local base_backup

	num_backup="$(count_rsync_backup)"
	cmd_code="$?"

	if [ "$cmd_code" -eq 0 ]; then
		if [ "$num_backup" -ge 0 ] && [ "$num_backup" -lt "$MAX_BACKUPS" ]; then
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_DIR"\
			"$BACKUP_DIR"; then
				ret_code=0
				# Touch the new backup to update it's modify time.
				touch "$BACKUP_DIR"
			else
				if [ -d "$BACKUP_DIR" ]; then
					rm -r "$BACKUP_DIR"
				fi
			fi
		elif [ "$num_backup" -ge "$MAX_BACKUPS" ]; then
			base_backup="$(get_oldest_rsync_backup)"
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_DIR"\
			"$base_backup"; then
				if mv "$base_backup" "$BACKUP_DIR"; then
					ret_code=0
					# Touch the new backup to update it's modify time.
					touch "$BACKUP_DIR"
				fi
			else
				if [ -d "$base_backup" ]; then
					rm -r "$base_backup"
				fi
			fi
		fi
	fi

	if [ "$ret_code" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
		echo "$TIMESTAMP" > "$BACKUP_DIR""$TIMESTAMP_FILE"
		log_systemd "Created new backup: $BACKUP_DIR ."
	else
		log_systemd "Created new backup: $BACKUP_DIR - FAILED ."
	fi

	return "$ret_code"
}

function get_oldest_rsync_backup()
{
	local ret_val=-1
	local num_backup
	local cmd_code
	local backup_list=()

	num_backup="$(count_rsync_backup)"
	cmd_code="$?"

	if [ "$cmd_code" -eq 0 ] && [ "$num_backup" -ge "$MAX_BACKUPS" ]; then
		mapfile -t backup_list <\
		<(ls -dqtr "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
		ret_val="${backup_list[0]}"
	fi

	echo "$ret_val"
}

function count_rsync_backup()
{
	local ret_val=-1
	local list_cmd="ls -1dq ${RSYNC_BACKUP_MAIN_PATH}*"
	local ret_val
	ret_val="$(_count_backup "$list_cmd")"

	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function list_rsync_backup()
{
	echo "Found the following backups:"
	ls -dqtF "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null | nl
}

function rotate_rsync_backup()
{
	local ret_code=1
	local num_backup="count_rsync_backup"
	local list_cmd="ls -dqt ${RSYNC_BACKUP_MAIN_PATH}*"
	local rm_backup="rm -r"

	(_rotate_backup "$num_backup" "$list_cmd" "$rm_backup")
	ret_code="${?:-1}"

	return "$ret_code"
}

function restore_rsync_backup()
{
	local ret_code=1
	local which_backup="${1:-0}"
	local num_backup
	local cmd_code
	local backup_list=()
	local backup

	num_backup="$(count_rsync_backup)"
	cmd_code="$?"


	log_systemd "Starting system restore."
	if [ "$cmd_code" -eq 0 ]; then
		if [ "$num_backup" -ge "$which_backup" ] &&\
		[ "$which_backup" -gt 0 ]; then
			mapfile -t backup_list <\
			<(ls -dqtF "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null)
			backup="${backup_list[$((which_backup-1))]}"
			echo "Restoring $backup ."
			log_systemd "Restoring $backup ."
			# A moment of silence before your system breaks down completely.
			sleep 5
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "-v" "$backup"\
			"$RESTORE_TARGET_PATH"; then
				ret_code=0
				log_systemd "Restored $backup ."
			else
				log_systemd "Restoring $backup - FAILED."
			fi
		fi
	fi

	return "$ret_code"
}

function help_text
{
cat << _EOF_
Usage:
rsync_backup {-b | --backup} {-r | --restore <num>} {-l | --list} {-h | --help}

-b | --backup         Create a backup as per configurations (requires sudo).
-r | --restore <num>  Restore backup <num>: 1 - latest backup (requires sudo).
-l | --list           Lists & numbers the available backups: 1 - latest backup.
-h | --help           Show this help message.

If you want to keep a particular backup, rename it so the script won't be able
to list it, or copy it to another dir. If you need to copy a backup, use the
same rsync command as the script to preserve the attributes.

For restoring, the file name should start with the backup prefix, so the
script can list/use it.
_EOF_
}



### MAIN

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
	ret_code=$?
	if [ "$ret_code" -eq 0 ]; then
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

### END

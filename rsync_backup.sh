#!/usr/bin/env bash



SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(dirname "$(readlink -f "$0")")"
CONF_PATH="${SCRIPT_PATH}/backup.conf"
LIB_PATH="${SCRIPT_PATH}/common_lib.sh"



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
			# '/' Is needed, otherwise rsync will copy the dir itself, not contents.
			# Trailing '/' are irrelevant for the target dirs.
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_DIR"/ \
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
			log_systemd "MAX_BACKUPS ($MAX_BACKUPS) reached, using $base_backup as base (rotating it)."
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "$SOURCE_DIR" \
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
		echo "$TIMESTAMP" > "$BACKUP_DIR"/"$TIMESTAMP_FILE"
		log_systemd "Created new backup: $BACKUP_DIR."
	else
		log_systemd "Created new backup: $BACKUP_DIR - FAILED."
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

	if [ "$cmd_code" -eq 0 ] && [ "$num_backup" -ge 1 ]; then
		mapfile -t backup_list < \
		<(list_rsync_backup | cut -f 2)
		ret_val="${backup_list[((${#backup_list[@]}-1))]}"
	fi

	echo "$ret_val"
}

function get_newest_rsync_backup()
{
	local ret_val=-1
	local num_backup
	local cmd_code
	local backup_list=()

	num_backup="$(count_rsync_backup)"
	cmd_code="$?"

	if [ "$cmd_code" -eq 0 ] && [ "$num_backup" -ge 1 ]; then
		mapfile -t backup_list < <(list_rsync_backup | cut -f 2)
		ret_val="${backup_list[0]}"
	fi
	echo "$ret_val"
}

function count_rsync_backup()
{
	local ret_val=-1
	local list_cmd="list_rsync_backup"
	local ret_val
	ret_val="$(_count_backup "$list_cmd")"

	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function count_targz_backup()
{
	local ret_val=-1
	local list_cmd="ls -1q ${BACKUP_ARCHIVE_DIR}/*${BACKUP_ARCHIVE_SUFFIX}"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function count_gpg2_backup()
{
	local ret_val=-1
	local list_cmd="ls -1q ${BACKUP_GPG_ARCHIVE_DIR}/*${BACKUP_GPG_SUFFIX}"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function count_scp_backup()
{
	local ret_val=-1
	local list_cmd="ssh ${SSH_USER}@${SSH_HOST} ls -1q ${REMOTE_BACKUP_DIR}/*${BACKUP_GPG_SUFFIX}"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function list_rsync_backup()
{
	# Newest 1st.
	ls -dqtF "$RSYNC_BACKUP_MAIN_PATH"* 2>/dev/null | nl
}

function rotate_rsync_backup()
{
	local ret_code=1
	local num_backup="count_rsync_backup"
	# Backups are sorted by mtime, oldest last.
	local list_cmd="ls -dqtr ${RSYNC_BACKUP_MAIN_PATH}*"
	local rm_backup="rm -r"

	(_rotate_backup "$num_backup" "$list_cmd" "$rm_backup")
	ret_code="$?"

	return "$ret_code"
}

function rotate_targz_backup()
{
	local ret_code=1
	local num_targz="count_targz_backup"
	# Newest 1st.
	local list_targz="ls -qt ${BACKUP_ARCHIVE_DIR}/*${BACKUP_ARCHIVE_SUFFIX}"
	local rm_targz="rm"

	(_rotate_backup "$num_targz" "$list_targz" "$rm_targz")
	ret_code="${?:-1}"

	return "$ret_code"
}

function rotate_gpg2_backup()
{
	local ret_code=1
	local num_gpg2="count_gpg2_backup"
	# Newest 1st.
	local list_gpg2="ls -qt ${BACKUP_GPG_ARCHIVE_DIR}/*${BACKUP_GPG_SUFFIX}"
	local rm_gpg2="rm"

    (_rotate_backup "$num_gpg2" "$list_gpg2" "$rm_gpg2")
	ret_code="${?:-1}"


	return "$ret_code"
}

function rotate_scp_backup()
{
	local ret_code=1
	local num_scp="count_scp_backup"
	local list_scp="ssh ${SSH_USER}@${SSH_HOST} ls -1qt ${REMOTE_BACKUP_DIR}/*${BACKUP_GPG_SUFFIX}"
	local rm_scp="ssh ${SSH_USER}@${SSH_HOST} rm"

	(_rotate_backup "$num_scp" "$list_scp" "$rm_scp" "$SSH_HOST")
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
		mapfile -t backup_list < \
		<(list_rsync_backup | cut -f 2)
		if [ "$num_backup" -gt 0 ] && [ "$which_backup" -gt 0 ] && \
			[ "$which_backup" -le "$num_backup" ]; then
			backup="${backup_list[$(($which_backup-1))]}"
			echo "Restoring $backup to $RESTORE_DIR."
			log_systemd "Restoring $backup to $RESTORE_DIR."
			# A moment of silence before your system breaks down completely.
			sleep 5
			if rsync "${RSYNC_BACKUP_OPTIONS[@]}" "-v" "$backup" \
			"$RESTORE_DIR"; then
				ret_code=0
				log_systemd "Restored $backup to $RESTORE_DIR."
			else
				log_systemd "Restoring $backup to $RESTORE_DIR - FAILED."
			fi
		else
			log_systemd "Available backups: ${backup_list[@]}."
			log_systemd "Invalid backup selection $which_backup."
		fi
	fi

	return "$ret_code"
}

function gpg2_encrypt()
{
	local ret_code=1
	local backup_list=()
	local backup_file

	mapfile -t backup_list < <(ls -dqt "$BACKUP_ARCHIVE_DIR"/*"$BACKUP_ARCHIVE_SUFFIX" 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 1 ] && [ -r "$GPG_PASS_FILE" ]; then
		backup_file="${backup_list[0]}"
		if gpg2 --compress-algo none --batch -c --cipher-algo AES256 \
		--passphrase-file "$GPG_PASS_FILE" -o \
		"${backup_file}${BACKUP_GPG_SUFFIX}" "$backup_file" ; then
			log_systemd "gpg2 ${backup_file}${BACKUP_GPG_SUFFIX} successfull."
			ret_code=0
		else
			rm "${backup_file}${BACKUP_GPG_SUFFIX}"
			log_systemd "gpg2 ${backup_file}${BACKUP_GPG_SUFFIX} failed."
		fi
	else
		log_systemd "Check if the gpg_pass file is readable."
	fi

	return "$ret_code"

}

function targz_archive()
{
	local ret_code=1
	local latest_backup
	local timestamp
	local targz_file

	latest_backup="$(get_newest_rsync_backup)"

	if [ "$latest_backup" != "-1" ] && [ "$latest_backup" != "" ] ; then
		read -r timestamp < "$latest_backup"/"$TIMESTAMP_FILE"
		targz_file="${BACKUP_ARCHIVE_DIR}/${BACKUP_ARCHIVE_PREFIX}${timestamp}"
		targz_file="${targz_file}${BACKUP_ARCHIVE_SUFFIX}"
		if tar -zcf "$targz_file" "$latest_backup" 1>/dev/null 2>&1; then
			log_systemd "Created $targz_file."
			ret_code=0
		fi
	fi

	return "$ret_code"
}

function scp_archive()
{
	local ret_code=1
	local backup_list=()
	local backup_file

	mapfile -t backup_list < <(ls -qt "$BACKUP_ARCHIVE_DIR"/*"$BACKUP_GPG_SUFFIX" 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 1 ]; then
		backup_file="${backup_list[0]}"
		if scp -q "$backup_file"\
		"$SSH_USER"@"$SSH_HOST":"$REMOTE_BACKUP_DIR"; then
			log_systemd "scp to $SSH_HOST, $backup_file successfull."
			ret_code=0
		fi
	fi

	return "$ret_code"
}

function archive()
{
	local ret_code=1

	log_systemd "Archiving $RSYNC_BACKUP_PREFIX backup."

	if targz_archive && rotate_targz_backup; then
		ret_code=0
	fi

	if [ "$ret_code" -eq 0 ]; then
		if [ "$TEST" ]; then
			if gpg2_encrypt && rotate_gpg2_backup; then
				m_exit=0
			else
				m_exit=1
			fi
		else
			if gpg2_encrypt && rotate_gpg2_backup && \
			scp_archive && rotate_scp_backup; then
				m_exit=0
			else
				m_exit=1
			fi
		fi
	fi

	return "$ret_code"
}

function help_text
{
	cat <<- _EOF_
	Usage:
	rsync_backup {-b | --backup} {-r | --restore <num>} {-l | --list} {-h | --help}
	
	-b | --backup         Create a backup as per configurations (requires sudo).
	-r | --restore <num>  Restore backup <num>: 1 - latest backup (requires sudo).
	-l | --list           Lists & numbers the available backups: 1 - latest backup.
	--archive             Archive, encrypt and possibly send over ssh.
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
	--archive)
		m_action=4
	;;
	-h|--help)
		m_action=5
	;;
	*)
		m_action=6
	;;
esac

if [ "$TEST" ]; then
	if ! [ -r "$TEST" ]; then
		echo "Missing $TEST conf."
		echo 
		m_action=6
	else
		source "$TEST"
	fi
else
	if ! [ -r "${CONF_PATH}" ]; then
		echo "Missing $CONF_PATH"
		echo 
		m_action=6
	else
		source "$CONF_PATH"
	fi
fi

source "$LIB_PATH"

# Gives resolved absolute path, gets rid of trailing slashes.
SOURCE_DIR="$(realpath -sm $SOURCE_DIR)"
RESTORE_DIR="$(realpath -sm $RESTORE_DIR)"
STORAGE_DIR="$(realpath -sm $STORAGE_DIR)"
RSYNC_BACKUP_MAIN_PATH="$(realpath -sm $STORAGE_DIR)"/"$RSYNC_BACKUP_PREFIX"
BACKUP_DIR="$RSYNC_BACKUP_MAIN_PATH"-"$TIMESTAMP"
BACKUP_ARCHIVE_DIR="$(realpath -sm $BACKUP_ARCHIVE_DIR)"
BACKUP_GPG_ARCHIVE_DIR="$(realpath -sm $BACKUP_GPG_ARCHIVE_DIR)"
REMOTE_BACKUP_DIR="$(realpath -sm $REMOTE_BACKUP_DIR)"

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
		echo "Found the following backups:"
		list_rsync_backup
	;;
	4)
		if archive; then
			m_exit=0
		fi
	;;
	5)
		help_text
		m_exit=0
	;;
	6)
		help_text
		m_exit=1
	;;
esac

exit "$m_exit"

### END

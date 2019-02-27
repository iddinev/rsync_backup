#!/usr/bin/env bash

SCRIPTNAME="$(basename "$0")"
SCRIPTPATH="$(dirname "$(readlink -f "$0")")"

source "${SCRIPTPATH}/backup.conf"
source "${SCRIPTPATH}/common_lib.sh"


function create_rsync_backup()
{
	local ret_code=1

	if "$BACKUP_SCRIPT" --backup; then
		ret_code=0
	fi

	return "$ret_code"
}

function count_targz_backup()
{
	local ret_val=-1
	local list_cmd="ls -1dq ${BACKUP_ARCHIVE_DIR}*${BACKUP_ARCHIVE_SUFFIX}"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
    ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function count_gpg2_backup()
{
	local ret_val=-1
	local list_cmd="ls -1dq ${BACKUP_GPG_ARCHIVE_DIR}*${BACKUP_GPG_SUFFIX}"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
	ret_val="${ret_val:--1}"

	echo "$ret_val"
}

function count_scp_backup()
{
	local ret_val=-1
	local list_cmd="ssh ${SSH_USER}@${SSH_HOST} ls -1dq ${REMOTE_BACKUP_DIR}*"
	local ret_val

	ret_val="$(_count_backup "$list_cmd")"
	ret_val="${ret_val:--1}"

	echo "$ret_val"
}


function rotate_targz_backup()
{
	local ret_code=1
	local num_targz="count_targz_backup"
	local list_targz="ls -1dqt ${BACKUP_ARCHIVE_DIR}*${BACKUP_ARCHIVE_SUFFIX}"
	local rm_targz="rm"

	(_rotate_backup "$num_targz" "$list_targz" "$rm_targz")
	ret_code="${?:-1}"


	return "$ret_code"
}

function rotate_gpg2_backup()
{
	local ret_code=1
	local num_gpg2="count_gpg2_backup"
	local list_gpg2="ls -1dqt ${BACKUP_GPG_ARCHIVE_DIR}*${BACKUP_GPG_SUFFIX}"
	local rm_gpg2="rm"

    (_rotate_backup "$num_gpg2" "$list_gpg2" "$rm_gpg2")
	ret_code="${?:-1}"


	return "$ret_code"
}

function rotate_scp_backup()
{
	local ret_code=1
	local num_scp="count_scp_backup"
	local list_scp="ssh ${SSH_USER}@${SSH_HOST} ls -1dqt ${REMOTE_BACKUP_DIR}*"
	local rm_scp="ssh ${SSH_USER}@${SSH_HOST} rm"

	(_rotate_backup "$num_scp" "$list_scp" "$rm_scp" "$SSH_HOST")
	ret_code="${?:-1}"


	return "$ret_code"
}

function get_latest_rsync_backup()
{
	local ret_val=-1
    local latest_backup
    local backup_list=()

	mapfile -t backup_list < <("$BACKUP_SCRIPT" --list 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 2 ]; then
		latest_backup="$(echo ${backup_list[1]} | cut -d ' ' -f 2)"
		ret_val="$latest_backup"
	fi
	echo "$ret_val"
}

function gpg2_encrypt()
{
	local ret_code=1
    local backup_list=()
    local backup_file

	mapfile -t backup_list < <(ls -dqt "$BACKUP_ARCHIVE_DIR"* 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 1 ] && [ -r "$GPG_PASS_FILE" ]; then
		backup_file="${backup_list[0]}"
		if gpg2 --batch -c --cipher-algo AES256 --passphrase-file "$GPG_PASS_FILE" -o "${backup_file}${BACKUP_GPG_SUFFIX}" "$backup_file" ; then
			log_systemd "gpg2 ${backup_file}${BACKUP_GPG_SUFFIX} successfull."
			ret_code=0
		fi
    else
        log_systemd "Check if the gpg_pass file is readable."
	fi

	return "$ret_code"

}

function targz_backup()
{
	local ret_code=1
	local latest_backup
    local timestamp
    local targz_file

	latest_backup="$(get_latest_rsync_backup)"

	if [ "$latest_backup" != "-1" ] && [ "$latest_backup" != "" ] ; then
		read -r timestamp < "$latest_backup""$TIMESTAMP_FILE"
		targz_file="${BACKUP_ARCHIVE_DIR}${BACKUP_ARCHIVE_PREFIX}${timestamp}${BACKUP_ARCHIVE_SUFFIX}"
        if tar -zcf "$targz_file" "$latest_backup" 1>/dev/null 2>&1; then
			log_systemd "Created $targz_file ."
			ret_code=0
		fi
	fi

	return "$ret_code"
}

function scp_backup()
{
    local ret_code=1
    local backup_list=()
    local backup_file

	mapfile -t backup_list < <(ls -dqt "$BACKUP_ARCHIVE_DIR"* 2>/dev/null)
	if [ "${#backup_list[@]}" -ge 1 ]; then
		backup_file="${backup_list[0]}"
		if scp -q "$backup_file" "$SSH_USER"@"$SSH_HOST":"$REMOTE_BACKUP_DIR"; then
			log_systemd "scp to $SSH_HOST, $backup_file successfull."
			ret_code=0
		fi
	fi

	return "$ret_code"
}

### MAIN

m_exit=1

log_systemd "Starting Monthly backup."
create_rsync_backup
ret_code=$?
if [ "$ret_code" -eq 0 ]; then
	m_exit=0
fi

if [ "$m_exit" -eq 0 ]; then
	if targz_backup && rotate_targz_backup; then
		m_exit=0
	else
		m_exit=1
	fi
fi

if [ "$m_exit" -eq 0 ]; then
	if gpg2_encrypt && rotate_gpg2_backup && scp_backup && rotate_scp_backup; then
		m_exit=0
	else
		m_exit=1
	fi
fi

exit "$m_exit"

### END

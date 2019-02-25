#!/USR/BIN/ENV BASH


BACKUP_SCRIPT="/mnt/backup/code/rsync_backup.sh"
TIMESTAMP_FILE="BACKUP-TIMESTAMP"
BACKUP_TARGZ_DIR="/mnt/backup/backup_targz/"
BACKUP_TARGZ_PREFIX="backup-"
BACKUP_TARGZ_SUFFIX=".tar.gz"
BACKUP_GPG_SUFFIX=".crypt"
SSH_USER="root"
SSH_HOST="mypi"
REMOTE_BACKUP_DIR="/mnt/storage/backups/pc_backup/"
# Should be the same as the max_num of backups in the backup script,
# otherwise you duplicate backups.
MAX_TARGZ=1


function create_rsync_backup()
{
	l_ret_code=1
	if "$BACKUP_SCRIPT" --backup; then
		l_ret_code=0
		log_systemd "Backup created."
	fi
	return "$l_ret_code"
}

function _count_backup()
{
	l_ret_val=-1
	l_list_cmd="${1:-None}"
	if [ "$l_list_cmd" != "None" ]; then
		l_num_backup=$($l_list_cmd 2>/dev/null | wc -l)
		if [ -n "$l_num_backup" ]; then
			l_ret_val="$l_num_backup"
		fi
	fi

	echo "$l_ret_val"
}

function count_targz_backup()
{
	l_ret_val=-1

	l_cmd="ls -1dq ${BACKUP_TARGZ_DIR}*"
	l_result="$(_count_backup $l_cmd)"
	if [ "$l_result" != "-1" ]; then
		l_ret_val="$l_result"
	fi

	echo "$l_ret_val"
}

function count_scp_backup()
{
	l_ret_val=-1

	l_cmd="ssh ${SSH_USER}@${SSH_HOST} 'ls -1dq ${REMOTE_BACKUP_PATH}*'"
	l_result="$(_count_backup $l_cmd)"
	if [ "$l_result" != "-1" ]; then
		l_ret_val="$l_result"
	fi

	echo "$l_ret_val"
}

function _rotate_backup()
{
	l_ret_code=1

	l_count_cmd="${1:-None}"
	l_list_cmd="${2:-None}"
	l_rm_cmd="${3:-None}"

	if [ "$l_count_cmd" != "None" ] && [ "$l_list_cmd" != "None" ]\
	&& [ "$l_rm_cmd" ]; then
		l_num_backup="$($l_count_cmd)"
		l_rc=$?

		if [ "$l_rc" -eq 0 ] && [ "$l_num_backup" -ge 0 ]; then
			if [ "$l_num_backup" -gt "$MAX_TARGZ" ]; then
				mapfile -t l_backup_list < <($l_list_cmd 2>/dev/null)
				for i in $(eval "echo {$MAX_TARGZ..$l_num_backup}"); do
					log_systemd "Rotating away ${l_backup_list[i]} ."
					"$l_rm_cmd ${l_backup_list[i]}"
				done
				l_ret_code=0
			else
				l_ret_code=0
			fi
		fi
	fi

	return "$l_ret_code"
}

function rotate_targz()
{
	l_ret_code=1

	l_num_targz="$(count_targz_backup)"
	l_rc=$?

	if [ "$l_rc" -eq 0 ] && [ "$l_num_targz" -ge 0 ]; then
		if [ "$l_num_targz" -gt "$MAX_TARGZ" ]; then
			mapfile -t l_backup_list < <(ls -dqt "$BACKUP_TARGZ_DIR"* 2>/dev/null)
			for i in $(eval "echo {$MAX_TARGZ..$l_num_targz}"); do
				log_systemd "Rotating away ${l_backup_list[i]} ."
				rm -rf "${l_backup_list[i]}"
			done
			l_ret_code=0
		else
			l_ret_code=0
		fi
	fi

	return "$l_ret_code"
}

function get_latest_rsync_backup()
{
	l_ret_val=-1
	mapfile -t l_backup_list < <("$BACKUP_SCRIPT" --list 2>/dev/null)
	if [ "${#l_backup_list[@]}" -ge 2 ]; then
		l_latest_backup="$(echo ${l_backup_list[1]} | cut -d ' ' -f 2)"
		l_ret_val="$l_latest_backup"
	fi
	echo "$l_ret_val"
}

function gpg2_encrypt()
{
	l_ret_code=1
	mapfile -t l_backup_list < <(ls -dqtr "$BACKUP_TARGZ_DIR"* 2>/dev/null)
	if [ "${#l_backup_list[@]}" -ge 1 ]; then
		l_backup_file="${l_backup_list[0]}"
		if gpg2 --batch -c --cipher-algo AES256\ 
		--passphrase "XXXX" -o "${l_backup_filer}${BACKUP_GPG_SUFFIX}" ; then
			log_systemd "gpg2 $l_backup_file successfull."
			l_ret_code=0
		fi
	fi

	return "$l_ret_code"
	
}

function targz_backup()
{
	l_ret_code=1
	l_latest_backup="$(get_latest_rsync_backup)"
	log_systemd "Found new backup $l_latest_backup ."
	if [ "$l_latest_backup" != "-1" ] && [ "$l_latest_backup" != "" ] ; then
		read l_timestamp < "$l_latest_backup""$TIMESTAMP_FILE"
		l_targz_file="${BACKUP_TARGZ_DIR}${BACKUP_TARGZ_PREFIX}${l_timestamp}${BACKUP_TARGZ_SUFFIX}"
		if tar -zcf "$l_targz_file" "$l_latest_backup"; then
			log_systemd "Created $l_targz_file ."
			l_ret_code=0
		fi
	fi

	return "$l_ret_code"
}

function scp_backup()
{
	l_ret_code=1
	mapfile -t l_backup_list < <(ls -dqtr "$BACKUP_TARGZ_DIR"* 2>/dev/null)
	if [ "${#l_backup_list[@]}" -ge 1 ]; then
		l_backup_file="${l_backup_list[0]}"
		if scp "$l_backup_file" "$SSH_USER"@"$SSH_USER":"$REMOTE_BACKUP_PATH"; then
			log_systemd "scp $l_backup_file successfull."
			l_ret_code=0
		fi
	fi

	return "$l_ret_code"
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
ret_code=$?
if [ "$ret_code" -eq 0 ]; then
	m_exit=0
fi

if [ "$m_exit" -eq 0 ]; then
	if targz_backup; then
		m_exit=0
	else
		m_exit=1
fi

if [ "$m_exit" -eq 0 ]; then
	if targz_backup && rotate_targz; then
		m_exit=0
	else
		m_exit=1
fi

if [ "$m_exit" -eq 0 ]; then
	if gpg2_encrypt && scp_backup; then
		m_exit=0
	else
		m_exit=1
fi

exit "$m_exit"

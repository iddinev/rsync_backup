# Common functions for the backup and archive scripts.

function log()
{
	local prio="${2:-info}"

	echo "$1"

}

function _count_backup()
{
	local ret_val=-1
	local list_cmd="${1:-None}"
	local num_backup

	if [ "$list_cmd" != "None" ]; then
		num_backup="$($list_cmd 2>/dev/null | wc -l)"
		if [ -n "$num_backup" ]; then
			ret_val="$num_backup"
		fi
	fi

	echo "$ret_val"
}

function _rotate_backup()
{
	# 'list_cmd' should give (mtime) sorted output - oldest last.
	local ret_code=1
	local count_cmd="${1:-None}"
	local list_cmd="${2:-None}"
	local rm_cmd="${3:-None}"
	local host="${4:-local}"
	local num_backup
	local backup_list=()
	local cmd_code
	local msg

	if [ "$count_cmd" != "None" ] && [ "$list_cmd" != "None" ]\
	&& [ "$rm_cmd" != "None" ]; then
		num_backup="$($count_cmd)"
		cmd_code=$?

		if [ "$cmd_code" -eq 0 ] && [ "$num_backup" -ge 0 ]; then
			if [ "$num_backup" -gt "$MAX_BACKUPS" ]; then
				mapfile -t backup_list < <($list_cmd 2>/dev/null)
				for i in $(eval "echo {$MAX_BACKUPS..$((num_backup-1))}"); do
					if ($rm_cmd "${backup_list[i]}"); then
						msg="Rotating away on $host, ${backup_list[i]}."
						log_systemd "$msg"
					fi
				done
				ret_code=0
			else
				ret_code=0
			fi
		fi
	fi

	if [ "$ret_code" != "0" ]; then
		log_systemd "Initiate rotation - FAILED."
	fi

	return "$ret_code"
}

#!/usr/bin/env bash



TEST_MAIN_DIR="test_mnt"
declare -A TEST_MNT
TEST_MNT=(
	[test_root.db]="$TEST_MAIN_DIR/root"
	[test_storage.db]="$TEST_MAIN_DIR/backup_storage"
	[test_archive.db]="$TEST_MAIN_DIR/backup_archive"
)
TEST_CONFIG_PATH="end2end.conf"
TEST_RESULT=0



# TEST SETUP
function _create_loop_dev()
{
	local l_rc=1
	local l_db="$1"
	local l_path="${2:-.}"
	local l_size="${3:-20M}"
	local l_loop="$(losetup -f)"

	if ! [ "$DEBUG" ]; then
		if ( dd if=/dev/zero of="$l_db" bs="$l_size" count=1 && \
		losetup -fP "$l_db" && mkfs.ext4 "$l_db" && mkdir -p "$l_path" && \
		mount "$l_loop" "$l_path" ) 1>/dev/null 2>&1; then
			l_rc=0
		fi
	else
		if dd if=/dev/zero of="$l_db" bs="$l_size" count=1 && \
		losetup -fP "$l_db" && mkfs.ext4 "$l_db" && \
		mkdir -p "$l_path" && mount "$l_loop" "$l_path"; then
			l_rc=0
		fi
	fi

	return "$l_rc"
}

function _create_test_dirs()
{
	local l_rc=1

	for db in "${!TEST_MNT[@]}"; do
		if _create_loop_dev "$db" "${TEST_MNT[$db]}" ; then
			l_rc=0
		fi
	done

	return "$l_rc"
}

function _destroy_loop_dev()
{
	local l_rc=1

	if ! [ "$DEBUG" ]; then
		for db in "${!TEST_MNT[@]}"; do
			if umount "${TEST_MNT[$db]}" && \
			rm "$db"; then
				l_rc=0
			fi
		done
		losetup -D
		rm -rf "$TEST_MAIN_DIR"
	else
		l_rc=0
	fi

	return "$l_rc"
}

function test_setup()
{
	echo '~~~~~~~~~~~~~~'
	echo "${FUNCNAME[0]}"
	local l_rc=1

	source "$TEST_CONFIG_PATH"
	BACKUP_SCRIPT="TEST=1 $BACKUP_SCRIPT"

	_create_test_dirs
	l_rc="$?"

	return "$l_rc"
}

function test_teardown()
{
	echo '~~~~~~~~~~~~~~'
	echo "${FUNCNAME[0]}"
	local l_rc=1

	_destroy_loop_dev
	l_rc="$?"

	return "$l_rc"
}

# TEST COMMON

function create_dummy_file()
{
	local l_rc=1
	local l_content="${1:-test_foo_bar}"
	local l_path="${2:-"${TEST_MNT[test_root.db]}"/dummy_file.txt}"

	if echo "$l_content" > "$l_path"; then
		l_rc=0
	fi

	return "$l_rc"
}

# TEST SCENARIOS

function all_tests()
{
	echo '@@@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1

	for tst in "test_rotation"; do
		if ! $tst; then
			TEST_RESULT="$(($TEST_RESULT+1))"
		fi
	done

	if [ "$TEST_RESULT" -eq "0" ]; then
		l_rc=0
	fi

	return "$l_rc"
}

function test_rotation()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_num_backups=0
	local l_rc=1

	create_dummy_file "${FUNCNAME[0]}"

	for ((i=0; i<=$MAX_BACKUPS; i++)); do
		l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}* | wc -l)"
		if [ "$l_num_backups" -ne "$i" ]; then
			echo "Rotation failed at $i/$MAX_BACKUPS."
			l_rc=1
			break
		fi
		sleep 1
		eval "$BACKUP_SCRIPT --backup"
		l_rc=0
	done

	# Test a single rotation.
	sleep 1
	eval "$BACKUP_SCRIPT --backup"
	l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
	${RSYNC_BACKUP_PREFIX}* | wc -l)"

	if [ "$l_num_backups" -ne "$(($MAX_BACKUPS))" ]; then
		echo "Rotation failed at deletion after max ($MAX_BACKUPS) backups."
		l_rc=1
	fi

	return "$l_rc"
}



### MAIN

case "$1" in
	-c|--clean)
		DEBUG="" test_teardown
	;;
	-a|--all)
		test_setup && all_tests; test_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	*)
		false
	;;
esac

### END

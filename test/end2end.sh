#!/usr/bin/env bash



TEST_MAIN_DIR="test_mnt"
declare -A TEST_MNT
TEST_MNT=(
	[test_root.db]="$TEST_MAIN_DIR/root"
	[test_storage.db]="$TEST_MAIN_DIR/storage"
	[test_archive.db]="$TEST_MAIN_DIR/archive"
)
TEST_CONFIG_PATH="end2end.conf"
TEST_RESULT=0



# TEST SETUP
function _create_loop_dev()
{
	local l_rc=1
	local l_db="$1"
	local l_path="${2:-.}"
	local l_size="${3:-5M}"
	local l_loop="$(losetup -f)"

	if ( dd if=/dev/zero of="$l_db" bs="$l_size" count=1 && \
	losetup -fP "$l_db" && mkfs.ext4 "$l_db" && mkdir -p "$l_path" && \
	mount "$l_loop" "$l_path" ) 1>/dev/null 2>&1; then
		l_rc=0
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

function test_teardown()
{
	local l_rc=1

	for db in "${!TEST_MNT[@]}"; do
		if rm -rf "${TEST_MNT[$db]}"/*; then
			l_rc=0
		fi
	done

	return "$l_rc"
}

function test_suite_setup()
{
	echo '~~~~~~~~~~~~~~'
	echo "${FUNCNAME[0]}"
	local l_rc=1

	source "$TEST_CONFIG_PATH"
	BACKUP_SCRIPT="TEST=1 $BACKUP_SCRIPT"
	BACKUP_ARCHIVE_SCRIPT="TEST=1 $BACKUP_ARCHIVE_SCRIPT"

	_create_test_dirs
	l_rc="$?"

	return "$l_rc"
}

function test_suite_teardown()
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

	for tst in "test_rotation" "test_restore" "test_archive_rotation" \
	"test_no_space_storage" "test_no_space_archive"; do
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
	# Main script always rotates by reusing the oldest backup as a base.
	# Still this is tested explicitly.
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_num_backups=0
	local l_rc=1

	create_dummy_file "${FUNCNAME[0]}" "${TEST_MNT[test_root.db]}/${FUNCNAME[0]}"

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

	if [ "$l_rc" -eq "0" ]; then
		# Test a single rotation.
		sleep 1
		eval "$BACKUP_SCRIPT --backup"
		l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}* | wc -l)"
		if [ "$l_num_backups" -ne "$(($MAX_BACKUPS))" ]; then
			echo "Rotation failed at deletion after max ($MAX_BACKUPS) backups."
			l_rc=1
		fi
	fi

	if test_teardown; then
		if [ "$l_rc" -eq "0" ]; then
			echo 'TEST: OK'
			l_rc=0
		else
			echo 'TEST: NOK'
		fi
	else
		echo 'TEST: NOK - teardown failed.'
	fi

	return "$l_rc"
}

function test_archive_rotation()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_num_backups=0
	local l_num_archives=0
	local l_num_gpgs=0
	local l_rc=1

	create_dummy_file "${FUNCNAME[0]}"

	for ((i=0; i<=$MAX_BACKUPS; i++)); do
		l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}* | wc -l)"
		l_num_archives="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_ARCHIVE_SUFFIX} | wc -l)"
		l_num_gpgs="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_GPG_SUFFIX} | wc -l)"
		if [ "$l_num_backups" -ne "$i" ] || [ "$l_num_archives" -ne "$i" ] || \
		[ "$l_num_gpgs" -ne "$i" ]; then
			echo "Rotation failed at $i/$MAX_BACKUPS."
			l_rc=1
			break
		fi
		sleep 1
		eval "$BACKUP_ARCHIVE_SCRIPT"
		l_rc=0
	done

	# Test a single rotation.

	if [ "$l_rc" -eq "0" ]; then
		sleep 1
		eval "$BACKUP_ARCHIVE_SCRIPT"
		l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}* | wc -l)"
		l_num_archives="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_ARCHIVE_SUFFIX} | wc -l)"
		l_num_gpgs="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_GPG_SUFFIX} | wc -l)"
		if [ "$l_num_backups" -ne "$MAX_BACKUPS" ] || \
		[ "$l_num_archives" -ne "$MAX_BACKUPS" ] || \
		[ "$l_num_gpgs" -ne "$MAX_BACKUPS" ]; then
			echo "Rotation failed at deletion after max ($MAX_BACKUPS) backups."
			l_rc=1
		fi
	fi

	if test_teardown; then
		if [ "$l_rc" -eq "0" ]; then
			echo 'TEST: OK'
			l_rc=0
		else
			echo 'TEST: NOK'
		fi
	else
		echo 'TEST: NOK - teardown failed.'
	fi

	return "$l_rc"
}

test_restore()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"

	for ((i=1; i<=$MAX_BACKUPS; i++)); do
		create_dummy_file "$i" "$l_tst_file"
		sleep 1
		eval "$BACKUP_SCRIPT --backup"
	done

	for ((i=$MAX_BACKUPS; i>=1; --i)); do
		eval "$BACKUP_SCRIPT --restore $i"
		content="$(cat $l_tst_file)"
		# Last backup is oldest - has smalles number as file contnetn.
		if [ "$content" -ne "$(($MAX_BACKUPS-$i+1))" ]; then
			echo "Restoration failed at backup $i."
			l_rc=1
			break
		else
			l_rc=0
		fi
	done

	if test_teardown; then
		if [ "$l_rc" -eq "0" ]; then
			echo 'TEST: OK'
			l_rc=0
		else
			echo 'TEST: NOK'
		fi
	else
		echo 'TEST: NOK - teardown failed.'
	fi

	return "$l_rc"
}

test_no_space_storage()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"
	local l_num_backups=0
	local l_backup_pre=""
	local l_backup_post=""


	if dd if=/dev/zero of="$l_tst_file" bs=3M count=1 2>/dev/null; then
		eval "$BACKUP_SCRIPT --backup"
		l_backup_pre="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}*)"
		sleep 1
		eval "$BACKUP_SCRIPT --backup"
		l_num_backups="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}* | wc -l)"
		l_backup_post="$(find ${TEST_MNT[test_storage.db]} -mindepth 1 -type d -name \
		${RSYNC_BACKUP_PREFIX}*)"
		if [ "$l_num_backups" -eq "1" ] && \
		[ "$l_backup_pre" == "$l_backup_post" ]; then
			l_rc=0
		fi
	fi

	if test_teardown; then
		if [ "$l_rc" -eq "0" ]; then
			echo 'TEST: OK'
			l_rc=0
		else
			echo 'TEST: NOK'
		fi
	else
		echo 'TEST: NOK - teardown failed.'
	fi

	return "$l_rc"
}

test_no_space_archive()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"
	local l_num_backups=0
	local l_backup_pre=""
	local l_backup_post=""

	# Sizes in the stuit setup and random file are such as that there is space for only
	# 1 gpg archive.
	if dd if=/dev/urandom of="$l_tst_file" bs=1M count=1 2>/dev/null; then
		eval "$BACKUP_ARCHIVE_SCRIPT"
		l_backup_pre="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_GPG_SUFFIX})"
		sleep 1
		eval "$BACKUP_ARCHIVE_SCRIPT"
		l_num_backups="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_GPG_SUFFIX} | wc -l)"
		l_backup_post="$(find ${TEST_MNT[test_archive.db]} -mindepth 1 -type f -name \
		*${BACKUP_GPG_SUFFIX})"
		if [ "$l_num_backups" -eq "1" ] && \
		[ "$l_backup_pre" == "$l_backup_post" ]; then
			l_rc=0
		fi
	fi

	if test_teardown; then
		if [ "$l_rc" -eq "0" ]; then
			echo 'TEST: OK'
			l_rc=0
		else
			echo 'TEST: NOK'
		fi
	else
		echo 'TEST: NOK - teardown failed.'
	fi

	return "$l_rc"
}



### MAIN

if [[ "$TEST_MAIN_DIR" =~ 'root' ]]; then
	echo "You really should change the TEST_MAIN_DIR var to something that doesn't match root."
	exit 1
fi

case "$1" in
	-c|--clean)
		DEBUG="" test_suite_teardown
	;;
	-a|--all)
		test_suite_setup && all_tests; test_suite_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	--rotate)
		test_suite_setup && test_rotation
		TEST_RESULT="$?"
		test_suite_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	--rotate-archive)
		test_suite_setup && test_archive_rotation
		TEST_RESULT="$?"
		test_suite_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	--restore)
		test_suite_setup && test_restore
		TEST_RESULT="$?"
		test_suite_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	--no-storage)
		test_suite_setup && test_no_space_storage
		TEST_RESULT="$?"
		test_suite_teardown
		echo '##############'
		echo "Test result: $TEST_RESULT failed."
		if [ "$TEST_RESULT" -ne "0" ]; then
			exit 1
		fi
	;;
	--no-archive)
		test_suite_setup && test_no_space_archive
		TEST_RESULT="$?"
		test_suite_teardown
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

#!/usr/bin/env bash



TEST_MAIN_DIR="test_main"
declare -A TEST_MNT
declare -A TEST_MNT_MAIN
TEST_MNT_MAIN=(
	[test_root.db]="$TEST_MAIN_DIR/root"
	[test_storage.db]="$TEST_MAIN_DIR/storage"
	[test_archive.db]="$TEST_MAIN_DIR/archive"
)
for key in "${!TEST_MNT_MAIN[@]}"; do
	TEST_MNT["$key"]="${TEST_MNT_MAIN[$key]}"
done

TEST_CONFIG_TEMPLATE="end2end.template.conf"
TEST_CONFIG="end2end.conf"
TEST_RESULT=0



# TEST SETUP
_create_loop_dev()
{
	local l_rc=1
	local l_db="$1"
	local l_path="${2:-.}"
	local l_size="${3:-5M}"
	local l_loop=""
	l_loop="$(losetup -f)"

	if ( dd if=/dev/zero of="$l_db" bs="$l_size" count=1 && \
	losetup -fP "$l_db" && mkfs.ext4 "$l_db" && mkdir -p "$l_path" && \
	mount "$l_loop" "$l_path" ) 1>/dev/null 2>&1; then
		l_rc=0
	fi

	return "$l_rc"
}

_create_test_dirs()
{
	local l_rc=1
	local l_test_tag="$1"
	local l_size="${2:-5M}"

	for db in "${!TEST_MNT[@]}"; do
		if _create_loop_dev "${TEST_MAIN_DIR}/${l_test_tag}_${db}" "${TEST_MNT[$db]}" "$l_size" ; then
			l_rc=0
		fi
	done

	return "$l_rc"
}

_destroy_loop_dev()
{
	local l_rc=1
	local l_test_tag="$1"

	for db in "${!TEST_MNT[@]}"; do
		if umount "${TEST_MNT[$db]}" && \
		rm -r "${TEST_MNT[$db]}" && \
		rm "${TEST_MAIN_DIR}/${l_test_tag}_${db}"; then
			l_rc=0
		fi
	done

	return "$l_rc"
}

test_setup()
{
	local l_rc=1
	local l_test_tag="$1"
	local l_size="${2:-5M}"

	cp "$TEST_CONFIG_TEMPLATE" "$TEST_CONFIG"
	for db in "${!TEST_MNT[@]}"; do
		TEST_MNT["$db"]="${TEST_MNT_MAIN[$db]}"/"$l_test_tag"
		if mkdir -p "${TEST_MNT[$db]}"; then
			l_rc=0
		fi
	done

	if [ "$l_rc" -eq "0" ]; then
		if ! _create_test_dirs "$l_test_tag" "$l_size"; then
			l_rc=1
		fi
	fi

	if [ "$l_rc" -eq "0" ]; then
		sed -i "s@SOURCE_DIR=\"\"@SOURCE_DIR=\"${TEST_MNT[test_root.db]}\"@" "$TEST_CONFIG"
		sed -i "s@STORAGE_DIR=\"\"@STORAGE_DIR=\"${TEST_MNT[test_storage.db]}\"@" "$TEST_CONFIG"
		sed -i "s@BACKUP_ARCHIVE_DIR=\"\"@BACKUP_ARCHIVE_DIR=\"${TEST_MNT[test_archive.db]}\"@" "$TEST_CONFIG"
	fi

	return "$l_rc"
}

test_teardown()
{
	local l_rc=1
	local l_test_tag="$1"

	if [ "$DEBUG" ]; then
		echo 'DEBUG: skipping teardown actions.'
		if mv "$TEST_CONFIG" "${TEST_MNT[test_root.db]}"; then
			l_rc=0
		fi
	else
		if rm "$TEST_CONFIG" && _destroy_loop_dev "$l_test_tag"; then
			l_rc=0
		fi
	fi

	return "$l_rc"
}

test_suite_setup()
{
	echo '~~~~~~~~~~~~~~'
	echo "${FUNCNAME[0]}"
	local l_rc=1

	# shellcheck source=end2end.template.conf
	if source "$TEST_CONFIG_TEMPLATE"; then
		if [ "$DEBUG" ]; then
			BACKUP_SCRIPT="TEST=$TEST_CONFIG ../rsync_backup.sh"
		else
			BACKUP_SCRIPT="TEST=$TEST_CONFIG ../rsync_backup.sh  2>/dev/null 1>&2"
		fi
		for db in "${!TEST_MNT_MAIN[@]}"; do
			if mkdir -p "${TEST_MNT_MAIN[$db]}"; then
				l_rc=0
			fi
		done
		l_rc="$?"
	fi

	return "$l_rc"
}

test_suite_teardown()
{
	echo '~~~~~~~~~~~~~~'
	echo "${FUNCNAME[0]}"
	local l_rc=1

	if [ "$DEBUG" ]; then
		echo 'DEBUG: skipping teardown actions.'
		l_rc=0
	else
		find $TEST_MAIN_DIR -depth ! -type l -exec mountpoint -q {} \; -exec umount {} \;
		if losetup --detach-all && rm -r "$TEST_MAIN_DIR"; then
			l_rc=0
		fi
	fi

	return "$l_rc"
}

# TEST COMMON

create_dummy_file()
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

all_tests()
{
	echo '@@@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1

	for tst in "test_rotation" "test_restore" "test_archive_rotation" \
	"test_no_space_storage" "test_no_space_archive"; do
		if ! $tst; then
			TEST_RESULT="$((TEST_RESULT+1))"
		fi
	done

	if [ "$TEST_RESULT" -eq "0" ]; then
		l_rc=0
	fi

	return "$l_rc"
}

test_rotation()
{
	# Script rotates by reusing the oldest backup as a base.
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_num_backups=0
	local l_rc=1
	local l_test_tag="${FUNCNAME[0]}"

	if test_setup "$l_test_tag"; then
		create_dummy_file "${FUNCNAME[0]}" "${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"

		for ((i=0; i<=MAX_BACKUPS; i++)); do
			l_num_backups="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*" | wc -l)"
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
			l_num_backups="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*" | wc -l)"
			if [ "$l_num_backups" -ne "$((MAX_BACKUPS))" ]; then
				echo "Rotation failed at deletion after max ($MAX_BACKUPS) backups."
				l_rc=1
			fi
		fi

		if test_teardown "$l_test_tag"; then
			if [ "$l_rc" -eq "0" ]; then
				echo 'TEST: OK'
			else
				echo 'TEST: NOK'
			fi
		else
			echo 'TEST: NOK - teardown failed.'
		fi
	fi

	return "$l_rc"
}

test_archive_rotation()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_num_backups=0
	local l_num_archives=0
	local l_num_gpgs=0
	local l_rc=1
	local l_test_tag="${FUNCNAME[0]}"

	if test_setup "$l_test_tag"; then

		create_dummy_file "${FUNCNAME[0]}" "${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"

		for ((i=0; i<=MAX_BACKUPS; i++)); do
			l_num_backups="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*" | wc -l)"
			l_num_archives="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_ARCHIVE_SUFFIX}" | wc -l)"
			l_num_gpgs="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_GPG_SUFFIX}" | wc -l)"
			if [ "$l_num_backups" -ne "$i" ] || [ "$l_num_archives" -ne "$i" ] || \
			[ "$l_num_gpgs" -ne "$i" ]; then
				echo "Rotation failed at $i/$MAX_BACKUPS."
				l_rc=1
				break
			fi
			sleep 1
			eval "$BACKUP_SCRIPT --backup"
			eval "$BACKUP_SCRIPT --archive"
			l_rc=0
		done

		# Test a single rotation.

		if [ "$l_rc" -eq "0" ]; then
			sleep 1
			eval "$BACKUP_SCRIPT --backup"
			eval "$BACKUP_SCRIPT --archive"
			l_num_backups="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*" | wc -l)"
			l_num_archives="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_ARCHIVE_SUFFIX}" | wc -l)"
			l_num_gpgs="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_GPG_SUFFIX}" | wc -l)"
			if [ "$l_num_backups" -ne "$MAX_BACKUPS" ] || \
			[ "$l_num_archives" -ne "$MAX_BACKUPS" ] || \
			[ "$l_num_gpgs" -ne "$MAX_BACKUPS" ]; then
				echo "Rotation failed at deletion after max ($MAX_BACKUPS) backups."
				l_rc=1
			fi
		fi

		if test_teardown "$l_test_tag"; then
			if [ "$l_rc" -eq "0" ]; then
				echo 'TEST: OK'
				l_rc=0
			else
				echo 'TEST: NOK'
			fi
		else
			echo 'TEST: NOK - teardown failed.'
		fi
	fi

	return "$l_rc"
}

test_restore()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file=""
	local l_test_tag="${FUNCNAME[0]}"
	local l_cmd_rc=1

	if test_setup "$l_test_tag"; then
		l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"
		for ((i=1; i<=MAX_BACKUPS; i++)); do
			create_dummy_file "$i" "$l_tst_file"
			sleep 1
			eval "$BACKUP_SCRIPT --backup"
		done

		for ((i=MAX_BACKUPS; i>=1; --i)); do
			eval "$BACKUP_SCRIPT --restore $i"
			content="$(cat "$l_tst_file")"
			l_cmd_rc="$?"
			if [ "$l_cmd_rc" -ne "0" ]; then
				l_rc=1
				break
			# Last backup is oldest - has smalles number as file contnetn.
			elif [ "$content" -ne "$((MAX_BACKUPS-i+1))" ]; then
				echo "Restoration failed at backup $i."
				l_rc=1
				break
			else
				l_rc=0
			fi
		done

		if test_teardown "$l_test_tag"; then
			if [ "$l_rc" -eq "0" ]; then
				echo 'TEST: OK'
				l_rc=0
			else
				echo 'TEST: NOK'
			fi
		else
			echo 'TEST: NOK - teardown failed.'
		fi
	fi

	return "$l_rc"
}

test_no_space_storage()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file=""
	local l_num_backups=0
	local l_backup_pre=""
	local l_backup_post=""
	local l_test_tag="${FUNCNAME[0]}"

	if test_setup "$l_test_tag"; then
		l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"
		if dd if=/dev/zero of="$l_tst_file" bs=3M count=1 2>/dev/null; then
			eval "$BACKUP_SCRIPT --backup"
			l_backup_pre="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*")"
			sleep 1
			eval "$BACKUP_SCRIPT --backup"
			l_num_backups="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*" | wc -l)"
			l_backup_post="$(find "${TEST_MNT[test_storage.db]}" -mindepth 1 -type d -name \
			"${RSYNC_BACKUP_PREFIX}*")"
			if [ "$l_num_backups" -eq "1" ] && \
			[ "$l_backup_pre" == "$l_backup_post" ]; then
				l_rc=0
			fi
		fi

		if test_teardown "$l_test_tag"; then
			if [ "$l_rc" -eq "0" ]; then
				echo 'TEST: OK'
				l_rc=0
			else
				echo 'TEST: NOK'
			fi
		else
			echo 'TEST: NOK - teardown failed.'
		fi
	fi

	return "$l_rc"
}

test_no_space_archive()
{
	echo '@@'
	echo "${FUNCNAME[0]}"

	local l_rc=1
	local l_tst_file=""
	local l_num_backups=0
	local l_backup_pre=""
	local l_backup_post=""
	local l_test_tag="${FUNCNAME[0]}"

	if test_setup "$l_test_tag"; then
		l_tst_file="${TEST_MNT[test_root.db]}/${FUNCNAME[0]}.txt"
		if dd if=/dev/urandom of="$l_tst_file" bs=1M count=1 2>/dev/null; then
			eval "$BACKUP_SCRIPT --backup"
			eval "$BACKUP_SCRIPT --archive"
			l_backup_pre="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_GPG_SUFFIX}")"
			sleep 1
			eval "$BACKUP_SCRIPT --backup"
			eval "$BACKUP_SCRIPT --archive"
			l_num_backups="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_GPG_SUFFIX}" | wc -l)"
			l_backup_post="$(find "${TEST_MNT[test_archive.db]}" -mindepth 1 -type f -name \
			"*${BACKUP_GPG_SUFFIX}")"
			if [ "$l_num_backups" -eq "1" ] && \
			[ "$l_backup_pre" == "$l_backup_post" ]; then
				l_rc=0
			fi
		fi

		if test_teardown "$l_test_tag"; then
			if [ "$l_rc" -eq "0" ]; then
				echo 'TEST: OK'
				l_rc=0
			else
				echo 'TEST: NOK'
			fi
		else
			echo 'TEST: NOK - teardown failed.'
		fi
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
		DEBUG='' test_suite_teardown
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

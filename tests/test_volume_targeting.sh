#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PROJECT_DIR/bypass-mdm-v2.sh"

failures=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

pass() {
	printf 'PASS: %s\n' "$1"
}

assert_success() {
	local name="$1"
	shift
	if "$@"; then
		pass "$name"
	else
		fail "$name"
	fi
}

assert_failure() {
	local name="$1"
	shift
	if "$@"; then
		fail "$name"
	else
		pass "$name"
	fi
}

make_fixture() {
	fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/bypass-mdm-tests.XXXXXX")"
	volumes_root="$fixture_dir/Volumes"
	mock_bin="$fixture_dir/bin"
	diskutil_log="$fixture_dir/diskutil.log"
	mkdir -p \
		"$volumes_root/GoldenGate/System/Library/CoreServices" \
		"$volumes_root/GoldenGate/private/var/db/dslocal/nodes/Default" \
		"$volumes_root/GoldenGate - Data/private/var/db/dslocal/nodes/Default" \
		"$volumes_root/GoldenGate - Data/Users" \
		"$mock_bin"

	cat >"$mock_bin/diskutil" <<'EOF'
#!/bin/bash

printf '%s\n' "$*" >>"$DISKUTIL_LOG"

if [ "$1" != "info" ] || [ "$2" != "-plist" ]; then
	exit 64
fi

case "$3" in
*"AlphaMac - Data")
	group_id="OTHER-MAC-GROUP"
	internal="true"
	external_device="false"
	volume_name="AlphaMac - Data"
	;;
*"AlphaMac")
	group_id="OTHER-MAC-GROUP"
	internal="true"
	external_device="false"
	volume_name="AlphaMac"
	;;
*"GoldenGate - Data")
	group_id="${DATA_GROUP_ID:-EXTERNAL-GROUP}"
	internal="${DATA_INTERNAL:-false}"
	external_device="${DATA_EXTERNAL_DEVICE:-true}"
	volume_name="GoldenGate - Data"
	;;
*"GoldenGate")
	group_id="${SYSTEM_GROUP_ID:-EXTERNAL-GROUP}"
	internal="${SYSTEM_INTERNAL:-false}"
	external_device="${SYSTEM_EXTERNAL_DEVICE:-true}"
	volume_name="GoldenGate"
	;;
*)
	exit 1
	;;
esac

cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>APFSVolumeGroupID</key>
	<string>$group_id</string>
	<key>Internal</key>
	<$internal/>
	<key>RemovableMediaOrExternalDevice</key>
	<$external_device/>
	<key>VolumeName</key>
	<string>$volume_name</string>
</dict>
</plist>
PLIST
EOF
	chmod +x "$mock_bin/diskutil"
}

remove_fixture() {
	rm -rf "$fixture_dir"
}

run_script() {
	if [ "${DEBUG_TESTS:-0}" = "1" ]; then
		if [ -n "${RUN_INPUT:-}" ]; then
			printf '%s\n' "$RUN_INPUT" | env \
				VOLUMES_ROOT="$volumes_root" \
				DISKUTIL_BIN="$mock_bin/diskutil" \
				DISKUTIL_LOG="$diskutil_log" \
				/bin/bash "$SCRIPT" "$@"
		else
			VOLUMES_ROOT="$volumes_root" \
			DISKUTIL_BIN="$mock_bin/diskutil" \
			DISKUTIL_LOG="$diskutil_log" \
			/bin/bash "$SCRIPT" "$@"
		fi
	else
		if [ -n "${RUN_INPUT:-}" ]; then
			printf '%s\n' "$RUN_INPUT" | env \
				VOLUMES_ROOT="$volumes_root" \
				DISKUTIL_BIN="$mock_bin/diskutil" \
				DISKUTIL_LOG="$diskutil_log" \
				/bin/bash "$SCRIPT" "$@" >/dev/null 2>&1
		else
			VOLUMES_ROOT="$volumes_root" \
			DISKUTIL_BIN="$mock_bin/diskutil" \
			DISKUTIL_LOG="$diskutil_log" \
			/bin/bash "$SCRIPT" "$@" >/dev/null 2>&1
		fi
	fi
}

test_interactive_system_volume_selection() {
	local output
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	output=$(printf '2\n' | env \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only 2>&1)
	status=$?
	if [ "$status" -eq 0 ]; then
		printf '%s\n' "$output" | grep -Fq '1) AlphaMac [Internal]' || status=1
		printf '%s\n' "$output" | grep -Fq '2) GoldenGate [External]' || status=1
	fi
	remove_fixture
	return "$status"
}

test_arrow_key_system_volume_selection() {
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	printf '\033[B\n' | env \
		BYPASS_MDM_FORCE_ARROW_MENU=1 \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only >/dev/null 2>&1
	status=$?
	remove_fixture
	return "$status"
}

test_real_tty_uses_arrow_menu() {
	local transcript
	local status

	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	transcript="$fixture_dir/tty-output.log"
	printf '\033[B\n' | TERM=xterm script -q -e "$transcript" env \
		VOLUMES_ROOT="$volumes_root" \
		DISKUTIL_BIN="$mock_bin/diskutil" \
		DISKUTIL_LOG="$diskutil_log" \
		/bin/bash "$SCRIPT" --require-external --validate-only >/dev/null 2>&1
	status=$?
	if [ "$status" -eq 0 ]; then
		grep -Fq 'Use Up/Down arrows to choose' "$transcript" || status=1
		grep -Fq 'Target volume pair validated' "$transcript" || status=1
	fi
	remove_fixture
	return "$status"
}

test_invalid_menu_selection_retries() {
	make_fixture
	mkdir -p \
		"$volumes_root/AlphaMac/System/Library/CoreServices" \
		"$volumes_root/AlphaMac - Data/private/var/db/dslocal/nodes/Default"
	RUN_INPUT=$'99\ninvalid\n2' run_script \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_explicit_external_pair() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_system_name_matches_data_volume() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_mismatched_volume_groups() {
	make_fixture
	DATA_GROUP_ID="OTHER-GROUP" run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_missing_data_volume() {
	make_fixture
	rm -rf "$volumes_root/GoldenGate - Data"
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_rejects_internal_target() {
	make_fixture
	SYSTEM_INTERNAL="true" SYSTEM_EXTERNAL_DEVICE="false" run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--require-external \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_rejects_path_traversal() {
	make_fixture
	run_script \
		--system-volume "../GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--validate-only
	local status=$?
	remove_fixture
	return "$status"
}

test_never_renames_volume() {
	make_fixture
	run_script \
		--system-volume "GoldenGate" \
		--data-volume "GoldenGate - Data" \
		--validate-only || {
		remove_fixture
		return 1
	}
	if grep -q '^rename ' "$diskutil_log"; then
		remove_fixture
		return 1
	fi
	remove_fixture
	return 0
}

test_password_is_visible() {
	grep -Fq 'read -p "Enter Temporary Password' "$SCRIPT" &&
		! grep -Fq 'read -s -p "Enter Temporary Password' "$SCRIPT" &&
		grep -Fq 'and password: ${YEL}$passw${NC}' "$SCRIPT"
}

assert_success "selects a system volume interactively and matches its data volume" test_interactive_system_volume_selection
assert_success "supports down-arrow and Enter system-volume selection" test_arrow_key_system_volume_selection
assert_success "automatically uses the arrow menu on a real TTY" test_real_tty_uses_arrow_menu
assert_success "re-prompts after an invalid system-volume menu choice" test_invalid_menu_selection_retries
assert_success "accepts an explicit external APFS volume pair" test_explicit_external_pair
assert_success "matches the data volume when only the system name is provided" test_system_name_matches_data_volume
assert_failure "rejects volumes from different APFS volume groups" test_mismatched_volume_groups
assert_failure "rejects an unmounted or missing data volume" test_missing_data_volume
assert_failure "rejects an internal target when external media is required" test_rejects_internal_target
assert_failure "rejects volume names containing path traversal" test_rejects_path_traversal
assert_success "does not rename the selected data volume" test_never_renames_volume
assert_success "shows password input and prints the password after completion" test_password_is_visible

if [ "$failures" -ne 0 ]; then
	printf '\n%d test(s) failed\n' "$failures" >&2
	exit 1
fi

printf '\nAll volume targeting tests passed\n'

#!/bin/sh
set -eu

ROM_MOUNT="/mnt/mmc"
WORK_DIR="$ROM_MOUNT/MUOS/boot-timing/fixed-runtime-services"
BACKUP_DIR="$WORK_DIR/backup"
LOG_FILE="$WORK_DIR/install.log"
MARKER="$WORK_DIR/fixed-runtime-services-installed"
CARD_INSTALLER="$ROM_MOUNT/MUOS/init/62-install-fixed-runtime-services.sh"

mkdir -p "$BACKUP_DIR"
exec >>"$LOG_FILE" 2>&1

sha_file() {
	sha256sum "$1" | awk '{print $1}'
}

fail() {
	printf 'FAILED: %s\n' "$*"
	exit 1
}

check_one() {
	NAME=$1
	SOURCE=$2
	TARGET=$3
	OLD_SHA=$4
	NEW_SHA=$5

	[ -f "$SOURCE" ] || fail "$NAME source missing"
	[ "$(sha_file "$SOURCE")" = "$NEW_SHA" ] || fail "$NAME source mismatch"
	[ -f "$TARGET" ] || fail "$NAME target missing"
	CURRENT_SHA=$(sha_file "$TARGET")
	[ "$CURRENT_SHA" = "$OLD_SHA" ] || [ "$CURRENT_SHA" = "$NEW_SHA" ] ||
		fail "refusing unknown $NAME target $CURRENT_SHA"
}

install_one() {
	NAME=$1
	SOURCE=$2
	TARGET=$3
	OLD_SHA=$4
	NEW_SHA=$5
	BACKUP="$BACKUP_DIR/$NAME.pre-fixed"
	TEMP="$TARGET.bird-new"

	CURRENT_SHA=$(sha_file "$TARGET")
	if [ "$CURRENT_SHA" = "$NEW_SHA" ]; then
		printf '%s already fixed\n' "$NAME"
		return 0
	fi

	if [ -f "$BACKUP" ]; then
		[ "$(sha_file "$BACKUP")" = "$OLD_SHA" ] || fail "$NAME backup mismatch"
	else
		cp "$TARGET" "$BACKUP"
	fi

	rm -f "$TEMP"
	cp "$SOURCE" "$TEMP"
	chmod 755 "$TEMP"
	sh -n "$TEMP" || fail "$NAME syntax check failed"
	[ "$(sha_file "$TEMP")" = "$NEW_SHA" ] || fail "$NAME temporary mismatch"
	mv -f "$TEMP" "$TARGET"
	[ "$(sha_file "$TARGET")" = "$NEW_SHA" ] || fail "$NAME installed mismatch"
	printf '%s installed\n' "$NAME"
}

DEVICE_SOURCE="$WORK_DIR/device-start-rg34xxsp.sh"
HOTKEY_SOURCE="$WORK_DIR/hotkey-rg34xxsp.sh"
LID_SOURCE="$WORK_DIR/lid-rg34xxsp.sh"
LOWPOWER_SOURCE="$WORK_DIR/lowpower-rg34xxsp.sh"
CHARGE_SOURCE="$WORK_DIR/charge-rg34xxsp.sh"
IDLE_SOURCE="$WORK_DIR/idle-disabled-rg34xxsp.sh"
MODULE_SOURCE="$WORK_DIR/module-rg34xxsp.sh"
USER_INIT_SOURCE="$WORK_DIR/user-init-fixed.sh"

DEVICE_TARGET="/opt/muos/script/device/start.sh"
HOTKEY_TARGET="/opt/muos/script/mux/hotkey.sh"
LID_TARGET="/opt/muos/script/device/lid.sh"
LOWPOWER_TARGET="/opt/muos/script/system/lowpower.sh"
CHARGE_TARGET="/opt/muos/script/device/charge.sh"
IDLE_TARGET="/opt/muos/script/mux/idle.sh"
MODULE_TARGET="/opt/muos/script/device/module.sh"
USER_INIT_TARGET="/opt/muos/script/system/user_init.sh"

DEVICE_OLD="3b285ad48e60339742239cf0d65811277f80f6e5fd3f3f2c53d0b5ec60b36507"
HOTKEY_OLD="40c32e47721f473d4a13d385cb2430f84f5ba863cc4861bb34c60051ca57574c"
LID_OLD="c27b59365902dbfbecda3b837e73b87f1d0cb9f096cc18eb0e515ff1c47e72cb"
LOWPOWER_OLD="4ad4df3a63dce8a918ad52e2e5dcf23d248bc15e73457c2fb4901ef7e976bc65"
CHARGE_OLD="ab94f6d1368d0736d9426dd3ee5edc6fff2adfe499a8e12b654e43c9ff73c0f1"
IDLE_OLD="8a79101adeeb6cc41731fac38550627bebeb1bca2f32929c783da4b2b9e88458"
MODULE_OLD="e99c6b9ef73e141e14c62b528df3d8c9a71e3930dd755d14e2dab40e17423c6e"
USER_INIT_OLD="783b546ca8c990954c419a9b6196ba83ac09426a34a56a5738e23b41087e7c87"

DEVICE_NEW="15ecc8e1dce834e06894c492a8dde7825df3c66fe40ebe5f673301adec91886b"
HOTKEY_NEW="6e7a19627872d084e3c41780111b4a241efd290d681c7656b60e77b7f08a0866"
LID_NEW="db8f9812bebd8c7590898c71d642dbba34e93183811f7ed1bf8c13fbc76c8e6e"
LOWPOWER_NEW="9a06308b829b735ce711064cd3a6f9ee848d79883648d55af961b7789e7545a9"
CHARGE_NEW="346c91762be866f3ed718d028b603c9b13af080a32203ea5806401ac55041830"
IDLE_NEW="5ad7651783150bca2fd1d8f55cf0db18d11aa9a6a1620d73a52ccd3cd6ba6c63"
MODULE_NEW="b17fa8ac0c6f5d0fa90e584d78724d0b4ebc71d883f92f3bee4f532e8a645d"
USER_INIT_NEW="d8a77b65826ebf680ed14b5a9a2c2871c5e31adae42d79b8741ecc71c495b2c7"

printf 'fixed RG34XX-SP runtime service installer start\n'

# Validate every payload and active target before modifying any target.
check_one device-start "$DEVICE_SOURCE" "$DEVICE_TARGET" "$DEVICE_OLD" "$DEVICE_NEW"
check_one hotkey "$HOTKEY_SOURCE" "$HOTKEY_TARGET" "$HOTKEY_OLD" "$HOTKEY_NEW"
check_one lid "$LID_SOURCE" "$LID_TARGET" "$LID_OLD" "$LID_NEW"
check_one lowpower "$LOWPOWER_SOURCE" "$LOWPOWER_TARGET" "$LOWPOWER_OLD" "$LOWPOWER_NEW"
check_one charge "$CHARGE_SOURCE" "$CHARGE_TARGET" "$CHARGE_OLD" "$CHARGE_NEW"
check_one idle "$IDLE_SOURCE" "$IDLE_TARGET" "$IDLE_OLD" "$IDLE_NEW"
check_one module "$MODULE_SOURCE" "$MODULE_TARGET" "$MODULE_OLD" "$MODULE_NEW"
check_one user-init "$USER_INIT_SOURCE" "$USER_INIT_TARGET" "$USER_INIT_OLD" "$USER_INIT_NEW"

install_one device-start "$DEVICE_SOURCE" "$DEVICE_TARGET" "$DEVICE_OLD" "$DEVICE_NEW"
install_one hotkey "$HOTKEY_SOURCE" "$HOTKEY_TARGET" "$HOTKEY_OLD" "$HOTKEY_NEW"
install_one lid "$LID_SOURCE" "$LID_TARGET" "$LID_OLD" "$LID_NEW"
install_one lowpower "$LOWPOWER_SOURCE" "$LOWPOWER_TARGET" "$LOWPOWER_OLD" "$LOWPOWER_NEW"
install_one charge "$CHARGE_SOURCE" "$CHARGE_TARGET" "$CHARGE_OLD" "$CHARGE_NEW"
install_one idle "$IDLE_SOURCE" "$IDLE_TARGET" "$IDLE_OLD" "$IDLE_NEW"
install_one module "$MODULE_SOURCE" "$MODULE_TARGET" "$MODULE_OLD" "$MODULE_NEW"
install_one user-init "$USER_INIT_SOURCE" "$USER_INIT_TARGET" "$USER_INIT_OLD" "$USER_INIT_NEW"

# This is persistent policy, not per-boot work.  Set it once during migration.
printf '%s' 100 >/opt/muos/device/config/audio/max

sync
printf '%s\n' installed >"$MARKER"
[ ! -f "$CARD_INSTALLER" ] || mv -f "$CARD_INSTALLER" "$CARD_INSTALLER.done"
printf 'SUCCESS: eight fixed RG34XX-SP runtime services installed; active next boot\n'

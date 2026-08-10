#!/bin/sh
# Host-only regression coverage for the fixed final-root systemd transaction.
# The retained image enables powerstate from multi-user.target. Making that
# unit wait for essway closes a cycle through graphical.target and can cause
# systemd to discard the supervisor start job.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
POWER=$ROOT/kernel/rocknix/stock-root/bird-powerstate.service
CONTROLS=$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.service
STORAGE=$ROOT/kernel/rocknix/stock-root/rocknix-automount.service
SAVE=$ROOT/kernel/rocknix/stock-root/bird-save-config.service
UI=$ROOT/kernel/rocknix/stock-root/essway.service
TARGET=$ROOT/kernel/rocknix/stock-root/rocknix.target
REPORT=$ROOT/kernel/rocknix/stock-root/rocknix-report-stats.service
AUTOSTART=$ROOT/kernel/rocknix/stock-root/rocknix-autostart.service
NETWORK_MANAGER=$ROOT/kernel/rocknix/stock-root/NetworkManager.service
IWD=$ROOT/kernel/rocknix/stock-root/iwd.service
RESOLVED=$ROOT/kernel/rocknix/stock-root/systemd-resolved.service
TIMESYNCD=$ROOT/kernel/rocknix/stock-root/systemd-timesyncd.service
RFKILL=$ROOT/kernel/rocknix/stock-root/systemd-rfkill.service
FIRST_FRAME=$ROOT/kernel/rocknix/stock-root/first-frame-prep.sh
DISPATCH=$ROOT/kernel/rocknix/stock-root/capture-requested-diagnostics.sh
CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-boot-state.sh
STAGE5_CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-stage5-state.sh
STAGE5_WINDOW=$ROOT/kernel/rocknix/stock-root/capture-stage5-window-counters.sh
STAGE5_ACQUIRE=$ROOT/kernel/rocknix/stock-root/capture-stage5-window.sh
MOUNT_STORAGE=$ROOT/kernel/rocknix/stock-root/mount-storage.sh
SYSTEM_MASK_POLICY=$ROOT/kernel/rocknix/hermetic-system-masks.tsv
RUNNER=$ROOT/kernel/rocknix/stock-root/run-content.sh
SUSPEND=$ROOT/kernel/rocknix/stock-root/bird-suspend.sh
CONTROLS_SOURCE=$ROOT/kernel/rocknix/stock-root/bird-fixed-controls.c

grep -Fqx 'After=local-fs.target' "$POWER"
grep -Fqx 'WantedBy=multi-user.target' "$POWER"
grep -Fqx 'ExecStart=/flash/bird/bird-powerstate' "$POWER"
if grep -Eq '^(After|Before|Wants|Requires)=.*essway\.service' "$POWER"; then
	printf '%s\n' 'powerstate must not order against essway' >&2
	exit 1
fi

grep -Fqx 'ExecStart=/flash/bird/bird-fixed-controls' "$CONTROLS"
grep -Fqx 'ExecStart=/flash/bird/fixed-storage.sh' "$STORAGE"
grep -Fqx 'ExecStart=/flash/bird/bird-save-config.sh' "$SAVE"

# These fixed unit bytes are themselves fast-development payloads. Exercise
# their offline/on-demand policy directly rather than only checking that some
# caller mentions their filenames.
grep -Fqx 'ExecStart=/bin/bash -a -c '\''source /etc/profile && exec /flash/bird/bird-autostart'\''' \
	"$AUTOSTART"
grep -Fqx 'WantedBy=rocknix.target' "$AUTOSTART"
grep -Fqx 'ConditionPathExists=/run/bird/network-request' "$NETWORK_MANAGER"
grep -Fqx 'ExecStart=/usr/sbin/NetworkManager --no-daemon' "$NETWORK_MANAGER"
grep -Fqx 'ConditionPathExists=/run/bird/network-request' "$IWD"
grep -Fqx 'ExecStart=/usr/lib/iwd' "$IWD"
grep -Fqx 'ConditionPathExists=/run/bird/network-request' "$RESOLVED"
grep -Fqx 'ExecStart=!!/usr/lib/systemd/systemd-resolved' "$RESOLVED"
grep -Fqx 'ConditionPathExists=/run/bird/network-request' "$TIMESYNCD"
grep -Fqx 'ExecStart=!!/usr/lib/systemd/systemd-timesyncd' "$TIMESYNCD"
grep -Fqx 'ConditionPathExists=/run/bird/network-request' "$RFKILL"
grep -Fqx 'ExecStart=/usr/lib/systemd/systemd-rfkill' "$RFKILL"
for NETWORK_UNIT in "$NETWORK_MANAGER" "$IWD" "$RESOLVED" "$TIMESYNCD" "$RFKILL"; do
	[ "$(grep -Fc 'ConditionPathExists=/run/bird/network-request' "$NETWORK_UNIT")" -eq 1 ]
done

sh -n "$FIRST_FRAME"
grep -Fq 'MAX=$(cat "$BACKLIGHT/max_brightness")' "$FIRST_FRAME"
grep -Fq 'RAW=$(cat "$BACKLIGHT/brightness")' "$FIRST_FRAME"
grep -Fq "printf 'brightness_write=none raw=%s max=%s" "$FIRST_FRAME"
if grep -Eq '(>|tee[[:space:]]).*(BACKLIGHT|/backlight/).*(brightness|bl_power)' \
	"$FIRST_FRAME"; then
	printf '%s\n' 'first-frame preparation regained a panel write' >&2
	exit 1
fi
if grep -Eq '(^|[;&|[:space:]])exit([[:space:]]|$)' "$FIRST_FRAME"; then
	printf '%s\n' 'first-frame observation gained an unconditional exit path' >&2
	exit 1
fi

grep -Eq '^After=.*graphical\.target' "$UI"
grep -Fqx 'ExecStartPre=/flash/bird/first-frame-prep.sh' "$UI"
grep -Fqx 'ExecStart=/flash/bird/supervisor.sh' "$UI"
grep -Eq '^Wants=.*essway\.service.*powerstate\.service.*rocknix-report-stats\.service' "$TARGET"
grep -Fqx 'After=rocknix-autostart.service' "$REPORT"
grep -Fqx \
	'ConditionPathExists=|/storage/bird-data/Bird/boot-diagnostics.request' \
	"$REPORT"
grep -Fqx \
	'ConditionPathExists=|/storage/bird-data/Bird/stage5-idle-window.request' \
	"$REPORT"
grep -Fqx 'ExecStart=/flash/bird/capture-requested-diagnostics.sh' "$REPORT"
grep -Fqx 'RuntimeMaxSec=120s' "$REPORT"
grep -Fq 'stock-root-boot-state-$BOOT_ID.log' "$CAPTURE"
grep -Fq 'cp -f "$LOG" "$LATEST"' "$CAPTURE"
grep -Fq 'bird_stage5_snapshot_version=1' "$STAGE5_CAPTURE"
grep -Fq 'BIRD_STAGE5_LABEL' "$STAGE5_CAPTURE"
if grep -Fq 'stage5-idle-window.request' "$CAPTURE"; then
	printf '%s\n' 'broad snapshot still owns the Stage 5 window' >&2
	exit 1
fi
grep -Fq 'STAGE5_CAPTURE=${BIRD_STAGE5_CAPTURE:-/flash/bird/capture-stage5-window.sh}' "$DISPATCH"
grep -Fq 'BOOT_CAPTURE=${BIRD_BOOT_DIAGNOSTICS_CAPTURE:-/flash/bird/capture-boot-state.sh}' "$DISPATCH"
grep -Fq '"$COUNTERS" start' "$STAGE5_ACQUIRE"
grep -Fq '"$COUNTERS" end' "$STAGE5_ACQUIRE"
grep -Fq 'bird_stage5_window_version=2' "$STAGE5_WINDOW"
grep -Fq 'rm -f "$REQUEST"' "$STAGE5_ACQUIRE"
grep -Fq 'settle_seconds=%s window_seconds=%s' "$STAGE5_ACQUIRE"
grep -Fq 'trap cleanup EXIT' "$CAPTURE"
grep -Fq "trap 'exit 1' HUP INT TERM" "$CAPTURE"

# Bird owns the one-user power/session policy without a login manager. The
# direct control process consumes both switch sources, the retained provider
# has no login1 client, and content explicitly joins seatd before Sway.
for MASKED_UNIT in systemd-logind.service systemd-tmpfiles-clean.timer \
	systemd-update-utmp.service systemd-update-utmp-runlevel.service; do
	grep -Fqx "$(printf 'mask\tusr/lib/systemd/system/%s' "$MASKED_UNIT")" \
		"$SYSTEM_MASK_POLICY"
done
grep -Fq 'systemctl start seatd.service' "$RUNNER"
grep -Fq 'SOURCE_POWER' "$CONTROLS_SOURCE"
grep -Fq 'SOURCE_LID' "$CONTROLS_SOURCE"
if grep -Eq 'loginctl|org[.]freedesktop[.]login1|systemd-inhibit' \
	"$RUNNER" "$SUSPEND" "$CONTROLS_SOURCE"; then
	printf '%s\n' 'active fixed-device path regained a login1 consumer' >&2
	exit 1
fi

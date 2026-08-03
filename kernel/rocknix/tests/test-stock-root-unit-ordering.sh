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
CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-boot-state.sh

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

grep -Eq '^After=.*graphical\.target' "$UI"
grep -Fqx 'ExecStartPre=/flash/bird/first-frame-prep.sh' "$UI"
grep -Fqx 'ExecStart=/flash/bird/supervisor.sh' "$UI"
grep -Eq '^Wants=.*essway\.service.*powerstate\.service' "$TARGET"
grep -Fqx 'After=rocknix-autostart.service' "$REPORT"
grep -Fqx \
	'ConditionPathExists=/storage/.config/bird/boot-diagnostics.request' \
	"$REPORT"
grep -Fqx 'ExecStart=/flash/bird/capture-boot-state.sh' "$REPORT"
grep -Fq 'stock-root-boot-state-$BOOT_ID.log' "$CAPTURE"
grep -Fq 'cp -f "$LOG" "$LATEST"' "$CAPTURE"
grep -Fq 'trap cleanup EXIT' "$CAPTURE"
grep -Fq "trap 'exit 1' HUP INT TERM" "$CAPTURE"

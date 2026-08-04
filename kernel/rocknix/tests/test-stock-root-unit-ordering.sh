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
STAGE5_SERVICE=$ROOT/kernel/rocknix/stock-root/bird-stage5-window.service
CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-boot-state.sh
STAGE5_CAPTURE=$ROOT/kernel/rocknix/stock-root/capture-stage5-state.sh
STAGE5_WINDOW=$ROOT/kernel/rocknix/stock-root/capture-stage5-window-counters.sh
STAGE5_ACQUIRE=$ROOT/kernel/rocknix/stock-root/capture-stage5-window.sh
MOUNT_STORAGE=$ROOT/kernel/rocknix/stock-root/mount-storage.sh
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

grep -Eq '^After=.*graphical\.target' "$UI"
grep -Fqx 'ExecStartPre=/flash/bird/first-frame-prep.sh' "$UI"
grep -Fqx 'ExecStart=/flash/bird/supervisor.sh' "$UI"
grep -Eq '^Wants=.*essway\.service.*powerstate\.service.*bird-stage5-window\.service' "$TARGET"
grep -Fqx 'After=rocknix-autostart.service' "$REPORT"
grep -Fqx \
	'ConditionPathExists=/storage/bird-data/MUOS/Bird/boot-diagnostics.request' \
	"$REPORT"
grep -Fqx 'ExecStart=/flash/bird/capture-boot-state.sh' "$REPORT"
grep -Fqx 'RuntimeMaxSec=45s' "$REPORT"
grep -Fq 'stock-root-boot-state-$BOOT_ID.log' "$CAPTURE"
grep -Fq 'cp -f "$LOG" "$LATEST"' "$CAPTURE"
grep -Fq 'bird_stage5_snapshot_version=1' "$STAGE5_CAPTURE"
grep -Fq 'BIRD_STAGE5_LABEL' "$STAGE5_CAPTURE"
if grep -Fq 'stage5-idle-window.request' "$CAPTURE"; then
	printf '%s\n' 'broad snapshot still owns the Stage 5 window' >&2
	exit 1
fi
grep -Fqx 'After=rocknix-autostart.service' "$STAGE5_SERVICE"
grep -Fqx 'ConditionPathExists=/storage/bird-data/MUOS/Bird/stage5-idle-window.request' "$STAGE5_SERVICE"
grep -Fqx 'ExecStart=/flash/bird/capture-stage5-window.sh' "$STAGE5_SERVICE"
grep -Fqx 'RuntimeMaxSec=120s' "$STAGE5_SERVICE"
grep -Fq '"$COUNTERS" start' "$STAGE5_ACQUIRE"
grep -Fq '"$COUNTERS" end' "$STAGE5_ACQUIRE"
grep -Fq 'bird_stage5_window_version=1' "$STAGE5_WINDOW"
grep -Fq 'rm -f "$REQUEST"' "$STAGE5_ACQUIRE"
grep -Fq 'settle_seconds=%s window_seconds=%s' "$STAGE5_ACQUIRE"
grep -Fq 'trap cleanup EXIT' "$CAPTURE"
grep -Fq "trap 'exit 1' HUP INT TERM" "$CAPTURE"

# Bird owns the one-user power/session policy without a login manager. The
# direct control process consumes both switch sources, the retained provider
# has no login1 client, and content explicitly joins seatd before Sway.
grep -Fq 'systemd-logind.service' "$MOUNT_STORAGE"
grep -Fq 'systemd-tmpfiles-clean.timer' "$MOUNT_STORAGE"
grep -Fq 'systemd-update-utmp.service' "$MOUNT_STORAGE"
grep -Fq 'systemd-update-utmp-runlevel.service' "$MOUNT_STORAGE"
grep -Fq 'systemctl start seatd.service' "$RUNNER"
grep -Fq 'SOURCE_POWER' "$CONTROLS_SOURCE"
grep -Fq 'SOURCE_LID' "$CONTROLS_SOURCE"
if grep -Eq 'loginctl|org[.]freedesktop[.]login1|systemd-inhibit' \
	"$RUNNER" "$SUSPEND" "$CONTROLS_SOURCE"; then
	printf '%s\n' 'active fixed-device path regained a login1 consumer' >&2
	exit 1
fi

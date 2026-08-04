#!/bin/sh
# Called by the stock ROCKNIX initramfs after SYSTEM is mounted at /sysroot.
# Present its exact writable ext4 reference image at /storage, then expose the
# existing large exFAT library below it without changing either filesystem.

STORAGE_IMAGE=/birddata/MUOS/runtime/ROCKNIX-STORAGE
mount_part "$STORAGE_IMAGE" /storage "loop,rw,noatime" || {
	error bird-storage-loop "Could not mount exact ROCKNIX storage image"
	return 1
}

# The H700's retained policy is fake suspend: CPU0 keeps running Bird while the
# provider parks CPU1--CPU3. Establish that authority before final-root systemd
# can consume power/lid events. The late generic 009-sleepmode job has been
# observed rewriting this card back to unsupported real `mem` suspend after the
# H700 policy ran. The generic writers are suppressed below; common/009 becomes
# a fixed post-recovery verifier because retained common/001 may restore defaults.
SUSPEND_CONFIG=/storage/.config/system/configs/system.cfg
SUSPEND_SLEEP_CONFIG=/storage/.config/sleep.conf.d/sleep.conf
FIXED_SLEEP_CONFIG=/flash/bird/bird-sleep.conf
FIXED_SUSPEND_POLICY=/flash/bird/bird-suspend-policy.generated.sh
SYSTEM_BUSYBOX=/sysroot/usr/bin/busybox
RETROARCH_CONFIG_DIR=/storage/.config/retroarch
FIXED_RETROARCH_CONFIG_DIR=/sysroot/usr/config/retroarch
PARK_CORES_SETTING=
SUSPEND_MODE_SETTING=
FAKE_SUSPEND_SETTING=
TIMED_SHUTDOWN_SETTING=
PARK_CORES_COUNT=0
SUSPEND_MODE_COUNT=0
FAKE_SUSPEND_COUNT=0
TIMED_SHUTDOWN_COUNT=0
SUSPEND_CONFIG_REPAIR=0

# This generated fixed-device subset is verified by the release manifest and
# by the host build before it is copied to /flash. Keep the runtime shell free
# of a TSV parser while making the shipped policy derive from one authority.
[ -r "$FIXED_SUSPEND_POLICY" ] && . "$FIXED_SUSPEND_POLICY" || {
	error bird-suspend-policy "Generated fixed suspend policy is missing"
	return 1
}

if [ ! -r "$SUSPEND_CONFIG" ]; then
	error bird-suspend-policy "Fixed suspend configuration is missing"
	return 1
else
	while IFS= read -r CONFIG_LINE; do
		case "$CONFIG_LINE" in
			system.suspendmode=*)
				SUSPEND_MODE_COUNT=$((SUSPEND_MODE_COUNT + 1))
				SUSPEND_MODE_SETTING=${CONFIG_LINE#*=}
				;;
			system.suspend.enable=*)
				FAKE_SUSPEND_COUNT=$((FAKE_SUSPEND_COUNT + 1))
				FAKE_SUSPEND_SETTING=${CONFIG_LINE#*=}
				;;
			system.suspend.enable_timed_shutdown=*)
				TIMED_SHUTDOWN_COUNT=$((TIMED_SHUTDOWN_COUNT + 1))
				TIMED_SHUTDOWN_SETTING=${CONFIG_LINE#*=}
				;;
			system.suspend.park_cores=*)
				PARK_CORES_COUNT=$((PARK_CORES_COUNT + 1))
				PARK_CORES_SETTING=${CONFIG_LINE#*=}
				;;
		esac
	done <"$SUSPEND_CONFIG"
	[ "$SUSPEND_MODE_COUNT" -eq 1 ] &&
		[ "$SUSPEND_MODE_SETTING" = "$BIRD_SUSPEND_PROVIDER_MODE" ] ||
		SUSPEND_CONFIG_REPAIR=1
	[ "$FAKE_SUSPEND_COUNT" -eq 1 ] &&
		[ "$FAKE_SUSPEND_SETTING" = "$BIRD_SUSPEND_FAKE_ENABLED" ] ||
		SUSPEND_CONFIG_REPAIR=1
	[ "$TIMED_SHUTDOWN_COUNT" -eq 1 ] &&
		[ "$TIMED_SHUTDOWN_SETTING" = "$BIRD_SUSPEND_TIMED_SHUTDOWN_ENABLED" ] ||
		SUSPEND_CONFIG_REPAIR=1
	[ "$PARK_CORES_COUNT" -eq 1 ] &&
		[ "$PARK_CORES_SETTING" = "$BIRD_SUSPEND_CORE_PARKING_REQUIRED" ] ||
		SUSPEND_CONFIG_REPAIR=1
	if [ "$SUSPEND_CONFIG_REPAIR" -eq 1 ]; then
		SUSPEND_CONFIG_TEMP=$SUSPEND_CONFIG.bird-new
		"$SYSTEM_BUSYBOX" rm -f "$SUSPEND_CONFIG_TEMP"
		if "$SYSTEM_BUSYBOX" awk \
			-v mode="$BIRD_SUSPEND_PROVIDER_MODE" \
			-v fake="$BIRD_SUSPEND_FAKE_ENABLED" \
			-v timed="$BIRD_SUSPEND_TIMED_SHUTDOWN_ENABLED" \
			-v park="$BIRD_SUSPEND_CORE_PARKING_REQUIRED" '
			/^system\.suspendmode=/ { next }
			/^system\.suspend\.enable=/ { next }
			/^system\.suspend\.enable_timed_shutdown=/ { next }
			/^system\.suspend\.park_cores=/ { next }
			{ print }
			END {
				print "system.suspendmode=" mode
				print "system.suspend.enable=" fake
				print "system.suspend.enable_timed_shutdown=" timed
				print "system.suspend.park_cores=" park
			}' "$SUSPEND_CONFIG" >"$SUSPEND_CONFIG_TEMP" &&
			"$SYSTEM_BUSYBOX" chmod 0644 "$SUSPEND_CONFIG_TEMP" &&
			"$SYSTEM_BUSYBOX" mv -f "$SUSPEND_CONFIG_TEMP" "$SUSPEND_CONFIG"; then
			:
		else
			"$SYSTEM_BUSYBOX" rm -f "$SUSPEND_CONFIG_TEMP"
			return 1
		fi
	fi
fi

mkdir -p "${SUSPEND_SLEEP_CONFIG%/*}"
for FIXED_POLICY in "$FIXED_SLEEP_CONFIG:$SUSPEND_SLEEP_CONFIG"; do
	POLICY_SOURCE=${FIXED_POLICY%%:*}
	POLICY_TARGET=${FIXED_POLICY#*:}
	POLICY_TEMP=$POLICY_TARGET.bird-new
	POLICY_MODE=
	if "$SYSTEM_BUSYBOX" cmp -s "$POLICY_SOURCE" "$POLICY_TARGET"; then
		# The exact BusyBox stat -t record is: path, bytes, blocks, hex mode,
		# followed by ownership/device fields. 0x81a4 is a regular 0644 file.
		POLICY_MODE=$("$SYSTEM_BUSYBOX" stat -t "$POLICY_TARGET" 2>/dev/null ||
			printf '')
		POLICY_MODE=${POLICY_MODE#* }
		POLICY_MODE=${POLICY_MODE#* }
		POLICY_MODE=${POLICY_MODE#* }
		POLICY_MODE=${POLICY_MODE%% *}
	fi
	if [ "$POLICY_MODE" = 81a4 ]; then
		:
	else
		"$SYSTEM_BUSYBOX" rm -f "$POLICY_TEMP" || return 1
		"$SYSTEM_BUSYBOX" cp -f "$POLICY_SOURCE" "$POLICY_TEMP" &&
			"$SYSTEM_BUSYBOX" chmod 0644 "$POLICY_TEMP" &&
			"$SYSTEM_BUSYBOX" mv -f "$POLICY_TEMP" "$POLICY_TARGET" || {
				"$SYSTEM_BUSYBOX" rm -f "$POLICY_TEMP"
				return 1
			}
	fi
done

# common/001-setup invokes a broad stock-config recovery when either of these
# application prerequisites is absent. Seed only the missing file now, after
# Bird is already usable but before systemd, so that recovery cannot overwrite
# Bird-owned system or sleep policy during the interactive session.
mkdir -p "$RETROARCH_CONFIG_DIR"
for RETROARCH_CONFIG in retroarch-core-options.cfg retroarch.cfg; do
	RETROARCH_SOURCE=$FIXED_RETROARCH_CONFIG_DIR/$RETROARCH_CONFIG
	RETROARCH_TARGET=$RETROARCH_CONFIG_DIR/$RETROARCH_CONFIG
	if [ ! -s "$RETROARCH_TARGET" ]; then
		RETROARCH_TEMP=$RETROARCH_TARGET.bird-new
		[ -s "$RETROARCH_SOURCE" ] || return 1
		"$SYSTEM_BUSYBOX" rm -f "$RETROARCH_TEMP" || return 1
		"$SYSTEM_BUSYBOX" cp -f "$RETROARCH_SOURCE" "$RETROARCH_TEMP" &&
			"$SYSTEM_BUSYBOX" chmod 0644 "$RETROARCH_TEMP" &&
			"$SYSTEM_BUSYBOX" mv -f "$RETROARCH_TEMP" "$RETROARCH_TARGET" || {
				"$SYSTEM_BUSYBOX" rm -f "$RETROARCH_TEMP"
				return 1
			}
	fi
done

# systemd merges every direct *.conf child in these persistent drop-in
# directories. Close the fixed-device policy boundary before PID 1 starts:
# keeping a second drop-in would let lexicographic ordering silently restore
# real suspend even though Bird's canonical file is correct. Logind is masked,
# so its old writable policy is inert and is not compared, copied or cleaned.
# Remove only competing sleep *.conf entries; README and other non-policy
# artifacts remain untouched. A directory or otherwise unremovable entry fails
# the boot transaction instead of allowing ambiguous policy.
for FIXED_POLICY in \
	"${SUSPEND_SLEEP_CONFIG%/*}:$SUSPEND_SLEEP_CONFIG"; do
	POLICY_DIRECTORY=${FIXED_POLICY%%:*}
	POLICY_TARGET=${FIXED_POLICY#*:}
	for POLICY_ENTRY in "$POLICY_DIRECTORY"/*.conf; do
		[ "$POLICY_ENTRY" = "$POLICY_TARGET" ] && continue
		if [ -e "$POLICY_ENTRY" ] || [ -L "$POLICY_ENTRY" ]; then
			"$SYSTEM_BUSYBOX" rm -f "$POLICY_ENTRY" || return 1
		fi
	done
done

# Keep the owning p6 mount outside the loop filesystem that its image backs.
# Only a bind alias lives below /storage, so shutdown can unmount the aliases,
# then the loop, then p6 without a mount/backing-filesystem dependency cycle.
NAMESPACE_RECORD=/birddata/Bird/namespace-v1.tsv
[ -r "$NAMESPACE_RECORD" ] &&
	[ "$(wc -l <"$NAMESPACE_RECORD")" -eq 2 ] &&
	grep -Fqx 'revision	bird-canonical-namespace-v1' "$NAMESPACE_RECORD" &&
	grep -Fqx 'state	committed' "$NAMESPACE_RECORD" || {
	error bird-namespace "Canonical namespace transaction is absent or ambiguous"
	return 1
}
mkdir -p /run/bird-data /storage/bird-data /storage/roms /storage/media
mount --move /birddata /run/bird-data || {
	error bird-data-move "Could not move large Bird data volume to its final mount"
	return 1
}
mount --bind /run/bird-data /storage/bird-data || {
	error bird-data-bind "Could not publish the large Bird data volume"
	return 1
}
mount --bind /storage/bird-data/ROMS /storage/roms || {
	error bird-rom-bind "Could not publish the Bird ROM library"
	return 1
}
mount --bind /storage/bird-data/MEDIA /storage/media || {
	error bird-media-bind "Could not publish the Bird media library"
	return 1
}

# The selected release is verified before /flash/bird is published and remains
# mounted for the complete final-root session. Immutable Bird executables and
# provider data run directly from that release. Keep only ROCKNIX's writable
# memory-manager policy in its established storage namespace.
cp -f /flash/bird/bird-swap.conf /storage/.config/swap.conf || return 1

# The exact initramfs BusyBox has no chmod applet. Use the already-mounted
# pinned final-root BusyBox to normalize only that mutable data file.
/sysroot/usr/bin/busybox chmod 0644 \
	/storage/.config/swap.conf || return 1

# Verify the remaining mutable capability after the mode transaction.
[ -f /storage/.config/swap.conf ] && \
	[ -r /storage/.config/swap.conf ] || return 1

# Replace the generic partition scanner with this device's fixed storage view.
# Its original service name preserves ROCKNIX's ordering contract while doing
# no probing and no launcher work.
mount --bind /flash/bird/rocknix-automount.service \
	/sysroot/usr/lib/systemd/system/rocknix-automount.service || {
	error bird-fixed-storage-service "Could not install fixed storage service"
	return 1
}

# Start the exact compatibility setup in parallel with Bird, but give it a
# private null console so late status text and `clear` cannot repaint the menu.
mount --bind /flash/bird/rocknix-autostart.service \
	/sysroot/usr/lib/systemd/system/rocknix-autostart.service || {
	error bird-background-autostart "Could not isolate compatibility autostart"
	return 1
}

# Replace the generic Bash/grep/evtest input graph with one fixed event
# process. The H700 gamepad remains ungrabbed; Bird and applications continue
# to read it directly while this process owns only system-global actions.
mount --bind /flash/bird/bird-fixed-controls.service \
	/sysroot/usr/lib/systemd/system/input.service || {
	error bird-fixed-controls "Could not replace generic input service"
	return 1
}

# Replace two-second battery polling with the fixed H700 policy plus kernel
# power-supply events. It never rewrites application performance policy after
# startup; one 40-second capacity safety timer exists only while discharging.
mount --bind /flash/bird/bird-powerstate.service \
	/sysroot/usr/lib/systemd/system/powerstate.service || {
	error bird-fixed-powerstate "Could not replace polling power service"
	return 1
}

# ROCKNIX's shutdown hook sources the full interactive profile and copies the
# same small config unconditionally. Keep the safety checkpoint with one exact
# compare/copy process instead.
mount --bind /flash/bird/bird-save-config.service \
	/sysroot/usr/lib/systemd/system/save-sysconfig.service || {
	error bird-fixed-shutdown "Could not replace generic config checkpoint"
	return 1
}

# The fixed post-frame coordinator calls the proven H700/common responsibilities
# directly from immutable paths. No generic directory scan, no no-op script
# launch, and no per-script autostart bind replacement is needed here.

# The four network providers keep their exact implementations but their boot
# jobs are condition-gated. Bird raises the request only around PortMaster.
for UNIT in NetworkManager.service iwd.service systemd-resolved.service \
	systemd-timesyncd.service; do
	mount --bind "/flash/bird/$UNIT" \
		"/sysroot/usr/lib/systemd/system/$UNIT" || {
		error bird-network-gate "Could not gate $UNIT"
		return 1
	}
done
mount --bind /flash/bird/systemd-rfkill.service \
	/sysroot/usr/lib/systemd/system/systemd-rfkill.service || {
	error bird-network-gate "Could not gate systemd-rfkill.service"
	return 1
}

# Reuse the release's dormant statistics-service slot for a requested,
# event-ordered diagnostic snapshot. Ordinary boots do not run the probe set;
# its periodic timer is masked below.
mount --bind /flash/bird/rocknix-report-stats.service \
	/sysroot/usr/lib/systemd/system/rocknix-report-stats.service || {
	error bird-boot-snapshot "Could not install post-frame snapshot service"
	return 1
}
# The accepted image already journals to /run. Make that bounded volatile
# contract explicit, then remove the empty persistent flush/catalog jobs.
# Journald itself remains active for recovery evidence.
mount --bind /flash/bird/bird-journald.conf \
	/sysroot/etc/systemd/journald.conf || {
	error bird-journal-policy "Could not install volatile journal policy"
	return 1
}

# Replace only the UI implementation after storage. All other ROCKNIX targets,
# platform quirks and application launch machinery remain.
mount --bind /flash/bird/essway.service \
	/sysroot/usr/lib/systemd/system/essway.service || {
	error bird-ui-service "Could not install Bird UI service"
	return 1
}
mount --bind /flash/bird/rocknix.target \
	/sysroot/usr/lib/systemd/system/rocknix.target || {
	error bird-target-timeout "Could not install guarded ROCKNIX target"
	return 1
}

# These units serve features absent from this one-user hardware profile. Mask
# their immutable definitions before systemd starts; no shell or resident
# compatibility daemon is needed to keep them stopped. Bird's direct control
# process owns lid/power and its retained fake-suspend provider never calls
# login1; Sway explicitly joins seatd. The writable roots cleaned by the daily
# tmpfiles timer are fresh tmpfs on every boot, so its 15-minute/daily wake has
# no persistent fixed-device work. UTMP boot/runlevel records likewise live
# only in volatile `/var`; Bird's durable boot/shutdown evidence is separate.
for UNIT in \
	debug-shell.service \
	show-version.service \
	rpcbind.service \
	rpcbind.socket \
	sshd.service \
	wsdd2.service \
	entware.service \
	touchkeyboard.service \
	sway-touch.service \
	hdmi-hotplug.path \
	video.service \
	sixaxis@.service \
	systemd-rfkill.socket \
	systemd-journal-flush.service \
	systemd-journal-catalog-update.service \
	systemd-logind.service \
	systemd-tmpfiles-clean.timer \
	systemd-update-utmp.service \
	systemd-update-utmp-runlevel.service \
	rocknix-report-stats.timer; do
	mount --bind /dev/null "/sysroot/usr/lib/systemd/system/$UNIT" || {
		error bird-unused-unit "Could not mask $UNIT"
		return 1
	}
done

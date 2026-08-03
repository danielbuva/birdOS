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
SUSPEND_LOGIND_CONFIG=/storage/.config/logind.conf.d/login.conf
FIXED_SLEEP_CONFIG=/flash/bird/bird-sleep.conf
FIXED_LOGIND_CONFIG=/flash/bird/bird-logind.conf
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

mkdir -p "${SUSPEND_SLEEP_CONFIG%/*}" "${SUSPEND_LOGIND_CONFIG%/*}"
for FIXED_POLICY in \
	"$FIXED_SLEEP_CONFIG:$SUSPEND_SLEEP_CONFIG" \
	"$FIXED_LOGIND_CONFIG:$SUSPEND_LOGIND_CONFIG"; do
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
# Bird-owned system, sleep, or logind policy during the interactive session.
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
# real suspend or logind input ownership even though Bird's canonical file is
# correct. Remove only competing *.conf entries; README and other non-policy
# artifacts remain untouched. A directory or otherwise unremovable entry fails
# the boot transaction instead of allowing ambiguous policy.
for FIXED_POLICY in \
	"${SUSPEND_SLEEP_CONFIG%/*}:$SUSPEND_SLEEP_CONFIG" \
	"${SUSPEND_LOGIND_CONFIG%/*}:$SUSPEND_LOGIND_CONFIG"; do
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
mkdir -p /run/bird-data /storage/bird-data /storage/roms /storage/.config/bird
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
mkdir -p /storage/roms/bios
mount --bind /storage/bird-data/MUOS/bios /storage/roms/bios || {
	error bird-bios-bind "Could not publish the existing BIOS library"
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

# These generic jobs either duplicate fixed Bird ownership or configure
# hardware/features absent from this one-user RG34XX-SP profile. The remaining
# autostart sequence is unchanged for this physical gate.
for SCRIPT in 001-emulationstation 001-sync-modules 002-device-switch \
	003-upgrade 006-display 007-rootpw 009-bluetooth 010-moonlight \
	010-uimode 020-configs 020-set_audio_latency 055-hdmi-check \
	080-dual_screen_mode 080-network 081-usbgadget 098-deviceutils \
	099-networkservices; do
	mount --bind /flash/bird/bird-autostart-noop \
		"/sysroot/usr/lib/autostart/common/$SCRIPT" || {
		error bird-fixed-autostart "Could not suppress $SCRIPT"
		return 1
	}
done

# common/001-setup is retained for its configuration-recovery contract. If an
# unrelated RetroArch file is absent, its chksysconfig transaction restores the
# complete stock /usr/config tree and can overwrite the pre-systemd suspend
# policy. Replace the immediately following common/009 hook with one fixed,
# manifest-verified repair. On ordinary boots the requested mode already
# matches, so ROCKNIX's suspendmode helper performs no write or logind restart.
mount --bind /flash/bird/bird-restore-suspend-policy.sh \
	/sysroot/usr/lib/autostart/common/009-sleepmode || {
	error bird-suspend-policy "Could not install post-recovery suspend policy"
	return 1
}

# The pinned STORAGE already contains the release-matched 54-file module tree,
# the EmulationStation compatibility link and no applicable platform/device
# config overlay. Avoid re-copying 548 KiB or forking a known-empty rsync job.

# Seven H700 scripts only rewrite immutable profile constants. Publish those
# constants once and replace the remaining writers with the common no-op.
mount --bind /flash/bird/bird-fixed-platform.sh \
	/sysroot/usr/lib/autostart/quirks/platforms/H700/001-device_config || {
	error bird-fixed-platform "Could not install fixed H700 profile"
	return 1
}
for SCRIPT in 002-turbo-mode_config 010-governors 010-led_control \
	020-fan_control 030-analog_leds 030-suspend_mode 050-modifiers 091-ui_shader; do
	mount --bind /flash/bird/bird-autostart-noop \
		"/sysroot/usr/lib/autostart/quirks/platforms/H700/$SCRIPT" || {
		error bird-fixed-platform "Could not suppress H700 $SCRIPT"
		return 1
	}
done

# Replace the 11.5 KiB multi-product DRM/EDID generator with the already-proven
# card1/DSI-1 contract. It does not touch essway.service, so Bird ownership is
# not restarted while the menu is live.
mount --bind /flash/bird/bird-fixed-sway.sh \
	/sysroot/usr/lib/autostart/common/111-sway-init || {
	error bird-fixed-sway "Could not install fixed internal-panel profile"
	return 1
}

# H700 repeats the same mismatched latency read/write as the common script.
# The pinned writable image already contains the required global value of 64.
mount --bind /flash/bird/bird-autostart-noop \
	/sysroot/usr/lib/autostart/quirks/platforms/H700/020-set_audio_latency || {
	error bird-fixed-audio-latency "Could not suppress duplicate latency write"
	return 1
}

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

# Reuse the release's dormant statistics-service slot for one event-ordered
# diagnostic snapshot. Its periodic timer is masked below.
mount --bind /flash/bird/rocknix-report-stats.service \
	/sysroot/usr/lib/systemd/system/rocknix-report-stats.service || {
	error bird-boot-snapshot "Could not install post-frame snapshot service"
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
# compatibility daemon is needed to keep them stopped.
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
	rocknix-report-stats.timer; do
	mount --bind /dev/null "/sysroot/usr/lib/systemd/system/$UNIT" || {
		error bird-unused-unit "Could not mask $UNIT"
		return 1
	}
done
mount --bind /flash/bird/090-ui_service \
	/sysroot/usr/lib/autostart/quirks/platforms/H700/090-ui_service || {
	error bird-ui-selection "Could not select Bird as the only boot UI"
	return 1
}
mount --bind /flash/bird/999-export \
	/sysroot/usr/lib/autostart/common/999-export || {
	error bird-application-ready "Could not install Bird application milestone"
	return 1
}

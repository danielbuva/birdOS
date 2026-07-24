#!/bin/sh
# Called by the stock ROCKNIX initramfs after SYSTEM is mounted at /sysroot.
# Present its exact writable ext4 reference image at /storage, then expose the
# existing large exFAT library below it without changing either filesystem.

STORAGE_IMAGE=/birddata/MUOS/runtime/ROCKNIX-STORAGE
mount_part "$STORAGE_IMAGE" /storage "loop,rw,noatime" || {
	error bird-storage-loop "Could not mount exact ROCKNIX storage image"
	return 1
}

mkdir -p /storage/bird-data /storage/roms /storage/.config/bird
mount --move /birddata /storage/bird-data || {
	error bird-data-move "Could not attach large Bird data volume"
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

# These are deliberately copied after /storage exists. Bird is a normal
# userspace UI service in this compatibility milestone, not initramfs payload.
for FILE in dani-launcher bird-pidwait bird-fixed-controls bird-powerstate \
	bird-fixed-control-exit.sh bird-save-config.sh supervisor.sh run-content.sh prepare-ports.sh \
	fixed-storage.sh first-frame-prep.sh capture-boot-state.sh \
	bird-network.sh; do
	cp -f "/flash/bird/$FILE" "/storage/.config/bird/$FILE" || return 1
done
cp -f /flash/bird/bird-swap.conf /storage/.config/swap.conf || return 1
chmod 0755 /storage/.config/bird/dani-launcher \
	/storage/.config/bird/bird-pidwait \
	/storage/.config/bird/bird-fixed-controls \
	/storage/.config/bird/bird-powerstate \
	/storage/.config/bird/bird-fixed-control-exit.sh \
	/storage/.config/bird/bird-save-config.sh \
	/storage/.config/bird/supervisor.sh \
	/storage/.config/bird/run-content.sh \
	/storage/.config/bird/prepare-ports.sh \
	/storage/.config/bird/fixed-storage.sh \
	/storage/.config/bird/first-frame-prep.sh \
	/storage/.config/bird/capture-boot-state.sh \
	/storage/.config/bird/bird-network.sh

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
for SCRIPT in 003-upgrade 006-display 007-rootpw 009-bluetooth 010-moonlight \
	010-uimode 020-set_audio_latency 055-hdmi-check 080-dual_screen_mode \
	080-network 081-usbgadget 098-deviceutils 099-networkservices; do
	mount --bind /flash/bird/bird-autostart-noop \
		"/sysroot/usr/lib/autostart/common/$SCRIPT" || {
		error bird-fixed-autostart "Could not suppress $SCRIPT"
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

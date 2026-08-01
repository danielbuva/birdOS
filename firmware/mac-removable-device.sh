#!/bin/sh
# Shared whole-device safety check for raw RG34XX-SP card operations.

bird_require_safe_removable_device() {
	BIRD_DEVICE=$1
	BIRD_INTERNAL=$(plist_value "$BIRD_DEVICE" Internal)
	BIRD_REMOVABLE=$(plist_value "$BIRD_DEVICE" Removable)

	[ "$BIRD_REMOVABLE" = true ] || fail 'refusing non-removable media'
	if [ "$BIRD_INTERNAL" = false ]; then
		return 0
	fi

	# macOS reports cards in Apple's built-in SDXC reader as Internal=true
	# even though the media itself is removable.  Accept only that exact,
	# independently constrained physical-device classification.  Callers
	# still verify the complete card size and fixed p5/p6 partition geometry.
	[ "$BIRD_INTERNAL" = true ] || fail 'unexpected internal-media value'
	[ "$(plist_value "$BIRD_DEVICE" OSInternalMedia)" = false ] ||
		fail 'refusing OS-internal media'
	[ "$(plist_value "$BIRD_DEVICE" BusProtocol)" = 'Secure Digital' ] ||
		fail 'internal device is not Secure Digital media'
	[ "$(plist_value "$BIRD_DEVICE" MediaName)" = 'Built In SDXC Reader' ] ||
		fail 'unexpected internal SD media identity'
	[ "$(plist_value "$BIRD_DEVICE" VirtualOrPhysical)" = 'Physical' ] ||
		fail 'refusing a virtual device'
	[ "$(plist_value "$BIRD_DEVICE" WholeDisk)" = true ] ||
		fail 'device is not a whole disk'
}

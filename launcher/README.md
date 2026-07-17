# Direct-framebuffer launcher proof

`dani-launcher.c` is an intentionally freestanding AArch64 Linux program. It
uses direct kernel syscalls and has no libc or dynamic-library dependencies.
The macOS build produces a relocatable object; the RG34XX-SP's own GNU linker
creates the final static executable during user-init.

The first staged run is deliberately late and temporary:

1. Stock muOS reaches its normal screen.
2. The proof stops stock after three seconds.
3. The proof draws its own 720x480 menu and opens evdev devices directly.
4. D-pad changes the selection, A displays the selected label and B exits.
5. A 15-second timeout exits even if the input mapping needs adjustment.
6. Stock muOS restarts automatically.

Results are written to `/mnt/mmc/MUOS/bespoke-launcher/proof-v1.log`. A
successful run gives the exact framebuffer format, stride, input device names,
first-frame uptime and exit reason needed for the early-boot version.

# Fixed-device optional emulator payloads

These are official MustardOS packages retained as source archives. User-init
extracts only the components used by the RG34XX-SP launcher.

## Nintendo DS

- Source: <https://github.com/MustardOS/extra/releases/download/release-20260712-040338/Extra.-.Nintendo.DS.muxzip>
- SHA-256: `1d9852f709342ab03a886b8f7f10f6690c93e4271de81bf4125bba1efa3a23fe`
- The `drastic-trngaje` files have been unchanged in the official source tree
  since November 17, 2025, so they predate and match the 2601.1 image.
- Installed: DraStic executable, RG libraries, 720x480 layout, English-default
  resources, controls, database, microphone data and cheats.
- Omitted: legacy DraStic, three unused libretro cores, TrimUI libraries,
  non-English language files, non-RG display layouts, assignments and docs.

## OpenBOR

- Source: <https://github.com/MustardOS/extra/releases/download/release-20260712-040338/Extra.-.OpenBOR.muxzip>
- SHA-256: `d01ae049e3e1a303668548ae6a2d51787c667009664780b7cc6aeb364b9d6595`
- The selected files are byte-identical to the November 7, 2025 package.
- Installed: OpenBOR 7530, its muOS launch wrapper and its control installer.
- Omitted: OpenBOR 4432, 6412 and 7142 plus generic assignment metadata.

The content revision covers both source archives and the extraction policy.
Changing either causes a one-time reinstall during user-init; normal boots do
not open or inspect these archives.

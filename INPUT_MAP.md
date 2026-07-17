# RG34XX-SP logical input reference

These values were observed in another operating system's built-in input test.
They are a logical additive bitmask reference, not yet assumed to be muOS's
Linux evdev or joystick event numbers.

## Digital controls

| Control | Mask |
| --- | ---: |
| D-pad up | `0x1` |
| D-pad down | `0x2` |
| D-pad left | `0x4` |
| D-pad right | `0x8` |
| A | `0x10` |
| B | `0x20` |
| Y | `0x40` |
| X | `0x80` |
| Start | `0x100` |
| Select | `0x200` |
| L1 | `0x400` |
| R1 | `0x800` |
| L2 | `0x1000` |
| R2 | `0x2000` |
| Volume up | `0x4000` |
| Volume down | `0x8000` |
| L3 | `0x20000` |
| R3 | `0x40000` |
| Menu | `0x100000` |

Confirmed D-pad combinations:

| Combination | Mask |
| --- | ---: |
| Up + right | `0x9` |
| Up + left | `0x5` |
| Down + left | `0x6` |
| Down + right | `0xA` |

## Stick-direction fields

The other OS reports the left-stick direction field with the D-pad-style
nibble: up `0x1`, down `0x2`, left `0x4`, right `0x8`; diagonals are `0x9`,
`0x5`, `0x6`, and `0xA`.

The right-stick direction field is: up `0x80`, down `0x20`, left `0x40`, right
`0x10`; diagonals are `0x90`, `0xC0`, `0x60`, and `0x30`.

Because these stick values overlap button bits, they must be separate fields
in that OS's input-test structure rather than one global mask. The muOS
calibration will map the actual `/dev/input/js*` axis and button numbers to the
same named controls.

## Confirmed muOS kernel mapping

The v3 launcher capture identified `/dev/input/event1` and `/dev/input/js0` as
the same `muOS-Keys` device. These values are now safe to compile directly into
the launcher:

| Control | evdev event | Linux joystick event |
| --- | --- | --- |
| Up | `EV_ABS`, code `17`, value `-1` | axis `5`, value `-32767` |
| Down | `EV_ABS`, code `17`, value `1` | axis `5`, value `32767` |
| Left | `EV_ABS`, code `16`, value `-1` | axis `4`, value `-32767` |
| Right | `EV_ABS`, code `16`, value `1` | axis `4`, value `32767` |
| A | `EV_KEY`, code `304` | button `0` |
| B | `EV_KEY`, code `305` | button `1` |
| X | `EV_KEY`, code `307` | button `3` |
| Y | `EV_KEY`, code `306` | button `2` |

The fixed launcher will use evdev directly. The joystick mapping remains useful
for validating emulator and SDL compatibility.

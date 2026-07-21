# RG34XX-SP fixed-device kernel profile

Baseline capture: boot `05b41194-0e95-42f3-a618-606f4a3c5286`, collected
2026-07-21 from the accepted direct-handoff image.

Pinned artifacts live under
`kernel/baseline/live/05b41194-0e95-42f3-a618-606f4a3c5286/`. The running DTB
SHA-256 is
`2a39a2473686c09ea03fea9ba55318d0b4af7ff14cf4261b898b243e08b2743b`.
It identifies the board as `allwinner,h616` / `arm,sun50iw9p1`, the panel as
`rg34xxsp_v1`, the PMIC as AXP2202 and the external RTC as PCF8563.

## Measured pre-init timeline

| Kernel time | Event | Fixed-device implication |
| ---: | --- | --- |
| 0.531 s | Display initialization begins | Required |
| 0.580 s | Display initialization finishes | The screen is ready long before userspace |
| 0.582–0.715 s | AXP2202 PMIC initializes | Required for power, battery and regulators |
| 0.716–0.722 s | Unused video-input/camera stack probes | Remove |
| 0.815–0.911 s | Trimmed initramfs is unpacked | Already reduced to about 95 ms |
| 0.949 s | Unused deinterlacer probes | Remove |
| 0.976–0.991 s | Bluetooth/WLAN platform discovery | Disable Bluetooth; retain WLAN for on-demand network |
| 0.995–1.310 s | Three EHCI and three OHCI host controllers initialize serially | Remove unused host ports; retain USB controller 0 |
| 1.414–1.527 s | Main SD card initializes and partitions appear | Required |
| 1.477–1.535 s | Empty second SD controller probes | Remove for the one-card device profile |
| 1.534–1.648 s | Wi-Fi SDIO controller probes and times out with radio off | Rebuild as a deferred/on-demand path later |
| 1.665–1.674 s | Unused HDMI/CEC stack initializes | Remove |
| 1.737–1.738 s | Fixed controls become available | Required |
| 1.792 s | PCF8563 supplies system time | Retain until a deliberate RTC policy replaces it |
| 1.794–1.827 s | Internal and unused HDMI audio cards register | Retain internal codec; remove HDMI audio |
| 1.829 s | Kernel frees init memory and may finally run `/init` | Current pre-userspace floor |
| 1.980 s | Launcher records input-ready frame | Accepted internal interactive baseline |
| 3.214–3.240 s | Mali module loads after the menu | Correctly outside first-frame dependency path |
| 3.987 s | CRNG becomes ready | Correctly outside first-frame dependency path |
| 4.063 s | exFAT ROM partition finishes mounting | Correctly outside first-frame dependency path |

Only one loadable module is active: `mali_kbase`. Everything else in the table
is built into the vendor kernel, which is why userspace service ordering cannot
remove its pre-`/init` cost.

## DTB v1 experiment

The first fixed-device candidate keeps the accepted kernel and initramfs
byte-for-byte unchanged. It disables exactly 20 device-tree nodes:

- USB host controllers 1–3: their `usbc`, EHCI and OHCI nodes;
- empty second SD slot (`sdc2`);
- HDMI display, HDMI codec, HDMI AHUB route and composite TV output;
- camera/video-input and deinterlacer;
- Bluetooth, Bluetooth low-power management and its dedicated UART1.

It deliberately retains:

- USB controller 0 and UDC for the USB-C device/charging path;
- `sdc0` for the single populated SD card;
- `sdc1` and WLAN so PortMaster/scraping can still request network later;
- LCD/display, PWM/backlight, GPIO/direct controls, power key, hall sensor;
- AXP2202 PMIC, battery/charging, thermal sensors and PCF8563 RTC;
- internal audio codec, Mali GPU, ext4 root and exFAT storage.

Candidate SHA-256:
`872a3d0d99ad6883942632f7adde9ffaa7c99eb922dca11f5efa2e89b8e7764f`.

Expected internal gain is approximately 0.2–0.35 seconds, mostly from removing
serial USB host initialization. A first-candidate-boot collector verifies which
probes actually disappeared; the device stopwatch remains the acceptance
measurement.

## Source-kernel removal queue

Once a source-complete kernel exists, the high-value removal/defer queue is:

1. Make Wi-Fi SDIO/radio initialization feature-triggered after the menu.
2. Remove unused USB host, USB network/storage/audio and alternate gamepad
   families from the image; retain only the chosen USB-C role if still wanted.
3. Remove HDMI/CEC, camera/VIN, deinterlace, NAND and alternate display paths.
4. Remove Bluetooth, PPP/PPTP, tunnels, IPv6, netfilter and unused network
   protocols; load the minimal Wi-Fi/IP closure only with a network feature.
5. Keep only ext4 and exFAT plus any filesystem proven necessary by a selected
   game or application.
6. Remove audit, profiling, generic debug and alternate-board machinery after
   the diagnostic phase ends.
7. Build in only first-frame hardware; make Mali, network and other optional
   feature closures explicit post-menu modules or fixed services.

The final kernel must still pass launcher input, games, video, audio, volume,
brightness, suspend/lid, power key, charging, shutdown and on-demand PortMaster
network acceptance.

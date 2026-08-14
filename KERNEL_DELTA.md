# What the birdOS kernel offers

birdOS uses a kernel tailored for one machine: the Anbernic RG34XX-SP. It keeps
ROCKNIX's broad game and application compatibility, then removes delay and
repeated work where the fixed hardware lets us be exact.

## Controls are ready earlier

The RG34XX-SP gamepad driver is part of the kernel itself. Stock ROCKNIX loads
the same driver later as a separate module. Building it in gives birdOS one
less boot-time file and loading step while keeping the same `H700 Gamepad`
identity expected by games and applications.

birdOS retains the complete control set:

- D-pad, A/B/X/Y, Menu, Start and Select;
- shoulders and triggers;
- both analog sticks and all four axes;
- built-in vibration and rumble; and
- reconnect behavior used when returning from games and applications.

## Input uses less repeated work

The stock gamepad code read every GPIO button twice in immediate succession:
once to detect a read error and again to obtain the value. birdOS reads it once
and safely uses that result for both purposes.

Stock code also published the stick state and button state as two separate
input frames every 10 milliseconds. birdOS publishes stick changes as one
coherent frame and does not publish an empty frame when every value is
unchanged. The 17 digital controls—including L3/R3—now use independent GPIO
edge interrupts with 5 ms per-key debounce. Only the four analog axes retain
the 10 ms ADC sampling interval.

The practical goal is responsive controls during use and less needless input
work between actions—not slower polling or missing controls.

## ROCKNIX compatibility stays intact

birdOS is based on the pinned ROCKNIX 20260701 Linux 7.0.11 source and retains
its full source-built module set. The RG34XX-SP device tree remains
byte-identical to stock. The input changes do not remove suspend, display,
audio, storage, networking, HDMI, Bluetooth, performance controls or rumble.

CPU, GPU and turbo controls remain available within RG34XX-SP-supported ranges
for a future birdOS performance interface. HDMI and Bluetooth remain available
until a separate product decision is made.

## Reproducible and hardware-tested

Every birdOS kernel candidate is built twice in isolated, pinned environments
and must produce byte-identical kernels, modules and device trees. The complete
release is then tested on the RG34XX-SP before becoming the accepted kernel.

The currently accepted kernel shipped in release
`v6.23-20260811-234132` (kernel SHA-256
`cad7ad8437d0a7de0d819846b12fdf83078f5878313704d0de79274431ec9d64`). Broad
hardware testing passed, including every digital button, L3/R3, both sticks,
rumble, games, media, suspend, shutdown and application return. Input Test
recorded all 29 checks: 17 gamepad buttons, three auxiliary buttons, eight
analog directions and rumble. This proves the IRQ-backed control path is
functional; it is not a calibrated latency or energy measurement.

Exact source commits, artifact hashes and experimental authority records remain
available under `kernel/rocknix/` for reproducibility without turning this
overview into a development log.

## Next improvements

The IRQ control path is accepted functionally. A later measurement pass may
compare event timestamps and power draw against the former polling kernel; no
latency or battery improvement is claimed from functional testing alone.

Future fixed-device work will investigate:

- measured kernel feature subtraction after every consumer is closed;
- bootloader timing attribution and fixed-device path reduction without
  sacrificing honest menu readiness; and
- the deferred green-at-power question only if a later hardware finding makes
  its owner obvious. The reviewed U-Boot color change did not remove the
  observed red-to-green startup and is not an active gate.

Each remains a separate measured candidate. birdOS does not claim a power or
latency improvement until the corresponding RG34XX-SP test supports it.

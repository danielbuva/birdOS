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
input frames every 10 milliseconds. birdOS publishes them together as one
coherent frame, and does not publish an empty frame when every value is
unchanged. This removes unnecessary input-core work while keeping the same
sampling interval and every physical control read.

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
`v6.23-20260811-220044` (kernel SHA-256
`e112527fac5790b4dfee8a5381224ff15dffc84a16e64202c46c981335b3b549`). Broad
hardware testing passed, including buttons, both sticks, games, media, suspend,
shutdown and application return. It uses direct fixed H700 GPIO reads for
digital controls, emits one initial input frame on open/reconnect, and stops
publishing empty frames when every accepted control value is unchanged.
Stopwatch boot timing remained below three seconds.

Exact source commits, artifact hashes and experimental authority records remain
available under `kernel/rocknix/` for reproducibility without turning this
overview into a development log.

## Next improvements

The next candidate moves the 17 digital controls—including L3/R3—to the H700
GPIO controller's edge interrupts with independent 5 ms debounce. The four
analog-stick axes remain polled every 10 ms because they are ADC values, not
GPIO events. It retains one `H700 Gamepad` identity, rumble, reconnect and the
stock device tree. This should remove repeated idle digital GPIO reads and can
shorten button recognition, but neither latency nor battery improvement is
claimed until the RG34XX-SP test.

Future fixed-device work will investigate:

- whether any stick or button polling can safely become interrupt-driven;
- kernel-owned panel readiness and exact brightness restoration;
- a green, low-power boot LED policy;
- measured kernel feature subtraction after every consumer is closed; and
- later bootloader optimization without sacrificing honest menu readiness.

Each remains a separate measured candidate. birdOS does not claim a power or
latency improvement until the corresponding RG34XX-SP test supports it.

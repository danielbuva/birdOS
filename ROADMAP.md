## Summary of the idea

You are turning muOS from a flexible general-purpose firmware into a **purpose-built RG34XXSP console OS** tuned for exactly one device, one language, one visual identity, one control layout and one game library.

Instead of discovering and configuring everything during every boot, the system should already know:

* RG34XXSP hardware and controls
* English-only text and font
* Fixed screen layout and wallpaper
* Fixed boot animation and sound
* Exact ROM locations
* Exact emulator/core for each game
* The menu page shown at startup
* Which services are actually necessary

The target experience is:

```text
Power button
→ immediate LED/display response
→ lightweight animation and sound
→ usable text menu within a few seconds
→ cached game collection appears
→ storage finishes mounting asynchronously
→ games become launchable
```

The long-term centerpiece would be a tiny custom launcher—ideally a small statically linked program—that replaces the heavier general-purpose frontend while retaining muOS underneath for hardware support, emulator launching, PortMaster, power controls and other useful infrastructure.

## Current implementation status

- [x] Preserve the working system, Git history, diagnostics and stopwatch baseline.
- [x] Define the fixed RG34XX-SP/English/offline-at-boot experience.
- [x] Build a freestanding static launcher with direct framebuffer rendering.
- [x] Start at the earliest proven point using direct evdev input before udev.
- [x] Prove the embedded game catalogue and asynchronous ROM readiness.
- [x] Add fixed SNES/PSP/Port launch handoff and reliable direct return.
- [x] Replace daily PortMaster/network and shutdown stock-frontend paths.
- [ ] Prove persistent Favorites and recent-game state (staged next).
- [ ] Complete the final visual, animation and audio identity.
- [ ] Remove superseded muOS components and produce a reproducible firmware image.
- [ ] Optimize kernel and U-Boot last.

Verified interactive milestone: the current build entered at 2.307 seconds of
kernel uptime with input ready and drew its first frame at 2.326 seconds. LED-on
to an immediately usable menu is now consistently below four seconds by stopwatch.
All three emulator/Port paths are playable with audio and return to a redrawn
launcher in 27--29 ms.

## Priority list

### 1. Preserve the working system and measurements

Before changing architecture:

* Keep an untouched recovery card or full image.
* Put every modification in Git on your Mac.
* Record cold-boot stopwatch/video timings.
* Preserve internal timing markers.
* Document the current startup scripts and process tree.

You need a reliable baseline and one-command rollback before making boot-critical changes.

### 2. Define the exact finished experience

Write down what the device will always do:

* Always English
* Always RG34XXSP
* Always open to the main games menu
* One wallpaper and visual style
* One font
* One boot animation
* One boot sound
* Fixed controls
* Fixed systems and emulator mappings
* Whether Wi-Fi, Bluetooth and SSH should start automatically
* Whether Resume, Favorites, Games and Shutdown appear immediately

This lets you replace runtime configuration with fixed build-time decisions.

### 3. Build a tiny early-display proof of concept

Create the smallest possible program that can:

* Turn the display into a usable canvas
* Draw a solid background or wallpaper
* Render one embedded English bitmap font
* Show several text entries
* Draw a selection arrow
* Read D-pad and A/B
* Exit cleanly

Do this after normal boot first. Stop the existing frontend and run your test program manually over SSH.

Do not initially include storage, artwork, audio, animation or emulator launching.

### 4. Determine the earliest reliable launch point

Move the tiny program earlier through the boot sequence until it can start reliably as soon as:

* The display device exists
* The built-in controls exist
* The backlight is usable

Do not wait for all of `udev`, networking, storage bindings or other unrelated hardware. Wait only for the exact devices the early UI requires.

This establishes your true earliest interactive-menu time.

### 5. Create a cached game index

Stop scanning the ROM collection during boot.

Generate a compact catalog ahead of time containing:

```text
Display name
System
ROM path
Emulator/core
Favorite status
Optional artwork path
```

The launcher can display this cached catalog immediately. Storage mounting happens concurrently, and each game becomes launchable once its ROM path is available.

Regenerate the index only when the collection changes.

### 6. Add asynchronous storage readiness

Separate these two concepts:

```text
The collection can be browsed
The ROM can be launched
```

The catalog can appear immediately from cache, while a background process:

* Mounts storage
* Creates required bindings
* Verifies the expected paths
* Signals the launcher when games are available

The launcher should remain responsive throughout this process.

### 7. Replace the full frontend with the tiny launcher

Once the proof of concept can browse the catalog:

* Launch the correct emulator/core
* Hide or release the display
* Wait for the emulator to exit
* Restore the launcher
* Handle shutdown and reboot
* Optionally handle suspend or save-state shutdown

At this point it becomes the permanent shell rather than a temporary loading screen.

This is likely the largest remaining boot-time improvement.

### 8. Embed one lightweight font

Replace the multilingual font dependency chain with exactly what you use.

Best starting option:

* Embedded monochrome bitmap font
* ASCII plus any symbols you actually need
* Fixed supported sizes
* No runtime font discovery
* No shaping engine
* No unused language libraries

A bitmap font is extremely cheap to load and render. Later, you could use one small English TrueType font if you strongly prefer smoother text, but bitmap is ideal for the first fast build.

### 9. Embed and optimize the wallpaper

Convert the wallpaper ahead of time into the display’s preferred pixel format and dimensions.

Instead of:

```text
open PNG
→ parse PNG
→ decompress it
→ convert pixels
→ scale image
→ draw
```

use something closer to:

```text
map embedded image
→ copy pixels to display
```

A preconverted RGB565 or other native-format image uses more storage but substantially less startup processing. Since it is only one fixed wallpaper, that trade is sensible.

### 10. Add the boot animation efficiently

Avoid general-purpose video playback.

Use one of:

* Procedural animation
* Sprite sheet
* Small sequence of preconverted frames
* Palette animation
* Movement of text/logo elements

For example, a logo sliding or unfolding over the wallpaper can look polished while involving only a few memory copies.

The animation should never delay menu readiness. Once input is available, the user should be able to skip it or interact immediately.

### 11. Add low-overhead boot audio

Avoid initializing an elaborate audio stack solely for a startup sound.

Use:

* One short embedded PCM sample
* Correct target sample rate and format ahead of time
* Direct ALSA playback or the simplest available device interface
* Playback in parallel with animation and storage mounting

Do not decode MP3, Ogg or another compressed format during early boot unless storage size genuinely matters. A short raw PCM sound is larger but trivial to play.

The UI should not wait for audio hardware; sound begins whenever the audio device becomes ready.

### 12. Eliminate runtime questions and configuration parsing

Hardcode or compile in your permanent choices:

* Screen dimensions
* Device model
* Control mapping
* Language
* Font
* Wallpaper
* Menu structure
* Initial selection
* Emulator mappings
* Storage locations
* Default brightness behavior
* Theme measurements

Avoid repeatedly reading configuration files for values that never change.

Keep configuration files only for things you genuinely expect to adjust, such as brightness, volume, favorites and recent games.

### 13. Defer all nonessential services

Do not start these before the launcher is usable unless necessary:

* Wi-Fi
* Bluetooth
* SSH
* Samba
* Time synchronization
* Scraping
* Update checks
* Maintenance jobs
* Emulator verification
* Log cleanup
* Artwork processing

Start them:

* After first frame
* In the background
* On demand from the menu
* Only when enabled

The critical path should contain only display, input, launcher and required storage.

### 14. Replace fixed delays with readiness checks

Remove patterns such as:

```sh
sleep 1
sleep 2
```

Replace them with narrow bounded checks:

```text
Wait until exact display device exists
Wait until exact input device exists
Wait until exact mount is available
```

This prevents the fast case from waiting unnecessarily while still handling slower boots safely.

### 15. Minimize dynamic dependencies

Once the launcher works, inspect what it loads.

Aim for:

* One executable
* Few or no shared libraries
* Embedded font
* Embedded wallpaper
* Embedded animation assets
* Embedded startup sound
* Minimal libc and hardware interfaces

Static linking is useful here because it makes startup predictable, but the more important goal is reducing the amount of code and data loaded at all.

### 16. Optimize perceived response before chasing milliseconds

Make the device react immediately even when Linux is still working:

* LED turns on at the earliest possible point
* Backlight/display activates early
* Static wallpaper or splash appears before menu construction
* Animation begins while input and storage initialize
* Menu becomes interactive before animation ends
* Loading state is visible rather than a black screen

A system that visibly responds at two seconds and becomes fully ready at five will feel much faster than one that remains black for four seconds and finishes at the same time.

### 17. Profile launcher internals

Once the custom launcher exists, add timestamps around:

* Process entry
* Display open
* First pixel written
* First frame presented
* Input open
* First input accepted
* Catalog loaded
* Storage ready
* First game launch

Optimize measured bottlenecks rather than assumptions.

### 18. Simplify the remaining muOS userspace

After replacing the frontend, inspect what parts of muOS remain necessary:

* Hardware initialization
* Emulator launching
* Power management
* Volume and brightness controls
* Save handling
* PortMaster environment
* Networking utilities

Disable or remove components that exclusively supported the old frontend or configurations you no longer use.

### 19. Customize and rebuild the root filesystem

When installed-file experimentation stabilizes, create a reproducible custom OS image containing:

* Your launcher
* Your fixed assets
* Your game index
* Your scripts
* Only required libraries
* Your service configuration
* Your permanent device settings

This turns the project from “modified SD card” into a repeatable personal firmware build.

### 20. Touch kernel and U-Boot last

Only proceed here after userspace is highly optimized and measurements prove meaningful time remains below it.

Possible later work:

* Fixed U-Boot boot target
* Remove unnecessary device probing
* Earlier splash or LED control
* Smaller kernel configuration
* Remove unused drivers and filesystems
* Build essential drivers directly into the kernel
* Tune kernel compression
* Narrow device-tree configuration

These changes are higher risk and will likely save less time than replacing the frontend and critical userspace path.

## Best immediate sequence

Your next concrete milestones should be:

```text
1. [done] Draw wallpaper and text from a tiny executable
2. [done] Read the RG34XXSP controls
3. [done] Launch it automatically at the earliest safe point
4. [done] Load a cached game list
5. [done] Mount storage in parallel
6. [done] Launch games and return directly to the menu
7. [in progress] Replace muxfrontend's remaining daily-use paths
8. Add optimized animation and audio
9. Strip services and dependencies
10. Package the complete custom image
```

The philosophy is simple: **one device, one experience, no unnecessary decisions, no unnecessary work, and something useful on-screen as early as the hardware permits.**

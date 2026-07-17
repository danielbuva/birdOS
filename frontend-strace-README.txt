muOS one-boot frontend file-I/O trace
=====================================

Purpose
-------
The deferred boot-log copy now allows muxfrontend to execute at roughly
6.0-8.5 seconds, but the first line inside the executable remains fixed around
13.5-13.8 seconds. Before that line, the binary hashes 75 scripts and loads
hundreds of small device, configuration, and kiosk values.

This diagnostic records only executable, file, read, directory, and memory-map
system calls. It intentionally avoids high-frequency input/render calls.

Boot sequence
-------------
1. First boot after staging: user-init arms the trace for the next boot.
2. Second boot: diagnostic trace. Do not stopwatch this boot because strace adds
   overhead. Leave the device running for at least 50 seconds.
3. During the diagnostic boot, user-init restores the normal muxfrontend binary
   automatically. Every later boot is normal and keeps the existing optimized
   shell settings.

Output
------
MUOS/log/frontend-strace/muxfrontend-<boot-id>.strace

Safety
------
The original executable is backed up before replacement. restore.sh can recover
either the temporarily renamed executable or the ROM-side backup.

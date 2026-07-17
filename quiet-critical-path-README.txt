muOS quiet critical-path experiment
===================================

Evidence
--------
The one-boot trace showed that muxfrontend spends about 4.8 seconds in the
dynamic loader before script verification begins. It directly loads eight font
libraries, including roughly 30 MB of CJK font data. Script verification itself
took about 0.16 seconds and device/config parsing about 0.27 seconds.

At the same time, stock startup launches unrelated I/O-heavy work, including:
- recursive chown/chmod of root, OpenSSH, and SFTPGo trees;
- MD5 verification of RetroArch, PPSSPP, and ScummVM binaries every boot;
- log cleanup, catalogue generation, and dmesg persistence.

Change
------
These jobs are delayed by 20 seconds so they no longer compete with first UI.
Emulator verification is retained and cached against the OS build value; an OS
update causes it to run again automatically.

Boot sequence
-------------
1. First boot after staging installs the change and is not an optimized sample.
2. On later boots, collect at least three stopwatch samples. Leave the first
   optimized boot running for 45 seconds so the initial per-build emulator
   verification can finish and write its stamp.

Restore
-------
Place restore.sh in MUOS/init and boot once, or run it on-device. Both original
scripts are restored from their backups.

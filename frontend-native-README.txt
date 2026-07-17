muOS frontend native startup log capture
========================================

Purpose
-------
The February 2026 muxfrontend binary already emits messages with CLOCK_MONOTONIC
uptime values. This diagnostic captures those existing messages so theme,
display, audio, and launcher initialization can be compared with stopwatch time.

Boot sequence
-------------
1. First boot: user-init patches /opt/muos/script/mux/frontend.sh and backs up
   the previous script. This boot is an installer run and is not the sample.
2. Second boot: leave the device on for at least 35 seconds. The timestamped
   frontend log is copied to MUOS/log/frontend-native on the ROM partition.

Files
-----
backup/frontend.sh.pre-native-log   previous on-device frontend shell script
install.log                         installation result
collection.log                      successful captures
MUOS/log/frontend-native/           captured logs, one per Linux boot ID

Impact
------
Only stderr from the launcher invocation is redirected to /tmp. No strace or
debugger is used in this stage. The frontend executable itself is unchanged.

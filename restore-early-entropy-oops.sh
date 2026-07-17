#!/bin/sh
# One-shot safety hook for the first boot after the V1 entropy regression.
# startup.sh runs /mnt/mmc/oops.sh before launching the frontend.

/opt/muos/script/init/S01entropy start
exit 0

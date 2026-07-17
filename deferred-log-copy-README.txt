muOS deferred boot-log copy experiment
======================================

Finding
-------
On boot 5ebe48dc-e587-4331-b284-66e8a8a32a52, frontend.sh reached its resume
check at uptime 7.71 seconds but did not dispatch the stock boot-log copy until
10.84 seconds. muxfrontend was not executed until 10.87 seconds. The synchronous
mkdir therefore held the UI path for about 3.13 seconds; the asynchronous copy
then overlapped the frontend executable's own loading.

Change
------
The existing boot-log copy is retained but placed in a background subshell that
sleeps for 20 seconds. The UI launcher can proceed immediately, while diagnostic
logs are still copied after the interface should be usable.

Boot sequence
-------------
1. First boot after staging: user-init installs this change. Do not time it as
   the optimized sample.
2. Subsequent boots: the deferred copy is active. Collect at least three
   stopwatch samples to distinguish the change from normal variance.

Restore
-------
Place restore.sh in MUOS/init and boot once, or run it on-device. It restores
the frontend shell as it existed immediately before this experiment.

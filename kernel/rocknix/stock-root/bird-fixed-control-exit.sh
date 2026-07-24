#!/bin/sh
# Match ROCKNIX input_sense's global process-kill contract without making the
# fixed event process parse shell words.  runemu.sh and the exact application
# wrappers own this root-generated file for the lifetime of selected content.

KILL_DATA=/tmp/.process-kill-data

[ -s "$KILL_DATA" ] || exit 0
IFS= read -r TO_KILL <"$KILL_DATA"
[ -n "$TO_KILL" ] || exit 0

# Intentional word splitting preserves entries such as
# "-9 retroarch retroarch32" from ROCKNIX's set_kill helper.
# shellcheck disable=SC2086
exec /usr/bin/killall $TO_KILL 2>/dev/null

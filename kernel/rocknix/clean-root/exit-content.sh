#!/bin/sh
# One Bird-owned exit contract for every application. Each launch gets its own
# session/process group, so Select+Start covers RetroArch, MPV, DraStic,
# PPSSPP, Port scripts and every child they create without naming binaries.

SESSION_FILE=/run/bird/content-session.pid

valid_session() {
	[ -s "$SESSION_FILE" ] || return 1
	SESSION=$(cat "$SESSION_FILE")
	case "$SESSION" in *[!0-9]*|'') return 1 ;; esac
	[ "$SESSION" -gt 1 ]
}

if valid_session; then
	/bin/kill -TERM "-$SESSION" 2>/dev/null || :
	COUNT=0
	while [ "$COUNT" -lt 100 ]; do
		/bin/kill -0 "-$SESSION" 2>/dev/null || exit 0
		COUNT=$((COUNT + 1))
		/bin/usleep 10000
	done
	/bin/kill -KILL "-$SESSION" 2>/dev/null || :
	exit 0
fi

# Recovery fallback for an interrupted launch before its session PID is
# published. The normal v5.4 path never needs this list.
/usr/bin/killall -TERM retroarch retroarch32 mpv ppsspp drastic 2>/dev/null || :
exit 0

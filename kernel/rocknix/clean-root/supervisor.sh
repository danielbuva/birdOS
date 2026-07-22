#!/bin/sh
# Bird's permanent launcher/content supervisor. This file deliberately has no
# muOS imports: the four-line request written by the static launcher is the
# complete interface between UI and application policy.

TARGET=/opt/dani-launcher
RUN=/run/muos
BIRD_RUN=/run/bird
REQUEST=$RUN/dani-launch-request
READY=$BIRD_RUN/runtime-ready
LOG=/tmp/bird-supervisor.log

snapshot_log() {
	[ -d /mnt/mmc/MUOS ] || return 0
	mkdir -p /mnt/mmc/MUOS/Bird/log
	cp -f "$LOG" /mnt/mmc/MUOS/Bird/log/supervisor-latest.log
}

wait_runtime() {
	COUNT=0
	while [ ! -e "$READY" ]; do
		COUNT=$((COUNT + 1))
		[ "$COUNT" -lt 500 ] || return 1
		/bin/usleep 10000
	done
}

case "${1-}" in
	start)
		[ -x "$TARGET" ] || exit 1
		mkdir -p "$RUN" "$BIRD_RUN"
		[ -s "$BIRD_RUN/supervisor.pid" ] && \
			kill -0 "$(cat "$BIRD_RUN/supervisor.pid")" 2>/dev/null && exit 0
		(
			{
				printf 'bird supervisor start uptime: '
				cut -d ' ' -f 1 /proc/uptime
				while :; do
					"$TARGET"
					RESULT=$?
					printf 'bird launcher result=%s uptime=' "$RESULT"
					cut -d ' ' -f 1 /proc/uptime
					case "$RESULT" in
						10)
							if wait_runtime; then
								/opt/bird/run-content.sh "$REQUEST"
							else
								printf '%s\n' 'bird runtime readiness timeout'
								sleep 1
							fi
							;;
						11)
							snapshot_log
							kill -USR2 1
							exit 0
							;;
						12)
							printf '%s\n' 'PortMaster deferred until Bird native networking cycle'
							sleep 1
							;;
						*)
							# B on Bird's top page used to request the stock frontend.
							# There is no second frontend in the clean root, so redraw Bird.
							/bin/usleep 50000
							;;
					esac
					snapshot_log
				done
			} >"$LOG" 2>&1
		) &
		printf '%s\n' "$!" >"$BIRD_RUN/supervisor.pid"
		;;
	stop)
		[ -s "$BIRD_RUN/supervisor.pid" ] && \
			kill "$(cat "$BIRD_RUN/supervisor.pid")" 2>/dev/null || :
		;;
	*)
		printf 'Usage: %s {start|stop}\n' "$0" >&2
		exit 1
		;;
esac

exit 0

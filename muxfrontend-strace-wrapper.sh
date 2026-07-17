#!/bin/sh
# One-boot wrapper installed under the muxfrontend filename.

TRACE="/tmp/muxfrontend-startup.strace"
: >"$TRACE"

exec /opt/muos/bin/strace \
	-f -ttt -T -s 256 \
	-o "$TRACE" \
	-e trace=%file,read,pread64,readv,close,getdents64,mmap,mprotect,munmap,brk \
	/opt/muos/frontend/muxfrontend.boottrace-real "$@"

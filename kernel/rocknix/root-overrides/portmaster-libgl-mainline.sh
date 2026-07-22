#!/bin/bash
# Sourced by PortMaster ports on Bird's source kernel.  The vendor policy
# prepends GL4ES/Mali-fbdev after the supervisor has selected Mesa; keep the
# port's process on the already-prepared DRM/GBM ABI instead.

unset LIBGL_ES LIBGL_GL LIBGL_FB
unset SDL_VIDEO_GL_DRIVER SDL_VIDEO_EGL_DRIVER

if [ -r /run/muos/bird-mainline-env ]; then
	. /run/muos/bird-mainline-env
	BIRD_MAINLINE_REASSERT
fi

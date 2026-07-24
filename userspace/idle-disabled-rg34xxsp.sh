#!/bin/sh
# BIRD_FIXED_RG34XXSP_NO_IDLE_SCANNER_V1

# The fixed hotkey service owns the configured display-idle transition directly.
# Idle sleep is disabled, networking is on demand, and none of the stock process
# watch-list applications are part of the fixed session, so no polling daemon is
# required.
exit 0

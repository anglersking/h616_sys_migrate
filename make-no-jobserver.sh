#!/bin/sh

# Docker Desktop's amd64 emulation does not preserve GNU make 4.3's pipe
# jobserver descriptors across BusyBox's Kconfig recursion. Start a fresh
# local job pool for each recursive build instead of inheriting those FDs.
jobs="${MAKE_NO_JOBSERVER_JOBS:-1}"
case "$jobs" in
    ''|*[!0-9]*|0) jobs=1 ;;
esac

unset MAKEFLAGS MFLAGS
exec /usr/bin/make -j"$jobs" "$@"

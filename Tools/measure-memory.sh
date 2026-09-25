#!/bin/sh
# Memory of the editor view in isolation, per configuration, using footprint(1).
# Usage: Tools/measure-memory.sh            (default set of configurations)
#        Tools/measure-memory.sh "--huge --php" "--nstextview --huge"
set -eu
cd "$(dirname "$0")/ViewHarness"
swift build -c release 2>&1 | grep -E "error|warning: " || true
bin="$(swift build -c release --show-bin-path)/ViewHarness"

if [ $# -eq 0 ]; then
    set -- "--empty" "--nstextview" "" "--gutter" "--php" "--huge" "--huge --gutter --php" "--nstextview --huge"
fi

printf "%-28s %8s %10s %10s %10s\n" "configuration" "total" "graphics" "iosurface" "heap"
for config in "$@"; do
    # shellcheck disable=SC2086
    "$bin" $config --seconds 12 >/dev/null 2>&1 &
    pid=$!
    sleep 6
    footprint "$pid" 2>/dev/null | awk -v C="${config:-(textview)}" '
        /Footprint:/ {t=$5" "$6}
        /\(graphics\)$/ && /Owned/ {g=$1" "$2}
        /IOSurface/ {io=$1" "$2}
        /MALLOC_SMALL/ {m=$1" "$2}
        END {printf "%-28s %8s %10s %10s %10s\n", C, t, (g==""?"0":g), (io==""?"0":io), m}'
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
done

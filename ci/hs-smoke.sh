#!/bin/sh
#
# hs-smoke.sh: install tilemo into a fresh Hammerspoon and run ci/hs_smoke.lua
# inside it (macOS only; CI's macOS job). Prints the results and exits 1 if
# any check failed or Hammerspoon never reported.
#
#   $TILEMO_SMOKE_WAIT  seconds to wait for Hammerspoon to report (default 120)

set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
wait_for=${TILEMO_SMOKE_WAIT:-120}
out=$(mktemp -d)/smoke.txt
: >"$out"
hs_dir=$HOME/.hammerspoon

if test -e "$hs_dir/init.lua"; then
    echo "hs-smoke: $hs_dir/init.lua exists; this is for a fresh runner" >&2
    exit 1
fi

make -C "$repo" install HAMMERSPOON_DIR="$hs_dir" >/dev/null

# App keys run tide's helpers through ~/scripts/runenv. A stand-in that runs
# its command from ~/scripts, and a helper that fails once the smoke test
# lets it go through a FIFO, check a failing key is reported, and that its
# task outlives a garbage collection while it runs.
if test -e "$HOME/scripts"; then
    echo "hs-smoke: $HOME/scripts exists; this is for a fresh runner" >&2
    exit 1
fi
mkdir -p "$HOME/scripts"
printf '#!/bin/sh\nPATH="$HOME/scripts:$PATH" exec "$@"\n' >"$HOME/scripts/runenv"
mkfifo "$HOME/scripts/tilemo-smoke-go"
printf '#!/bin/sh\nread -r _ <"$HOME/scripts/tilemo-smoke-go"\necho "no such app" >&2\nexit 3\n' >"$HOME/scripts/tilemo-smoke-fail"
chmod +x "$HOME/scripts/runenv" "$HOME/scripts/tilemo-smoke-fail"
cat >"$hs_dir/init.lua" <<LUA
TILEMO_SMOKE_OUT = "$out"
local ok, err = xpcall(dofile, debug.traceback, "$repo/ci/hs_smoke.lua")
if not ok then
    local f = io.open(TILEMO_SMOKE_OUT, "a")
    if f then
        f:write("FAIL hs_smoke.lua: ", tostring(err), "\\nRESULT fail\\n")
        f:close()
    end
    hs._exit(true, true)
end
LUA

# No crash-report prompt or Dock icon on a runner nobody watches.
defaults write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false
defaults write org.hammerspoon.Hammerspoon MJShowDockIconKey -bool false

# Run the binary itself: Launch Services may not know about an app Homebrew
# moved into /Applications a moment ago, so `open -a` can't find it.
log=$(dirname "$out")/hammerspoon.log
/Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon >"$log" 2>&1 &
pid=$!

# hs_smoke.lua writes the results and quits Hammerspoon, so wait for it to
# exit. The wait is for an app launch on a cold runner, not a retry.
waited=0
while kill -0 "$pid" 2>/dev/null; do # kill -0 fails once it has exited
    if test "$waited" -ge "$wait_for"; then
        echo "hs-smoke: Hammerspoon didn't finish within ${wait_for}s" >&2
        # Where its main thread is stuck, before it goes.
        sample "$pid" 2 -file "$log.sample" >/dev/null ||
            echo "hs-smoke: couldn't sample Hammerspoon" >&2
        kill "$pid"
        if test -s "$log.sample"; then
            echo "hs-smoke: its main thread:" >&2
            sed -n '/^Call graph:/,/^$/p' "$log.sample" | head -n 120 >&2
        fi
        cat "$log" >&2
        if test -s "$out"; then
            echo "hs-smoke: got this far:" >&2
            cat "$out" >&2
        fi
        exit 1
    fi
    sleep 1
    waited=$((waited + 1))
done

cat "$out"
if ! grep -qx "RESULT ok" "$out"; then
    if ! grep -q "^RESULT " "$out"; then
        echo "hs-smoke: Hammerspoon exited without finishing" >&2
        cat "$log" >&2
    fi
    exit 1
fi

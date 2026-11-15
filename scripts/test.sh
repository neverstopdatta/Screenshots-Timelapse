#!/bin/sh
# Simulates the failure states the menu bar icon reports, and puts everything back afterwards.
#   scripts/test.sh lowdisk|idle|noaccess|failing on|off
#   scripts/test.sh asleep|lock      one-shot, nothing to restore
#   scripts/test.sh status|restore|log
# Needs the app built (scripts/build.sh). Starting capture presses your shortcut through System Events
# (Accessibility permission for your terminal); if that is not granted, press the shortcut yourself.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Screenshots Timelapse.app"
BUNDLE=dev.local.sstl
SUPPORT="$HOME/Library/Application Support/Screenshots Timelapse"
SETTINGS="$SUPPORT/settings.json"
LOG="$HOME/Library/Logs/Screenshots Timelapse.log"
STATE="$HOME/.sstl-test-state"
touch "$STATE"

get() { sed -n "s/.*\"$1\":\([^,}]*\).*/\1/p" "$SETTINGS"; }
set_value() { sed -i '' "s/\"$1\":[0-9.]*/\"$1\":$2/" "$SETTINGS"; }
state_get() { sed -n "s/^$1=//p" "$STATE"; }
state_set() { state_clear "$1"; echo "$1=$2" >> "$STATE"; }
state_clear() { grep -v "^$1=" "$STATE" > "$STATE.new" || true; mv "$STATE.new" "$STATE"; }

# Changes a setting, remembering the original the first time only.
override() {
    [ -n "$(state_get "$1")" ] || state_set "$1" "$(get "$1")"
    set_value "$1" "$2"
}
revert() {
    [ -z "$(state_get "$1")" ] || { set_value "$1" "$(state_get "$1")"; state_clear "$1"; }
}

restart_app() {
    osascript -e 'tell application "Screenshots Timelapse" to quit' >/dev/null 2>&1 || true
    while pgrep -x SSTL >/dev/null; do sleep 0.2; done
    open "$APP"
    sleep 2
}

# Presses the app's own Start/Stop shortcut, read from settings.
press_shortcut() {
    code=$(sed -n 's/.*"keyCode":\([0-9]*\).*/\1/p' "$SETTINGS")
    mods=$(sed -n 's/.*"carbonModifiers":\([0-9]*\).*/\1/p' "$SETTINGS")
    using=""
    [ $((mods & 256)) -ne 0 ] && using="$using, command down"
    [ $((mods & 512)) -ne 0 ] && using="$using, shift down"
    [ $((mods & 2048)) -ne 0 ] && using="$using, option down"
    [ $((mods & 4096)) -ne 0 ] && using="$using, control down"
    using=${using#, }
    osascript -e "tell application \"System Events\" to key code $code using {$using}" 2>/dev/null \
        || echo "Could not press the shortcut. Start screenshots yourself."
}

report() {
    sleep "${1:-4}"
    echo "--- log"
    grep -E "Status changed|Screenshot failed|Screen Recording|System state" "$LOG" | tail -5
}

failing_dir() {
    root=$(get rootPath | tr -d '"' | sed 's#\\/#/#g')
    echo "$(echo "$root" | sed "s#^~#$HOME#")/$(get activeProject | tr -d '"')/$(date +%F)"
}

case "${1:-}" in
lowdisk)
    if [ "${2:-}" = on ]; then override minFreeSpaceGB 100000; restart_app; press_shortcut; report
    else revert minFreeSpaceGB; restart_app; echo "restored"; fi ;;
idle)
    if [ "${2:-}" = on ]; then override pauseWhenIdleSeconds 5; restart_app; press_shortcut
        echo "Hands off the keyboard and mouse for 5 seconds."; report 8
    else revert pauseWhenIdleSeconds; restart_app; echo "restored"; fi ;;
noaccess)
    if [ "${2:-}" = on ]; then
        tccutil reset ScreenCapture "$BUNDLE"; restart_app; press_shortcut; report 6
        echo "macOS may ask for permission: ignore it, or choose Don't Allow."
    else
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        echo "Allow Screenshots Timelapse, then quit and reopen it."
    fi ;;
failing)
    if [ "${2:-}" = on ]; then
        dir=$(failing_dir); mkdir -p "$dir"; chmod a-w "$dir"; state_set failing_dir "$dir"
        echo "Made read-only: $dir. Start screenshots; the alert shows after the first capture ($(get intervalSeconds)s)."
    else
        dir=$(state_get failing_dir)
        [ -z "$dir" ] || { chmod u+w "$dir"; state_clear failing_dir; }
        echo "restored"
    fi ;;
asleep) pmset displaysleepnow ;;
lock) osascript -e 'tell application "System Events" to key code 12 using {control down, command down}' ;;
status)
    echo "app running: $(pgrep -x SSTL >/dev/null && echo yes || echo no)"
    echo "minFreeSpaceGB=$(get minFreeSpaceGB) pauseWhenIdleSeconds=$(get pauseWhenIdleSeconds)"
    echo "overrides in place:"; cat "$STATE"
    grep -E "Status changed" "$LOG" | tail -3 ;;
restore)
    changed=no
    for key in minFreeSpaceGB pauseWhenIdleSeconds; do
        [ -z "$(state_get $key)" ] || { revert $key; changed=yes; }
    done
    dir=$(state_get failing_dir)
    [ -z "$dir" ] || { chmod u+w "$dir"; state_clear failing_dir; }
    [ $changed = no ] || restart_app
    echo "restored (Screen Recording permission, if you reset it, is re-granted in System Settings)" ;;
log) tail -f "$LOG" ;;
*) sed -n '2,6p' "$0" ;;
esac

#!/usr/bin/env bash

# lib/bt_menu.sh - rofi-based Bluetooth device menu (stage 2)
#
# Opened via middle-click on the panel's "BLT:" widget (only when powered on).
# Opens INSTANTLY with the currently known devices and kicks off a background
# scan so newly discovered devices appear on the next open (no blocking wait).
#   - Enter / left-click : toggle connection (connect if off, disconnect if on)
#   - Alt+p              : pair the selected device (no auto-connect)
# After any action it re-reads panel state via the bt_refresh hook.
#
# Status tags shown in small font: connected / disconnected / paired / unpaired.

# How long a background scan keeps running once triggered.
SCAN_SECS=6
# Don't start a new background scan if one ran within this many seconds.
SCAN_COOLDOWN=20
STAMP="${XDG_RUNTIME_DIR:-/tmp}/bt_menu.scan.stamp"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/bt_menu.scan.lock"

# Kick off a non-blocking background scan, but only if none is running and the
# last one is older than SCAN_COOLDOWN. Returns immediately either way.
maybe_scan() {
    # Already scanning? (lock dir exists) -> do nothing.
    if ! mkdir "$LOCK" 2>/dev/null; then
        return
    fi
    # Cooldown still active? -> release lock, do nothing.
    if [ -f "$STAMP" ]; then
        local last now
        last=$(cat "$STAMP" 2>/dev/null || echo 0)
        now=$(date +%s)
        if [ $(( now - last )) -lt "$SCAN_COOLDOWN" ]; then
            rmdir "$LOCK" 2>/dev/null
            return
        fi
    fi
    # Run the scan detached so rofi can open immediately.
    (
        { echo "scan on"; sleep "$SCAN_SECS"; echo "scan off"; echo "quit"; } \
            | bluetoothctl >/dev/null 2>&1
        date +%s > "$STAMP"
        rmdir "$LOCK" 2>/dev/null
    ) &
    disown
}

# Collect MACs from a "devices <filter>" call into an associative set.
collect_set() {
    local -n _set=$1
    local filter=$2 line mac
    while read -r line; do
        mac=$(printf '%s' "$line" | cut -d' ' -f2)
        [ -n "$mac" ] && _set["$mac"]=1
    done < <(bluetoothctl devices "$filter" 2>/dev/null)
}

main() {
    # Fire-and-forget scan; do NOT wait for it.
    maybe_scan

    # Build status sets from whatever bluez knows right now.
    declare -A paired connected
    collect_set paired Paired
    collect_set connected Connected

    # Build the menu: "<MAC>\t<Name> <small>status</small>".
    local menu="" line mac name status
    while read -r line; do
        mac=$(printf '%s' "$line" | cut -d' ' -f2)
        name=$(printf '%s' "$line" | cut -d' ' -f3-)
        [ -z "$mac" ] && continue

        if [ -n "${connected[$mac]}" ]; then
            status="connected"
        elif [ -n "${paired[$mac]}" ]; then
            status="disconnected"
        else
            status="unpaired"
        fi

        menu+="${mac}\t${name} <span size='small' foreground='#565f89'>${status}</span>\n"
    done < <(bluetoothctl devices 2>/dev/null)

    [ -z "$menu" ] && menu="\tNo devices found"

    # rofi: hide the MAC (column 1), show only column 2; Alt+p = kb-custom-1.
    local sel exit_code
    sel=$(printf "%b" "$menu" \
        | rofi -dmenu -i -p "Bluetooth" \
               -markup-rows \
               -display-columns 2 -display-column-separator "\t" \
               -mesg "Enter: connect/disconnect    Alt+p: pair    (rescans in background)" \
               -kb-custom-1 "Alt+p")
    exit_code=$?

    [ -z "$sel" ] && exit 0
    mac=$(printf '%s' "$sel" | cut -f1)
    [ -z "$mac" ] && exit 0

    case $exit_code in
        0)
            if bluetoothctl devices Connected 2>/dev/null | grep -q "$mac"; then
                bluetoothctl disconnect "$mac" >/dev/null 2>&1
            else
                bluetoothctl connect "$mac" >/dev/null 2>&1
            fi
            ;;
        10)
            bluetoothctl pair "$mac" >/dev/null 2>&1
            ;;
    esac

    herbstclient emit_hook bt_refresh
}

main

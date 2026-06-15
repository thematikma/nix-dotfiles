#!/usr/bin/env bash
# Generate Events, so the panel will be dynamically populated. This function is called in panel.sh

event_generator() {
pids=()

    # Date remains on one second cycle
    while true ; do
        printf "date\t^fg($color_fg_dim)%(%a)T, ^fg($color_fg)%(%d)T.%(%m.%Y)T ^fg($color_fg)%(%H:%M)T\n"
        sleep 1 || break
    done > >(uniq_linebuffered) &
    pids+=($!)

    # Initial call, so the bar has actual values at login
    volume_event
    brightness_event
    battery_event
    weather_event
    bt_event

    # Media is event based on track change and start/stop/pause
    playerctl --follow metadata --format $'med\t{{artist}}\x1f{{title}}' 2>/dev/null \
        > >(uniq_linebuffered) &
    pids+=($!)

    # Bluetooth – event-based. bluetoothctl stays attached and prints [CHG]
    # lines; we re-read full state on any Connected/Powered change.
    # 'echo' keeps stdin open so interactive bluetoothctl does not exit early.
    { echo; sleep infinity; } | stdbuf -oL bluetoothctl 2>/dev/null \
        | grep --line-buffered -E 'Connected: (yes|no)|Powered: (yes|no)' \
        | while read -r _ ; do bt_event ; done > >(uniq_linebuffered) &
    pids+=($!)

    # PipeWire volume changes that bypass our keybind hooks — e.g. AVRCP from
    # the headset's own volume buttons, or a default-sink switch on connect.
    # pw-mon is noisy (fires on track changes too); we filter to volume lines
    # and let uniq_linebuffered drop unchanged results downstream.
    stdbuf -oL pw-mon 2>/dev/null \
        | grep --line-buffered -i 'volume' \
        | while read -r _ ; do volume_event ; done > >(uniq_linebuffered) &
    pids+=($!)

    # Battery – event-based via upower. We use 'upower --monitor' purely as a
    # bell: on any line we re-read the actual values from sysfs through
    # battery_event. uniq_linebuffered drops the many identical notifications
    # (upower fires very often, e.g. on voltage jitter we don't display).
    stdbuf -oL upower --monitor-detail 2>/dev/null \
        | grep --line-buffered -E 'percentage:|state:' \
        | while read -r _ ; do battery_event ; done > >(uniq_linebuffered) &
    pids+=($!)

    hc --idle
    kill "${pids[@]}" 2>/dev/null
}

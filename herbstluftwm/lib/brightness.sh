#!/usr/bin/env bash

# lib/brightness.sh - Brightness backlight widget for the panel.
#
# On a desktop there is no backlight. brightnessctl with no -d defaults to the
# first device it can find, which is often a NIC/keyboard LED in class 'leds'
# (e.g. "enp5s0-3::lan ... 0%"), producing a bogus "bri 0". We therefore only
# read class 'backlight' devices and render nothing when none exist.
#
# brightness_read sets act_bri (empty if no backlight) and returns non-zero
# when there is nothing to show, so brightness_event/_format produce no widget.

# Pick the first real backlight device name, cached after first lookup.
_bri_device() {
    if [ -z "${_BRI_DEV+x}" ]; then
        _BRI_DEV=""
        if command -v brightnessctl >/dev/null 2>&1; then
            # -lm lists all devices, machine-readable: name,class,cur,pct,max
            _BRI_DEV=$(brightnessctl -lm 2>/dev/null \
                | awk -F, '$2=="backlight"{print $1; exit}')
        fi
    fi
    [ -n "$_BRI_DEV" ]
}

brightness_read() {
    if ! _bri_device; then
        act_bri=""
        return 1
    fi
    act_bri=$(brightnessctl -m -d "$_BRI_DEV" 2>/dev/null \
        | head -n1 | awk -F, '{print $4}' | tr -d '%')
    [ -n "$act_bri" ] || return 1
}

brightness_event() {
    brightness_read || return
    printf 'bri\t%s\n' "$act_bri"
}

brightness_format() {
    if [ -z "$act_bri" ]; then
        brightness=""
        return
    fi
    local ca_open ca_close
    ca_open="^ca(4,$hc_quoted spawn sh -c 'brightnessctl -e4 -n2 set 5%+; herbstclient emit_hook brightness_refresh')"
    ca_open+="^ca(5,$hc_quoted spawn sh -c 'brightnessctl -e4 -n2 set 5%-; herbstclient emit_hook brightness_refresh')"
    ca_close="^ca()^ca()"
    brightness="${ca_open}^fg($color_fg_dim)bri: ^fg($color_fg)${act_bri}%^fg()${ca_close}"
}

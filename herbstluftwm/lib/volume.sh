#!/usr/bin/env bash
# lib/volume.sh - Volume logics for the panel
# We need the volume_event, in case the volume is altered outside the script. The function is called in the event loop in panel.sh
# The function volume_read will provide actual values and is executed through herbstclient emit_hook in panel.sh under the data handling section and defined as volume_refresh. So we get fresh values on change, no matter the event loops position.
#
# Genernate events
volume_event() {
    vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    if [ -n "$vol_raw" ]; then
        vol_pct=$(awk '{ printf "%d", $2 * 100 }' <<< "$vol_raw")
        if [[ "$vol_raw" == *"[MUTED]"* ]]; then
            vol_muted="yes"
        else
            vol_muted="no"
        fi
        printf 'vol\t%s\t%s\n' "$vol_pct" "$vol_muted"
    fi
}
# Read and set vol_pct / vol_muted
volume_read() {
    local raw
    raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    vol_pct=$(awk '{ printf "%d", $2 * 100 }' <<< "$raw")
    if [[ "$raw" == *"[MUTED]"* ]]; then
        vol_muted="yes"
    else
        vol_muted="no"
    fi
}
# Build dzen2-String incl. ^ca() to use mouse buttons for volume settings. Expects $hc_quoted,
# $color_fg, $color_fg_dim def in panel.sh.
# Scroll up = louder, scroll down = attenuate, mouse lefr-click = mute.
volume_format() {
    local ca_open ca_close
    ca_open="^ca(1,$hc_quoted spawn sh -c 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle; herbstclient emit_hook volume_refresh')"
    ca_open+="^ca(4,$hc_quoted spawn sh -c 'wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ 5%+; herbstclient emit_hook volume_refresh')"
    ca_open+="^ca(5,$hc_quoted spawn sh -c 'wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ 5%-; herbstclient emit_hook volume_refresh')"
    ca_close="^ca()^ca()^ca()"
    if [ "$vol_muted" = "yes" ]; then
        volume="${ca_open}^fg($color_fg_dim)vol: M ${vol_pct}%^fg()${ca_close}"
    else
        volume="${ca_open}^fg($color_fg_dim)vol: ^fg()^fg(color_fg)${vol_pct}%^fg()${ca_close}"
    fi
}

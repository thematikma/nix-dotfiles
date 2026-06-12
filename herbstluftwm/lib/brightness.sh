#/usr/bin/env bash

# lib/brightness.sh - Brightness LCD panel set and render on the panel
# We need the brightnes_event, in case the brightness is altered outside the script. The function is called in the event loop in panel.sh 
# The function brightness_read will provide actual values and is executed through herbstclient emit_hook in panel.sh under the data handling section and defined as brightness_refresh. So we get fresh values on change, no matter the event loops position.
#
# Generate events
brightness_read() {
act_bri=$(brightnessctl | grep % | awk -F' ' '{print $4}' | tr -d '(%)' 2>/dev/null)
}

brightness_event() {
    brightness_read
    printf 'bri\t%s\n' "$act_bri"
}

brightness_format() {
    local ca_open ca_close
    ca_open+="^ca(4,$hc_quoted spawn sh -c 'brightnessctl -e4 -n2 set 5%+; herbstclient emit_hook brightness_refresh')"
    ca_open+="^ca(5,$hc_quoted spawn sh -c 'brightnessctl -e4 -n2 set 5%-'; herbstclient emit_hook brightness_refresh)"
    ca_close="^ca()^ca()"
    brightness="${ca_open}^fg($color_fg_dim)bri: ^fg($color_fg)${act_bri}%^fg()${ca_close}"
}


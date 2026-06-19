#!/usr/bin/env bash

# lib/bluetooth.sh - Bluetooth logic for the panel (stage 1)
#
# Panel display: always "BLT:" - toggleable via left-click (power on/off).
#   - adapter off -> "BLT:" in color_fg_dim
#   - adapter on  -> "BLT:" in color_fg, followed by the (first) connected device
#
# bt_event   : emits a 'blt' line for the event generator (initial value
#              plus every change reported by bluetoothctl in the generator block).
# bt_read    : reads power status + first connected device without printing
#              (for the bt_refresh hook in the data-handling section).
# bt_format  : builds the dzen string incl. ^ca() for left/right click.
#
# Expects from panel.sh: $hc_quoted, $color_fg, $color_fg_dim.
# Reads power status (bt_power = on|off) and the name of the first connected
# device (bt_dev, may be empty). Only sets variables, prints nothing

bt_read() {
    # No adapter present (e.g. a desktop without bluetooth): bail out fast.
    # Without this, 'bluetoothctl show' can block and stall the whole
    # event generator, since bt_event runs as an initial call.
    if ! bluetoothctl list 2>/dev/null | grep -q .; then
        bt_power=""
        bt_dev=""
        return 1
    fi

    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        bt_power="on"
    else
        bt_power="off"
    fi

    bt_dev=""
    if [ "$bt_power" = "on" ]; then
        # "Device <MAC> <Name>" -> everything from the 3rd field on is the name.
        bt_dev=$(bluetoothctl devices Connected 2>/dev/null \
                 | head -n1 | cut -d' ' -f3-)
    fi
}

# Event line for the generator: blt <power> <device-name...>
bt_event() {
    bt_read || return
    printf 'blt\t%s\t%s\n' "$bt_power" "$bt_dev"
}

# Build the dzen string. Left-click toggles power, right-click opens (only when
# on) the rofi menu via bt_menu.sh and triggers bt_refresh afterwards.
bt_format() {
    local ca_open ca_close label
    # Left-click (button 1): toggle power, then re-read status
    ca_open="^ca(1,$hc_quoted spawn sh -c 'bluetoothctl power "
    if [ "$bt_power" = "on" ]; then
        ca_open+="off"
    else
        ca_open+="on"
    fi
    ca_open+="; herbstclient emit_hook bt_refresh')"

    # Right-click (button 3): only when on -> open rofi menu
    if [ "$bt_power" = "on" ]; then
        ca_open+="^ca(2,$hc_quoted spawn ~/.config/herbstluftwm/lib/bt_menu.sh)"
        ca_close="^ca()^ca()"
    else
        ca_close="^ca()"
    fi

    if [ "$bt_power" = "on" ]; then
        label="^fg($color_fg)blt:^fg()"
        [ -n "$bt_dev" ] && label+=" ^fg($color_fg)${bt_dev}^fg()"
    else
        label="^fg($color_fg_dim)blt:^fg()"
    fi

    bluetooth="${ca_open}${label}${ca_close}"
}

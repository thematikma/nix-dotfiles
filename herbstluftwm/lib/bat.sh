#!/usr/bin/env bash

# lib/bat.sh - Batterie Logik für das Panel

# Event generation

battery_event() {
    # battery: emit "bat <capacity> <status>" only if a battery exists.
    # uniq_linebuffered below suppresses repeats, so this only redraws
    # when the percentage or charging state actually changes.

    if [ -n "$BATTERY" ] && [ -r "$bat_path/capacity" ]; then
            bat_cap=$(cat "$bat_path/capacity" 2>/dev/null)
            bat_status=$(cat "$bat_path/status" 2>/dev/null)
            printf 'bat\t%s\t%s\n' "$bat_cap" "$bat_status"
    fi
}

# Read and render status
battery_status() {
    if [ "$bat_status" = "Charging" ]; then
        # charging: green with a leading '+'
        battery="^fg($color_fg_dim)bat: ^fg($color_mint)+${bat_cap}%^fg()"
    elif [ "$bat_status" = "Full" ]; then
            # full (often on AC at 100%): green check
            battery="^fg($color_fg_dim)bat: ^fg($color_green)${bat_cap}%^fg()"
    elif [ -n "$bat_cap" ] && [ "$bat_cap" -le 15 ] 2>/dev/null; then
        # low battery: red warning
        battery="^fg($color_fg_dim)bat: ^fg($color_red)${bat_cap}%^fg()"
    else
        # normal discharge
        battery="^fg($color_fg_dim)bat: ^fg($color_fg)${bat_cap}%^fg()"
    fi
}


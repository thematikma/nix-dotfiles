#!/usr/bin/env bash

# lib/bat.sh - panel battery logics

# Battery configuration.
#
# Auto-detect the first battery under /sys/class/power_supply.
# Override by setting BATTERY=BAT1 (etc.) in the environment if needed.
if [ -z "$BATTERY" ]; then
	for _bat in /sys/class/power_supply/BAT*; do
	    if [ -d "$_bat" ]; then
	        BATTERY=$(basename "$_bat")
	        break
	    fi
	done
fi
BAT="/sys/class/power_supply/${BATTERY}"

# Event generation
battery_event() {
    # battery: emit "bat <capacity> <status>" only if a battery exists.
    # uniq_linebuffered below suppresses repeats, so this only redraws
    # when the percentage or charging state actually changes.
    [ -n "$BATTERY" ] && [ -r "$BAT/capacity" ] || return
    bat_cap=$(<"$BAT/capacity")
    bat_status=$(<"$BAT/status")
    printf 'bat\t%s\t%s\n' "$bat_cap" "$bat_status"
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


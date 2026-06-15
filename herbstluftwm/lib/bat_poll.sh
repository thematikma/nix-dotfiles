#!/usr/bin/env bash

# Polling function for battery events
#

BAT=/sys/class/power_supply/BAT0

# battery_poll() {
    while true
    do
        cap=$(<"$BAT/capacity")
        if [[ $cap != $last_cap ]]; then
            printf 'capacity: %s\n' "$cap"
            last_cap="$cap"
        fi

        stat=$(<"$BAT/status")
        if [[ $stat != $last_stat ]]; then
            printf 'status: %s\n'   "$stat"
            last_stat="$stat"
        fi

        sleep 10
    done

# }

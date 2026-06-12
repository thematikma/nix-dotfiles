#!/usr/bin/env bash

# lib/media.sh - Media logics for the panel

media_event() {
    playing=$(playerctl metadata --format '{{artist}} - {{title}}' 2>/dev/null | cut -c1-50)
    printf 'med\t%s\n' "$playing"
}

media_format() {
    local ca_open ca_close
    ca_open="^ca(1,$hc_quoted spawn sh -c 'playerctl play-pause')"
    ca_close="^ca()"
    media="${ca_open}^fg($color_red)${playing}^fg()${ca_close}"
}


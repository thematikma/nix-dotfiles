#!/usr/bin/env bash

# lib/media.sh - Media logics for the panel

# trunc words, to have a cleaner look (no cutouts in a word)
trunc_word() {
    local s=$1 max=${2:-25}
    if (( ${#s} > max )); then
        s=${s:0:max}
        s=${s% *}        # Back to last whitespace
    fi
    printf '%s' "$s"
}

media_event() {
    playing=$(playerctl metadata --format $'{{artist}}\x1f{{title}}' 2>/dev/null)
    printf 'med\t%s\n' "$playing"
}

media_format() {
    local ca_open ca_close artist title
    ca_open="^ca(1,$hc_quoted spawn sh -c 'playerctl play-pause')"
    ca_close="^ca()"
    artist=$(trunc_word "${playing%%$'\x1f'*}" 25)
    title=$(trunc_word "${playing#*$'\x1f'}" 25)
    media="${ca_open}^fg($color_fg_dim)${artist}^fg($color_fg) - ${title}^fg()${ca_close}"
}

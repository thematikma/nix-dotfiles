#/usr/bin/env bash
# lib/waether.sh - weather LCD panel set and render on the panel
# We need the brightnes_event, in case the weather is altered outside the script. The function is called in the event loop in panel.sh
# The function weather_read will provide actual values and is executed through herbstclient emit_hook in panel.sh under the data handling section and defined as weather_refresh. So we get fresh values on change, no matter the event loops position.
#
# Generate events
weather_event() {
    weather_raw=$(cat "$HOME/.cache/weather_cache.file" 2>/dev/null)
    printf 'wea\t%s\n' "$weather_raw"
}

weather_format() {
    if [ -z "$weather_raw" ]; then
        weather=""
        return
    fi
    local cond="${weather_raw%%|*}"
    local temp="${weather_raw##*|}"
    weather="^fg($color_fg_dim)${cond} ^fg($color_fg)${temp//+/}^fg()"
}

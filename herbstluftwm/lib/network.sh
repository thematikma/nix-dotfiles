#!/usr/bin/env bash

# lib/network.sh - network panel block logics

# Formatting
out() { printf 'name:%s\tip:%s\tactive:%s\tconnected:%s\n' "$1" "$2" "$3" "$4"; }

# Check if nmcli is installed
if ! command -v nmcli &> /dev/null; then
    echo "NetworkManager CLI not present." >&2
    exit 127
    break
else
    echo "Found $(nmcli --version)" >&2
fi

# Find interface func
get_interface() {
    local dev type state ip4 conn
    while IFS=: read -r dev type state; do
        [ "$type" = "$1" ] || continue
 
        local active=no
        [ "$state" = "connected" ] && active=yes

        # Ipv4 with prefix
        ip4="$(nmcli -t -g IP4.ADDRESS device show "$dev")"

        # Internet connectivity
        conn="$(nmcli -t -g GENERAL.IP4-CONNECTIVITY device show "$dev")"
        conn="${conn%)}"
        conn="${conn##*\(}"
        out "$dev" "${ip4:-none}" "$active" "$conn"
        break
    done < <(nmcli -t -f DEVICE,TYPE,STATE device status)
}

main() {
    get_interface wifi
    get_interface ethernet
}


main

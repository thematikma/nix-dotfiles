#!/usr/bin/env bash
# lib/util.sh - panel helper functions (library style).
#
# This file ONLY defines functions. It calls nothing on its own. Source it
# from panel.sh and invoke the helpers explicitly where you want them to run:
#
#   source "$script_dir/lib/util.sh"
#   enable_sleep_builtin
#   [ -n "$PANEL_DEBUG" ] && panel_selfcheck
#
# (start_picom lives here too but is normally called from the hlwm autostart,
#  not from panel.sh — see lib/picom.sh notes below if you prefer it separate.)

# ---------------------------------------------------------------------------
# enable_sleep_builtin: load bash's loadable 'sleep' builtin if available, to
# avoid forking an external `sleep` once per second in the date loop. The path
# differs per distro; on NixOS it lives under the bash store path, not /usr/lib.
# Falls back silently to external `sleep` (one fork/sec, harmless) if not found.
# ---------------------------------------------------------------------------
enable_sleep_builtin() {
    local p
    for p in \
        /usr/lib/bash/sleep \
        /usr/lib/bash/sleep.so \
        /usr/local/lib/bash/sleep \
        "${BASH%/bin/bash}/lib/bash/sleep" \
        "$(command -v bash 2>/dev/null | sed 's,/bin/bash,,')/lib/bash/sleep"
    do
        if [[ -n "$p" && -f "$p" ]]; then
            enable -f "$p" sleep 2>/dev/null && return 0
        fi
    done
    enable -f sleep sleep 2>/dev/null && return 0   # maybe already on load path
    return 1
}

# ---------------------------------------------------------------------------
# panel_selfcheck: print to stderr what the *running panel* actually sees —
# its PATH and which tools resolve. The panel's PATH can differ from your
# interactive shell (notably on NixOS), so a "MISSING" here while the tool
# works in your terminal means a PATH-scope problem, not a script bug.
# Writes only to stderr; never touches the dzen output.
# ---------------------------------------------------------------------------
panel_selfcheck() {
    {
        echo "── panel self-check ($(date '+%F %T')) ─────────────────────────"
        echo "PATH=$PATH"
        local t
        for t in herbstclient dzen2 awk wpctl pw-mon playerctl \
                 brightnessctl upower bluetoothctl rofi nmcli picom \
                 textwidth dzen2-textwidth xftwidth; do
            if command -v "$t" >/dev/null 2>&1; then
                printf '  %-16s %s\n' "$t" "$(command -v "$t")"
            else
                printf '  %-16s MISSING\n' "$t"
            fi
        done
        if command -v brightnessctl >/dev/null 2>&1; then
            local bl
            bl=$(brightnessctl -lm 2>/dev/null | awk -F, '$2=="backlight"{print $1; exit}')
            printf '  %-16s %s\n' "backlight" "${bl:-none}"
        fi
        local bat
        for bat in /sys/class/power_supply/BAT*; do
            [ -d "$bat" ] && { printf '  %-16s %s\n' "battery" "$(basename "$bat")"; break; }
        done
        echo "─────────────────────────────────────────────────────────────"
    } >&2
}

# ---------------------------------------------------------------------------
# start_picom: bring up picom only if nothing already manages it. Idempotent —
# safe to call more than once. Defined here for reuse; call it from the hlwm
# autostart (not panel.sh) so the compositor starts with the session.
#   - systemd user unit active  -> leave it
#   - picom already running      -> leave it
#   - otherwise                  -> picom -b
# ---------------------------------------------------------------------------
start_picom() {
    command -v picom >/dev/null 2>&1 || return
    if command -v systemctl >/dev/null 2>&1 \
       && systemctl --user is-active --quiet picom.service 2>/dev/null; then
        return
    fi
    pgrep -x picom >/dev/null 2>&1 && return
    picom -b
}

# ---------------------------------------------------------------------------
# restart_picom: force a clean restart (e.g. bound to a key after a config
# change). Deliberately NOT called from autostart — restarting on every login
# causes a repaint flash and can race a service-managed picom.
# ---------------------------------------------------------------------------
restart_picom() {
    command -v picom >/dev/null 2>&1 || return
    pkill -x picom 2>/dev/null
    sleep 0.2
    picom -b
}

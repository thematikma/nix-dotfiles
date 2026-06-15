#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/volume.sh"
source "$script_dir/lib/bat.sh"
source "$script_dir/lib/brightness.sh"
source "$script_dir/lib/media.sh"
source "$script_dir/lib/weather.sh"
source "$script_dir/lib/bluetooth.sh"
source "$script_dir/lib/event_generator.sh"

# variables
# Tokyo Night theme colors

color_bg="#1a1b26"
color_bg_light="#24283b"
color_fg="#ffffff"
color_fg_dim="#565f89"
color_blue="#6dade3"
color_sandy="#e3a36d"
color_cyan="#0db9d7"
color_green="#9ece6a"
color_teal="#63b7b7"
color_magenta="#9a6ace"
color_red="#d72b0d" #"0db9d7"
color_lavendar="#ad8ee6"
color_mint="#c7e68e"
color_black="#15161e"

quote() {
	local q="$(printf '%q ' "$@")"
	printf '%s' "${q% }"
}

if [[ -f /usr/lib/bash/sleep ]]; then
    # load and enable 'sleep' builtin (does not support unit suffixes: h, m, s!)
    # requires pkg 'bash-builtins' on debian; included in 'bash' on arch.
    enable -f /usr/lib/bash/sleep sleep
fi

hc_quoted="$(quote "${herbstclient_command[@]:-herbstclient}")"
hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}
monitor=${1:-0}
geometry=( $(hc monitor_rect "$monitor") )
if [ -z "$geometry" ] ;then
    echo "Invalid monitor $monitor"
    exit 1
fi
# geometry has the format W H X Y
x=${geometry[0]}
y=${geometry[1]}
panel_width=${geometry[2]}
panel_height=40
font="-adobe-helvetica-medium-r-normal--20-140-100-100-p-100-iso10646-1"
#font="-misc-fixed-medium-r-normal--15-140-75-75-c-90-iso10646-1"
#font="-*-fixed-medium-*-*-*-16-*-*-*-*-*-*-*"
# extract colors from hlwm and omit alpha-value
bgcolor=$(hc get frame_border_normal_color|sed 's,^\(\#[0-9a-f]\{6\}\)[0-9a-f]\{2\}$,\1,')
selbg=$(hc get window_border_active_color|sed 's,^\(\#[0-9a-f]\{6\}\)[0-9a-f]\{2\}$,\1,')
selfg='#101010'

####

# Try to find textwidth binary.
# In e.g. Ubuntu, this is named dzen2-textwidth.
if which textwidth &> /dev/null ; then
    textwidth="textwidth";
elif which dzen2-textwidth &> /dev/null ; then
    textwidth="dzen2-textwidth";
elif which xftwidth &> /dev/null ; then # For guix
    textwidth="xftwidth";
else
    echo "This script requires the textwidth tool of the dzen2 project."
    exit 1
fi



####
# true if we are using the svn version of dzen2
# depending on version/distribution, this seems to have version strings like
# "dzen-" or "dzen-x.x.x-svn"
if dzen2 -v 2>&1 | head -n 1 | grep -q '^dzen-\([^,]*-svn\|\),'; then
    dzen2_svn="true"
else
    dzen2_svn=""
fi

if awk -Wv 2>/dev/null | head -1 | grep -q '^mawk'; then
    # mawk needs "-W interactive" to line-buffer stdout correctly
    # http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=593504
    uniq_linebuffered() {
      awk -W interactive '$0 != l { print ; l=$0 ; fflush(); }' "$@"
    }
else
    # other awk versions (e.g. gawk) issue a warning with "-W interactive", so
    # we don't want to use it there.
    uniq_linebuffered() {
      awk '$0 != l { print ; l=$0 ; fflush(); }' "$@"
    }
fi

hc pad $monitor $panel_height

{
    ### Event generator ###
    # Was outsourced to /lib/event_generator.sh, to de-clutter this file
    #
    event_generator

    } 2> /dev/null |

{
    
    IFS=$'\t' read -ra tags <<< "$(hc tag_status $monitor)"
    visible=true
    date=""
    # windowtitle=""
    battery=""
    volume=""
    brightness=""
    media=""
    weather=""
    while true ; do

        ### Output ###
        # This part prints dzen data based on the _previous_ data handling run,
        # and then waits for the next event to happen.

        separator="^bg()^fg($selbg) "
        # draw tags
        for i in "${tags[@]}" ; do
            case ${i:0:1} in
                '#')
                    echo -n "^bg($selbg)^fg($selfg)"
                    ;;
                '+')
                    echo -n "^bg(#9CA668)^fg(#141414)"
                    ;;
                ':')
                    echo -n "^bg()^fg(#ffffff)"
                    ;;
                '!')
                    echo -n "^bg(#FF0675)^fg(#141414)"
                    ;;
                *)
                    echo -n "^bg()^fg(#ababab)"
                    ;;
            esac
            if [ ! -z "$dzen2_svn" ] ; then
                # clickable tags if using SVN dzen
                echo -n "^ca(1,$hc_quoted focus_monitor \"$monitor\" && "
                echo -n "$hc_quoted use \"${i:1}\")"
                echo -n "^ca(4,$hc_quoted spawn $hc_quoted use_index +1)"
                echo -n "^ca(5,$hc_quoted spawn $hc_quoted use_index -1)"
                echo -n " ${i:1} "
                echo -n "^ca()^ca()^ca()"
            else
                # non-clickable tags if using older dzen
                echo -n " ${i:1} "
            fi
        done
        # echo -n "$separator"
        # echo -n "^bg()^fg() ${windowtitle//^/^^}"
        # small adjustments
        right="$weather $separator^bg() $media $separator^bg() $brightness $separator^bg() $volume $separator^bg() $bluetooth $separator^bg() $battery $separator^bg() $date $separator"
        right_text_only=$(echo -n "$right" | sed 's.\^[^(]*([^)]*)..g')
        # get width of right aligned text.. and add some space..
        width=$($textwidth "$font" "$right_text_only    ")
        # Divide placemnt by 2 for centering the text
        echo -n "^pa($((($panel_width - $width) / 2)))$right"
        echo

        ### Data handling ###
        # This part handles the events generated in the event loop, and sets
        # internal variables based on them. The event and its arguments are
        # read into the array cmd, then action is taken depending on the event
        # name.
        # "Special" events (quit_panel/togglehidepanel/reload) are also handled
        # here.

        # wait for next event
        IFS=$'\t' read -ra cmd || break
        # find out event origin
        case "${cmd[0]}" in
            tag*)
                #echo "resetting tags" >&2
                IFS=$'\t' read -ra tags <<< "$(hc tag_status $monitor)"
                ;;
            date)
                #echo "resetting date" >&2
                date="${cmd[@]:1}"
                ;;
            bat)
                # cmd[1] = capacity (number), cmd[2] = status string
                bat_cap="${cmd[1]}"
                bat_status="${cmd[2]}"
                battery_status
                ;;
            vol)
                vol_pct="${cmd[1]}"
                vol_muted="${cmd[2]}"
                volume_format
                ;;
            volume_refresh)
                volume_read
                volume_format
                ;;
            bri)
                act_bri="${cmd[1]}"
                brightness_format
                ;;
            brightness_refresh)
                brightness_read
                brightness_format
                ;;
            med)
                playing="${cmd[@]:1}"
                media_format
                ;;
            wea)
                weather_raw="${cmd[@]:1}"
                weather_format
                ;;
            weather_refresh)
                weather_read
                weather_format
                ;;
            blt)
                bt_power="${cmd[1]}"
                bt_dev="${cmd[@]:2}"
                bt_format
                ;;
            bt_refresh)
                bt_read
                bt_format
                ;;
            quit_panel)
                exit
                ;;
            togglehidepanel)
                currentmonidx=$(hc list_monitors | sed -n '/\[FOCUS\]$/s/:.*//p')
                if [ "${cmd[1]}" -ne "$monitor" ] ; then
                    continue
                fi
                if [ "${cmd[1]}" = "current" ] && [ "$currentmonidx" -ne "$monitor" ] ; then
                    continue
                fi
                echo "^togglehide()"
                if $visible ; then
                    visible=false
                    hc pad $monitor 0
                else
                    visible=true
                    hc pad $monitor $panel_height
                fi
                ;;
            reload)
                exit
                ;;
            # focus_changed|window_title_changed)
                # windowtitle="${cmd[@]:2}"
                # ;;
            #player)
            #    ;;
        esac
    done

    ### dzen2 ###
    # After the data is gathered and processed, the output of the previous block
    # gets piped to dzen2.

} | dzen2 -w $panel_width -x $x -y $y -fn "$font" -h $panel_height \
    -e "button3=" \
    -ta l -bg "$color_bg" -fg "$color_fg"

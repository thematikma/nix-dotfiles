# herbstluftwm dzen2 Panel

A modular status panel for herbstluftwm built on dzen2. Each information source
(volume, brightness, battery, media, weather, bluetooth) lives in its own
library under `lib/` and is sourced by `panel.sh`.

## Architecture

The panel consists of two parts connected by a pipe:

1. **Event generator**: produces lines of the form `<event>\t<data...>`. Sources
   that can push their own events run as persistent listeners; only what truly
   needs polling runs in a timed loop.
2. **Data handling / output**: reads the event lines, updates the matching
   display variable through the source's `*_format` function, and prints the
   finished dzen line.

Each library typically provides three functions:

- `*_event`   : reads the current value and prints an event line (for the
  generator, e.g. as the initial value at startup).
- `*_read`    : reads the value and only sets variables, without printing (for
  the `*_refresh` hooks in the data-handling section).
- `*_format`  : builds the dzen string including `^ca()` clickable areas.

## Event sources at a glance

| Source      | Mechanism                                | Update trigger |
|-------------|------------------------------------------|----------------|
| Date        | timed loop, 1 s                          | cyclic, fork-free (bash builtins) |
| Media       | `playerctl --follow`                     | event on track/status change |
| Bluetooth   | `bluetoothctl` listener                  | event on connect/powered change |
| Volume      | herbstclient hook + `pw-mon` listener    | hook on keybind/click, pw-mon on external change |
| Brightness  | herbstclient hook                        | hook on keybind/click |
| Battery     | timed loop, 10 s                         | cyclic (sysfs provides no events) |
| Weather     | timed loop, 10 s (reads cache file)      | cyclic; cache filled hourly by a systemd timer |

## What changed compared to the original setup

### 1. Away from the central one-second polling loop

Originally a single loop queried *all* sources once per second, spawning roughly
a dozen external processes every second (wpctl, playerctl, brightnessctl, cat,
and so on). This was split up:

- The **date display** is the only thing left in a one-second loop. It is now
  fully fork-free (`printf '%(...)T'` and the `sleep` builtin), so it costs
  practically no process spawns.
- Sources with their own push mechanism run as persistent listeners (see below).
- Only **battery** is still actively polled (every 10 s), because sysfs provides
  no usable events.

A note on the benefit: the main gain is not CPU or RAM (the difference is not
measurable in practice), but responsiveness and a clean architecture. Sources
that can deliver events are treated as events.

### 2. Media is event-based instead of polled

`playerctl --follow metadata --format` stays open and emits a line only on a
track or status change. The `med\t` prefix is embedded directly in the format
string, which removes the detour through `media_event` (the function in
`lib/media.sh` is no longer called).

### 3. Weather decoupled via a cache file

The weather data comes from a cache file that a systemd timer fills hourly.
The timer and service are defined in the NixOS configuration as a **system**
unit running as the user, with a small updater script that fetches from wttr.in
and writes the result to the cache:

```nix
systemd.timers."get-weather" = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    Persistent = true;
    Unit = "get-weather.service";
  };
};
systemd.services."get-weather" = {
  path = [ pkgs.curl ];
  script = ''
    ${pkgs.bash}/bin/bash "/home/thomas/.local/bin/weather-update.sh"
  '';
  serviceConfig = {
    Type = "oneshot";
    User = "thomas";
  };
};
```

The updater writes to `$HOME/.cache/weather_cache.file`. The panel does not talk
to the network or watch the file: `weather_event` simply reads the cache on the
10-second poll loop (a cheap `cat`, no `curl`). The hourly timer keeps the file
fresh independently of the X session.

This keeps the fetch (network, runs as a system unit) cleanly separated from the
display (reads a local file, runs in the panel). Note that because the timer is
a system unit it has no access to the X session, so a herbstclient hook from the
service would not work here; the poll-from-cache approach sidesteps that
entirely. Make sure the cache path in `lib/weather.sh` matches the path the
updater script writes to.

### 4. Bluetooth module (new)

New `lib/bluetooth.sh` plus `lib/bt_menu.sh`. Panel display: always `BLT:`.

- **Left-click**: toggles the adapter on/off (`bluetoothctl power on|off`).
  Off is dimmed (`color_fg_dim`), on is shown in `color_fg`; the first connected
  device appears after `BLT:`.
- **Middle-click** (only when the adapter is on): opens a rofi menu.

The listener uses a trick: `bluetoothctl` without a subcommand stays in
interactive mode and prints `[CHG]` lines, but exits immediately when stdin is
closed. stdin is therefore kept open via `{ echo; sleep infinity; }`:

```bash
{ echo; sleep infinity; } | stdbuf -oL bluetoothctl 2>/dev/null \
    | grep --line-buffered -E 'Connected: (yes|no)|Powered: (yes|no)' \
    | while read -r _ ; do bt_event ; done > >(uniq_linebuffered) &
```

### 5. rofi menu for bluetooth (`lib/bt_menu.sh`)

- **Enter / left-click** on a device: toggle the connection (connect if off,
  disconnect if on).
- **Alt+p**: pair the highlighted entry, without an automatic connect.
  (rofi does not distinguish mouse buttons as separate actions, so this uses a
  key binding via `kb-custom-1` instead of a right-click.)

Devices carry a small, dimmed status tag: `connected`, `disconnected`, `paired`,
`unpaired`. The MAC is carried as a hidden first field (`-display-columns 2`)
and read back when the selection is evaluated.

The menu opens **instantly** with the known devices and kicks off the scan in
the background (non-blocking). A lock and timestamp file prevents a new scan
from starting on every open (`SCAN_COOLDOWN`). Freshly scanned devices appear on
the next open. After any action the `bt_refresh` hook is emitted so the panel
field updates.

### 6. Volume: hooks plus pw-mon listener

Instant updates on keybinds and panel clicks still go through the
`volume_refresh` hook. In addition, a `pw-mon` listener catches changes that do
not go through the keybinds, in particular the volume buttons on the bluetooth
headset (AVRCP) and the default-sink switch on connect:

```bash
stdbuf -oL pw-mon 2>/dev/null \
    | grep --line-buffered -i 'volume' \
    | while read -r _ ; do volume_event ; done > >(uniq_linebuffered) &
```

`pw-mon` also fires on track changes; the resulting unchanged `vol` line is
discarded by `uniq_linebuffered`.

## Play/pause on the headset

The play/pause button on the headset sends AVRCP, which BlueZ forwards over
MPRIS, the same interface `playerctl` listens on. In most setups this works
without any action. If it does not, the AVRCP-to-MPRIS bridge is missing:

```bash
systemctl --user enable --now mpris-proxy
```

## Requirements

- `herbstluftwm`, `dzen2` (with clickable-area support), `awk`
- `wpctl` / WirePlumber and `pw-mon` (PipeWire) for volume
- `playerctl` for media
- `brightnessctl` for brightness
- `bluetoothctl` (BlueZ) and `rofi` for bluetooth
- a dzen2 `textwidth` tool (`textwidth`, `dzen2-textwidth`, or `xftwidth`)

## Known gotchas

- **Right-click in the panel**: dzen2 binds `button3` to `exit` by default in
  title-only mode. The bluetooth menu is therefore on the middle-click.
- **First menu open after login**: shows only known devices, because the
  background scan is just starting. Simply reopen it shortly after.
- **Weather cache path**: the path read in `lib/weather.sh` must match the path
  the updater script writes to (`$HOME/.cache/weather_cache.file`). If the
  weather field stays empty, check that the file exists and is populated.

## Files

```
panel.sh            Main script: event generator, data handling, dzen2 call
lib/volume.sh       Volume: event/read/format
lib/bat.sh          Battery: event/status
lib/brightness.sh   Brightness: read/event/format
lib/media.sh        Media: event/format (event unused since --follow)
lib/weather.sh      Weather: event/format (reads cache file)
lib/bluetooth.sh    Bluetooth: read/event/format
lib/bt_menu.sh      rofi menu for bluetooth devices
```

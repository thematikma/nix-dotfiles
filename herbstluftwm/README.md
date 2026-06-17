# herbstluftwm dzen2 Panel

A modular status panel for herbstluftwm built on dzen2. Each information source
(volume, brightness, battery, media, weather, bluetooth) lives in its own
library under `lib/` and is sourced by `panel.sh`. The panel is fully
event-driven: every source that can push events runs as a persistent listener,
and the only periodic timer left is the clock.

## Architecture

The panel consists of two parts connected by a pipe:

1. **Event generator** (`lib/event_generator.sh`): produces lines of the form
   `<event>\t<data...>`. Sources that can push their own events run as
   persistent listeners; the clock is the only timed loop. The generator is
   factored into its own `event_generator` function, called from `panel.sh`.
2. **Data handling / output**: reads the event lines, updates the matching
   display variable through the source's `*_format` function, and prints the
   finished dzen line.

Each library typically provides:

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
| Battery     | `upower --monitor` listener              | event on charge/state/AC change |
| Weather     | systemd path unit -> herbstclient hook   | event when the cache file changes |

## Design notes and the path to fully event-driven

The original panel queried all sources once per second from a single loop,
spawning roughly a dozen external processes every second. Over time each source
was moved to the most appropriate mechanism. The main gain is responsiveness and
a clean, uniform architecture rather than measurable CPU or RAM savings; the one
real efficiency point is fewer timer wakeups on battery.

### Date

The only remaining timed loop (1 s). It is fork-free (`printf '%(...)T'` and the
`sleep` builtin), so it costs practically no process spawns.

### Media

`playerctl --follow metadata --format` stays open and emits a line only on a
track or status change. The `med\t` prefix is embedded in the format string,
which removes the detour through `media_event`.

### Bluetooth

`lib/bluetooth.sh` plus `lib/bt_menu.sh`. Panel display: always `BLT:`.

- **Left-click**: toggles the adapter on/off (`bluetoothctl power on|off`).
  Off is dimmed; on is shown in `color_fg`, with the first connected device
  shown after `BLT:`.
- **Middle-click** (only when on): opens a rofi menu (see below).

The listener keeps `bluetoothctl` in interactive mode so it prints `[CHG]`
lines, and keeps stdin open so it does not exit early:

```bash
{ echo; sleep infinity; } | stdbuf -oL bluetoothctl 2>/dev/null \
    | grep --line-buffered -E 'Connected: (yes|no)|Powered: (yes|no)' \
    | while read -r _ ; do bt_event ; done > >(uniq_linebuffered) &
```

### rofi menu for bluetooth (`lib/bt_menu.sh`)

- **Enter / left-click** on a device: toggle the connection.
- **Alt+p**: pair the highlighted entry, without an automatic connect.
  (rofi does not distinguish mouse buttons as separate actions, so this uses a
  key binding via `kb-custom-1`.)

Devices carry a small, dimmed status tag (`connected`, `disconnected`,
`unpaired`). The MAC is carried as a hidden first column (`-display-columns 2`).
The menu opens instantly with known devices and kicks off the scan in the
background; freshly scanned devices appear on the next open. After any action it
emits `bt_refresh` so the panel updates.

### Volume

Instant updates on keybinds and panel clicks go through the `volume_refresh`
hook. A `pw-mon` listener additionally catches changes that bypass the keybinds:
the volume buttons on the bluetooth headset (AVRCP) and the default-sink switch
on connect.

```bash
stdbuf -oL pw-mon 2>/dev/null \
    | grep --line-buffered -i 'volume' \
    | while read -r _ ; do volume_event ; done > >(uniq_linebuffered) &
```

`pw-mon` also fires on track changes; the unchanged `vol` line is dropped by
`uniq_linebuffered`.

### Battery

Moved from a 10-second poll to an event listener once upower was installed and
its service enabled. `upower --monitor` is used purely as a bell: on any
notification, `battery_event` re-reads the actual values from sysfs (the
existing `lib/bat.sh` logic is unchanged; upower is only the trigger). The
listener filters to the battery device so unrelated events (AC, USB-C ports,
a wireless mouse battery) do not fire it:

```bash
stdbuf -oL upower --monitor 2>/dev/null \
    | grep --line-buffered 'battery_BAT0' \
    | while read -r _ ; do battery_event ; done > >(uniq_linebuffered) &
```

Note: `upower --monitor-detail` always prints the full device block (including
`percentage:` and `state:`) on every event, even on irrelevant voltage jitter,
so filtering those fields does not actually reduce triggers. Filtering on the
device with the lean `--monitor` is the effective approach; `uniq_linebuffered`
plus the sysfs re-read absorb the rest. Battery detection lives in `lib/bat.sh`
and auto-detects the first `/sys/class/power_supply/BAT*` (override via
`BATTERY=BAT1`).

### Weather

The data comes from a cache file that a systemd timer fills hourly. The fetch
service is a **system** unit (it only needs the network, not the X session):

```nix
systemd.timers."get-weather" = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "hourly";
    OnBootSec = "2min";        # also refresh shortly after every boot
    Persistent = true;
    Unit = "get-weather.service";
  };
};
systemd.services."get-weather" = {
  path = [ pkgs.curl ];
  script = ''${pkgs.bash}/bin/bash "/home/thomas/.local/bin/weather-update.sh"'';
  serviceConfig = { Type = "oneshot"; User = "thomas"; };
};
```

`OnBootSec` matters: `Persistent` only replays a run if a full interval was
missed, so booting shortly after a run would otherwise leave a stale cache until
the next hour. `OnBootSec` refreshes a couple of minutes after every boot.

Because the fetch service runs in the system scope it has no access to the X
session, so it cannot emit a herbstclient hook directly. Instead a **user** path
unit watches the cache file and emits the hook, which has session access:

```nix
systemd.user.paths."weather-watch" = {
  wantedBy = [ "default.target" ];
  pathConfig = {
    PathChanged = "/home/thomas/.cache/weather_cache.file";
    Unit = "weather-watch.service";
  };
};
systemd.user.services."weather-watch" = {
  serviceConfig = {
    Type = "oneshot";
    # absolute store path: the user systemd PATH does not include herbstclient
    ExecStart = "-${pkgs.herbstluftwm}/bin/herbstclient emit_hook weather_refresh";
  };
};
```

The panel handles `weather_refresh` by re-reading the cache via `weather_read`.
The chain is: system timer -> fetch service writes cache -> user path unit sees
the change -> emits `weather_refresh` -> panel re-reads. The updater writes the
file directly (`printf ... > "$cache"`), which triggers `PathChanged`. If you
ever switch to atomic writes (temp file plus `mv`), use `PathModified` or watch
the directory instead.

## Play/pause on the headset

The headset's play/pause button sends AVRCP, which BlueZ forwards over MPRIS,
the interface `playerctl` listens on. If it does not work out of the box, enable
the AVRCP-to-MPRIS bridge:

```bash
systemctl --user enable --now mpris-proxy
```

## Network block (work in progress)

`lib/network.sh` is an early draft and not yet wired into the panel. It uses
`nmcli` to report the active wifi/ethernet interface, its IPv4 address, and
connectivity. Current caveats before it can be sourced like the other libs:

- It is written as a standalone script (calls `main` at the end) rather than a
  sourceable library. The top-level `exit 127` on missing `nmcli` would
  terminate the whole panel if sourced; this needs to become a guard inside a
  function that returns instead of exits.
- Its output format (`name:.. ip:.. active:.. connected:..`) differs from the
  `<event>\t<data>` protocol the other sources use; it needs an event name
  prefix and a data-handling case to integrate.

In other words: the data-gathering logic is taking shape, but the integration
(protocol, sourcing safety, a `*_format` step, an event source in the generator)
is still open.

## Requirements

- `herbstluftwm`, `dzen2` (with clickable-area support), `awk`
- `wpctl` / WirePlumber and `pw-mon` (PipeWire) for volume
- `playerctl` for media
- `brightnessctl` for brightness
- `upower` (service enabled) for battery events
- `bluetoothctl` (BlueZ) and `rofi` for bluetooth
- `nmcli` (NetworkManager) for the upcoming network block
- a dzen2 `textwidth` tool (`textwidth`, `dzen2-textwidth`, or `xftwidth`)

## Known gotchas

- **Right-click in the panel**: dzen2 binds `button3` to `exit` by default in
  title-only mode, so the bluetooth menu is on the middle-click.
- **First menu open after login**: shows only known devices, because the
  background scan is just starting. Reopen it shortly after.
- **Weather hook needs DISPLAY**: the user path/service can only reach
  herbstclient if the session environment was imported. Early in the autostart:
  `systemctl --user import-environment DISPLAY XAUTHORITY`. Check with
  `systemctl --user show-environment | grep DISPLAY`.
- **herbstclient path in user units**: the user systemd PATH does not include
  herbstclient, so reference the absolute store path in `ExecStart`, not a bare
  command.

## Files

```
panel.sh                 Main script: sources libs, runs generator + data handling, calls dzen2
lib/event_generator.sh   The event_generator function (listeners + clock loop)
lib/volume.sh            Volume: event/read/format
lib/bat.sh               Battery: detection + event/status
lib/brightness.sh        Brightness: read/event/format
lib/media.sh             Media: event/format (event unused since --follow)
lib/weather.sh           Weather: event/read/format (read used by the refresh hook)
lib/bluetooth.sh         Bluetooth: read/event/format
lib/bt_menu.sh           rofi menu for bluetooth devices
lib/network.sh           Network block (work in progress, not yet integrated)
```

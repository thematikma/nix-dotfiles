# herbstluftwm dzen2 Panel

A modular status panel for herbstluftwm built on dzen2. Each information source
(volume, brightness, battery, media, weather, bluetooth) lives in its own
library under `lib/` and is sourced by `panel.sh`. The panel is fully
event-driven: every source that can push events runs as a persistent listener,
and the only periodic timer left is the clock.

> **Portability note:** this panel was originally developed on NixOS and later
> ported to Fedora. The libraries are now hardened to run unmodified on Arch,
> Debian/Ubuntu, RHEL/Fedora, and NixOS: every source self-disables when its
> tool or hardware is absent, so the same files work on a laptop with battery,
> brightness and bluetooth and on a desktop without any of them. See
> [Cross-distro portability](#cross-distro-portability) and
> [Fedora migration notes](#fedora-migration-notes).

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

### The event loop must always reach `hc --idle`

A subtle but critical invariant: the generator runs a handful of **synchronous**
`*_event` calls at startup (for initial values), then spawns the persistent
listeners in the background, and finally blocks on `hc --idle` in the
**foreground**. That foreground `hc --idle` is what delivers every herbstclient
hook (`volume_refresh`, `brightness_refresh`, `weather_refresh`, `bt_refresh`)
into the pipe.

If any synchronous startup step *blocks* (e.g. `bluetoothctl show` on a machine
with no adapter, or a tool that hangs), the function never reaches `hc --idle`,
and **no hooks ever reach the panel** — initial values appear once, the clock
keeps ticking, but nothing event-driven updates until a full reload re-runs the
init calls. For this reason every initial `*_event` call and every listener is
guarded so a missing tool or absent hardware can never stall the path to
`hc --idle`. (This was the root cause of the "volume only updates on reload"
bug seen right after the Fedora migration.)

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

Every source in this table is optional: if its tool or hardware is missing, the
generator skips both its initial event and its listener, and the widget simply
does not appear.

## Design notes and the path to fully event-driven

The original panel queried all sources once per second from a single loop,
spawning roughly a dozen external processes every second. Over time each source
was moved to the most appropriate mechanism. The main gain is responsiveness and
a clean, uniform architecture rather than measurable CPU or RAM savings; the one
real efficiency point is fewer timer wakeups on battery.

### Date

The only remaining timed loop (1 s). It is fork-free (`printf '%(...)T'` and the
`sleep` builtin), so it costs practically no process spawns. The `sleep` builtin
is loaded by `enable_sleep_builtin` in `lib/util.sh`, which probes several
distro-specific locations (and the Nix store path) and falls back to external
`sleep` if none is found — one fork per second, harmless. See
[lib/util.sh](#libutilsh-cross-distro-helpers).

### Media

`playerctl --follow metadata --format` stays open and emits a line only on a
track or status change. The `med\t` prefix is embedded in the format string,
which removes the detour through `media_event`. The listener is only spawned
when `playerctl` is installed.

### Bluetooth

`lib/bluetooth.sh` plus `lib/bt_menu.sh`. Panel display: always `BLT:`.

- **Left-click**: toggles the adapter on/off (`bluetoothctl power on|off`).
  Off is dimmed; on is shown in `color_fg`, with the first connected device
  shown after `BLT:`.
- **Middle-click** (only when on): opens a rofi menu (see below).

The listener keeps `bluetoothctl` in interactive mode so it prints `[CHG]`
lines, and keeps stdin open so it does not exit early. It is only started when
`bluetoothctl` exists **and** an adapter is actually present (`bluetoothctl
list` returns something) — on a desktop with no radio it is skipped entirely, so
it can neither block startup nor spawn a dead pipe:

```bash
if command -v bluetoothctl >/dev/null 2>&1 \
   && bluetoothctl list 2>/dev/null | grep -q .; then
    { echo; sleep infinity; } | stdbuf -oL bluetoothctl 2>/dev/null \
        | grep --line-buffered -E 'Connected: (yes|no)|Powered: (yes|no)' \
        | while read -r _ ; do bt_event ; done > >(uniq_linebuffered) &
fi
```

`bt_read` itself also bails out fast when no adapter is present, so the initial
`bt_event` cannot block the path to `hc --idle`.

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
on connect. The listener is only started when `pw-mon` is installed.

```bash
stdbuf -oL pw-mon 2>/dev/null \
    | grep --line-buffered -i 'volume' \
    | while read -r _ ; do volume_event ; done > >(uniq_linebuffered) &
```

`pw-mon` also fires on track changes; the unchanged `vol` line is dropped by
`uniq_linebuffered`.

**Locale-safe parsing (important).** `wpctl get-volume` prints e.g.
`Volume: 0.65`. The parsing in `lib/volume.sh` is now **pure bash** — it splits
the `0.NN` float on the dot and assembles the integer percent by hand, with no
`awk` and no subprocess. This was a real bug after the Fedora move: the previous
`awk '{ printf "%d", $2 * 100 }'` is locale-sensitive, and under a
comma-decimal locale (e.g. `de_DE.UTF-8`) `awk` parsed `0.65` as `0`, producing
frozen/garbage percentages. The pure-bash parser is immune to locale:

```bash
# "Volume: 0.65 [MUTED]" -> vol_pct=65, vol_muted=yes
_vol_parse() {
    local raw=$1
    [ -n "$raw" ] || return 1
    local f=${raw#* }; f=${f%% *}        # second token -> "0.65"
    local int=${f%%.*} frac
    [[ $f == *.* ]] && frac=${f#*.} || frac=""
    frac=${frac}00; frac=${frac:0:2}     # hundredths, padded
    int=$((10#${int:-0})); frac=$((10#$frac))
    vol_pct=$(( int * 100 + frac ))
    [[ $raw == *"[MUTED]"* ]] && vol_muted="yes" || vol_muted="no"
}
```

### Brightness

`lib/brightness.sh` only reads a real **backlight-class** device. On a desktop
there is no backlight, and `brightnessctl` with no `-d` defaults to the first
device it finds — often a NIC or keyboard LED in class `leds` (e.g.
`enp5s0-3::lan ... 0%`), which previously showed up as a bogus stuck `bri: 0%`.
The library now picks the first `class==backlight` device from
`brightnessctl -lm` and renders nothing when none exists:

```bash
_BRI_DEV=$(brightnessctl -lm 2>/dev/null \
    | awk -F, '$2=="backlight"{print $1; exit}')
```

`brightness_read`/`brightness_event` return non-zero when there is no backlight,
so the widget disappears cleanly on a desktop. On a laptop it works as before.

### Battery

Event-based via upower. `upower --monitor` is used purely as a bell: on any
notification, `battery_event` re-reads the actual values from sysfs (the logic
in `lib/bat.sh` is unchanged; upower is only the trigger). The listener is only
started when `upower` is installed **and** a battery exists (`$BATTERY` set), so
a desktop neither shows the widget nor spawns the listener.

Battery detection lives in `lib/bat.sh` and auto-detects the first
`/sys/class/power_supply/BAT*` (override via `BATTERY=BAT1`). `battery_event`
returns early when no battery is present, so the initial call is safe.

Note: `upower --monitor-detail` always prints the full device block (including
`percentage:` and `state:`) on every event, even on irrelevant voltage jitter,
so filtering those fields does not actually reduce triggers; `uniq_linebuffered`
plus the sysfs re-read absorb the rest.

### Weather

The data comes from a cache file that a systemd timer fills hourly. `weather.sh`
just reads that cache, so it is safe even before the fetcher is set up (it
renders nothing while the cache is absent).

The fetch service is a **system** unit (it only needs the network, not the X
session). On NixOS this was expressed declaratively; on Fedora the equivalent is
a pair of systemd units (system timer + service to fetch, user path unit to emit
the hook). The original Nix expressions are kept here for reference:

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

On Fedora the same two units are written as plain `~/.config/systemd/user/`
(and system) unit files; the logic is identical. The chain is: system timer ->
fetch service writes cache -> user path unit sees the change -> emits
`weather_refresh` -> panel re-reads via `weather_read`. The updater writes the
file directly (`printf ... > "$cache"`), which triggers `PathChanged`. If you
ever switch to atomic writes (temp file plus `mv`), use `PathModified` or watch
the directory instead.

## lib/util.sh (cross-distro helpers)

`lib/util.sh` is a **library of definitions only** — sourcing it runs nothing;
you call the helpers explicitly where you want them. Source it once in
`panel.sh` (and, for `start_picom`, once in the hlwm autostart).

- **`enable_sleep_builtin`** — loads bash's loadable `sleep` builtin to avoid
  forking `sleep` once per second in the date loop. Replaces the old
  Debian-specific `/usr/lib/bash/sleep` literal; probes `/usr/lib/bash/sleep`,
  `.../sleep.so`, `/usr/local/lib/bash/sleep`, and the bash store path (NixOS),
  then falls back to external `sleep`. Call once in `panel.sh`:
  ```bash
  source "$script_dir/lib/util.sh"
  enable_sleep_builtin
  ```
- **`panel_selfcheck`** — prints the panel's PATH and which tools resolve to
  **stderr** (never to dzen). Gate it on an env var so it stays silent normally:
  ```bash
  [ -n "$PANEL_DEBUG" ] && panel_selfcheck
  ```
  Run the panel from a terminal as `PANEL_DEBUG=1 ./panel.sh 0` to read it. This
  is the fastest way to diagnose the NixOS "tool works in my shell but the panel
  says MISSING" trap — the panel's PATH can differ from your login shell.
- **`start_picom`** — bring up picom only if nothing already manages it
  (idempotent). Used on systems with no picom service, e.g. Fedora. Skips if a
  `picom.service` user unit is active or picom is already running, otherwise runs
  `picom -b`. Call from the **hlwm autostart**, not `panel.sh`:
  ```bash
  source ~/.config/herbstluftwm/lib/util.sh
  start_picom
  ```
- **`restart_picom`** — force a clean restart (`pkill picom; sleep 0.2; picom
  -b`). Deliberately **not** called at startup (it causes a repaint flash and
  can race a service-managed picom). Bind it to a key instead:
  ```bash
  herbstclient keybind $Mod-Shift-c spawn bash -c \
    'source ~/.config/herbstluftwm/lib/util.sh; restart_picom'
  ```

On NixOS, `services.picom.enable = true` creates a user unit, so `start_picom`
correctly does nothing and lets systemd manage it. On Fedora (no unit) it starts
picom itself. Same snippet, no per-distro branching.

## Play/pause on the headset

The headset's play/pause button sends AVRCP, which BlueZ forwards over MPRIS,
the interface `playerctl` listens on. If it does not work out of the box, enable
the AVRCP-to-MPRIS bridge:

```bash
systemctl --user enable --now mpris-proxy
```

## Cross-distro portability

The scripts are written to run unmodified on Arch, Debian/Ubuntu, RHEL/Fedora,
and NixOS. What makes that work, and what to watch for:

- **Tool/hardware guards.** Every source checks `command -v <tool>` (and, where
  relevant, that the hardware exists) before its init call and before spawning
  its listener. A missing tool means the widget is simply absent — never a crash
  and never a dead pipe. This is what lets a desktop run the same files as a
  laptop.
- **awk flavor.** Debian/Ubuntu default to **mawk**, the others to **gawk**.
  `panel.sh` already branches on this for `uniq_linebuffered` (mawk needs
  `-W interactive` for line buffering; gawk warns about it).
- **PATH scope on NixOS (the big one).** The panel is spawned from the hlwm
  autostart, whose environment can have a different PATH than your interactive
  shell. A tool can be installed yet invisible to the panel, in which case the
  guards correctly hide its widget and you might think the script is broken.
  `PANEL_DEBUG=1 ./panel.sh 0` plus `panel_selfcheck` shows exactly what the
  panel sees. Fix by importing the session environment early in autostart or by
  ensuring the tools are on the autostart's PATH.
- **sleep builtin path** differs per distro and is handled by
  `enable_sleep_builtin` (see above).
- **picom** may or may not be service-managed; `start_picom` handles both.

## Fedora migration notes

Specific things that came up moving this setup from NixOS to Fedora:

- **Volume showed frozen/garbage percentages.** Locale issue in the old
  `awk` float parse; fixed by the pure-bash parser in `lib/volume.sh` (see
  [Volume](#volume)). Symptom was values unrelated to `wpctl status` that only
  changed on `herbstclient reload`.
- **Volume only updated on reload.** The unconditional bluetooth/brightness
  init calls in the old generator stalled the path to `hc --idle`, so hooks
  never reached the panel. Fixed by guarding every init call and listener (see
  [The event loop must always reach `hc --idle`](#the-event-loop-must-always-reach-hc---idle)).
- **Brightness showed a stuck `bri: 0%`.** `brightnessctl` was reporting a NIC
  LED, not a backlight. Fixed by reading only `class==backlight` devices (see
  [Brightness](#brightness)). On this desktop the brightness widget is now
  correctly absent.
- **No picom service on Fedora.** Started from the hlwm autostart via
  `start_picom` (see [lib/util.sh](#libutilsh-cross-distro-helpers)).
- **Bitmap fonts for the title/panel XLFDs were missing.** The panel and the
  hlwm `title_font` use old-style XLFDs like
  `-adobe-helvetica-medium-r-normal--…`. Fedora does not ship the Adobe
  Helvetica bitmaps by default, so the title rendered as dashed tofu boxes (the
  font loaded but lacked glyphs / the requested encoding did not exist). Install
  the X bitmap font packages:
  ```bash
  sudo dnf install xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi
  ```
  After installing, confirm the exact XLFD resolves (the encoding suffix is part
  of the match — the available variants here are `iso10646-1`, not `iso8859-1`):
  ```bash
  xlsfonts | grep -i 'helvetica.*-14-'
  ```
  Use a variant that actually appears in that list (e.g.
  `-adobe-helvetica-medium-r-normal--14-100-100-100-p-76-iso10646-1`).

### Optional future change: Xft fonts in the panel

The panel currently keeps the Helvetica XLFD. If you ever want a scalable Xft
font (e.g. DejaVu Sans) in the panel, note the catch found during migration:

- Fedora's `dzen2` **is** built with Xft (`dzen2 -fn 'xft:DejaVu Sans:pixelsize=18'`
  renders fine), **but** its `dzen2-textwidth` gadget is **not** — and cannot be,
  because the upstream `gadgets/textwidth.c` contains no Xft code at all (it uses
  X-core `XFontStruct`/`XmbTextExtents` only). Rebuilding it with Xft flags does
  not help; the source has no Xft path.
- The panel needs a width measurement to center the right block
  (`^pa((panel_width - width) / 2)`). With an Xft font, `dzen2-textwidth`
  returns an error instead of a number, `width` goes empty, and the centering
  arithmetic aborts the whole panel.
- Workaround if pursued: a small Pango/cairo helper
  (`lib/textwidth-xft.py`) used as the `textwidth` tool, ideally with a
  cache so Python is only invoked when the visible text actually changes
  (otherwise it runs on every clock tick). Render size and measure size must
  match exactly (`xft:DejaVu Sans:pixelsize=18` ↔ `DejaVu Sans 18px`).

This is deferred for now; the XLFD path works once the bitmap fonts are
installed.

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

Core (always needed):

- `herbstluftwm`, `dzen2` (with clickable-area support), `awk`
- a dzen2 `textwidth` tool (`textwidth`, `dzen2-textwidth`, or `xftwidth`)
- the X bitmap fonts for the XLFD title/panel font, on distros that don't ship
  them: `xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi` (Fedora)

Optional (each widget self-disables if its tool/hardware is absent):

- `wpctl` / WirePlumber and `pw-mon` (PipeWire) for volume
- `playerctl` for media
- `brightnessctl` for brightness (only renders with a real backlight)
- `upower` (service enabled) for battery events (only with a battery present)
- `bluetoothctl` (BlueZ) and `rofi` for bluetooth (only with an adapter)
- `picom` for compositing (started by `start_picom` if not service-managed)
- `python3` with `python3-gobject` + `python3-cairo` only if you adopt the
  optional Xft panel font (see above)
- `nmcli` (NetworkManager) for the upcoming network block

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
  herbstclient, so reference the absolute path in `ExecStart`, not a bare
  command.
- **XLFD encoding suffix matters**: `…-iso8859-1` and `…-iso10646-1` are
  different fonts to the X server. If the title renders as dashed boxes, the
  exact XLFD (including the suffix) probably does not exist; check `xlsfonts`.
- **Panel dies on font change**: if `dzen2-textwidth` can't measure the
  configured font it returns nothing, `width` is empty, and the centering
  arithmetic aborts. Keep a measurable font, or guard with
  `[ -z "$width" ] && width=0`.
- **NixOS: widget missing though the tool is installed**: almost always a PATH
  scope difference in the panel's spawn environment. Use `PANEL_DEBUG=1` +
  `panel_selfcheck`.

## Files

```
panel.sh                 Main script: sources libs, runs generator + data handling, calls dzen2
lib/util.sh              Cross-distro helpers: enable_sleep_builtin, panel_selfcheck, start_picom, restart_picom
lib/event_generator.sh   The event_generator function (guarded listeners + clock loop)
lib/volume.sh            Volume: pure-bash parse + event/read/format
lib/bat.sh               Battery: detection + event/status
lib/brightness.sh        Brightness: backlight-only read/event/format
lib/media.sh             Media: event/format (event unused since --follow)
lib/weather.sh           Weather: event/read/format (read used by the refresh hook)
lib/bluetooth.sh         Bluetooth: read/event/format
lib/bt_menu.sh           rofi menu for bluetooth devices
lib/network.sh           Network block (work in progress, not yet integrated)
lib/textwidth-xft.py     Optional Pango/cairo width helper (only if adopting Xft panel font)
```

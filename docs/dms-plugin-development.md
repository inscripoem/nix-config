# DMS plugin development notes (dux-shell 2.0 "Heisenberg")

Hard-won lessons from building the in-repo plugins (`onedrive-sync`,
`argb-fans`) against dux-shell 2.0.0, 2026-10. Every rule below was paid
for with at least one failed deploy. Verify against the shell you
actually run — see the first section for how.

## The embedded QML is the only API truth

The nixpkgs `dux-shell` package ships only the Go CLI; the QML shell is
embedded in `bin/.dms-wrapped` (~85 MB). The GitHub `main` of
`duxlabs-dev/dux-qml-common` can be ahead of what your shell embeds:
`DDropdown` on `main` has `optionValues` (label→key mapping), while the
2.0.0 embedded copy speaks label-string semantics only — assigning
`optionValues` makes the whole plugin fail to load with `Cannot assign
to non-existent property`.

To check what your shell actually supports, extract the component API
from the binary instead of trusting docs or `main`:

```sh
python3 - <<'EOF'
import re
data = open("/run/current-system/sw/bin/dms", "rb").read()  # resolve wrapper to .dms-wrapped
for m in re.finditer(rb'property\s+\w+\s+\w*[Ww]idth\w*', data):
    ...  # dump context windows, grep for the component of interest
EOF
```

## Popout width accounting

`popoutWidth` is the **window** width. The shell's `DPopout` insets
`PopoutMetrics.contentPadding` (16px in 2.0.0) on both sides before
your content lands, and your own container margins subtract again:

```
popoutWidth 400  →  visible card 368  →  content area 344 (12px margins)
popoutWidth 380  →  visible card 348  →  content area 324
```

A `RowLayout`'s minimum width is the **sum of its children's minimum
widths plus spacing**. Rows that mix fixed-size items (chips, a picker)
are hard floors: hand-budget them under the content area. In
`argb-fans` the color row floor is `180 (picker) + 12 (spacing) +
136 (two 64px scope chips + 8 gap) = 328`; at `popoutWidth: 380` the
324px budget was exceeded by 4px and **every fillWidth child in the
column was laid out at the implicit 328 and clipped at 324** — the
symptom was "the right edge of Off is cut" and "the restore text is
off-center", which survived four wrong fixes. Prefer widening the
popout (`400` is the shell's own default) over shrinking content.

Debugging rule: never diagnose layout from screenshots. Drop
`console.info("[tag]", width)` probes on each container and read
`journalctl --user -u dms.service`; `implicitWidth > width` on a
container is the overflow signature. Remove the probes before
committing.

## Widget sizing quirks

- `DButton` (ex `DankButton`) pins its implicit width as an internal
  minimum; an external `Layout.minimumWidth: 0` cannot override it. A
  single `DButton` per row is fine; **two side-by-side fillWidth
  DButtons overflow a narrow popout**. When a row must share width, use
  `StyledRect` + `MouseArea` pills (implicit width ≈ 0, shrinks freely),
  styled `Theme.primary` / `Theme.onPrimary` to match the filled look.
- Every `fillWidth` leaf widget should still carry
  `Layout.minimumWidth: 0`.
- Full-pill radius (`height / 2`) on dark themes reads as a straight
  cut at the right edge; `Theme.cornerRadius` reads as a real border.
- Plain (non-Layout) positioning containers like the popout's outer
  column ignore `Layout.*` attached properties on their children;
  children there need explicit `width: parent.width`.

## Long-lived child processes

`Quickshell.Io.Process` `running = false` does **not** reliably kill
Python children. Five orphaned `anim-daemon` processes ended up
fighting over the same USB controller and wedging every command — the
"cannot switch away from meteor, off does nothing" state. Stop
long-lived children through a dedicated reaper `Process` running
`pkill -f` keyed on a store path (bracket trick — `ene-fanctl
[a]nim-daemon` — so the pattern cannot match its own shell), then
dispatch the follow-up action (off / fill / next daemon) from that
process's `onExited`, never speculatively.

## State persistence: persist desire, re-apply on start

Plugin settings (`pluginData`) are read-only inside widgets, so the
widget owns a plain state file (`~/.local/state/<plugin>/`). The model
that works: **persist the desired state and re-apply it when the shell
starts**, letting reality catch up (re-stroke static fills that faded,
relaunch the animation daemon the shell restart killed, replay an
explicitly chosen fan duty).

Two traps we hit:

- Deriving "on/off" from a hardware probe instead of the state file
  breaks persistence: animation daemons park the LEDs black when the
  shell's cgroup reaps them, so every dms restart read as "off".
- Never persist values observed from hardware by polling. The fan poll
  reads the BIOS/EC curve baseline (61%); replaying a polled baseline
  would silently swap the EC's temperature curve for a fixed duty at
  boot. Persist only values that originate from explicit user actions
  (the fan duty token is written exclusively by the slider/default
  button path).

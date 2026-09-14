# CreateExecutorsFromCSV

A grandMA2 Lua plugin that batch-creates executors and timecode
objects from a CSV list of names — instead of running a manual
"create item" plugin by hand once per item.

Built originally for a dance showcase running 40+ sequences on a physical
grandMA2 console, where each number needed its own executor, cue, and
timecode object with matching setup/teardown macros. Doing that by
hand for dozens of items is slow and error-prone; this script does it
in one pass from a spreadsheet export. The pattern generalizes to
anything that maps to "one executor + one timecode object per named
item" — recital numbers, scenes, chapters, race legs, segments,
whatever your show or event breaks into.

## What it does

For each row in a CSV of item names, the plugin runs:

```
Store Executor <exec>
Label Executor <exec> "<name>"
Assign Executor <exec> Cue 1 /cmd="Macro 3; SetVar $item=<n>; Macro 4"
Select Executor <exec>
Move Cue 1 At 0.1
Store Cue 0.5
Store Timecode <n>
Label Timecode <n> "<name>"
Assign Timecode <n> /Offset=<timecodeOffset>
```

...auto-incrementing the item/timecode number and executor number as
it goes.

It also:
- **Sanitizes names** — strips leading bracket tags like `[A]` / `[B]`
  / `[Special]`, drops a trailing `- Note` suffix, and replaces
  characters that break grandMA2 command-line parsing (`& * / \ ; % "`).
  Both of these transforms are easy to remove in the script if your
  list doesn't use that convention.
- **Wraps executors across fader pages** — addresses executors as
  `page.executor` (e.g. `2.1`) once the count exceeds your console's
  physical faders per page, and pauses with a confirm dialog at each
  page boundary so you can physically move to the next page.
- **Applies a timecode offset** to each item, so its timecode show
  only starts once incoming MTC/SMPTE reaches a given point (useful
  when everything shares one long timecode source).
- **Logs progress** to the System Monitor every 5 items, plus a final
  summary of the executor/timecode range created.

## Files

| File | Purpose |
|---|---|
| `plugins/CreateExecutorsFromCSV.lua` | Main plugin — reads the CSV and builds the executors/timecodes |
| `plugins/CreateExecutorsFromCSV.xml` | Plugin manifest for importing into grandMA2 |
| `plugins/FindCSVPath.lua` | Diagnostic — finds the exact filesystem path your console uses for USB files |
| `plugins/FindCSVPath.xml` | Manifest for the diagnostic plugin |
| `sample-data/items-sample.csv` | Example CSV showing the expected format |

## Setup

### 1. Find your console's USB mount path (do this first)

grandMA2's Lua `io.open()` reads files by raw filesystem path, which is
**not** the same as the path shown in the Import dialog's file browser,
and it can differ by console or even by session (e.g. `/media/sdb1` one
day, `/media/sdc1` the next).

1. Edit `FindCSVPath.lua`: set `knownPath` to a file you know exists —
   easiest is to use the exact path your console prints in the command
   line feedback when you import `FindCSVPath.xml` itself.
2. Put your actual CSV filename into the `candidates` list (a few
   likely folder paths are pre-filled — add your own mount point).
3. Copy both `FindCSVPath.lua` and `FindCSVPath.xml` onto your USB
   stick's `gma2/plugins/` folder, import the `.xml` on the console,
   and run it (`Plugin <index>`, then confirm).
4. Open **System Monitor** (tap an empty area ≥2×2, tap **System**, tap
   **System Monitor**) and look for a `FOUND:` line — that's your
   working path.

### 2. Prepare your CSV

One item name per line, optionally with a header row (`Item Name`,
`Name`, `Title`, or `Song Name` — auto-detected and skipped). See
`sample-data/items-sample.csv` for the format. If your list uses
bracket tags or a `- suffix` convention, those are stripped
automatically; if not, just delete the two `sanitizeName` blocks that
handle them.

### 3. Configure `CreateExecutorsFromCSV.lua`

Edit the constants at the top of `main()`:

```lua
local csvFolder      = "/media/sdb1/items/"  -- from step 1
local startItem      = 1                     -- first item/timecode number
local startExec      = 1                     -- first executor number
local execsPerPage   = 15                    -- physical faders per page
local timecodeOffset = "1h"                  -- e.g. "1h", "30m"
```

If you've already created some items manually, set `startItem` /
`startExec` above whatever numbers are already in use so this script
doesn't overwrite them.

### 4. Create the required macros

The script assumes **Macro 3** (per-item init) and **Macro 4** (reset)
already exist on the console — create them ahead of time, or edit the
`Assign Executor ... Cue 1 /cmd=` line in the script to inline whatever
setup/teardown your show actually needs. If you don't need per-item
macros at all, delete that line and the ones it depends on.

### 5. Import and run

```
Import "CreateExecutorsFromCSV" At Plugin <slot>
Plugin <slot>
```

You'll be prompted for a CSV filename (with or without the `.csv`
extension — it's read from `csvFolder`). Progress prints to System
Monitor every 5 items; at each fader page boundary you'll get a
Yes/No prompt to move pages before it continues.

## Adapting it to your own use case

This script's real value is the loop structure and the console-specific
lessons baked into it (page-aware executor addressing, name
sanitization, pacing to avoid DMX overload, USB path discovery) — the
per-item command sequence itself is easy to swap out. If you don't
need timecode objects at all, or want a different cue structure per
item, edit the body of the `for i, itemname in ipairs(items) do` loop
and leave everything else as-is.

## Known limitations

- The timecode offset behavior (`/Offset=`) has not been fully
  verified against every console firmware version — check it against
  a small test run before relying on it for a full show.
- Executor button mapping (Select / ToZero / ToFull) is hardcoded to
  match one show's convention — adjust the `Assign Select/ToZero/ToFull
  ExecButton...` lines if your show uses different key behavior.
- Macros 3/4 must exist beforehand; the script doesn't create or
  verify them.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `could not open` error for the CSV | `csvFolder` or the USB mount point no longer matches reality | Re-run `FindCSVPath.lua` and update `csvFolder` |
| Repeated confirmation popups mid-run | `Store`/`Assign`/`Move` colliding with existing objects from a prior partial run | Already mitigated with `/o /nc` flags — clear any duplicate objects if it still happens |
| `EncodeDMX::Reached Packet Sendlimit` | Rapid-fire commands across many executors outrunning the console's DMX/network output stage | A `gma.sleep(0.1)` pause already runs after each item; increase it if this recurs |
| Script stops after 15 executors | Flat executor numbers beyond a page's fader count aren't addressable without a page prefix | Already handled via `page.executor` addressing — adjust `execsPerPage` to match your console |

## License

MIT — see [LICENSE](LICENSE).

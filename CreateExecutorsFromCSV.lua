--[[
  CreateExecutorsFromCSV.lua
  grandMA2 Lua plugin

  Author: Jai hao Wu (with help from Claude)

  Batch-creates one executor + timecode object per row of a CSV list.
  Originally built to set up dozens of dance-recital cues by hand, one
  at a time, via a manual "create item" plugin - this automates that
  same per-item sequence in a loop, reading names from a CSV instead
  of prompting for each one individually.

  Works for anything that maps to "one executor + one timecode object
  per named item": recital numbers, scenes, chapters, stations,
  segments - whatever your show/event breaks into.

  Per item, it runs:
    Store Executor <exec>
    Label Executor <exec> "<name>"
    Assign Executor <exec> Cue 1 /cmd="Macro 3; SetVar $item=<n>; Macro 4"
    Select Executor <exec>
    Move Cue 1 At 0.1
    Store Cue 0.5
    Store Timecode <n>
    Label Timecode <n> "<name>"
    Assign Timecode <n> /Offset=<timecodeOffset>

  CONFIG - adjust for your show (see the top of main()):
    csvFolder      - folder on the USB stick containing your CSV
    startItem      - first item/timecode number to assign
    startExec      - first executor number to assign
    execsPerPage   - physical faders per page on your console
    timecodeOffset - how far to shift each item's timecode show,
                     e.g. so it only starts once incoming MTC/SMPTE
                     reaches a given point

  If you've already created some items manually, set startItem /
  startExec above whatever numbers are already in use so this script
  doesn't overwrite them.

  Macros referenced: this script assumes Macro 3 and Macro 4 already
  exist on the console (per-item init / reset). Create them ahead of
  time, or adapt the Assign line below to inline whatever setup/
  teardown commands your show actually needs.

  Requires FindCSVPath.lua to confirm your console's USB mount point
  first - see the README for setup instructions.
--]]

function main()

  ------------------------------------------------------------------
  local csvFolder      = "/media/sdb1/items/"  -- adjust to match your USB mount point
  local startItem      = 1
  local startExec      = 1
  local execsPerPage   = 15    -- physical faders per page on this console; adjust if different
  local timecodeOffset = "1h"  -- shifts each item's timecode show forward, so it only
                                -- starts once incoming MTC/SMPTE reaches this point
  ------------------------------------------------------------------

  local csvFilename = gma.textinput("CSV filename (in items folder)", "")
  if not csvFilename or csvFilename == "" then
    gma.echo("CreateExecutorsFromCSV: no filename entered - aborting.")
    return
  end
  -- allow entering the name with or without the .csv extension
  if not csvFilename:match("%.csv$") then
    csvFilename = csvFilename .. ".csv"
  end
  local csvPath = csvFolder .. csvFilename

  local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
  end

  local function stripBOM(s)
    if s:byte(1) == 0xEF and s:byte(2) == 0xBB and s:byte(3) == 0xBF then
      return s:sub(4)
    end
    return s
  end

  -- Characters that can break grandMA2 command-line parsing (quotes end
  -- a quoted string, & is a logical operator, * is a wildcard, / starts
  -- an option, \ is an escape, ; separates chained commands, % can be
  -- read as a variable/format marker). Strip or replace them so names
  -- are always safe to embed in a command string.
  local function escapeMagic(c)
    return c:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  end

  local function sanitizeName(s)
    -- Drop a leading bracket tag like "[P] " or "[Board Dance] " -
    -- remove this block entirely if your list doesn't use tags.
    s = s:gsub("^%[[^%]]*%]%s*", "")

    -- Keep only the portion before the first " - " (drops a
    -- "- Artist"/"- Notes" suffix, which is also where most forbidden
    -- characters like & and / tend to show up). Remove this block if
    -- you want to keep full row text as-is.
    local title = s:match("^(.-)%s%-%s")
    if title and title ~= "" then
      s = title
    end

    local replacements = {
      { char = "&",  repl = "and" },
      { char = "*",  repl = "" },
      { char = "/",  repl = "-" },
      { char = "\\", repl = "-" },
      { char = ";",  repl = "," },
      { char = "%",  repl = "pct" },
      { char = '"',  repl = "'" },
    }
    local result = s
    for _, r in ipairs(replacements) do
      result = result:gsub(escapeMagic(r.char), r.repl)
    end
    result = result:gsub("%s%s+", " ")  -- collapse doubled spaces left by removals
    return trim(result)
  end

  local file, err = io.open(csvPath, "r")
  if not file then
    gma.echo("CreateExecutorsFromCSV: could not open '" .. csvPath .. "' (" .. tostring(err) .. ")")
    return
  end

  local items = {}
  local lineNum = 0
  for rawLine in file:lines() do
    lineNum = lineNum + 1
    local line = trim(stripBOM(rawLine))
    if line ~= "" then
      -- use only the first comma-separated field, in case the CSV
      -- ever gains extra columns
      local firstField = trim(line:match("^[^,]*") or line)
      local lower = firstField:lower()
      local isHeader = (lineNum == 1) and
        (lower == "name" or lower == "item" or lower == "item name" or
         lower == "title" or lower == "song name")
      if not isHeader then
        table.insert(items, sanitizeName(firstField))
      end
    end
  end
  file:close()

  if #items == 0 then
    gma.echo("CreateExecutorsFromCSV: no items found in '" .. csvPath .. "'.")
    return
  end

  gma.echo("CreateExecutorsFromCSV: found " .. #items .. " items. Building...")

  for i, itemname in ipairs(items) do
    local newItem = startItem + (i - 1)
    local safeName = itemname  -- already sanitized when read from CSV

    -- Convert a flat 1-based executor count into "page.executor" so it
    -- wraps to the next page once it exceeds this console's physical
    -- faders per page, instead of trying to address a non-existent
    -- flat executor number beyond page 1.
    local globalExecNum = startExec + (i - 1)
    local page = math.ceil(globalExecNum / execsPerPage)
    local localExec = globalExecNum - (page - 1) * execsPerPage
    local executor = page .. "." .. localExec

    gma.cmd("Store Executor " .. executor .. " /o /nc")
    gma.cmd("Label Executor " .. executor .. " \"" .. safeName .. "\"")

    -- Executor keys default to Off (ExecButton1) / On (ExecButton2) /
    -- Go (ExecButton3). Overridden here to: Select (bottom), ToZero
    -- (middle), ToFull (top). Adjust to taste, or delete these three
    -- lines to keep the defaults.
    gma.cmd("Assign Select ExecButton1 " .. executor)
    gma.cmd("Assign ToZero ExecButton2 " .. executor)
    gma.cmd("Assign ToFull ExecButton3 " .. executor)

    gma.cmd("Assign Executor " .. executor .. " Cue 1 /cmd=\"Macro 3; SetVar $item=" .. newItem .. "; Macro 4\" /nc")
    gma.cmd("Select Executor " .. executor)
    gma.cmd("Move Cue 1 At 0.1 /o /nc")
    gma.cmd("Store Cue 0.5 /o /nc")
    gma.cmd("Store Timecode " .. newItem .. " /o /nc")
    gma.cmd("Label Timecode " .. newItem .. " \"" .. safeName .. "\"")
    gma.cmd("Assign Timecode " .. newItem .. " /Offset=" .. timecodeOffset .. " /nc")

    gma.sleep(0.1)  -- brief pause so DMX/network output isn't overwhelmed across many stores

    -- Lightweight progress feedback via System Monitor instead of the
    -- gui.progress widget (its handle-based API threw "LUA API Syntax
    -- error" on every call on this console build - not worth chasing
    -- since it's purely cosmetic).
    if i % 5 == 0 or i == #items then
      gma.echo("CreateExecutorsFromCSV: " .. i .. " / " .. #items .. " done (" .. executor .. " - " .. safeName .. ")")
    end

    -- Pause at every page boundary so you can physically move to the
    -- next fader page before the script keeps going.
    local isLastOnPage = (localExec == execsPerPage)
    local moreToGo = (i < #items)
    if isLastOnPage and moreToGo then
      local ok = gma.gui.confirm(
        "Page " .. page .. " done",
        "Move to fader page " .. (page + 1) .. ", then press Yes to continue."
      )
      if not ok then
        gma.echo("CreateExecutorsFromCSV: stopped by user after page " .. page ..
          " (" .. i .. " / " .. #items .. " items created).")
        return
      end
    end
  end

  local firstExecPage = math.ceil(startExec / execsPerPage)
  local firstExecLocal = startExec - (firstExecPage - 1) * execsPerPage
  local lastGlobalExec = startExec + #items - 1
  local lastExecPage = math.ceil(lastGlobalExec / execsPerPage)
  local lastExecLocal = lastGlobalExec - (lastExecPage - 1) * execsPerPage
  gma.echo("CreateExecutorsFromCSV: created " .. #items .. " items. Timecode " ..
    startItem .. "-" .. (startItem + #items - 1) .. ", Executors " ..
    firstExecPage .. "." .. firstExecLocal .. " thru " .. lastExecPage .. "." .. lastExecLocal .. ".")
end

return main

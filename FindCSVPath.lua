--[[
  FindCSVPath.lua
  grandMA2 Lua plugin - diagnostic only

  Run this FIRST, before CreateExecutorsFromCSV.lua, to figure out the
  exact filesystem path your physical console uses to reach files on
  a USB stick via Lua's io.open(). This path is NOT the same as the
  "Import" dialog's file browser, and it varies by console/session
  (e.g. /media/sdb1 one day, /media/sdc1 the next), so guessing wastes
  time - this script finds it empirically instead.

  Two-part test:
   1) Tries to open this very file (FindCSVPath.xml) at the exact path
      the console's own import log showed when you imported it (check
      the command line feedback after importing - it prints the full
      path it read from). Edit `knownPath` below to match that path.
      If this succeeds, io.open works fine at that location, and your
      CSV is simply missing or misnamed there.
      If this fails, io.open can't reach that folder via raw paths at
      all (even though Import can) - a different approach is needed.
   2) Tries a list of candidate paths for your actual CSV file, and
      prints the ACTUAL error io.open returns for each one (not just
      pass/fail), which helps distinguish "no such file" from other
      problems like permissions or a locked mount.

  HOW TO USE:
  1. Edit `knownPath` below to the exact path your console printed
     when it imported FindCSVPath.xml.
  2. Edit the `candidates` list to include the mount point you found,
     plus the filename of the CSV you're actually trying to read.
  3. Copy this file (and its .xml) to your USB stick's gma2/plugins/
     folder, import it, and run it (Plugin <index>).
  4. Check System Monitor (tap an empty area >=2x2, tap System, tap
     System Monitor) for "FOUND:" and "fail:" lines.

  Whichever path reports FOUND is what you should use for `csvFolder`
  in CreateExecutorsFromCSV.lua.
--]]

function main()

  gma.echo("=== PART 1: known-good file test ===")
  -- Replace with the exact path your console printed when it imported
  -- this very file (e.g. "/media/sdb1/gma2/plugins/FindCSVPath.xml").
  local knownPath = "/media/sdb1/gma2/plugins/FindCSVPath.xml"
  local kf, kerr = io.open(knownPath, "r")
  if kf then
    gma.echo("OK: opened " .. knownPath .. " successfully. io.open works at this location.")
    kf:close()
  else
    gma.echo("FAILED to open " .. knownPath .. " -- error: " .. tostring(kerr))
    gma.echo("This means io.open cannot reach this folder via raw path at all.")
  end

  gma.echo("=== PART 2: CSV candidates with error detail ===")
  -- Replace "yourfile.csv" with your actual CSV filename, and add/adjust
  -- mount points as needed (sdb1, sdb2, sdc1, etc. - check your own
  -- console's import log for the one it actually used).
  local candidates = {
    "/media/sdb1/yourfile.csv",
    "/media/sdb1/items/yourfile.csv",
    "/media/sdb1/gma2/yourfile.csv",
    "/media/sdb1/gma2/plugins/yourfile.csv",
    "/media/sdb1/gma2/importexport/yourfile.csv",
  }

  for _, path in ipairs(candidates) do
    local f, err = io.open(path, "r")
    if f then
      local firstLine = f:read("*l") or ""
      f:close()
      gma.echo("FOUND: " .. path .. "  (first line: " .. firstLine .. ")")
    else
      gma.echo("fail: " .. path .. "  -- " .. tostring(err))
    end
  end

  gma.echo("=== done ===")
end

return main

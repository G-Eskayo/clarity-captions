#!/bin/bash
# Visible progress window for the engine accuracy run (#145). Display only: redraws the status files; the work
# itself is the driver's sequential loop. Closes its own window when the driver reports FINISHED.
printf '\033]0;engine-eval-watch\007'
W="$HOME/edacc-eval"
while true; do
  clear
  cat "$W/status.txt" 2>/dev/null || echo "waiting for the driver..."
  echo
  [ -f "$W/status-engine.json" ] && /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(f"Engine: {d[\"engine\"]}  clips {d[\"done\"]}/{d[\"total\"]}  ({d[\"note\"]})  ETA this engine: {d[\"eta\"]}")' "$W/status-engine.json" 2>/dev/null
  echo; echo "--- driver log ---"; tail -n 12 "$W/logs/driver.log" 2>/dev/null
  grep -q FINISHED "$W/status.txt" 2>/dev/null && break
  sleep 5
done
echo; echo "Run finished. This window closes in 30 seconds."
sleep 30
( sleep 2; osascript -e 'tell application "Terminal" to close (every window whose name contains "engine-eval-watch")' ) >/dev/null 2>&1 &
exit 0

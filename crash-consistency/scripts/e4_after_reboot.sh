#!/usr/bin/env bash
# E4 part 2: check the state after the panic, then make a change that depends
# on a record written right after the torn one.
#
# After recovery the agent creates b.txt and renames it to c.txt. The b.txt
# record is appended directly after the torn record, with no newline between
# them. The rename record goes on a new line and refers to b.txt.
#
# Usage (inside the VM):  bash e4_after_reboot.sh 2>&1 | tee e4_after_output.txt

yolo reload
cd ~/cc-exp/e4

show_journal() {
  echo "-- journal (| marks a field separator):"
  tr '\0' '|' < .yolofs/journal; echo "[end of journal]"
  echo "-- last bytes of the journal:"; tail -c 16 .yolofs/journal | od -c | head -3
}

echo "== fi_point after reboot"; cat /sys/module/yolofs/parameters/fi_point

echo "== real project files"; ls -la | grep -v '^d'
echo "== base main.c"; cat main.c; echo "size: $(wc -c < main.c) bytes"

echo "== JOURNAL AFTER THE CRASH"; show_journal

echo "== MOUNT (replays the journal)"
yolo mount; echo "mount exit=$?"
echo "-- files through YoloFS:"; yolo run --no-review -- ls

echo "== AGENT: create b.txt, then rename it to c.txt"
yolo run --no-review -- sh -c 'echo "agent file b" > b.txt && mv b.txt c.txt'
echo "-- files through YoloFS:"; yolo run --no-review -- ls
show_journal

echo "== RESTART: unmount + mount (replays the journal again)"
yolo unmount; yolo mount; echo "mount exit=$?"
echo "-- files through YoloFS:"; yolo run --no-review -- ls

echo "== COMMIT"
yolo commit; echo "commit exit=$?"

echo "== REAL PROJECT AFTER COMMIT"
ls -la | grep -v '^d'
echo "-- main.c:"; cat main.c; echo "size: $(wc -c < main.c) bytes"
echo "-- c.txt:"; cat c.txt 2>/dev/null || echo MISSING

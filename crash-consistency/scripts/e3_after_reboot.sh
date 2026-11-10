#!/usr/bin/env bash
# E3 part 2: check the state after the panic and reboot.
#
# Usage (inside the VM):  bash e3_after_reboot.sh 2>&1 | tee e3_after_output.txt

yolo reload
cd ~/cc-exp/e3

echo "== fi_point after reboot"; cat /sys/module/yolofs/parameters/fi_point

echo "== base main.c (the real file)"; cat main.c; echo "size: $(wc -c < main.c) bytes"

echo "== journal"; tr '\0' '|' < .yolofs/journal

echo "== store files"
find .yolofs/inodes -type f -exec ls -l {} \;
for f in $(find .yolofs/inodes -type f); do echo "-- $f:"; cat "$f"; echo "[end]"; done

echo "== mount (replays the journal)"
yolo mount; echo "mount exit=$?"

echo "== main.c as seen through YoloFS"
yolo run --no-review -- cat main.c; echo "[end]"

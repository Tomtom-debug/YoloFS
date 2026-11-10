#!/usr/bin/env bash
# E3 part 1: journal record on disk without its store data.
#
# Arms the fault injection point fi_point=1 in the kernel module, then lets the
# "agent" append to a base file. The append makes YoloFS copy main.c into the
# store and append an S record to the journal. With fi_point=1 the module then
# fsyncs only the journal and panics, so the copied data never reaches disk.
# The VM reboots by itself after 10 seconds. Then run e3_after_reboot.sh.
#
# Copy the terminal output by hand: anything written to a file in this run is
# lost in the panic.

yolo reload
sudo sysctl -w kernel.panic=10
D=~/cc-exp/e3; rm -rf $D; mkdir -p $D && cd $D

# Base project
printf 'line 1 of main.c\nline 2 of main.c\nline 3 of main.c\n' > main.c
yolo init --agents claude >/dev/null
yolo mount
echo "== base main.c"; cat main.c; echo "size: $(wc -c < main.c) bytes"
echo "== journal before"; tr '\0' '|' < .yolofs/journal

# Everything so far goes to disk, so the append below is the only thing in flight
sync

echo "== arming fault injection"
echo 1 | sudo tee /sys/module/yolofs/parameters/fi_point

echo "== agent appends to main.c (the kernel should panic now)"
yolo run --no-review -- sh -c 'echo "line 4 added by agent" >> main.c'
echo "== if you can read this, the injection did not fire"

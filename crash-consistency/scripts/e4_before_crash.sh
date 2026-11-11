#!/usr/bin/env bash
# E4 part 1: torn journal record.
#
# Arms fault injection point fi_point=2 in the kernel module, then lets the
# "agent" create a.txt. Creating a file appends an S record to the journal.
# With fi_point=2 the module writes only the first half of that record, with
# no newline, fsyncs the journal and panics. The VM reboots by itself after
# 10 seconds. Then run e4_after_reboot.sh.
#
# Copy the terminal output by hand: anything written to a file in this run is
# lost in the panic.

yolo reload
sudo sysctl -w kernel.panic=10
D=~/cc-exp/e4; rm -rf $D; mkdir -p $D && cd $D

# Base project: a user file that must survive
printf 'line 1 of main.c\nline 2 of main.c\nline 3 of main.c\n' > main.c
yolo init --agents claude >/dev/null
yolo mount
echo "== base main.c"; cat main.c; echo "size: $(wc -c < main.c) bytes"
echo "== journal before"; tr '\0' '|' < .yolofs/journal

# Everything so far goes to disk, so the create below is the only thing in flight
sync

echo "== arming fault injection"
echo 2 | sudo tee /sys/module/yolofs/parameters/fi_point

echo "== agent creates a.txt (the kernel should panic now)"
yolo run --no-review -- sh -c 'echo "agent file a" > a.txt'
echo "== if you can read this, the injection did not fire"

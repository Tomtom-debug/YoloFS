#!/usr/bin/env bash
# E2: crash between two staged files during commit (YoloFS crash consistency).
#
# Fault injection: strace kills `yolo commit` right before its 2nd rename
# (inject=...:signal=SIGKILL:when=2). Each staged file is installed with one
# rename (store file -> project path), so a.c is installed and b.c is not.
# This models the commit process dying, not a power loss.
#
# Usage (inside the VM):  bash e2_commit_crash.sh 2>&1 | tee e2_output.txt

yolo reload
D=~/cc-exp/e2; rm -rf $D; mkdir -p $D && cd $D

# Base project
echo "a v1" > a.c
echo "b v1" > b.c

# "Agent" changes, staged by YoloFS: edit both files
yolo init --agents claude >/dev/null
yolo run --no-review -- sh -c 'echo "a v2" > a.c && echo "b v2" > b.c'
echo "== journal"; tr '\0' '|' < .yolofs/journal
echo "== store before commit"; find .yolofs/inodes -type f

# Commit, killed right before its 2nd rename
echo "== COMMIT, killed before its 2nd rename"
strace -f -o /tmp/e2.trace -e trace=renameat,renameat2,unlinkat \
  -e inject=renameat,renameat2:signal=SIGKILL:when=2 yolo commit; echo "commit exit=$?"
grep -E "rename|killed" /tmp/e2.trace
echo "-- project:"; for f in a.c b.c; do printf '%s: ' $f; cat $f 2>/dev/null || echo MISSING; done
echo "-- store after crash:"; find .yolofs/inodes -type f

# Restart: unmount + mount replays the journal, as after a reboot
echo "== RESTART: unmount + mount (replays journal)"
yolo unmount; yolo mount; echo "mount exit=$?"

#!/usr/bin/env bash
# E1: crash inside a rename during commit (YoloFS crash consistency).
#
# Fault injection: strace kills `yolo commit` right before its 2nd rename
# (inject=...:signal=SIGKILL:when=2). This models the commit process dying,
# not a power loss. The problem comes from the order of the commit steps,
# not from data still in memory, so a process kill is enough to show it.
#
# Usage (inside the VM):  bash e1_commit_crash.sh 2>&1 | tee e1_output.txt

yolo reload
D=~/cc-exp/e1; rm -rf $D; mkdir -p $D && cd $D

# Base project
echo "old header" > old.h
echo "main v1" > main.c

# "Agent" changes, staged by YoloFS: rename old.h -> new.h, edit main.c
yolo init --agents claude >/dev/null
yolo run --no-review -- sh -c 'mv old.h new.h && echo "main v2" > main.c'
echo "== journal"; tr '\0' '|' < .yolofs/journal

check() {
  echo "-- project:"
  for f in old.h new.h main.c; do printf '%s: ' $f; cat $f 2>/dev/null || echo MISSING; done
  echo "-- temp files:"
  ls -la .yolofs/ | grep commit-tmp
  for t in .yolofs/.yolofs-commit-tmp-*; do [ -e "$t" ] && echo "$t: $(cat $t)"; done
}

# Commit, killed right before its 2nd rename
echo "== COMMIT, killed before its 2nd rename"
strace -f -o /tmp/e1.trace -e trace=renameat,renameat2,unlinkat \
  -e inject=renameat,renameat2:signal=SIGKILL:when=2 yolo commit; echo "commit exit=$?"
grep -E "rename|killed" /tmp/e1.trace
check

# Restart: unmount + mount replays the journal, as after a reboot
echo "== RESTART: unmount + mount (replays journal)"
yolo unmount; yolo mount; echo "mount exit=$?"

# The user's natural next step: run commit again
echo "== RETRY COMMIT"
yolo commit; echo "retry exit=$?"
check

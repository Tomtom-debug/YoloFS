# Crash Consistency in YoloFS

Fault injection experiments that test whether [YoloFS](https://github.com/YoloFS/YoloFS) stays consistent across crashes.

[Paper](https://arxiv.org/abs/2604.13536) · [Upstream](https://github.com/YoloFS/YoloFS)

## The problem

YoloFS stages every change in a session journal and a flat file store, then applies it to the real files on `yolo commit`. The paper says the journal is replayed on the next mount after a crash (§5.5), but it does not cover when data is forced to disk, in what order, or what happens if the crash lands during commit.

A state is treated as **consistent** if, after a crash and recovery:

- the session can still be mounted, and
- no version is left half applied, with some files updated and others not.

Losing the last few changes before a crash is a durability issue and is out of scope here.

## Why the base filesystem is not enough

The journal and store are ordinary files on the base filesystem (Ext4 in the paper). Ext4's own journal and its default `data=ordered` mode keep each of those files structurally sound after a crash. Ext4 cannot keep two related files consistent with each other, such as a journal record and the store file it points to, and a write is only durable once it is fsynced.

## Findings from the code

- **No fsync.** The journal, store files, store directories and committed files are never fsynced, so they reach disk in whatever order Ext4 writes them back. `fsync` called by a program inside YoloFS is a no-op.
- **Commit has no recovery.** The commit plan lives only in memory, staged files are moved (not copied) into the project, and the journal is cleared only after every step completes.
- **Journal records have no framing.** There is no length or checksum, so a record cut off by a crash can be skipped or accepted with a wrong value.

## Method

Crashes are injected at exact points instead of waiting for a random one.

For commit, `strace` kills `yolo commit` at a chosen system call:

```bash
strace -f -e trace=renameat,renameat2,unlinkat \
  -e inject=renameat,renameat2:signal=SIGKILL:when=2 yolo commit
```

`when=2` kills the process as it enters its second rename, so the first rename completes and the second never runs. This models the commit process dying rather than a power loss, which is sufficient here because the failures come from the order of the commit steps, not from unflushed data. Recovery is then exercised with `yolo unmount` and `yolo mount`, which replays the journal.

## Experiments

| ID | Scenario | Script | Output |
|----|----------|--------|--------|
| E1 | Crash inside a rename during commit | [e1_commit_crash.sh](scripts/e1_commit_crash.sh) | [e1_output.txt](results/e1_output.txt) |
| E2 | Crash between two staged files during commit | [e2_commit_crash.sh](scripts/e2_commit_crash.sh) | [e2_output.txt](results/e2_output.txt) |
| E3 | Journal record on disk without its store data | | |
| E4 | Torn journal record | | |

### Running

Requires a working YoloFS install (`make install`) and `strace`. Inside the VM:

```bash
bash scripts/e1_commit_crash.sh 2>&1 | tee e1_output.txt
```

Each script builds a fresh project under `~/cc-exp/`, stages changes with `yolo run`, injects the crash, and prints the project, store and journal state before and after recovery.

Environment for the included results: Ubuntu 24.04.5 ARM64 (UTM), Linux 6.8.0-147, strace 6.8.

## Results

### E1: crash inside a rename during commit

The staged change renames `old.h` to `new.h` and edits `main.c`. Commit moves a renamed file in two steps, first to a temporary path inside `.yolofs`, then to its destination. The crash is injected before the second step.

| Check | Result |
|-------|--------|
| Project after crash | `old.h` and `new.h` both missing, `main.c` unchanged; the only copy of `old.h` is the temporary file |
| Remount | fails with `ENOENT`; the journal still refers to `old.h` |
| Retry `yolo commit` | fails, and deletes the temporary file; the contents of `old.h` are lost |

### E2: crash between two staged files during commit

The staged change edits `a.c` and `b.c`. Each staged file is installed with one rename from the store. The crash is injected before the second rename.

| Check | Result |
|-------|--------|
| Project after crash | `a.c` is the new version; `b.c` is missing, because commit removes the existing file before moving the new one in |
| Store | the store file for `a.c` has been moved out |
| Remount | fails with `ENOENT`; the journal still points `a.c` to the moved store file |

In both cases the project is left half applied and the session cannot be mounted. In E1, the normal retry also destroys data.

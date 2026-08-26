# Review 8: the next session, starting cold

**The lens.** Somebody opens this repository with no memory of how it got here.
They read `HISTORY/misc/outstanding-work.md`, which claims to be standalone, and
start on task 1. Where does that document send them wrong?

⭐ **This is the claim audit applied to the handover itself.** Every other review
checked the code. This one checks whether the instructions for continuing are
true, because a wrong instruction costs the next session more than a wrong test
costs this one.

---

## Method

Every factual claim in `outstanding-work.md` that names a number, a path, a line
or a command was re-run. Claims about intent were left alone; they are the
maintainer's and are not checkable.

## Finding 1: a count was wrong, and it was the kind that reads as precise

The document said the riscv64 pool holds **seven** hand-maintained servers.

```bash
grep -c '^Server' mirrors/riscv64.pool
```

```
6
```

Six in the pool file; the generated list carries seven because the anchor is
added. ⭐ **Fixed** before the document was committed. ⚠ Worth naming because it
is the failure mode this whole file is written against: a number that is nearly
right, in a document nobody will re-measure.

## Finding 2: line citations survive, but only because they were re-checked

The document cites `scripts/gen-mirrorlist:22` and `:23` for the two pool
sources, and `scripts/make-rootfs.sh:46` in a reference clone.

```bash
grep -n 'ARCH_STATUS_JSON=\|ALARM_POOL_URL=' scripts/gen-mirrorlist
```

Both resolve. ⚠ **They did not survive untouched during the session.** Adding
action lines to `die` shifted line numbers in the same file, and the citations
were re-measured afterwards rather than carried forward. A reader should assume
any line number in `HISTORY/` is accurate as of its commit and no later.

## Finding 3: the reviews section named lenses that did not exist yet

The document listed eight lenses under "do not repeat", including three from
reviews 6, 7 and 8 that had not been written when the line was typed.

⭐ **Fixed by writing them.** ⚠ Recorded because it is a forward reference that
would have been false if the session had ended early, and it is exactly the shape
`reviews.md` warns about: a summary claiming an artefact that is not on disk.

## Finding 4: the document tells a cold reader to run something that needs a flag it does not mention

The working notes give:

```bash
bash tests/run.sh static
```

and separately note the image suite needs `EVIDENCE`. ⭐ Correct. But
`tests/run.sh image` fails with a bare `EVIDENCE: unbound variable` style message
from `40-evidence.sh` rather than from `run.sh`, which checks only `IMAGE` and
`PLATFORM`.

```bash
grep -n 'EVIDENCE' tests/run.sh
```

No output. ⚠ **Not fixed.** Moving the check into `run.sh` would duplicate a
requirement that belongs to one test file, and the message `40-evidence.sh`
produces already names the variable. Recorded so the next reader is not surprised
that `run.sh` does not validate it.

## Finding 5: two claims about the world, not the tree, that will decay first

- **161 tags on each registry.** True at the last publish. It changes the next
  time the daily cron runs and mints a new dated tag. ⚠ The document states it as
  a fact about now; a reader in a month should re-measure, and the command to do
  so is beside it.
- **187 code hits for downstream consumers.** A search result, dated in the text.

⭐ Both carry their command, which is the only mitigation available. Neither is
load-bearing for any task.

## What this review did NOT look at

- Whether the outstanding tasks are the **right** tasks. That is the maintainer's
  judgement and this review has no standing over it.
- The accuracy of anything in `HISTORY/references/`. Those were checked when
  written and not re-checked here.
- The commit body on `main`, which review 6 covers.
- Any claim in `README.md`. `tests/static/80-docs-claims.sh` covers those
  mechanically, which is stronger than a reading.

## Change summary

| | |
| --- | --- |
| files touched | 2 |
| lines added | 3 |
| lines removed | 3 |

One count corrected in `HISTORY/misc/outstanding-work.md`. This file.

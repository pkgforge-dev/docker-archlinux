# Review 23: a task whose scope was understated

**Lens.** The brief described TODO 10 as two false comments and one stale name.
The same grep it supplied found four false statements and the stale name. This
review asks how a task description came to undercount what it described, whether
anything else in this session's work had the same shape, and what a session
should do when the brief and the tree disagree.

**Date.** 2026-08-28, against the working tree of the commit this ships in.

⚠ Distinct from review 13, the brief checked line by line against the tree,
which asked whether the brief's claims were true. This asks about a claim that
was true and incomplete, which is the harder failure to notice: nothing in it
was wrong.

---

## What was opened

- `.tmp/PROMPT_COMPLETION.md`, TODO 10 as it stood. ⚠ It lives in a gitignored
  directory, so no line count here can be checked later.
- `tests/image/50-consumer-contract.sh`, whole, 183 lines.
- `Dockerfile`, lines 20 to 32.
- `bootstrap/any/usr/local/bin/pacstrap-docker`, lines 1 to 30.
- `HISTORY/tests-seen-to-fail.md`, the `50` rows.
- `HISTORY/noextract-reverted.md`, whole.
- `rootfs/amd64/etc/pacman.conf`, lines 25 to 70.
- The output of the brief's own `grep -rn NoExtract Dockerfile bootstrap/ tests/ rootfs/`.

## What was compared

The brief's enumeration against the grep's 32 hits at `dcf9263`, one at a time,
asking of each whether it was true of the tree as it stood.

## What was found

### 1. ⭐ The undercount is specific and its cause is visible

The brief named two false comments, in `Dockerfile` and in `pacstrap-docker`,
and one stale assertion name. It then said, under a ⭐, that the same grep finds
four more and every one of them is true, and listed them: five `pacman.conf`
files, `locale.gen`, `60-defect-parity.sh` twice, and `80-docs-claims.sh`.

⛔ **That list is where the miss is.** `tests/image/50-consumer-contract.sh`
appears in the brief only as the stale **name**, at three lines. The section
header above it and the failure reason below it were never classified, and both
were false:

- `# 5. locale-gen and the data it needs survive NoExtract.`
- `Decision 6 strips usr/share/i18n through NoExtract with re-includes, and the
  re-include lines are what keep this working.`
- `the ! re-include lines in pacman.conf are load-bearing, see decision 6`

⭐ **No shipped `pacman.conf` has ever carried a `!` re-include line.** Checked:
`grep -n '!' rootfs/*/etc/pacman.conf` matches nothing. So the sentence
describes a mechanism that does not exist, in a file the brief had already
opened for a different reason.

⚠ **And `decision 6` is a stale cross reference.** Decision 6 in the brief is
loong64. The `NoExtract` supersession is decision 5. The comment was written when
the numbering was different and nothing renumbered it.

### 2. ⭐ The cause is that the task was enumerated by symptom, not by rule

The brief classified each hit as false or true. That works for a hit that is a
whole statement. It does not work for a file where one line is a stale **name**
and the lines around it are a stale **explanation**: classifying the name pulled
the file into the "wrong" list, and the reader who wrote the ⭐ list then treated
the rest of the file as handled.

⭐ **The rule that would have caught it**: read every hit's paragraph, not every
hit's line. The brief's own instruction says exactly this in another place, "Grep
locates, it does not confirm; open the file", under policy 11. It was not applied
to its own TODO.

### 3. ⚠ The same shape appears once more in this session, in the other direction

TODO 3 said the first real obstacle was `scripts/resolve-anchor` reading gzip
only, and listed three obstacles. All three were real. Two more were not in the
list and neither is small: ArchPOWER's origin refuses GitHub runners, and
`docker/setup-qemu-action` registers no big endian PowerPC emulator.

⭐ **Both were invisible from a workstation**, which is where the brief's
obstacles were found. Neither was an error in the brief; both were outside the
network it could see. `HISTORY/powerpc.md` records them and says so.

⚠ **The lesson is not "the brief was wrong".** It is that a list of obstacles
compiled from one environment is a list of the obstacles that environment shows.
The brief already says every claim in it is a lead rather than a fact. This is
the shape that rule exists for, and it held.

### 4. ⭐ The rename was re-recorded rather than assumed

`HISTORY/tests-seen-to-fail.md` carried `not ok 7 - the UTF-8 charmap survives
NoExtract`. Renaming the assertion makes that string false. The brief flagged the
coupling and said to rename and re-record in one change, or leave both.

The fault was re-injected: a two line `Containerfile` on the published image
removing `/usr/share/i18n/charmaps/UTF-8.gz`, and the suite run against it. The
recorded output is what the run printed, and the fixture is quoted inline rather
than named as a path under `.tmp/`, which is TODO 13's complaint about seven
other rows.

### 5. ⚠ Two of the four false statements would never have failed a test

`tests/static/80-docs-claims.sh` greps for `^[[:space:]]*NoExtract[[:space:]]*=`
in every shipped `pacman.conf`, which is the rule and not the word. That is the
right assertion and it is why nothing was broken. It also means the four false
comments could have stood indefinitely.

⛔ **No test is added for this and none should be.** A test that a comment is
true is a test of prose, and the repository's answer to prose is that
documentation claims get tests, while a comment gets a reader. What changed the
odds here was a task that said to grep and then read.

## ⚠ What this did not look at

- **The other 27 hits.** The brief classified them and this review spot checked
  the five `pacman.conf` blocks and `locale.gen`. The two in
  `60-defect-parity.sh` were read and are true. `80-docs-claims.sh` is the check
  itself.
- ⛔ **Whether any other superseded decision left comments behind.** `NoExtract`
  was searched because a task named it. `DownloadUser`, `SigLevel` and the
  `machine-id` truncation were not swept the same way.
- **The brief's other TODO bodies.** Only 10 was checked against the tree in
  this way. 1, 2 and 3 were acted on rather than audited.
- **Whether the numbering gap is right.** TODO 10's body is replaced by a pointer
  and the number is kept. That follows review 17's finding about renumbering; it
  was not re-derived here.

## Change summary

Files touched by the change this reviews: 57 changed, 4186 insertions, 88
deletions against `dcf9263`. The parts this review covers: `Dockerfile` 6 lines
changed, `bootstrap/any/usr/local/bin/pacstrap-docker` 9,
`tests/image/50-consumer-contract.sh` 19, `HISTORY/tests-seen-to-fail.md` 2. This
review adds no change of its own.

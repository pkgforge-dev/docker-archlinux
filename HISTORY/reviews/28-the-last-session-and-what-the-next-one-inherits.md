# Review 28: the last session, and what the next one inherits

**Lens.** This is stated to be the last session for a long time. The next person
here may be a different agent, a different human, or the maintainer with no
memory of any of it, and they will arrive at a repository rather than at a
handover. Everything that is only in this session's head is lost. So: what did
this session leave that is load-bearing and undocumented, what did it leave
half-done, and what will look finished but is not.

**Date.** 2026-08-29, against `03e5442`.

⚠ Distinct from review 8, the next session starting cold, which checked whether
the brief was sufficient to start. This one asks what a long gap does, and it is
written knowing the brief now lives in the repository.

⚠ **Scratch paths in this document** are quoted as the subject of a finding,
not cited as evidence. `.tmp/` is gitignored and wiped between sessions and
nothing in it outlives the session that made it. ⛔ Do not follow one
expecting to find a file.

---

## What was opened

- `HISTORY/CONTINUE.md`, whole, 1103 lines, after the migration.
- Every `## Completed` row added this session, against the evidence it names.
- Every TODO section, for whether its state matches the tree.
- `git status`, `git log`, the tag list, both registries and the releases API.
- `HISTORY/`, all 51 documents, for anything the migration made false.

## Findings

### 1. The brief is in the repository, and that changes two things nobody has written down.

⭐ **The move is the single most durable thing this session did.** The file was
gitignored and handed to each session by paste; it is now `HISTORY/CONTINUE.md`
and survives on its own.

⚠ **First consequence: it is now subject to the tests.**
`tests/static/97-scratch-citations.sh` failed on it within an hour of the move,
because it names `.tmp/` in the traps section. That is correct behaviour and it
means the brief can now break CI, which was never true before. ⛔ A future
session editing it must run the static suite. Written into the file's header.

⚠ **Second consequence: `git log` now records who changed the plan.** Every
previous rewrite of it is unrecoverable. From here the diff exists, and a
session that quietly drops a TODO leaves a trace. Nothing was done to exploit
that and it is worth knowing.

### 2. Three things are load-bearing, were learned the hard way, and are one document away from being lost.

⛔ **Each cost a run or a container build to find, and none is inferable from the
code:**

| what | where it is written | what happens without it |
| --- | --- | --- |
| `ubuntu-latest` carries podman and docker, and `gen-evidence` prefers podman | a comment at four call sites, and one assertion | the next workflow that builds an image and reads it fails on a registry error naming a local tag |
| apt's meson is too old for zig's linker | `pacman-static.yml`, and an assertion in the script | a twenty minute build fails at its last step |
| progress on stdout is captured by `$(...)` | `scripts/build-pacman-static`, and a general assertion | a compiler wrapper contains a banner |

⭐ **All three are guarded by a test, not only by a comment.** That was the
deliberate choice each time: a comment tells the next reader, and an assertion
tells them whether they broke it.

### 3. What will look finished and is not.

⛔ **The list a next session should not trust its own reading of.**

- ⚠ **`freshness-pacman-static.yml` has never run at all**, and four more have
  never fired on their own schedule. Counted from the API in review 26. They are
  green in the sense that nothing is red.
- ⚠ **The bootstrap guide has never been executed.** Its commands parse. That is
  the largest unproven claim this project makes, it is in a release body now,
  and TODO 2 item 2 is where it lives.
- ⚠ **The `pacman-static.yml` meson pin has no freshness job.** Every other
  pinned thing has one. Policy 9 says this one should.
- ⚠ **The rootfs assets' relationship to the published image was wrong twice
  before it was right.** It now exports the published image by digest. That is
  one run old.
- ⚠ **`api.rv.pkgforge.dev` is a dependency nothing watches**, and the ArchPOWER
  tracker says the origin blocks networks by policy, so it is permanent.

### 4. The static suite is not deterministic on this workstation, and that was nearly recorded as a repository defect.

⛔ **Three separate full runs failed on the same twelve assertions**, across
`40-mirrors-reachable.sh`, `67-mangled-responses.sh` and one fixture assertion in
`96-release-assets.sh`. Each file passed when run alone, immediately afterwards,
unchanged.

⭐ **The common factor is load, not the tree.** Every failure happened while
container builds and `gh run watch` processes were running concurrently. Two
clean runs with nothing else in flight passed 24 of 24.

⚠ **A session that saw only the failing runs would have "fixed" something that
was not broken.** Recorded as a trap in `HISTORY/CONTINUE.md` so the next one
does not.

### 5. Two things this session changed on the remote that a reader cannot see from the tree.

- ⛔ **Branch protection was turned off and back on.** `allow_force_pushes` was
  the only field changed, verified by diffing a capture taken before against one
  taken after. ⚠ If a session ever ends without restoring it, nothing in the
  repository would say so. That is inherent.
- ⛔ **`debug` was deleted and `template-adoption` was found already gone**, the
  latter holding 11 commits that exist in one working clone and nowhere else.
  `HISTORY/maintainer-actions.md` carries the sha and the command. ⚠ That entry
  is the only record and it decays the moment that clone is cleaned.

### 6. The Completed table is now 51 rows and is the wrong shape for a cold reader.

⚠ It reads as a changelog, and the brief's own rule 8 says documentation is a
manual and history lives elsewhere, with `HISTORY/` for the detail. The table
obeys that: each row is a summary pointing at evidence.

⛔ **What it does not do is say which rows still hold.** Row 35 says both
registries rose 161 to 176; row 42 says 176 to 194. Both were true when written.
A cold reader has to read all 51 in order to know the current number, and the
current number is in "Where things stand" three sections later.

⭐ **Not changed, and the reason is written down**: renumbering or pruning the
table is what review 17 recorded as costing a session a manual cross reference
remap. The fix is that "Where things stand" is authoritative for current state
and the table is a ledger. Made explicit in the file rather than left implied.

## What this review did not look at

- ⛔ **Whether the next session will read any of this.** The brief says to
  re-read it before each task and this review cannot enforce that.
- **The 47 `HISTORY/` documents this session did not touch.** Only those it
  changed, plus the ones the migration's substitution reached.
- **Whether the TODOs left open are the right ones.** Four were left untouched
  by the maintainer's instruction; nothing here re-argues them.
- **Any measurement made by a previous session that this one did not have cause
  to re-derive.** Review 27 covers this session's corrections only.

## Change summary

Files touched: 1.

| file | added | removed |
| --- | --- | --- |
| `HISTORY/CONTINUE.md` | 14 | 2 |

Two paragraphs: the trap about the suite under load, and one sentence saying the
Completed table is a ledger and "Where things stand" is the current state.

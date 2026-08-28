# Review 27: a correction that was itself wrong

**Lens.** This session corrected a lot: stale counts, a false claim about the
cron, two swapped signer names, a brief that said a repository was something it
is not. Every correction is a new claim, made under the same conditions that
produced the thing being corrected, and usually made faster. This review treats
the session's own corrections as suspects and re-derives them from the source
rather than from the correction.

**Date.** 2026-08-29, against `03e5442`.

⚠ Distinct from review 17, a report entering the record as though it were a
measurement, which asked whether claims were measured at all. This asks whether
the fixes are right, having assumed the originals were not.

⚠ **Scratch paths in this document** are quoted as the subject of a finding,
not cited as evidence. `.tmp/` is gitignored and wiped between sessions and
nothing in it outlives the session that made it. ⛔ Do not follow one
expecting to find a file.

---

## What was opened

- Every claim this session changed, re-derived from its own source.
- `HISTORY/CONTINUE.md`, the header, the counts, the layout table, and all
  fourteen TODO sections.
- `bootstrap/pacman-static/sources.pin`, the signer block.
- `HISTORY/loong64.md`, the keyring section.
- `HISTORY/maintainer-actions.md`, section 3.
- `git log`, `git ls-files`, the GitHub API and both registries.

## The corrections, re-checked

| correction | re-derived how | verdict |
| --- | --- | --- |
| the cron did fire on 2026-08-28 | runs API, `event=schedule` | ⭐ holds, run `33195147714` at 17:32:25Z |
| that run published five, not eight | its `headSha` is `dcf9263`; `4992326` committed 18:01:41Z | ⭐ holds |
| the two signer names were swapped | imported both fingerprints, read the uids | ⭐ holds |
| the lcpu pin has 10 keys, not 8 | `scripts/check-keyring-pin` output | ⭐ holds |
| two of them already expired | same output, dates 2026-04-24 and 2026-07-14 | ⭐ holds |
| `debug` held nothing unique | `git merge-base --is-ancestor` | ⭐ holds |
| the repository is detached | `gh api`, `fork:false parent:none` | ⭐ holds |
| `kth5/archpower` is not where a layout change appears | 1825 top level entries, 1823 are packages | ⭐ holds |
| both registries hold 194 tags | both tag lists, counted | ⭐ holds |

## Findings

### 1. One correction was wrong, and it was mine, in a review.

⛔ **Review 25 claimed `/etc/os-release` in a rootfs tarball "records the version
and the source commit".** It does not. Read out of a real archive:

```bash
tar -xzOf rootfs-amd64.tar.gz etc/os-release
```

Thirteen keys, of which the relevant ones are `VERSION_ID`, `IMAGE_ID` and
`IMAGE_VERSION`. ⛔ **No commit.** The claim was written from a memory of what
`write-os-release` does rather than from the file.

⭐ Corrected in review 25 before it shipped, and the corrected version is the
stronger finding: a consumer holding only the tarball can date it and cannot tie
it to a revision. That went into `README.md` and `HISTORY/releases.md`.

⚠ **The shape is worth naming.** It was a claim about a file that was open in
the same session, made while writing about being careful with claims.

### 2. A blanket rewrite made three true statements false.

⛔ **Moving the brief into the repository was done with a global substitution**
of `.tmp/PROMPT_COMPLETION.md` for `HISTORY/CONTINUE.md` across `HISTORY/`. It
hit three sentences whose whole point was that the file was **not** in the
repository:

```
Files touched: 1, `HISTORY/CONTINUE.md`, which is not in the repository.
```

and, in the migrated file's own header, the sentence explaining the move:

```
It lives in the repository now, at `HISTORY/CONTINUE.md`. It used to live
in `HISTORY/CONTINUE.md`, which is gitignored and wiped between sessions,
```

⭐ **Found by reading, then re-found by a test.** The first pass caught the three
sentences. Rewording two of them reintroduced a `.tmp/` path, and
`tests/static/97-scratch-citations.sh`, written earlier in the same session,
failed on the file it had just been taught about. ⛔ That is the test doing its
job against its own author.

⚠ **The general lesson, and it is the second time this session:** a substitution
that is right for a path is wrong for a sentence about that path. Both times the
damage was in prose, and both times a scan that read prose as data was involved.

### 3. Two test assertions read documentation as configuration.

⛔ **Both were written this session and both passed while asserting nothing
useful.**

- `95-publish-watchdog.sh` asserted no job declares `needs: watchdog`. The
  comment above the watchdog job explains that it has neither, so the scan
  matched its own documentation and reported a failure that was not one.
- `96-release-assets.sh` looked for `CONTAINER_RUNTIME` in the 25 lines before
  each `gen-evidence` call. Every one of those calls now carries a comment
  saying why the runtime is set, so the lookback was satisfied by the
  explanation rather than by the setting. ⚠ Confirmed by injecting the fault and
  watching the assertion pass.

⭐ Both now strip comments first, which is what `25-pipeline-traps.sh` has done
since it was written. ⛔ Three files in this repository have now made this
mistake, so it is a pattern rather than an accident.

### 4. One correction is still only half re-derived.

⚠ **`HISTORY/CONTINUE.md` says both registries hold 194 tags.** Counted on both,
so it holds. ⛔ **What was not re-derived is the claim it replaced.** The old
text said 161 and the session before said 176; nobody recounted 161 at the time
it was written, and it cannot be recounted now because no registry keeps a
history of its tag count.

⭐ **Not a defect, and worth writing down anyway.** A number that can only ever
be checked forwards should say when it was measured, and the migrated file now
does for this one.

## What this review did not look at

- ⛔ **Corrections made by earlier sessions.** Only this session's. Reviews 13
  and 17 covered the brief against the tree at their own dates and neither is
  re-run here.
- **Whether the counts in the migrated file will stay right.** `175 tracked
  files` was true when measured and the commit that records it changes it. That
  is inherent to writing a count into a file inside the tree, and the file says
  when it was measured.
- **The reference document's tracker findings.** Five issues were read in full
  with comments; the other 71 were filtered by keyword and not opened. That is
  stated in the reference itself.
- **Any claim in `HISTORY/` older than this session that was not touched.**

## Change summary

No file was changed by this review. The one wrong correction it found was fixed
in review 25 and in `README.md` before either was committed, and both test
assertions were fixed as part of the reviews that found them.

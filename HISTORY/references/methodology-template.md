# The methodology template

Reference study of the nine methodology documents in `Azathothas/TEMPLATE`.
Policy 11 already routes to one of them, `references.md`. The other nine had
not been opened. Five deep reviews were written before `reviews.md` was read.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/Azathothas/TEMPLATE` |
| commit read | `3191d08c4fc4dd42f9384066741bf4b0fbbe1e1e` |
| commit date | 2026-08-25 |
| clone depth | full, local at `.tmp/TEMPLATE` |
| files read | all ten under `docs/methodology/`, 1853 lines |
| studied on | 2026-08-26 |

```bash
git -C .tmp/TEMPLATE rev-parse HEAD
wc -l .tmp/TEMPLATE/docs/methodology/*.md
```

| file | lines |
| --- | --- |
| `authoring.md` | 209 |
| `choosing-a-work-model.md` | 123 |
| `gate.md` | 150 |
| `ingest.md` | 251 |
| `initialize.md` | 326 |
| `references.md` | 179 |
| `reviews.md` | 120 |
| `sessions.md` | 224 |
| `work-stages.md` | 118 |
| `work-todo.md` | 153 |

## Verdict: adopt, for `reviews.md` and `gate.md`. Confirms, for the rest.

⭐ **Two documents change what this repository does. The other seven describe a
project shape this repository does not use** and are recorded as read so no
later session re-opens them expecting a finding.

## Finding 1: the reviews here are missing the change summary

`reviews.md:114` lists what a review owes the record:

> - The findings, per pass, with which lens found each.
> - The change summary: files touched, lines added and removed.
> - What was **fixed** as a result. A listed finding that was not fixed says
>   where it is now tracked.
> - For any pass with no findings, what would have made it fire.

Measured against the five reviews in `HISTORY/reviews/`:

```bash
grep -ln 'lines added\|insertions\|files changed\|--stat' HISTORY/reviews/*.md
```

Exit status 1. None of the five carries a change summary. Every other item is
present: each states its lens, each carries a `What this review did NOT look at`
section, and `5-the-tests-themselves.md` is the one with no new defect and it
says what would have made it fire.

⭐ **The correction is for the next reviews, not for the five.** Amending a
review after the fact would restate a pass that did not take place. Phase D
reviews carry the change summary.

## Finding 2: the three lenses are named, and they are not the five used here

`reviews.md:12` names them: the door sweep, the guard mutation, the claim audit.
Phase C used five different ones, recorded in `HISTORY/reviews/`. The template's
three are questions about a change; Phase C's five are questions about an
audience. Both satisfy `reviews.md:82`, which requires only that each pass can
name what it looked at that the others did not.

⭐ **The guard mutation lens is the one this repository already practises under
another name.** `reviews.md:34` requires planting the defect a guard exists to
catch and reading the exit code unpiped. That is
`HISTORY/tests-seen-to-fail.md`, which carries a fault per test.

## Finding 3: the gate has three parts, and part (b) is met under another name

`gate.md:3` states that there are three, and their headings are `gate.md:17`,
`gate.md:43` and `gate.md:82`: the automated suites, driving the real thing, and
the deep reviews. Part (b), `gate.md:43`, requires running the real system as a
user would, and `gate.md:70` calls deferring it a failed gate rather than a
deferral.

⚠ **For a container image, part (b) is pulling the published image and using
it.** That is what `HISTORY/reviews/1-a-consumer-who-upgrades-blind.md` does, so
the gate is met, under a different name.

## Finding 4: two rules that bear on how this repository records numbers

- `gate.md:25` requires counting the test files the runner reports against the
  files on disk, because a green count beside an error line is a file that never
  ran. `tests/run.sh` reports a TAP plan, so the count is checkable.
- `gate.md:33` requires reading every exit code from the process that produced
  it, unpiped. This is the same defect class as the `grep -c` and `head`
  pipeline traps recorded against `scripts/gen-mirrorlist`.

## Deliberately not adopted

| document | why not |
| --- | --- |
| `work-stages.md`, `work-todo.md`, `choosing-a-work-model.md` | both describe a record shape with a plan file or an entry index per unit. Decision 1 settles adoption at `.gitattributes` and nothing else, so neither record shape is created here. |
| `authoring.md` | it separates authoring from implementing into two sessions with an approval gate between them. This repository is worked from a single brief with the decisions already made. |
| `initialize.md` | for a project that does not exist yet. |
| `ingest.md` | for taking over a project. Its cardinal rule at `ingest.md:19`, that documentation is a claim rather than truth, is already the precedence rule in use. |
| `sessions.md` | the summary table at `sessions.md:61` and the next prompt at `sessions.md:96` are session artefacts. `sessions.md:98` forbids writing the next prompt into a file, so nothing here is tracked. |

## What this study did not do

- The rest of `.tmp/TEMPLATE` was not read. Only `docs/methodology/`.
- `../conventions/`, `../security/remote-ops.md` and `../templates/` are linked
  from the methodology files and were not opened.
- No tracker was read. The template is a document set with no issues bearing on
  this repository.

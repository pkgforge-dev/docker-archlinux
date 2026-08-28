# Nothing noticed when the publish stopped

⛔ **A scheduled workflow that stops firing produces no run, so no failure, no
annotation and no red mark.** It happened here. Scheduled `build-deploy.yml`
runs were daily and unbroken to 2026-07-13, then **45 days of nothing**, then
one on 2026-08-27 that failed.
`HISTORY/reviews/19-a-job-that-stops-running.md` has the measurement and rules
out four causes without finding the fifth.

⚠ **Every workflow reported `state: active` throughout those 45 days.** A
session checking only the state field concludes the schedule is healthy. The
state field is not the signal.

## What the 2026-08-29 session measured, and one thing the brief got wrong

⭐ **The cron did fire on 2026-08-28, and the brief said it did not.** Read from
the runs API on 2026-08-29:

```bash
gh api "repos/pkgforge-dev/docker-archlinux/actions/workflows/build-deploy.yml/runs?event=schedule&per_page=10" \
  --jq '.workflow_runs[] | "\(.id) \(.created_at) \(.conclusion)"'
```

| run | created | conclusion |
| --- | --- | --- |
| `33195147714` | 2026-08-28T17:32:25Z | success |
| `33094128354` | 2026-08-27T16:36:52Z | failure |
| `29235804728` | 2026-07-13T08:32:37Z | success |

Two consecutive days of scheduled runs, the second green. ⚠ The gap is still
unexplained and nothing in this work explains it. What changed is that a
recurrence is now visible.

⚠ **That run published five architectures, not eight.** It ran at 17:32:25Z on
`dcf9263`; the PowerPC commit `4992326` landed at 18:01:41Z, twenty nine minutes
later. So `v2026.08.28` lists five platforms and the three PowerPC ports were
still in no registry after it.

⚠ **The cron fires late.** It is `30 05 * * *` and the two runs above started at
17:32Z and 16:36Z. GitHub queues scheduled runs at low priority. Nothing here
depends on the hour, which is why every threshold below is counted in days.

## The mechanism

Two checks, run from two workflows on two schedules, each the other's witness.

| script | what it reads | what it sees |
| --- | --- | --- |
| `scripts/check-publish-recency` | the newest dated index tag on GHCR, anonymously | the publish stopped, including a run that started and published nothing |
| `scripts/check-schedules-fired` | the newest `event=schedule` run of every scheduled workflow | a schedule stopped firing, including this watcher's own |
| `scripts/cron-tolerance` | one workflow's cron | how many days of silence that schedule makes normal |
| `scripts/date-age` | two dates | whole days between them |

```
freshness-publish.yml  runs both        sees build-deploy.yml go quiet
build-deploy.yml       runs the second  sees freshness-publish.yml go quiet
```

⛔ **The outcome is measured, not the attempt.** A run that started and created
no tag is as much a stop as a run that never started, and only the registry
tells them apart. Policy 6 exists for exactly that: 59 days of green runs
publishing nothing.

⛔ **The watchdog job in `build-deploy.yml` gates nothing and is gated by
nothing.** A broken alarm must not be able to stop a publish. The run goes red
while every tag is still created. `tests/static/95-publish-watchdog.sh` asserts
the job declares no `needs:` and that no job declares `needs: watchdog`.

## Nothing is written down that should be derived

⛔ **Three ways this rots, each with a precedent, and each closed.**

**A hardcoded day threshold.** The tolerance comes from the cron itself.
`scripts/cron-tolerance` walks one full leap cycle from a fixed start, 1461 days
from 2024-01-01, and reports the largest gap the schedule produces:

```bash
scripts/cron-tolerance .github/workflows/build-deploy.yml   # 1 3
scripts/cron-tolerance .github/workflows/freshness-mirrors.yml   # 31 63
```

`tolerance = gap * 2 + 1`. One missed firing is a transient. Two is a stop.

⚠ **An under-reported gap is the dangerous direction**: it makes the tolerance
too small, so the check fails on a schedule that is working, and a check that
cries wolf is one nobody reads. The silence after the last firing in the window
is therefore counted, which errs long.

**A hardcoded year.** The brief's own worked example was
`select(startswith("v2026"))`. That passes for sixteen months and then matches
nothing, and matching nothing reads exactly like a repository that has never
published. The date is recognised by shape instead, and the check is tested by
running it against a tag list dated 2030 with the clock set to 2087.

**A hardcoded list of what is watched.** `check-schedules-fired` discovers every
workflow carrying a cron from `.github/workflows/`, so a scheduled workflow
added later is watched with no edit, and the workflows with no schedule are
named in the output rather than silently skipped.

⭐ **The tag spelling is asked for, not written.** `scripts/tag-names` is handed
a sentinel and the answer is parsed, so a change to the tag family follows here
instead of leaving the check looking for a name nothing creates.

## What it cannot see, written down rather than solved

- ⛔ **Every schedule in the repository stopping at once.** That is what GitHub
  does to a repository with 60 days of no activity, and it leaves no run for
  either check to be run by. Both workflows are dispatchable, so a person asking
  gets the answer.
- ⛔ **GitHub not scheduling anything at all.** Same shape, same answer.
- ⚠ **Docker Hub.** Only GHCR is read for recency. The publish job verifies both
  registries in one step and a copy that fails there fails the run loudly, so
  the silence this guards leaves both registries equally untouched.
- ⚠ **A workflow that has never once fired on schedule** is not a failure on the
  day it is added. It becomes one when the workflow has existed longer than its
  own tolerance with no scheduled run, which is a cron that never worked.

## Measured

```
$ scripts/check-publish-recency
check-publish-recency: the schedule's largest gap is 1 day(s), so tolerance is 3 days
check-publish-recency: a dated index tag is v<date>
check-publish-recency: 137 dated index tag(s), newest v2026.08.28
check-publish-recency: newest dated index tag is v2026.08.28, 0 day(s) old on 2026-08-28
check-publish-recency: v2026.08.28 is 0 day(s) old, within 3

$ scripts/check-schedules-fired
check-schedules-fired: pkgforge-dev/docker-archlinux, measured on 2026-08-28
check-schedules-fired: no schedule, not checked: ci.yml pacman-static.yml release.yml
ok        build-deploy.yml                   last scheduled run 2026-08-28, 0 day(s) ago, tolerance 3
new       freshness-image-pins.yml           no scheduled run yet, added 2 day(s) ago, tolerance 15
new       freshness-keyring.yml              no scheduled run yet, added 2 day(s) ago, tolerance 15
new       freshness-mirrors.yml              no scheduled run yet, added 2 day(s) ago, tolerance 63
new       freshness-pacman-static.yml        no scheduled run yet, added 0 day(s) ago, tolerance 15
check-schedules-fired: 5 schedule(s), all firing
```

⚠ **The four freshness workflows have never had a scheduled run.** Their crons
are weekly and monthly and the history was rewritten on 2026-08-26, so GitHub
records them as created that day. They are inside their own tolerance and the
check says `new` rather than `ok`, which is the difference between "has fired"
and "has not been quiet long enough to worry about". ⛔ Nobody has yet seen one
of them turn `ok`, and until one does, that branch of the check is exercised
only by fault injection.

## Seen to fail

`HISTORY/tests-seen-to-fail.md`, the `95` and `date-age` rows.

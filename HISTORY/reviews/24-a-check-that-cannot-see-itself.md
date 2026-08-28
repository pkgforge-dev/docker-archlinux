# Review 24: a check that cannot see itself

**Lens.** This session built a watchdog whose whole purpose is to notice
silence. A watchdog is the one kind of check that can fail by not running, and
the failure looks exactly like success: nothing red, nothing said. So the
question is not "does it work" but "what state is it blind to, and would anybody
find out". Every claim the mechanism makes about its own coverage is treated as
a claim to be checked, not as documentation.

**Date.** 2026-08-29, against `9205295`.

⚠ Distinct from review 19, which asked whether anything would notice a stopped
schedule and found that nothing would. This one reads the thing built in answer
and asks where its own blind spots are.

---

## What was opened

- `scripts/check-publish-recency`, whole, 259 lines.
- `scripts/check-schedules-fired`, whole, 212 lines.
- `scripts/cron-tolerance`, whole, 215 lines before this review's edit, 225 after.
- `scripts/date-age`, whole, 80 lines.
- `.github/workflows/freshness-publish.yml`, whole, 106 lines.
- `.github/workflows/build-deploy.yml`, the `watchdog` job, lines 571 to 598.
- `tests/static/95-publish-watchdog.sh`, whole, 429 lines before this review's edit, 460 after.
- `HISTORY/publish-watchdog.md`, whole.
- The live output of both checks, and of `cron-tolerance` against all six
  scheduled workflows.

## The blind spots, and whether each is written down

⭐ **Four states the mechanism cannot see. Three are named in the code; the
fourth was not, and is now.**

| state | who sees it | written down |
| --- | --- | --- |
| the publish schedule stops | `freshness-publish.yml`, both checks | yes |
| the watcher's schedule stops | `build-deploy.yml`'s `watchdog` job | yes |
| a freshness schedule stops | whichever of the two ran most recently | yes |
| **every schedule stops at once** | **nothing** | yes, in three places |
| **a check runs and its verdict is never read** | **nothing** | ⚠ was not |

⛔ **The fourth is the real one and it is the 60 day rule.** GitHub disables
scheduled workflows in a repository with 60 days of no activity. That disables
all of them together, which is precisely the case both halves are blind to.
`scripts/check-schedules-fired` says so in its header and in its failure text,
and `HISTORY/publish-watchdog.md` says it twice. ⭐ It is solved as far as it can
be: both workflows are `workflow_dispatch`, so a person asking gets an answer.

⚠ **The fifth was not written down and is now.** `freshness-publish.yml` runs
both checks and then a third step takes the verdict. If that third step were
ever removed, the two checks would still run, still print, still be green as
steps, and the workflow would pass while reporting a stopped publish in its own
log. The `case` statements set an output and do **not** exit non-zero.

⭐ **It is guarded, and I had to read it twice to be sure.** The `Take the
verdict` step reads both outputs and exits 1 on either. The reason the checks do
not exit non-zero themselves is deliberate and stated: stopping at the first
failure would hide the second, and the two answer different questions. ⛔ But
nothing asserted the third step exists. A new assertion now does.

## Findings

### 1. The verdict step was unasserted. Fixed.

`tests/static/95-publish-watchdog.sh` asserted that `freshness-publish.yml` runs
both scripts. It did not assert that anything acts on their results. Deleting
the `Take the verdict` step left a workflow that runs both checks and is green
when both report a stop.

⭐ Injected: the step removed. Before the fix, 53 of 53 still passed. After,
`not ok 50 - freshness-publish.yml acts on both check results`.

### 2. The tolerance is derived from the cron, and the cron is not the schedule.

⚠ **`cron-tolerance` answers a question about the calendar, not about GitHub.**
A daily cron has a gap of 1 whether or not GitHub ever honours it. The two runs
this repository has on record fired at 17:32Z and 16:36Z against a `30 05` cron,
so GitHub's delay is measured in hours, not days.

⭐ **That is correct for this use and the reason is worth stating.** The tag
carries a date, not a time, so a check finer than a day has nothing to compare
against. A twelve hour delay cannot move a date by more than one day, and the
tolerance is three.

⛔ **It is not correct if anybody ever shortens the cron.** A cron of
`0 */6 * * *` still has a gap of 1 day by this measure, and the tolerance would
be 3 days for a schedule expected to fire four times a day. ⚠ That is a
weakening, not a break: the check would still catch a stop, just later. Written
into `scripts/cron-tolerance`'s header rather than left for somebody to discover.

### 3. The `new` state can persist forever without anyone noticing.

`check-schedules-fired` reports `new` for a scheduled workflow that has never
had a scheduled run and is younger than its own tolerance. Four of the six are
in that state today, because the history was rewritten on 2026-08-26 and their
crons are weekly and monthly.

⭐ **It closes itself** and I checked the arithmetic rather than trusting the
comment: once a workflow is older than its tolerance with no scheduled run, the
branch reports `NEVER` and counts as stopped. For `freshness-mirrors.yml` that
is 63 days after 2026-08-26, so 2026-10-28.

⚠ **Nobody has seen `ok` on any of the four**, and nobody has seen `NEVER`
either. Both branches are exercised only by fault injection. Recorded in
`HISTORY/publish-watchdog.md`.

### 4. The recency check reads one registry and the publish writes two.

⚠ Only GHCR is read. Docker Hub could fall behind while GHCR is current, and
this check would say the publish is healthy.

⭐ **Ruled out as a real gap, with the reason.** The publish job's
`Verify what was published` step inspects the index on both registries in the
same step, and a copy that fails there fails the run loudly. The silence this
check guards is the run that never happened, which leaves both registries
equally untouched. ⛔ The case it cannot see is a Docker Hub tag deleted by hand
afterwards, which no check here covers and which policy says never happens.

## What this review did not look at

- ⛔ **Whether GitHub actually disables schedules at 60 days.** That is upstream
  behaviour, taken from GitHub's documentation and not measured. The 45 day gap
  in the record is shorter than 60, so it is not an instance of it.
- **The freshness workflows' own histories.** Only that they have none.
- **Whether the tolerance numbers are the right ones.** `gap * 2 + 1` is a
  judgement, stated in the code with its reasoning. Nothing here tested whether
  three days is too eager or too slow against real delay data, because there are
  two scheduled runs on record and that is not data.
- **The runs API's own reliability.** `check-schedules-fired` trusts what
  `gh api` returns. A truncated or stale response would read as a stopped
  schedule, which errs toward a false alarm rather than a missed one.

## Change summary

Files touched: 2.

| file | added | removed |
| --- | --- | --- |
| `tests/static/95-publish-watchdog.sh` | 31 | 0 |
| `scripts/cron-tolerance` | 10 | 1 |

One new assertion, 54 of 54 passing. One comment block recording the sub-daily
cron limitation.

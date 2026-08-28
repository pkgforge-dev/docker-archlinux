# Review 19: a job that stops running

**Lens.** Every failure this repository designs for is loud: a red job, a
refused tag, an annotation. This one is silent. A scheduled workflow that stops
firing produces no run, so it produces no failure, no annotation and no red
mark. Nothing is broken and nothing reports. What in the repository would
notice, and how long could it go on.

**Date.** 2026-08-28, against `756bef1`.

⚠ Distinct from review 3, the day upstream breaks, and review 9, an operator
during a mirror outage. Both of those are active failures with an error to read.
This is the absence of a run.

---

## What was opened

- `.github/workflows/build-deploy.yml`, the `on:` block at lines 14 to 34.
- All five workflow files' schedule blocks.
- The workflow states from the API.
- The full `event=schedule` run history for `build-deploy.yml`, 20 rows.
- `scripts/check-anchor-floor`, and a grep across `scripts/`, `tests/` and
  `.github/` for any recency assertion.
- `HISTORY/evidence-race.md` for what the last scheduled run did.

## It has already happened, and for 45 days

```bash
gh run list --workflow=build-deploy.yml --event=schedule --limit 20 --json databaseId,createdAt,status,conclusion,headSha --jq '.[] | "\(.databaseId) \(.createdAt) \(.status)/\(.conclusion) \(.headSha[0:7])"'
```

| run | created | result | sha |
| --- | --- | --- | --- |
| `33094128354` | 2026-08-27T16:36:52Z | failure | `528860c` |
| `29235804728` | 2026-07-13T08:32:37Z | success | `9d1e142` |
| `29184613300` | 2026-07-12T07:40:51Z | success | `9d1e142` |

⛔ **2026-07-13 to 2026-08-27 is 45 days with no scheduled run.** Before the gap
they are daily and unbroken back to 2026-06-25, the limit of the page read.

⚠ **And it is happening now.** The cron is `30 05 * * *`,
`.github/workflows/build-deploy.yml:33`. No scheduled run existed on 2026-08-28
at 14:10 UTC, eight and a half hours past it. The historical delay in the rows
above is two to four hours.

⭐ **The workflow is not disabled.** That was the first hypothesis and it is
wrong:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/workflows --jq '.workflows[] | "\(.name) state=\(.state)"'
```

All five report `state=active`. ⛔ **So the state field is not the signal**, and
a session checking only that would conclude the schedule is healthy.

## Nothing in the repository would notice

```bash
grep -rn -e 'last published' -e 'days since' scripts/ tests/ .github/
```

No match. Read individually rather than inferred from the grep:

| what it does | why it does not notice |
| --- | --- |
| `scripts/check-anchor-floor` | reads the public tag list for the **anchor version**, to refuse a downgrade. It runs **inside** a build, so a run that never starts never calls it |
| the three freshness workflows | each watches one pinned thing: keyring, mirrors, image digests. None watches whether a publish happened |
| `tests/static/35-publish-targets.sh` | asserts the workflow names both registries. It says nothing about when either was last written |
| `.github/workflows/ci.yml` | runs on push and pull request. A quiet repository runs it less, not more |

⛔ **The failure is invisible in both directions.** No run means no red mark, and
the newest published image stays pullable and keeps working. A consumer on
`:latest` gets an image that is quietly older every day, with no signal at any
point that the pipeline stopped.

## What the 45 day gap actually cost, and what it did not

⭐ **It cost less than it looks**, and the reason is worth writing down. All 15
scheduled runs before the gap ran at `9d1e142`, which is the `history-archive`
tip. They were green and, per policy 6's own framing in the brief, publishing
nothing of consequence. The gap replaced runs that were already not doing what
they appeared to do.

⚠ **That is not a defence of the gap.** It means the two failure modes were
present at once, and the noisier one, a green run that publishes nothing, is the
one the repository already has a policy against. ⛔ The quieter one, no run at
all, has no policy and no check.

## The current state is the two stacked

1. No scheduled run today.
2. The last scheduled run, `33094128354`, failed on the evidence race and
   published nothing. That fix is on `main` at `30d75ed` and has never been
   through a real publish.

⛔ **So the newest published index is `v2026.08.26` while `main` is at
`756bef1`**, and no `loong64` tag exists on either registry.

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:pkgforge-dev/archlinux:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/pkgforge-dev/archlinux/tags/list?n=1000" | jq -r '[.tags[] | select(startswith("v2026"))] | max'
```

161 tags on each registry, newest dated index `v2026.08.26`, no `loong` tag on
either.

## What would close it, stated as a shape and not as a change

⚠ **Nothing was changed by this review.** A check is a design decision and this
records the requirement rather than taking it.

The check has to run somewhere a stopped schedule cannot silence. ⛔ **A step
inside `build-deploy.yml` cannot do it**, which is the whole point: that is the
job that is not running. The three freshness workflows are on their own
schedules, and any of them stopping is the same problem one level up.

⭐ **What it must assert:** the newest `v<date>` index tag on GHCR is within some
number of days of today, and fail loudly when it is not. That reads the public
tag list with no token, which `scripts/check-anchor-floor` already does, so the
mechanism exists and only the caller is missing.

⚠ **And it must state its own dependency.** A recency check on a schedule that
can itself stop is not a solution, it is a smaller instance of the same problem.
Whatever is chosen, the document should say which silence it can and cannot see.

## What was fixed, and where it is tracked

⛔ **Nothing was fixed.** No check was added, because where it runs is a design
decision with a cost the maintainer carries: decision 2 records that this
repository is meant to need very little attention, and a new red mark is
attention.

⭐ **It is tracked as TODO 14** in `.tmp/PROMPT_COMPLETION.md`, carrying the
measurement above, the shape a check must have, and the question to ask first.
⚠ That file is scratch and is wiped between sessions, which is why the
measurement lives here and only the task lives there.

## What was ruled out

- **The cron expression being wrong.** `30 05 * * *` is valid and the runs
  before the gap fired daily against it. ⚠ Its trailing comment says
  `08:30 PM UTC everyday`, which does not describe `30 05`. That is a false
  comment and not a defect in behaviour; it is the same class as the two
  `NoExtract` comments in TODO 10 and is left for that task.
- **The history rewrite having broken it.** The rewrite is `HISTORY/rewrite.md`
  and the gap starts 2026-07-13, well before it. The dates do not line up.
- **Concurrency cancelling the runs.** `cancel-in-progress: true` on group
  `build-deploy-${{ github.ref }}` would leave cancelled runs in the list.
  There are none in the 20 rows read.
- **A repository inactivity disable.** GitHub disables schedules after 60 days
  without activity. The gap is 45, and the state field reports `active`.

## ⚠ What this did not look at

- ⛔ **Why the schedule stopped.** Nothing here explains it. Four hypotheses are
  ruled out above and none is replaced by an answer. GitHub's scheduler drops
  runs under load and does not report which it dropped.
- **The three freshness workflows' own run histories.** Only their cron
  expressions were read. Whether they have gaps of their own is unmeasured.
- **Whether a recency check belongs here at all.** An argument exists that a
  repository whose maintainer merges an occasional pull request does not want
  another red mark. That is the maintainer's call and TODO 11 is where those
  live.

## Change summary

No file was changed by this review. The measurements are in `HISTORY/` and in
`.tmp/PROMPT_COMPLETION.md` TODO 1, which is not in the repository.

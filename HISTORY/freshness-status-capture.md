# The freshness checks could not act on a result

⭐ **Measured 2026-10-12.** Every freshness workflow runs a check that exits
non-zero on a normal result. The step read that status on the line after the
command, and the command's exit ended the step before the line ran.

## What the 2026-10-12 run shows

`Freshness, port keyring pins`, run `38245829268`, the `archlinux-lcpu` job:

```bash
gh run view --job 114799312447 --log \
  | grep -E 'result: GONE|Process completed'
```

```
result: GONE, the pinned package no longer answers, this port is broken now
##[error]Process completed with exit code 4.
```

⭐ The check ran and answered correctly. The step had two lines after it:

```bash
scripts/check-keyring-pin "$PIN" | tee /tmp/check.txt
rc="${PIPESTATUS[0]}"
```

Neither ran. The `::error` annotation was never printed, and
`steps.check.outputs.rc` was empty, so every
`if: steps.check.outputs.rc != '0'` recovery step was skipped.

## The mechanism

GitHub Actions runs every `shell: bash` block as
`bash --noprofile --norc -e -o pipefail`. A block may add `set -u` (and these
do, `set -uo pipefail`) but `-e` stays on. A check that exits 3, 4 or 5 and the
capture of that status therefore cannot sit in that order: the shell leaves at
the check.

⛔ **The interface is not the defect.** Exiting 3, 4 or 5 is what
`tests/static/95-publish-watchdog.sh` and the freshness workflows were built
around. The step was reading that interface with the one construct `-e`
forbids.

## What changed

The command goes in a `||` list, where a non-zero status is the result the list
was written for:

| file | before | after |
| --- | --- | --- |
| `freshness-keyring.yml` | `cmd \| tee ...; rc="${PIPESTATUS[0]}"` | `rc=0; cmd \| tee ... \|\| rc=$?` |
| `freshness-keyring.yml`, apply | same shape | same fix |
| `freshness-image-pins.yml` | same shape | same fix |
| `freshness-image-pins.yml`, apply | same shape | same fix |
| `freshness-publish.yml`, recency | `cmd; rc=$?` | `rc=0; cmd \|\| rc=$?` |
| `freshness-publish.yml`, schedules | `cmd; rc=$?` | same fix |
| `build-deploy.yml`, watchdog | `cmd; rc=$?` | same fix |

⭐ `cmd || rc=$?` is already the shape the tests use, and it is not one of the
shapes `tests/static/20-no-swallowed-errors.sh` forbids. `set +e` and `|| true`
would have let the check run and then discarded its answer, which is the defect
that policy exists for.

## What each red run was trying to say

| workflow | the result that was lost |
| --- | --- |
| `freshness-keyring.yml` | the loong64 pin had been gone from its mirror since 2026-09-06, and the job no longer applied the bump |
| `freshness-image-pins.yml` | the base image digest had moved, and the job no longer applied it |
| `freshness-publish.yml` | the publish had stopped, but the run said `the recency check could not run` instead of `the newest dated index tag is older than the schedule allows` |
| `build-deploy.yml` | the watchdog produced a bare red mark and no annotation |

## What is checked by a test

`tests/static/25-pipeline-traps.sh` gained a third shape. It reports a line that
reads `rc=$?` or `PIPESTATUS` unless the command is guarded by `||`. The one
file it does not read is itself, because the regular expression is its own
source. `HISTORY/tests-seen-to-fail.md`.

⚠ **What it cannot see** is a step that reads the status through some other
variable name. `rc` is the name every step here uses; a step that invents
another would pass the scan.

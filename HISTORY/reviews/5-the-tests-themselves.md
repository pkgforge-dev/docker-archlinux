# Review 5: the tests themselves

**Lens.** For each test, break the thing it guards and confirm it fails. A test
never seen to fail is not known to work.

**Result.** All 14 test files have been made to fail against an injected fault.
The faults and the assertions that caught them are recorded in
[`../tests-seen-to-fail.md`](../tests-seen-to-fail.md), which is the evidence for
this review rather than a summary of it.

**Date.** 2026-08-26.

---

## What this review changed

Three tests were found to be weaker than they read.

⛔ **A workflow assertion that could not fail.** The publish job checked the
index for armv7 with `grep -q 'arm'`, which matches `arm64`. It would have
passed on an index with no armv7 in it at all. armv7 renders as `arm/v7` and is
now matched as such, and the negative control fails.

⛔ **A test whose subject did not exist.** `tests/image/40-evidence.sh` had never
run, because nothing generated an evidence file. It was a specification, not a
test. `scripts/gen-evidence` now writes the file, and the test has since been
made to fail ten different ways.

⚠ **An assertion that failed for the wrong reason.** `40-mirrors-reachable.sh`
required every entry to answer 200. A mirror that answers from a workstation and
403s from a GitHub runner made the repository unbuildable for a reason outside
it. The assertion is now a floor per list, which is the defect the outage
actually had, and it still names every entry that does not answer.

## What the fault injection could not reach

⛔ **The publish job's cross-registry copy.** A dry run pushes to one registry by
design, so the Docker Hub path was only exercised by the real publish, once,
successfully. There is no fault injection for it.

⛔ **The freshness jobs.** `check-keyring-pin` and `check-image-pins` have been
run by hand and made to fail three ways each. The workflows that call them have
never fired.

⚠ **The image fixtures are synthetic.** `10-shell-present` was proven against a
`FROM scratch` image, not against a real bootstrap that installed nothing. The
real failure mode produces the same missing paths, but that is reasoning, not a
measurement.

## What this review did NOT look at

- **Whether the assertions are the right assertions.** Every test was shown to
  fail on the fault it was written for. Whether a different fault would slip
  through was not explored except where noted above.
- **Test runtime.** The static suite takes about 50 seconds, dominated by the
  mirror probe. Nobody measured whether that is a problem.
- **Flakiness over repeated runs.** Each negative control was run once.
- ⛔ **The harness itself.** `tests/lib/harness.sh` has no test. A bug in `ok`,
  `fail` or `summary` would make every suite lie, and nothing guards it.

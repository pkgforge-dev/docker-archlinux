# Conventions

Keep these conventions in every change. The static suite checks most of them. [tests.md](tests.md) names the test of each rule.

## Commits

- Make one squashed commit per piece of work on `main`.
- Commit with the maintainer's own git identity. Run `git commit` with no `-c user.name`, no `-c user.email`, no `--author` and no `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variable. Check it before the push:

  ```bash
  git var GIT_AUTHOR_IDENT
  git var GIT_COMMITTER_IDENT
  ```

- Add no co-author line and no "generated with" line. Credit no tool, bot or assistant in a commit, a pull request, a document or a comment.
- `main` denies force pushes. Push the squashed commit once.

## Scripts

- A script has no extension. Its header says what it does, how to call it, and what its exit codes mean.
- A bash script starts with `#!/usr/bin/env bash` and `set -euo pipefail`. `bootstrap/any/usr/local/bin/pacman-oci` is POSIX sh, and a byte-for-byte copy of another repository's file: do not edit it.
- A python script (`scripts/status-render`) uses the standard library only. It runs as `python3 -I`, and starts itself again with `-I` when it is run without.
- A file with a `#!` line is mode 100755 in the git index: `git update-index --chmod=+x FILE`. A sourced file (`scripts/lib.sh`, `scripts/lib-mirrors.sh`, `tests/lib/harness.sh`) has no `#!` line and stays 100644. `tests/static/70-executable-bits.sh` checks this.
- A script reads its inputs as data. A conf, a pin or a port file is parsed, never sourced.
- ⛔ A script reads each fact about a port from `scripts/ports`. Never write the list of ports, aliases, platforms or pacman architectures in a script, a workflow or a test. A fixture may name ports. `tests/static/75-architecture-set.sh` fails on a line that names 3 or more ports outside `ports/`, `tests/fixtures/` and `docs/`.
- A document may show the port list. `tests/static/80-docs-claims.sh` checks the architecture table and the port badges of `README.md` against `scripts/ports`.
- Use `scripts/lib.sh` for conf parsing, HTTP reads with retries, and registry reads (`reg_token`, `reg_head`, `reg_head_limit`, `reg_get`, `reg_blob`, `reg_tags`). Do not write a second token or tag-list reader.

## Failures stay visible

⛔ Never hide a failure.

- Do not write `|| true`, `set +e` or `continue-on-error`.
- Do not send the output of a command that matters to `/dev/null` (`2>/dev/null`, `>/dev/null 2>&1`). A needed exception goes into `tests/policy/swallowed-errors.allow`, with a reason.
- Capture an exit status as `rc=0; cmd || rc=$?`, then act on it.
- Give every curl call `--connect-timeout`, and `--max-time` or `--speed-time`. Give every other network call a deadline: `timeout -k 5 N`.
- Give every gpg keyserver call `--keyserver-options timeout=N`.

`tests/static/20-no-swallowed-errors.sh` and `tests/static/65-fetch-policy.sh` check these rules.

⛔ Do not end a pipeline in a reader that stops early under `pipefail`: `head -n1`, `grep -q`, `grep -m`, `awk '... exit'`. The producer gets SIGPIPE and the script ends with status 141. Read the whole stream and decide at the end, for example `awk 'NR == 1'`. Do not count with `grep -c`: a count of 0 is exit status 1. `tests/static/25-pipeline-traps.sh` checks both.

- Each failure message says what was measured and gives a line to reproduce it.
- A step that raises or clears an issue runs with `if: always()` or `if: ${{ !cancelled() }}`, so a failed check still reports.

## Workflows

`tests/static/51-workflow-policy.sh` checks each rule:

- `permissions: {}` at the top. Each job asks for what it needs.
- `runs-on: ubuntu-24.04`, a pinned label, never `*-latest`. Renovate moves the label, and a person merges that update.
- `timeout-minutes` on every job. A job that calls a reusable workflow cannot have one; the jobs of the called workflow have their own.
- `shell: bash` by default, so each `run:` block runs with `-eo pipefail`.
- Each action pinned by a 40 hex commit, with the version in a comment: `uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`.
- `persist-credentials: false` on each checkout, unless the job has `contents: write`.
- No `${{ inputs.* }}`, `${{ matrix.* }}`, `${{ needs.* }}`, `${{ github.event.* }}` or `${{ github.head_ref }}` inside a `run:` block. Pass the value through `env:`.
- No `pull_request_target` trigger. `workflow_run` only in `bot-merge.yml`.
- No unquoted `if: !...`, which YAML reads as a tag.
- No job that writes cancels a run in progress.
- `upload-artifact` with `overwrite: true`, so a re-run can upload again.
- Nothing deletes a package version or a manifest. No tag is ever deleted.
- ⛔ Keep the workflow name `CI` and the job name `Static suite and linters`. Branch protection and `bot-merge.yml` read them.

## Images

- Pin each image as `name:tag@sha256:<64 hex>`.
- Write a `# tag: <tag>` line at most 3 lines before the pin, with the tag of the pin. Renovate and `scripts/check-image-pins` read that line. `tests/static/50-supply-chain.sh` and `tests/static/89-bot-merge-guard.sh` check each pin.
- The base image of the Dockerfile is an `ARG BASE_IMAGE` of that shape. The build can take the same digest from another registry.

## Tests

- Output is TAP, through `tests/lib/harness.sh`.
- A failed assertion prints what was measured and a `reproduce:` line. `tests/static/15-actionable-failures.sh` checks each `fail` call.
- ⛔ See each new or changed assertion fail once. Break the code or the fixture in a copy, run the test, see `not ok`, and keep the tree as it was. Record the test, the fault and the `not ok` line in [tests.md](tests.md).
- The static suite is hermetic: no network and no container runtime. A live read goes into `tests/network/`.
- A test that needs a tool calls `need_tool`. Under `TESTS_REQUIRE_TOOLS=1` (CI sets it), a missing tool is a failure.
- ⛔ A test asserts behaviour or structure, not wording. Do not match comment text, message text or YAML indentation. Read YAML with `yq`, use job ids and step ids, and run scripts on fixtures.

## Measurements

- Every number in the documents comes from the code or from a measurement. [measurements.md](measurements.md) gives the date and the source of each measurement.
- ⚠ Do not take timings in Git Bash on Windows. A process start costs about 165 ms there.

## Text

Comments, messages, documents, issue bodies and test names use ASD-STE100 Simplified Technical English.

- Write one idea per sentence.
- Keep a procedural sentence to 20 words or fewer, and a descriptive sentence to 25 words or fewer.
- Use the active voice. Use the imperative for an instruction. Use simple tenses.
- Use simple, approved words: use, do, make, start, stop, show, get, put, set, read, write, check, find, keep, give, try. Do not use utilize, leverage, ensure, robust, seamless, comprehensive, deliberately, simply, just, very, really, "note that" or "in order to".
- Use one name for one thing: "port", "leg", "anchor", "pin", "the GHCR mirror", "the Worker".
- Put a warning before the step it applies to.
- State the fact, the rule and the measurement. Write no narrative history: no "we found", no "used to", no "the previous session", no run id outside [measurements.md](measurements.md). Dates of events go in [measurements.md](measurements.md) only.
- Do not use em dashes or marketing adjectives.
- When a value is not known, write a dash or "unknown". Never write a value that was not measured.

Use only these three markers, one at a time:

| marker | means |
| --- | --- |
| ⛔ | a rule that must not be broken |
| ⭐ | a property the design depends on |
| ⚠ | a caution or a known limit |

## Upstream

- Read upstream; do not write to it. File no issue, pull request or comment on an upstream tracker.
- Pin by commit hash or by content hash, never by a tag name. A tag can move.
- Copy code from another project only when its licence allows it, and record the source commit and the sha256, as `bootstrap/pacman-oci.pin` does.

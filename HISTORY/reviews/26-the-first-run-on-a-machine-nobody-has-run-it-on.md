# Review 26: the first run on a machine nobody has run it on

**Lens.** `pacman-static.yml` was written, reviewed, documented and merged, and
had never once executed on a GitHub runner. Every binary in
`HISTORY/pacman-static.md` came from a container on the maintainer's
workstation. This session ran it, three times, and it failed twice. The lens is
what that gap between "works here" and "works there" was actually made of, and
whether anything else in this repository sits in the same gap.

**Date.** 2026-08-29, against `03e5442`.

⚠ Distinct from review 5, the tests themselves, which asks whether assertions
can fail. This asks what a workflow's never having run hides, and it is answered
by measurements from three real runs rather than by reading.

---

## What was opened

- `.github/workflows/pacman-static.yml`, whole, 191 lines after the change.
- `scripts/build-pacman-static`, whole, 1021 lines after the change.
- `tests/static/85-pacman-static-pin.sh`, whole, 315 lines after the change.
- The full job logs of runs `33206329907`, `33208408451` and `33210060549`.
- `mesonbuild/linkers/detect.py` at tags 1.3.2, 1.4.0, 1.5.0, 1.6.0, 1.7.0,
  1.8.0, 1.9.0 and 1.10.0, fetched from GitHub.
- `tests/static/85-pacman-static-pin.sh`, whole.
- A full local reproduction in an `ubuntu:latest` container.

## Three runs, and what each cost

| run | outcome | cause |
| --- | --- | --- |
| `33206329907` | 8 of 8 failed at zlib, silently | progress on stdout captured as part of a path |
| `33208408451` | 8 of 8 built every library, failed at pacman | apt's meson is older than zig linker support |
| `33210060549` | 8 of 8 green | both fixed |

## Findings

### 1. The first defect was invisible, and that was a second defect.

⛔ **The whole of run `33206329907` said this and nothing more:**

```
==>   zlib 1.3.2
##[error]Process completed with exit code 1.
```

Every library build ended `>/dev/null`. zlib's configure printed
`Missing or broken C compiler` on **stdout**, so the one line that explained the
failure went to `/dev/null` on all eight architectures at once.

⭐ **Two separate things were wrong and fixing one would have hidden the
other.** The cause was `step() { echo "==> $*"; }` writing progress to stdout,
while `ZIGBIN="$(ensure_zig)"` takes stdout as a return value. Every compiler
wrapper therefore began:

```sh
#!/bin/sh
exec ==> zig x86_64-linux
/tmp/ps/zig/zig cc -target x86_64-linux-musl "$@"
```

⚠ **It never fired on the workstation** because `ensure_zig` prints nothing once
zig is already unpacked, which is the state of every run after the first. ⛔ A
recipe whose first run differs from its second is one nobody had taken from the
top.

Both are fixed: `step` writes to stderr, and the dispatch loop keeps a per
library log and prints its tail on failure. `tests/static/85-pacman-static-pin.sh`
now asserts both, and the second assertion is the general one: no captured
function may write progress to stdout.

### 2. The second defect was a host tool version, and the fix was to stop depending on the host.

`meson 1.3.2`, which is what `ubuntu-latest` gives through apt, cannot recognise
zig's linker banner:

```
ERROR: Unable to detect linker for compiler `.../cc -Wl,--version -static`
stdout: zig ld 0.16.0
```

⭐ **The minimum was measured, not guessed.** `mesonbuild/linkers/detect.py`
gained `elif o.startswith('zig ld')` in **1.6.0**; 1.5.0 and earlier have no
mention of zig at all.

```bash
for v in 1.3.2 1.4.0 1.5.0 1.6.0; do
  curl -s "https://raw.githubusercontent.com/mesonbuild/meson/$v/mesonbuild/linkers/detect.py" | grep -ci zig
done   # 0 0 0 2
```

⛔ **The workflow now pins meson rather than taking apt's**, and the script
asserts the minimum separately so a host with an old one fails with the version
named instead of with meson's message. ⚠ That is a new pin with no freshness
job, which policy 9 says should exist. Recorded in TODO 2.

### 3. What else in this repository has never run where it will run.

⛔ **This is the part of the review that generalises, and it produced a list.**

Counted from the API on 2026-08-29, not from memory:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/workflows --jq '.workflows[].path' | sed 's#.*/##' | while read -r w; do
  printf '%s %s %s\n' "$w" \
    "$(gh api "repos/pkgforge-dev/docker-archlinux/actions/workflows/$w/runs?per_page=1" --jq .total_count)" \
    "$(gh api "repos/pkgforge-dev/docker-archlinux/actions/workflows/$w/runs?event=schedule&per_page=1" --jq .total_count)"
done
```

| workflow | runs | of them scheduled |
| --- | --- | --- |
| `build-deploy.yml` | 374 | 348 |
| `ci.yml` | 42 | 0, it has no schedule |
| `pacman-static.yml` | 3 | 0, all this session |
| `release.yml` | 3 | 0, all this session |
| `freshness-image-pins.yml` | 1 | ⛔ **0** |
| `freshness-keyring.yml` | 1 | ⛔ **0** |
| `freshness-mirrors.yml` | 1 | ⛔ **0** |
| `freshness-pacman-static.yml` | ⛔ **0** | ⛔ **0** |
| `freshness-publish.yml` | ⛔ **0** | ⛔ **0** |

⛔ **Five workflows have never fired on their own schedule and one has never run
at all.** Three of the five carry a `# tag:` pin bump and a pull request path
that has never executed.

⚠ **Three of those had a latent defect of exactly this shape and it was found by
running `release.yml`, not by reading them.** `scripts/gen-evidence` prefers
podman, `ubuntu-latest` now carries both podman and docker, and every image in
these workflows is built with docker. `build-deploy.yml` set
`CONTAINER_RUNTIME=docker` and the two freshness workflows that call
`gen-evidence` did not. Both would have failed on their first real run.

⭐ Fixed in all of them, and `tests/static/96-release-assets.sh` now asserts that
every `gen-evidence` call in a workflow names its runtime.

### 4. The defect classes are the same two, twice.

⚠ Worth naming because they recur:

- **A value that is only correct on a warm machine.** zig unpacked, an image
  already in the store, a cached database. The first run is the only one that
  tests the cold path, and nobody runs it.
- **A host tool taken from the environment rather than pinned.** meson from apt,
  a container runtime from `command -v`. Both are upstream's mood, which policy
  6 exists to be immune to.

## What this review did not look at

- ⛔ **The other seven architectures' binaries.** Run `33210060549` is green on
  all eight and each reports a real version, but only `ppc`'s log was read line
  by line.
- **Whether the binaries are correct**, only that they link, name the right ELF
  machine, carry no `INTERP` and run under their emulator far enough to print a
  version. That is what the build asserts and it is not the same as working.
- **The freshness workflows' first scheduled runs.** They still have not
  happened. This review lists them; it did not force any.
- **Whether `ubuntu-latest` will keep carrying podman.** The runtime fix does not
  depend on it either way, which is the point of setting it explicitly.

## Change summary

Files touched: 7. ⚠ These are the session totals for each file against
`4992326`, not this review's share of them, because several were edited before
this review began and separating the two after the fact would be a guess.

```bash
git diff --numstat 4992326 -- <paths>
```

| file | added | removed |
| --- | --- | --- |
| `scripts/build-pacman-static` | 296 | 36 |
| `tests/static/96-release-assets.sh` | 412 | 0 |
| `.github/workflows/release.yml` | 425 | 0 |
| `tests/static/85-pacman-static-pin.sh` | 121 | 1 |
| `.github/workflows/pacman-static.yml` | 64 | 69 |
| `.github/workflows/freshness-keyring.yml` | 5 | 1 |
| `.github/workflows/freshness-image-pins.yml` | 5 | 0 |

# The ARM rollback exposure, and what was done about it

⭐ **Decided 2026-08-27.** The plain http mirrors stay. A version floor now
refuses a build whose anchor went backwards.

## The exposure

```bash
for a in amd64 arm64 armv7 riscv64; do
  printf '%-9s http=%s https=%s\n' "$a" \
    "$(awk '/^Server[[:space:]]*=[[:space:]]*http:\/\//' rootfs/$a/etc/pacman.d/mirrorlist | wc -l)" \
    "$(awk '/^Server[[:space:]]*=[[:space:]]*https:\/\//' rootfs/$a/etc/pacman.d/mirrorlist | wc -l)"
done
```

Re-measured 2026-08-27, unchanged from 2026-08-26:

| architecture | http | https |
| --- | --- | --- |
| amd64 | 0 | 13 |
| arm64 | 10 | 3 |
| armv7 | 10 | 3 |
| riscv64 | 0 | 7 |

20 of 46 entries are plain http, all on the two ARM ports.

⛔ **Injection is not the risk. Freezing is.** Packages are signed and
`SigLevel = Required` catches a forgery. An on-path attacker on a plain http
mirror cannot make a package the keyring will accept, and can serve an **older**
set that is validly signed. The build takes it, every signature checks out, and
the image goes backwards. Nothing in the pipeline noticed.

## Two corrections to the original framing, both measured

- The unsigned repository **database** is not ARM specific. `core.db.sig` is 404
  on Arch proper and on Arch RISC-V too, which is what `DatabaseOptional` is
  for. The differentiator is transport, not signing.
- Dropping plain http costs more than it looks. The ARM anchor is
  `http://mirror.archlinuxarm.org`, which offers no https at all, and it is the
  endpoint Arch Linux ARM recommends and the only active entry in the mirror
  list they ship. The three https servers are `fl.us`, `ca.us` and `de3`, all
  nodes of that same operator. Dropping http means dropping the recommended
  anchor and depending on one operator's three nodes.

## The decision

| option | verdict |
| --- | --- |
| drop the plain http mirrors | ⛔ **refused.** It costs the recommended anchor and the geographic spread, and leaves three nodes of one operator |
| add a version floor | ⭐ **taken** |
| record it and move on | refused. The groundwork was already there |

⭐ **The floor needs no new state.** Every architecture already publishes a tag
family named after its anchor, so the highest anchor ever published can be read
from the registry by anyone, with no token and no file to keep in sync:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:pkgforge-dev/archlinux:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ghcr.io/v2/pkgforge-dev/archlinux/tags/list?n=1000" | jq -r '.tags[]' | grep '^aarch64-7'
```

## What it does

`scripts/check-anchor-floor` runs in the resolve job, before anything is built
or pushed. It takes the anchors that job already resolved, reads the published
tag list, and refuses the run if any architecture resolved something older than
what is already published.

```bash
scripts/check-anchor-floor '{"amd64":"7.1.0.r9.g54d9411-2","arm64":"7.1.0.r9.g54d9411-2"}'
```

Measured against the real repository on 2026-08-27:

| input | result | exit |
| --- | --- | --- |
| the four current anchors | `ok` for all four, floor `7.1.0.r9.g54d9411-2` | 0 |
| `arm64` at `7.1.0.r9.g54d9411-1`, one pkgrel back | `BEHIND arm64` | 3 |
| `arm64` at `6.0.0-1` and `armv7` at `7.0.0.r1.gabcdef0-1`, `amd64` current | `BEHIND` on two, `ok` on `amd64` | 3 |
| the same, with `ALLOW_ANCHOR_DOWNGRADE=1` | reported, then taken deliberately | 0 |
| `amd64` at `7.2.0-1`, a step forward | `ok` | 0 |

⭐ **It discriminates per architecture.** A rollback on one port does not hide a
healthy resolve on another, and a healthy amd64 does not hide a rolled back
arm64.

## The two open questions from the brief, both answered

- ⛔ **`vercmp` is not on `ubuntu-latest`, and it is the only correct way to
  compare two pacman versions.** It comes from the Arch image already pinned by
  digest in the `Dockerfile`, read out of the `Dockerfile` rather than repeated,
  so there is one pin and not two. One container run compares all four
  architectures rather than one run per comparison.
- ⚠ **A legitimate upstream downgrade would block the daily publish.** A port
  can revert a pkgrel. `allow_anchor_downgrade` is a `workflow_dispatch` input,
  so taking one is a named deliberate act with a run behind it, and not a
  silent pass. `tests/static/35-publish-targets.sh` asserts that the input
  exists, that the workflow calls the script, and ⛔ that the override is not
  switched on in the workflow itself, because a guard that always passes reads
  exactly like one that works.

## What this does not do

- ⚠ It does not detect a rollback **within** an anchor version. A mirror serving
  an older `bash` while `pacman` is current passes the floor. The anchor is one
  package, chosen because every port has it and its version carries the commit
  it was built from. A per package floor would need the evidence file from the
  previous build as an input, which is a state file, which is what this avoids.
- ⚠ It does not protect the **first** build for a new architecture. With no
  published tag there is no floor, and the script says so and passes.
- ⚠ It reads GHCR only. Both registries hold the same 161 tags, checked in
  [`defect-parity.md`](defect-parity.md), and reading one is enough for a floor.
  If the two ever diverge, the floor is the lower of the two.

# Review 1: a consumer who upgrades blind

**Lens.** Someone who pulls a tag and never reads the repository. Does every
published tag resolve to what the documentation says it does, and did the first
real publish change anything under an existing consumer?

**What was looked at.** All 161 tags on both registries, before and after the
first real publish. Every alias family. Every tag shape. `:latest` and
`v<date>` on both registries. A live pull and run on all four platforms.

**Date.** 2026-08-26, against run `32992678276`.

---

## Nothing was taken away

```bash
comm -23 <(jq -r '.tags[]' before.json | sort) <(jq -r '.tags[]' after.json | sort)
```

Empty. All **136** tags that existed before the publish still exist. GHCR went
from 136 to **161**, Docker Hub from 136 to **161**, and the two tag sets are
identical:

```
GHCR: 161   Hub: 161   on GHCR but not Hub: 0
```

25 names were added per registry. The 26th, `latest`, already existed and moved,
which is what a rolling tag is for.

## `:latest` still means what it meant

| | platforms |
| --- | --- |
| before | `amd64`, `arm/v7`, `arm64`, `riscv64` |
| after | `amd64`, `arm/v7`, `arm64`, `riscv64` |

Same on Docker Hub. A consumer pinned to `:latest` or to any `v<date>` sees the
same shape they saw before.

## The alias claim in the README holds

The README says the alias names for one architecture "share one manifest, so
`x86_64` and `amd64` are two names for one digest". Checked by digest:

| architecture | names | one digest |
| --- | --- | --- |
| amd64 | `x86_64`, `amd64` | yes, `sha256:c1820c0bac0a939e273...` |
| arm64 | `aarch64`, `arm64` | yes, `sha256:9de9fe088e31ad102bf...` |
| armv7 | `armv7l`, `armv7h`, `armv7` | yes, `sha256:dc92a8f0f9c2f63d848...` |
| riscv64 | `riscv64` | one name by design |

The three shapes for one alias also agree today, because a rolling tag, a dated
tag and an anchor tag all point at the build that just happened:

```
x86_64                       sha256:c1820c0bac0a939e273...
x86_64-v2026.08.26           sha256:c1820c0bac0a939e273...
x86_64-7.1.0.r9.g54d9411-2   sha256:c1820c0bac0a939e273...
```

⚠ They diverge on the next build. `x86_64` moves, the other two do not.

## A blind pull works on all four platforms

Both registries, both routes:

| platform | `:latest` reports | Docker Hub per-architecture tag reports |
| --- | --- | --- |
| `linux/amd64` | `pacman 7.1.0.r9.g54d9411-2` | `x86_64` |
| `linux/arm64` | `pacman 7.1.0.r9.g54d9411-2` | `aarch64` |
| `linux/arm/v7` | `pacman 7.1.0.r9.g54d9411-2` | `armv7l` |
| `linux/riscv64` | `pacman 7.1.0.r9.g54d9411-2` | `riscv64` |

All four report the anchor version the tag family is named after, so the anchor
tag is not a claim, it is checkable from inside the image.

## What this review found

⛔ **One documented claim was wrong and is now corrected.** `examples/01` said a
single-architecture tag is a bare manifest and needs no `--platform`. It is not:
`imagetools create` wraps even one digest in an index and records the platform,
so a foreign architecture tag fails without `--platform`:

```
docker pull ghcr.io/pkgforge-dev/archlinux:aarch64
no image found in image index for architecture "amd64", variant "", OS "linux"
```

A consumer hitting that has no way to guess the cause from the message. Fixed in
the example and in the README.

⚠ **The image ships no package database.** `pacman -Q` prints
`warning: database file for 'core' does not exist`. That is deliberate and
matches what the published image has always done, because a shipped database is
stale the moment anyone pulls it. A consumer runs `pacman -Sy` first. It is
documented in `examples/05-as-a-base-image.Dockerfile`.

## What this review did NOT look at

- ⛔ **Anything before 2026-05-15.** The 136 pre-existing tags were compared by
  name only. Whether an old dated tag still pulls and runs was not tested.
- **Image size as a consumer experience.** The new builds are smaller than the
  published ones on every architecture, which changes pull times, and nothing
  here measured whether that matters to anyone.
- **The `unknown/unknown` entries** in the index, which are the provenance and
  SBOM attestations. Old tooling that does not filter them may show four extra
  entries. Not tested against old tooling.
- **Docker Hub's rate limits** for an anonymous consumer.
- **Whether any downstream consumer actually pins by digest**, which is what the
  documentation recommends.

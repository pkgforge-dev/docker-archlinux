# Pinned tags are created once

⭐ **Decided 2026-10-15.** A pinned tag is created by the first build that
names it and is never pointed at another image: `v<date>`, `<alias>-v<date>`
and `<alias>-<anchor>`. `latest` and `<alias>` move with every build. The
maintainer asked for the rule that is easier to maintain. This is it: one rule
for every pinned family, in one place, under one test. The other choice, an
anchor tag that follows the newest build with its pacman version, is a second
rule with its own tests.

## What moved

`README.md` said all three pinned families never move. The publish job created
every tag on every build, and only the backup cron stood down when the day's
`v<date>` existed. So a second real publish on one day moved that day's dated
tags. The runs whose `Create tags` job succeeded, read from their logs:

```bash
gh run list --workflow build-deploy.yml --limit 200 --json databaseId --jq '.[].databaseId'
gh run view RUN --log | grep -E '^Create tags' | grep -oE 'ghcr\.io/pkgforge-dev/archlinux(-ci)?:v[0-9.]+' | sort -u
```

| day | real publishes of `v<date>` | runs |
| --- | --- | --- |
| 2026-08-26 | 5 | `32992678276`, `33003974783`, `33005958600`, `33008010432`, `33009605655`, all dispatches |
| 2026-08-28 | 3 | `33184973002` dispatch, `33195147714` schedule, `33206327128` dispatch |
| every other day with a real publish, 2026-08-29 to 2026-10-14 | 1 | |

⚠ On 2026-08-28 the last of the three added the PowerPC ports, so
`v2026.08.28` went from five platforms to eight. Completed row 42 of
`HISTORY/CONTINUE.md` records that as a result. It was also a pinned tag
moving.

⚠ The anchor tags moved every day, not only on days with two builds. pacman
stayed at one version for weeks, and each build created
`<alias>-7.1.0.r9.g54d9411-2` again. Measured 2026-10-15 on GHCR: `x86_64`,
`x86_64-v2026.10.14` and `x86_64-7.1.0.r9.g54d9411-2` were one digest,
`sha256:690e2a8d99a37a5f64c6d45d78d367f9211f94c4e2bf698e57c59b78ab758275`,
and `x86_64-v2026.10.13` was another. So the anchor tag had moved from the
2026-10-13 image to the 2026-10-14 image.

## Who pins what

GitHub code search, 2026-10-15:

| search | results |
| --- | --- |
| `"pkgforge-dev/archlinux:v2026"` | 11. Nine are outside this repository: three release workflows of `VSCodium/vscodium`, their copies in `crow-cli/crow-cli`, and one each in `stoatchat/for-desktop`, `Chillboio-Studios/Dawnchat-For-DESKTOP` and `edgarcnp/homebrew-tap` |
| `"pkgforge/archlinux:v2026"` | 1, in this repository |
| `"pkgforge-dev/archlinux:x86_64-v2026"` and the Docker Hub name | 0 |
| `"pkgforge-dev/archlinux:x86_64-7"` and the Docker Hub name | 0 |

```bash
gh api -X GET search/code -f q='"pkgforge-dev/archlinux:v2026"' --jq .total_count
```

The dated index is what consumers pin, and a moved one gives a consumer who
pinned it another image. No result pins an anchor tag, so freezing those is a
change nobody found in use.

## How

1. The publish job reads the target repository's tag list with
   `scripts/registry-tags`, before it creates a tag. GHCR is read because every
   digest is staged there, and one `imagetools create` gives both registries
   their tags.
2. Both tag steps pass that list to `scripts/tag-names --existing`, which
   leaves out each pinned tag on it and names it on stderr. A tag that is not
   passed to `imagetools create` cannot move.
3. The verify step reads the platforms of `latest`, which this run always
   writes, and requires the dated index to exist. A dated index from an earlier
   build of the day carries that build's platforms.

⛔ A list that cannot be read stops the publish. Read as empty, it would move
every pinned tag. That is the same choice as the anchor floor: a guard that a
transient switches off is not a guard.

The backup cron still stands down when `v<date>` exists. It saves the runner
time; it is no longer what keeps the dated tag in place.

## What it changes for a consumer

| case | before | after |
| --- | --- | --- |
| a second build on one day, a dispatch or a cron | every tag of that day moves | `latest` and `<alias>` move |
| a build with the same pacman version as yesterday | `<alias>-<anchor>` moves | `<alias>-<anchor>` stays on the first image with that version |
| a port that published nothing earlier in the day | its `<alias>-v<date>` is created | the same |
| the emergency path, TODO 4: a dispatch after the day published | moves every tag of the day | moves the rolling tags. The fix reaches `latest` and `<alias>`, and the dated tags keep the morning's image |

⚠ An anchor tag that exists now stays where it is, so each
`<alias>-7.1.0.r9.g54d9411-2` keeps the image it pointed at when this change
landed.

⚠ If the first image with a pacman version is defective, its anchor tag keeps
it. The rolling and the next day's dated tags carry the fix.

## Measured

Dry run `38675434990` on a branch, into the scratch repository, the second
build of 2026-10-15 there. The first was dry run `38670811239`. Digests read
anonymously before and after, first 12 hex digits:

| tag in `ghcr.io/pkgforge-dev/archlinux-ci` | before | after |
| --- | --- | --- |
| `latest` | `445762b79215` | `6ee338a7249d` |
| `v2026.10.15` | `445762b79215` | `445762b79215` |
| `x86_64` | `316148d98390` | `dc77face842c` |
| `x86_64-v2026.10.15` | `316148d98390` | `316148d98390` |
| `x86_64-7.1.0.r9.g54d9411-2` | `316148d98390` | `316148d98390` |
| `aarch64` | `ddf3f281cbab` | `e74f4e376390` |
| `aarch64-v2026.10.15` | `ddf3f281cbab` | `ddf3f281cbab` |
| `aarch64-7.1.0.r9.g54d9411-2` | `ddf3f281cbab` | `ddf3f281cbab` |
| `riscv64` | `aa6be4315646` | `80b633486e7b` |
| `riscv64-v2026.10.15` | `aa6be4315646` | `aa6be4315646` |
| `riscv64-7.1.0.r9.g54d9411-2.1` | `aa6be4315646` | `aa6be4315646` |

The rolling tags moved and the pinned ones did not. The tag steps named 21
pinned tags as kept, which is every pinned tag of the five ports that built,
four for amd64, arm64 and loong64, six for armv7, two for riscv64, and
`v2026.10.15`. The verify step read the platforms of `latest`:
`published ghcr.io/pkgforge-dev/archlinux-ci:latest with platforms amd64 arm/v7 arm64 loong64 ppc ppc64 ppc64le riscv64, and ghcr.io/pkgforge-dev/archlinux-ci:v2026.10.15 exists`.

```bash
gh run view 38675434990 --log | grep -E '^Create tags' | grep -c 'is pinned and exists'
```

## What this does not verify

- ⚠ Docker Hub. The list is read from GHCR only. A pinned tag that exists on
  GHCR and not on Docker Hub, because an earlier copy failed, is not created on
  Docker Hub again. That earlier run's verify step fails loudly on the missing
  copy.
- ⚠ Two aliases of one architecture can diverge if one pinned name exists and
  the other does not. Both are created by one command, so that needs an earlier
  partial failure.

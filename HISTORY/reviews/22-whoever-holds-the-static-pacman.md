# Review 22: whoever holds the static pacman and no base image

**Lens.** Somebody has one binary from a release and nothing else: no Arch host,
no `pacman`, no keyring, no container runtime. The guide says they can build a
working root. This review asks what they actually have, what the guide asks them
to trust, and where it would leave them if a step failed.

**Date.** 2026-08-28, against the working tree of the commit this ships in.

⚠ This lens was named in the brief as fitting the work outstanding, and it is
new. Distinct from review 1, a consumer who upgrades blind, which is about
somebody who already has the image.

---

## What was opened

- `docs/bootstrap-with-pacman-static.md`, whole, 247 lines, the file under
  review.
- `scripts/build-pacman-static`, whole, 761 lines.
- `bootstrap/pacman-static/sources.pin`, whole, 105 lines.
- `scripts/release-notes`, whole, 154 lines.
- `.github/workflows/pacman-static.yml`, whole, 196 lines.
- `tests/static/85-pacman-static-pin.sh`, whole, 195 lines.
- `tests/static/80-docs-claims.sh`, the block extraction, lines 89 to 145.
- The eight evidence files the build wrote, in `/work/dist`.

## What was compared

Every claim the guide makes about what the reader needs, against what the
scripts actually require, and every command in it against whether anything
checks it.

## What was found

### 1. ⭐ The reader is asked to trust one thing, and it is named

The binary is `pacman` and nothing verifies it for them: a release asset has a
`SHA256SUMS` beside it and both come from the same place. The guide does not
claim otherwise. What it gives instead is the recipe: every input pinned by
`sha256` or by commit, so a reader who does not trust the asset can build the
same binary and compare.

⭐ **That is the honest shape**, and it is the reason `bootstrap/pacman-static/sources.pin`
is a file in the repository rather than a step inside a workflow.

⚠ **The comparison is not byte for byte and the guide does not say so.** Two
`amd64` builds from one script and one pin, on one host, produced different
`sha256` values. `HISTORY/pacman-static.md` records that measurement. A reader
following the guide to check an asset would find a different hash and have no
way to tell that from tampering.

⛔ **That is a real gap in the guide.** It is recorded here rather than fixed,
because fixing it means either making the build reproducible or telling the
reader to compare something other than the hash, and neither is a paragraph.

### 2. ⭐ The two pass shape is stated as a trust boundary, not a procedure

The guide says in three places that pass one verifies nothing, and says why:
`pacman-key` is a shell script that drives `gpg`, and there is no `gpg` inside a
static `pacman`. A reader who stops after pass one has a root that downloaded
correctly and is unverified.

⚠ **Nothing stops them stopping.** The guide is prose, and the commands work
one at a time. A reader who runs pass one and walks away has an unverified root
and no marker on it saying so. The reference this was studied from has the same
property.

### 3. ⚠ Four host requirements are named and one is easy to miss

`/etc/ssl/certs/ca-certificates.crt` is a compiled in path, not embedded data.
The guide names it twice, once in the requirements table and once in what it does
not remove, with the `http` fallback. That is the one a reader on a minimal
rescue system will hit, and it fails as a TLS error that reads like a mirror
problem.

⭐ Checked against the build: `--with-ca-bundle` is passed that exact path in
`build_curl`, with a comment naming the same consequence. The guide and the
recipe agree, which they would not if either had been written from memory.

### 4. ⛔ Every command in the guide parses and none of them has been run

`tests/static/80-docs-claims.sh` now discovers `docs/`, so all 29 fenced blocks
across the documentation are fed to `bash -n`. That catches the class the old
README shipped, a block that cannot run at all.

⛔ **It does not catch a block that runs and does the wrong thing.** The guide's
central claim, that these commands produce a root that passes this repository's
image suite, is unexecuted. `HISTORY/pacman-static.md` says so under what is not
proven, and it is the largest single gap in this task.

### 5. ⚠ The architecture table in the guide is a fourth copy

The keyring table lists which `--populate` argument each architecture needs. The
same fact lives in `bootstrap/keyrings/*.pin` as `arch =` lines, in
`install-port-keyring` as the pin lookup, and in the reference corpus as G-11.
Nothing checks the guide's copy against the pins.

⚠ **Small and real.** A port whose keyring name changed would leave the guide
wrong with every test passing. The pins are the authority and the guide does not
say so.

### 6. ⭐ The release refuses an asset nobody ran

`pacman-static.yml` reads `reported_version` from each evidence file and fails
the job when it says `NOT MEASURED`. `scripts/release-notes` separately refuses
a binary with no evidence, an evidence file with no binary, and a set built from
more than one `pacman` commit.

⭐ Those are three different partial failures, each of which produces a release
that looks complete. Reading them together was what this review was for, and
they hold.

⚠ Neither has run. The workflow has never executed on a runner and no release
exists. `release-notes` was run by hand against a directory of eight built
assets, which is how the table in `HISTORY/pacman-static.md` was produced.

## ⚠ What this did not look at

- ⛔ **Whether the binary is correct.** It links, it names the right machine, it
  has no `PT_INTERP` and it prints a version under emulation. Nothing here
  installed a package with it.
- **The eleven libraries as software.** Their versions are pinned and their
  hashes measured. No CVE check, no audit, no comparison against what Arch's own
  `pacman` links.
- **`qemu-user` as an oracle.** Every non `x86_64` claim rests on it. The guide
  says so; this review did not test the claim.
- **The AUR reference's own recipe.** `HISTORY/references/static-pacman-reference-roles.md`
  records what each reference is for. This review read the guide against this
  repository's scripts, not against theirs.
- **Licence compliance in practice.** The source offer is the pin, and no
  release exists to carry it.

## Change summary

Files touched by the change this reviews: 57 changed, 4186 insertions, 88
deletions against `dcf9263`. The parts this review covers: `scripts/build-pacman-static`
761 lines new, `docs/bootstrap-with-pacman-static.md` 247 new,
`bootstrap/pacman-static/sources.pin` 105 new, `tests/static/85-pacman-static-pin.sh`
195 new, `.github/workflows/pacman-static.yml` 196 new, `scripts/release-notes`
154 new. This review adds no change of its own.

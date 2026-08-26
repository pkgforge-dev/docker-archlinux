# The rewrite

`main` carries one commit. Everything before it is on the
[`history-archive`](https://github.com/pkgforge-dev/docker-archlinux/tree/history-archive)
branch, whose tip is `9d1e1429259625323139cb39dd1c81764c73501d`.

⭐ **Nothing about the published images changed shape.** Same registries, same
organisation names, same tag families, same `:latest`. No tag was removed from
either registry.

## Why

The build had defects that a reader could not see from the tree, and the commit
history recorded the discovery rather than the result. The two together made the
repository hard to audit, so it was rebuilt and the history archived instead of
patched.

What the rebuild was for:

- **A bootstrap that does not need its own output.** The Dockerfile built
  `FROM ghcr.io/fwcd/archlinux:latest`, its own published image. It now builds
  from the official Arch image, pinned by digest.
- **Signature checking that stays on.** A patch to `pacman-key` added
  `--allow-weak-key-signatures` to work around marginal trust on the ARM ports.
  That is gone. `bootstrap/keyrings/archlinuxarm.pin` pins the Arch Linux ARM
  keyring by sha256 and by master key fingerprint, and `SigLevel = Required`
  holds on every architecture.
- **A publish that cannot half-succeed.** One job per architecture pushes by
  digest and creates no tag. A merge job needing the whole matrix creates every
  tag. A run that loses one architecture publishes nothing.
- **Evidence per build.** Every package, its version, its size, its sha256 and
  its release date, per platform, beside a provenance attestation and an SBOM.
- **Pins that cannot go stale quietly.** Every pinned thing has a scheduled job
  that checks it, tests the bump and opens a pull request carrying the
  measurement.
- **Tests that have been seen to fail.** Every assertion has a recorded fault
  that makes it fail, in [`tests-seen-to-fail.md`](tests-seen-to-fail.md).

## What is recorded here

| file | what it holds |
| --- | --- |
| [`removed-architectures.md`](removed-architectures.md) | ppc64le and i686, each with the measurement that excluded it |
| [`tests-seen-to-fail.md`](tests-seen-to-fail.md) | every test, and the fault that makes it fail |
| [`maintainer-actions.md`](maintainer-actions.md) | what only the repository owner can apply |
| [`noextract-reverted.md`](noextract-reverted.md) | a downstream break, and why the image now withholds nothing |
| [`references/`](references/) | the projects studied, each with a verdict |
| [`reviews/`](reviews/) | the deep reviews, each with its lens and its blind spot |
| [`misc/`](misc/) | the working brief, and what is still outstanding |

## The archive

```bash
git fetch origin history-archive
git log --oneline origin/history-archive
```

⛔ It is kept, not merged. Nothing on `main` derives from it by ancestry.

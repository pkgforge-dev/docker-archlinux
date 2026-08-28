# kth5/archpower

The ArchPOWER port itself. Read because this repository now depends on that
project's repository layout in four places, and policy 11 requires mining a
reference before depending on it. ⚠ It was named in TODO 3 as the place where a
change to that layout would appear first.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/kth5/archpower` |
| commit read | `96e3c9b257a17e0aa2fb531e59cc45d7b6b6f2d6` |
| commit date | 2026-08-28 |
| commit subject | `* update aubio to 0.4.9-24.1` |
| clone depth | 1 |
| licence | **none.** The API reports `null` and the tree carries no `LICENSE` |
| tracker read | 128 items: **76 issues**, 52 pull requests, discriminated on the `pull_request` field |
| issues by state | 63 closed, 13 open |
| top level entries | 1825, of which 1823 are package directories |
| tracked files | 28253 |
| default branch | `master` |
| last push | 2026-08-28 |
| archived, fork | no, no |
| studied on | 2026-08-29 |

```bash
git clone --depth 1 https://github.com/kth5/archpower.git
git -C archpower rev-parse HEAD
gh api --paginate 'repos/kth5/archpower/issues?state=all&per_page=100' \
  | jq -s 'add | {issues:[.[]|select(has("pull_request")|not)]|length, pulls:[.[]|select(has("pull_request"))]|length}'
```

⛔ **The working tree could not be checked out on this workstation and it is
worth saying so rather than implying a full read.** `git clone` completed and
then failed at checkout: the tree holds paths Windows will not create, so
`git status` reports 28253 deletions against an empty directory. Everything
below was read through `git show HEAD:<path>` and `git ls-tree`, which read the
objects rather than the working tree, so the content is the commit's. ⚠ What was
not done is a filesystem level survey.

⛔ **No licence.** The repository publishes PKGBUILDs and carries no licence
file and no SPDX identifier. Nothing from it is vendored here and nothing needs
to be: policy 1's route is vendor, then patch, then document, and this reference
required none of that. ⚠ Anyone who does want to copy from it has no grant to
rely on.

## What it is, and what it is not

⛔ **It is a PKGBUILD collection, not the infrastructure.** 1823 of the 1825
top level entries are package directories. The two that are not are `README.md`
and `CONTRIBUTORS.txt`.

⚠ **So the repository layout this project depends on is not defined here.**
There is no publish script, no repository configuration and no mirror list in
the tree. A layout change would appear here only as a side effect. ⭐ That
answers the question TODO 3 asked, and the answer is the opposite of what was
assumed: watching this repository would **not** show a layout change first.

⭐ **One file family does state the layout, and it is the useful find.**
`cross-compilers/*/pacman.conf` are ArchPOWER's own pacman configurations for
its cross toolchains. They are the project's own statement of how its
repositories are addressed.

```bash
git show HEAD:cross-compilers/powerpc-unknown-linux-gnu-pacman/pacman.conf
```

```
Architecture = @@CARCH@@
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
[base-any]
Server = https://repo.archlinuxpower.org/base/any
[base]
Server = https://repo.archlinuxpower.org/base/$arch
```

⭐ **Every load-bearing choice this repository made for the PowerPC ports is the
one upstream makes for itself**, read side by side with
`rootfs/ppc/etc/pacman.conf`:

| this repository | ArchPOWER's own |
| --- | --- |
| `[base]` from the `$repo/$arch` mirror list | `Server = .../base/$arch` |
| `[base-any]` as a second section with its own mirror list | `[base-any]`, `Server = .../base/any` |
| `SigLevel = Required DatabaseOptional` | identical |
| `LocalFileSigLevel = Optional` | identical |

⚠ **The section name matches too, and it was arrived at independently.**
`base-any` is what this repository called it and what upstream calls it. Nothing
required that; a second section could have been named anything.

⚠ **An asymmetry worth recording.** The `powerpc64le` configuration carries
`[testing]` and no `[base-any]`; the 32 bit `powerpc` one carries `[base-any]`
and no `[testing]`. Both `base/any` and `testing-any` exist on the server, seen
in issue 149's pacman output. ⛔ So `base/any` is not a 32 bit special case, and
this repository is right to ship the second list for all three ports.

⚠ **A fifth architecture exists upstream and is not built here.** PKGBUILDs
declare `arch=(x86_64 powerpc64le powerpc64 powerpc espresso)`. `espresso` is
the Wii U's PowerPC variant. Nothing here needs it and nothing about the three
adopted ports depends on it.

## The tracker

⭐ **Closed is where the decisions are**, and four of them bear on this project.

### Issue 69, and the 403 this repository works around

**"You are unable to access archlinuxpower.org"**, opened and closed
2023-12-29. A user could not reach the site; `everything works through vpn`.
The maintainer's answer, in full, is a statement of policy:

> After careful consideration I blocked all traffic from the Russian Federation

⭐ **This changes what the repository's own 403 means.** `HISTORY/powerpc.md`
records `repo.archlinuxpower.org` answering 403 to every GitHub runner and 200
from a workstation, with a Cloudflare interstitial, and treats it as an
unexplained bot rule. The origin is known to block whole networks deliberately.

⚠ **That is a lead, not a diagnosis.** Nothing in the tracker says GitHub's
ranges are blocked, and no issue names a CI runner. What it establishes is that
network level blocking is this origin's normal practice, so ⛔ **the read
through proxy should be treated as permanent rather than as a workaround waiting
for upstream to fix something.** Nobody upstream has been asked and, under
policy 1, nobody will be.

### Issue 149 and discussion 150, the key that expired

**"PGP key changed recently?"**, closed 2026-03-06. Every database failed:

> error: base: key "D201F92AE42528456537C3F9B96775F34689694C" is unknown

Discussion 150, `MANUAL INTERVENTION REQUIRED (archpower-keyring)`, gives the
cause in the maintainer's words:

> the ultimately trusted pubkey used for signing packages and the pacman.db
> files expired and cannot be seemlessly be refreshed in the pacman keyring
> anymore

⛔ **This is the exact failure `scripts/check-keyring-pin` and
`.github/workflows/freshness-keyring.yml` exist to see coming**, and it happened
to this port five months before the port was adopted here.

⭐ **The repository is already on the right side of it.** The replacement key is
what `bootstrap/keyrings/archpower.pin` pins, with its expiry:

```
trusted = D201F92AE42528456537C3F9B96775F34689694C 2031-02-22
```

⚠ **What this does not prove.** The pin carries the key that replaced the
expired one, so this specific event is behind us. It does not show that the
weekly check would have caught the original in time: nobody has seen that
annotation fire, which is still open as a task.

### Issue 28, an anti-pattern exhibit

**"[powerpc32] pgp keys outdated/missing"**, 2021, closed 2022-01-11. The
reporter's stated workaround:

> my dirty workaround is to set SigLevel = Never in /etc/pacman.conf

⛔ **This is the thing policy 5 forbids, in the wild, on this exact port.**
`tests/static/30-signature-checking-on.sh` fails on it. The upstream fix was a
new keyring package and a corrected ISO, not a weakened `SigLevel`, which is the
same answer this repository would give.

⚠ The root cause is recorded there too and is not a signing problem at all: a
`haveged` systemd unit misbehaving on `powerpc` meant `pacman-key --init` never
ran. ⭐ A missing key and a key that was never imported look identical to a user.

### Issue 140, a second publisher that is not one

**"Alternative packages repo"**, opened 2025-11-12, **still open**.
`Link4Electronics` is building powerpc64 packages and publishing them at
`github.com/Link4Electronics/archpower-packages` and on archive.org.

⚠ **Filed against TODO 6, and refused as a second trust root.** The single
publisher is the standing PowerPC risk. This is not a fix for it: the packages
are an individual's uploads with no keyring, no signing story stated in the
thread, and no repository database mentioned. ⛔ Adding it would mean trusting a
second signer that the `archpower-keyring` package does not name, which is a
larger change than the redundancy it buys.

### Issue 30, what repositories exist

**"community and extra repo, what to do?"**, closed 2024-05-06. The answer is
that neither exists for PowerPC and packages have to be built by hand.

⭐ **Confirms the two repository assumption.** This repository configures `base`
and `base-any` and nothing else, and there is nothing else to configure. ⚠ There
is also `testing` and `testing-any`, which this repository deliberately does not
ship, consistent with the other five ports.

### What was searched and found nothing

⚠ Filtered all 76 issues for `repo`, `mirror`, `sign`, `key`, `any`, `base`,
`database`, `db`, `404`, `403`, `arch`, `layout`, `url`, `server`, `host`. That
returned 14, of which the five above are the ones bearing on this project. ⛔ No
issue discusses a change to the repository path layout, and none names a CI
system, a container image or a GitHub runner.

## Verdict: confirms

⭐ **Nothing here is adopted, because nothing needs to be.** Every PowerPC design
decision this repository made independently is the one upstream makes for
itself, down to the `base-any` section name.

⛔ **Two things changed as a result**, and both are corrections to what this
repository believed rather than to what it does:

1. **`kth5/archpower` is not where a layout change would appear first.** TODO 3
   said it was. It is a PKGBUILD collection with no infrastructure in it. The
   `cross-compilers/*/pacman.conf` files are the closest thing to a layout
   statement, and they are a by-product.
2. **The 403 is not a bot rule to wait out.** The origin blocks networks by
   policy and has said so. The proxy is a permanent second path.

⚠ **Re-mine on every bump**, per policy 11. The thing to re-read is
`cross-compilers/*/pacman.conf`: if a repository is added, renamed or moved,
that is where it will show.

⛔ **Not mined, and named so the gap is visible**: `kth5/archiso`,
`lcpu-club/loongarch-packages`, `lcpu-club/loongshot/tree/main/scripts`. All
three remain open under policy 11.

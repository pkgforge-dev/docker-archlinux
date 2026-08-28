# Every test, and the fault that makes it fail

⭐ **A test that has never been seen to fail is not known to work.** A test can
pass because the thing it guards is healthy, or because it asserts nothing. The
two look identical in a green run.

Each row below records a fault that was injected into a scratch copy of the
tree, and the assertion that caught it. Measured 2026-08-26, the `45` and `60`
rows on 2026-08-27, and the `68`, `gen-evidence`, `90` and port keyring rows on
2026-08-28. Nothing here was injected into the repository itself.

⚠ A quoted failure message is what that run printed. Counts inside one, such as
the number of `fail` calls, are the value at the time and are not kept current.

Re-run any of these by copying the tree to a scratch directory, applying the
fault, and pointing `REPO_ROOT` at that directory.

## Static suite

| test | fault injected | caught by |
| --- | --- | --- |
| `00-workflow-branch-buildable.sh` | the pre-change workflow, which hand-cloned the default branch | `not ok 1 - actions/checkout is used`, `not ok 2 - the workflow does not hand-clone the repository`, `not ok 3 - build context is the workspace` |
| `00` | `actions/checkout@v7.0.1`, a pin rewritten back to a tag | `not ok 1 - actions/checkout is pinned to a commit hash` |
| `05-harness.sh` | `not_ok` stops incrementing `TESTS_FAILED`, so a suite with a failing assertion exits 0 | `not ok 5 - summary returns 1 when one assertion failed` |
| `05` | `ok` stops incrementing `TESTS_RUN` | `not ok 1`, `not ok 2`, `not ok 4`, `not ok 5`, showing `ok 0 - first` and a plan of `1..0` |
| `05` | `summary` returns 0 instead of 1 | `not ok 5`, `not ok 6 - summary returns 1 when nothing ran at all` |
| `05` | `grep_matches` returns 0 instead of 2 on a file it cannot read | `not ok 9 - grep_matches returns 2 when the file cannot be read` |
| `05` | `fail` stops calling `diag`, so an assertion fails with no reason printed | `not ok 3 - fail prints its diagnostics as TAP comments` |
| `10-bootstrap-not-circular.sh` | `FROM docker.io/library/archlinux:latest`, a digest rewritten to a tag | `not ok 1 - every base image is pinned by digest` |
| `15-actionable-failures.sh` | the `reproduce:` argument removed from one `fail` call, and the continuation backslash above it dropped | `not ok 1 - all 103 fail calls in tests/ carry a reproduce: line`, naming `tests/static/90-package-lists.sh:19` |
| `20-no-swallowed-errors.sh` | `\|\| true` appended to the pacstrap line in the Dockerfile | `not ok 1 - no swallowed error at Dockerfile:41` |
| `20` | `continue-on-error: true` on a workflow step | `not ok 1 - no swallowed error at .github/workflows/ci.yml:41` |
| `25-pipeline-traps.sh` | `\| head -n "$LIMIT"` in a script that sets pipefail | `not ok 1 - none of the N pipefail scripts uses a pipeline that fails on a normal result`, naming `scripts/faulty:3` |
| `25` | the `grep -c` form restored at `scripts/gen-mirrorlist:278` | `not ok 1`, naming the file and line |
| `25` | the `grep -c` form restored at `.github/workflows/freshness-mirrors.yml:47` | `not ok 2 - none of the 5 workflows uses a pipeline that fails on a normal result` |
| `30-signature-checking-on.sh` | `SigLevel = Never` in `rootfs/riscv64/etc/pacman.conf` | `not ok 7 - does not disable signature checking`, `not ok 8 - sets SigLevel = Required` |
| `35-publish-targets.sh` | a tag-creating step changed back to `images+=("$HUB_IMAGE")` | `not ok 4 - no tag-creating step names GHCR_IMAGE or HUB_IMAGE directly`, naming both lines |
| `35` | `HUB_SCRATCH_IMAGE` set to `pkgforge/archlinux`, the real repository | `not ok 3 - HUB_SCRATCH_IMAGE names a different repository from HUB_IMAGE` |
| `35` | the `dry_run_hub needs dry_run` guard deleted | `not ok 5 - the resolve step refuses dry_run_hub without dry_run` |
| `35` | the `verify_index "$HUB_TARGET"` call deleted | `not ok 6 - the publish job verifies the index on both registries`, `matched 1 of the 2` |
| `35` | the `scripts/check-anchor-floor` call replaced with `true`, and `ALLOW_ANCHOR_DOWNGRADE` hardcoded to `1` | `not ok 7 - the workflow runs scripts/check-anchor-floor`, and `not ok 9 - the override is not switched on in the workflow itself`, naming the line |
| `35` | the `allow_anchor_downgrade` input deleted | `not ok 8 - allow_anchor_downgrade is a workflow_dispatch input` |
| `40-mirrors-reachable.sh` | the riscv64 list cut to one server, which is the shape that caused the outage | `not ok 11 - offers a fallback server`, `not ok 16 - keeps at least 2 reachable servers` |
| `40` | ten of thirteen amd64 servers replaced with unresolvable hosts | `not ok 13 - keeps at least 7 reachable servers` |
| `45-pacman-conf-shape.sh` | `#DisableSandboxSyscalls` deleted from `rootfs/riscv64/etc/pacman.conf`, and `DownloadUser = alpm` added to it | `not ok 16 - carries both DisableSandbox directives, commented`, naming the missing one, `not ok 18 - does not set DownloadUser`, and `not ok 20 - has the same options directives as rootfs/amd64/etc/pacman.conf`, which names both differing lines |
| `45` | `DisableSandboxFilesystem` uncommented in `rootfs/armv7/etc/pacman.conf` | `not ok 12 - leaves the pacman sandbox on`, naming the line, plus `not ok 11` and `not ok 15` because uncommenting also removes the commented form |
| `45` | `Architecture = auto` in `rootfs/arm64/etc/pacman.conf`, and `riscv64` set to `x86_64` | `not ok 9 - sets Architecture to one named architecture`, and `not ok 21 - each shipped config names a different architecture`, reporting `3 configs, 2 distinct values` |
| `45` | `[options]` renamed to `[opt-typo]` in all four files, so the extraction returns nothing | `not ok 5 - the reference options block holds at least 20 directives`, `read 0`. ⭐ Every comparison assertion still passes, because two empty lists are equal. This one assertion is the whole reason the file is not vacuous |
| `55-shipped-hooks.sh` | `When` deleted from `bindir-links.hook`, `Depends` deleted from `package-cleanup.hook` | `not ok 1 - declares Operation, Type, Target, When and Exec`, `missing: When`, `not ok 3 - runs PreTransaction or PostTransaction`, and `not ok 10 - declares Depends` |
| `55` | `Exec` pointed at a `/usr/local` path that does not ship, and `When = Sometimes` | `not ok 4 - every /usr/local path ... ships in rootfs/any`, naming it, and `not ok 3`, `found: Sometimes` |
| `55` | the `[Action]` header deleted from `package-cleanup.hook` | `not ok 7 - carries one [Trigger] and one [Action]`, `matched 1 section header(s)` |
| `55` | every `.hook` file deleted from the directory | `not ok 1 - at least one hook ships`, and the file stops there rather than reporting ten passes over nothing |
| `50-supply-chain.sh` | `actions/checkout@v7.0.1` at all three call sites | `not ok 1..3 - action is pinned to a commit hash at ...` |
| `60-tag-families.sh` | `riscv64` given `amd64` as a second alias | `not ok 4 - riscv64 has 1 alias name(s)`, `not ok 22 - no alias is claimed by two architectures` |
| `60` | `loong64` given one alias instead of two | `not ok 4 - loong64 has 2 alias name(s)`, `got 1: loongarch64` |
| `60` | `emit` stopped after the first registry, so only one organisation name is used | `not ok 5 - amd64 emits 12 tags` and 14 others, `# failed 15 of 24` |
| `65-fetch-policy.sh` | `--connect-timeout` and `--max-time` removed from `scripts/resolve-anchor` and from `freshness-mirrors.yml` | `not ok 2 - all 13 fetches set --connect-timeout` and `not ok 3 - all 13 fetches set --max-time`, each naming both file:line |
| `67-mangled-responses.sh` | the old `head -1` restored in `resolve-anchor`, which took tar's blank first line | `not ok 8 - every complaint names a reason`, printing the four complaints that end at the colon |
| `67` | `continue` changed to `break`, so one bad mirror stops the search | `not ok 1 - resolve-anchor survives five mangled mirrors and exits 0`, `not ok 2 - it falls through to the one good mirror`, four `not ok` for mirrors never reached, and `not ok 9`, `counted 2 complaints, expected 5`. ⚠ 7 of the 9 |
| `67` | the archive check removed altogether | ⭐ **nothing failed, correctly.** The version extraction finds no `pacman-` line in an error page either, so the mirror is still refused and the good one still answers. What changes is the wording of the complaint, not the outcome. Recorded because a fault that does not fail a test is worth knowing about |
| `68-evidence-snapshot.sh` | `FROM scratch AS dbsnapshot` deleted from the Dockerfile | `not ok 1 - the Dockerfile declares a dbsnapshot stage` |
| `68` | the copy into `/dbsnapshot` moved below the line that empties the sync directory | `not ok 3 - the databases are copied out before the directory is emptied`, `the copy is at line 76, the delete at line 75` |
| `68` | `target: dbsnapshot` deleted from the build workflow | `not ok 4 - the build job builds the dbsnapshot target` |
| `68` | `DB_SNAPSHOT` deleted from the evidence step | `not ok 5 - the evidence step is given DB_SNAPSHOT` |
| `68` | the whole `DB_SNAPSHOT` validation block removed from `scripts/gen-evidence` | `not ok 6` and `not ok 7`, both reporting the runtime error instead of a refusal. ⭐ Assertion 8, the control, stays green, because without the validation the run reaches the image and dies there, so nothing names DB_SNAPSHOT at all. A control that flipped here would be measuring the wrong thing |
| `90-package-lists.sh` | `archlinux-lcpu-keyring` deleted from `bootstrap/loong64/etc/bootstrap-packages.txt` | `not ok 11 - bootstrap/loong64 names archlinux-lcpu-keyring`, naming the pin that serves that architecture |
| `90` | every pin's `arch` line changed to `sparc64`, so no pin matches any shipped `pacman.conf` | `not ok 11 - every pinned keyring was matched to an architecture that ships it`, `no pacman.conf Architecture matched any pin's arch list, so nothing above was checked`. ⭐ The floor is the whole point: the pairing is derived, and a derivation that matches nothing would otherwise report no failure and assert nothing |
| `70-executable-bits.sh` | `git update-index --chmod=-x scripts/tag-names` | `not ok 1 - every invoked file is executable in the index` |
| `70` | a test file present on disk but not added to git | `not ok 2 - every invoked file is tracked by git` |
| `75-architecture-set.sh` | ⭐ **a fifth architecture, `loong64`, added to the build matrix and nowhere else.** The whole reason the file exists. ⚠ Injected on 2026-08-27 and then repeated for real on 2026-08-28, as the first step of adding the port | `failed 17 of 24`, naming every loop site by file and line, plus `not ok 16`, `it exits non-zero for: loong64`, `not ok 17` for the usage string, `not ok 21 - loong64 has all 4 of its per architecture files` listing all four, and `not ok 24` for the tag family coverage. It went quiet one assertion at a time as each site was edited, which is how the port was wired |
| `75` | `riscv64` dropped from the loop at `freshness-mirrors.yml:46` | `not ok 6 - .github/workflows/freshness-mirrors.yml:46 names the whole architecture set`, `missing: riscv64` |
| `75` | `riscv64` replaced with `ppc64le` at `gen-mirrorlist:317`, a removed architecture left behind | `not ok 9 - scripts/gen-mirrorlist:317 names architectures and nothing else`, `not a spelling of any architecture in the matrix: ppc64le` |
| `75` | an `arch-subset:` marker put above a loop that names the whole set | `not ok 10 - tests/static/60-tag-families.sh:54 is marked a subset and is one` |
| `75` | the list at `gen-mirrorlist:317` continued onto a second line with a backslash | `not ok 9 - scripts/gen-mirrorlist:317 keeps its architecture list on one line`, `read so far: amd64 arm64` |
| `75` | the scanner's own `for` pattern changed to `forx`, so it matches nothing | `not ok 2 - the scan found the architecture loops` |
| `75` | a `ppc64le)` case added to `aliases_for` in `tag-names` | `not ok 16 - scripts/tag-names has an alias set for exactly the 4 matrix architectures`, `has an alias set and is not built: ppc64le` |
| `75` | `aliases_for` rewritten as an if chain, so it still answers and has no case labels | `not ok 16 - the alias table in scripts/tag-names can be read` |
| `75` | `riscv64` given a second matrix entry | `not ok 1 - each architecture appears once in the build matrix` |
| `75` | the `platform:` line deleted from the `armv7` matrix entry | `not ok 1 - every matrix entry carries a platform`, `no platform: line for: armv7` |
| `75` | `docker_arch:` renamed throughout the matrix | `not ok 1 - the build matrix names its architectures`, and the file stops there rather than measuring 22 assertions against nothing |
| `75` | `.github/workflows/build-deploy.yml` deleted | `not ok 1 - the build workflow exists` |
| `75` | `rootfs/ppc64le/` created | `not ok 22 - no rootfs or bootstrap directory belongs to an architecture the matrix does not build`, `not in the matrix: rootfs/ppc64le` |
| `75` | the usage string cut to `gen-mirrorlist ARCH` | `not ok 17 - the gen-mirrorlist usage string names the architectures it takes` |
| `75` | every `expect_alias_count` call commented out in `60-tag-families.sh` | `not ok 23 - 60-tag-families.sh checks an alias count per architecture` |
| `75` | `chmod -x scripts/tag-names` | `not ok 16 - scripts/tag-names is executable`. ⚠ Injected in the container. MSYS reports every file executable, so this fault cannot be made on Windows at all |
| `80-docs-claims.sh` | the usage block the README shipped before, where `!#` is not a comment | `not ok 2 - README.md bash block 9 parses` |
| `80` | the badge pointed back at `github.com/pkgforge/docker-archlinux` | `not ok 3 - README does not link to github.com/pkgforge/docker-archlinux` |
| `80` | every mention of GHCR removed from the README | `not ok 4 - README names the publish target ghcr.io/pkgforge-dev/archlinux` |
| `80` | a tag name documented that `tag-names` never emits | `not ok 6 - documented but never created: rv64gc` |
| `80` | a tag name emitted that the README does not document | `not ok 7 - created but undocumented: armv7` |
| `80` | an example with a shell syntax error | `not ok 1 - examples/99-broken.sh parses as bash` |
| `80` | `examples/` deleted | `not ok 1 - examples/ exists` |
| `80` | `set -euo pipefail` restored above a pipeline piping into `head` | `not ok 2 - no example sets pipefail alongside a pipeline that exits early` |

⭐ **One of these faults found a defect in the test rather than in the tree.**
`75-architecture-set.sh` first reported a list running onto a second line by
sending the word `continued` in place of the words it had read. The caller
counts recognised architecture names to decide whether a loop is about
architectures at all, `continued` is not one, so the count was zero and the
loop was skipped before it could be reported. The assertion could not fail. It
now carries the words it did read alongside a flag, and the fault above is what
exposed that. ⛔ A test written and never broken on purpose would have shipped
saying nothing.

## Image suite

Fixtures were built for these rather than modifying a real image.

| test | fault injected | caught by |
| --- | --- | --- |
| `10-shell-present.sh` | `FROM scratch` with one file, which is the state the published riscv64 image was in | `not ok 1 - /bin/sh exists and resolves`, `not ok 2 - /usr/bin/bash exists and resolves` |
| `20-os-release.sh` | `/etc/os-release` and `/usr/lib/os-release` removed | `not ok 1 - /etc/os-release exists` |
| `30-ca-bundle.sh` | `/etc/ssl/certs/ca-certificates.crt` removed | `not ok 1 - resolves in ...` |
| `30` | the published `riscv64` image, unmodified | `not ok 1 - resolves`, and the published `amd64` image passes with 121 certificates, so the test discriminates rather than always failing |
| `40-evidence.sh` | a `sha256` set to null on one entry | `not ok 13 - incomplete entries: audit` |
| `40` | a `sha256` that is not 64 hex characters | `not ok 13` |
| `40` | a package `size` of zero | `not ok 13` |
| `40` | a `released` date of `-`, the value written when upstream publishes none | `not ok 13` |
| `40` | `platform` changed to another architecture | `not ok 9 - evidence platform matches the image under test` |
| `40` | `digest` changed to zeroes | `not ok 10 - evidence digest matches the image` |
| `40` | `source_commit` truncated to a short hash | `not ok 11 - evidence source_commit is a full commit hash` |
| `40` | `anchor.version` set to a version no package carries | `not ok 14 - the anchor appears in the recorded packages` |
| `40` | `packages` emptied | `not ok 12 - evidence records at least one package` |
| `40` | a top level key deleted | `not ok 5 - evidence has a top level built` |
| `40` | one package removed from `.packages`, leaving `package_count` untouched | `not ok 12 - the evidence records every package the image reports installed`, `the image says 137, the evidence records 136`. ⭐ The check asks pacman inside the image, so it is not the derived `package_count` comparison, which could never disagree |
| `40` | ⛔ both of the two above re-run on 2026-08-28, against evidence written from a snapshot rather than from a fetch, to show the change did not soften the check | `not ok 14 - every package entry has a name, a version, a positive size, a sha256 and a release date`, `incomplete entries: bash`, and `not ok 12`, `the image says 137, the evidence records 136` |
| `scripts/gen-evidence` | one installed package removed from the snapshot `core.db`, and that snapshot handed to it as `DB_SNAPSHOT` | exit 1, `these installed packages are in no repository database: bash 5.3.15-1`, then `.tmp/holed/snap is not the snapshot this image was installed from`. ⭐ The completeness check survives the change, which is the point of making it |
| `scripts/gen-evidence` | the same holed `core.db` served from a `file://` mirrorlist, with `DB_SNAPSHOT` unset | exit 1, and the other branch of the diagnostic: `the databases moved between the build and this run, so the evidence has holes`, advising `set DB_SNAPSHOT`. ⭐ Found by injecting the first fault: one message served both causes and told a snapshot reader to re-run against the same image, which fixes nothing |
| `50-consumer-contract.sh` | `LocalFileSigLevel` moved above the global `SigLevel` | `not ok 2 - the first SigLevel line in /etc/pacman.conf is the global one` |
| `50` | every `SigLevel` line deleted | `not ok 2 - /etc/pacman.conf carries a SigLevel line`, `not ok 3 - SigLevel is Required in the shipped /etc/pacman.conf` |
| `50` | a commented `#[multilib]` block appended to `/etc/pacman.conf` | `not ok 4 - /etc/pacman.conf carries no multilib block` |
| `50` | `/etc/pacman.d/gnupg/pubring.gpg` truncated to zero bytes | `not ok 5 - the pacman keyring is populated` |
| `50` | `/usr/bin/locale-gen` removed | `not ok 6 - locale-gen is present` |
| `50` | `/usr/share/i18n/charmaps/UTF-8.gz` removed, the file the `!` re-include lines keep | `not ok 7 - the UTF-8 charmap survives NoExtract` |
| `50` | root's password field emptied to `root::`, the CVE-2019-5021 shape | `not ok 8 - root has no empty password field in /etc/shadow` |
| `60-defect-parity.sh` | fixture D, `FROM scratch` carrying one file, so the probe cannot run at all | `not ok 1 - the probe runs inside ...`, carrying `crun: executable file bash not found in $PATH`. The file then stops, rather than reporting 27 assertions read from an empty result |
| `60` | fixture C, `/usr/bin/getfattr` removed | `not ok 2 - getfattr is available inside the image to read extended attributes`, and `not ok 3`, `not ok 4` behind it, which is why the tool is checked before the attributes |
| `60` | fixture A, `/usr/bin/newuidmap` deleted | `not ok 3 - /usr/bin/newuidmap is present`, the absent branch rather than the empty one |
| `60` | fixture A, `setfattr -x security.capability /usr/bin/newgidmap` | `not ok 4 - /usr/bin/newgidmap carries the security.capability attribute`. ⭐ The file is untouched otherwise, so this is the exact shape of upstream issue 106 |
| `60` | fixture A, `chmod ug-s` on every setuid and setgid file | `not ok 5 - /usr/bin/passwd keeps its setuid bit`, reporting mode `-rwxr-xr-x`, and `not ok 6 - at least 10 files keep a setuid or setgid bit`, counted 0 |
| `60` | fixture G, `/usr/bin/passwd` deleted | `not ok 5 - /usr/bin/passwd is present`, the other branch of the same assertion |
| `60` | fixture A, `/usr/sbin` replaced with a real directory | `not ok 7 - /usr/sbin is a symlink to bin` |
| `60` | fixture G, `/sbin` and `/bin` replaced with real directories | `not ok 8 - /sbin is a symlink to usr/bin`, `not ok 9 - /bin is a symlink to usr/bin` |
| `60` | fixture A, `ENV PATH="/usr/local/bin:/bin"` | `not ok 10 - PATH carries /usr/bin`, printing the PATH it found |
| `60` | fixture G, `/var/lib/pacman` removed entirely | `not ok 11`, `not ok 12`, and `not ok 13 - pacman initialises and lists at least 50 installed packages`, which listed 0 |
| `60` | fixture C, only `/var/lib/pacman/local` removed | `not ok 12 - /var/lib/pacman/local is a directory`, `not ok 13` |
| `60` | fixture B, the `%BACKUP%` section stripped from the `filesystem` package's file list | `not ok 14 - /etc/hosts is a pacman backup file`, `not ok 15 - /etc/resolv.conf is a pacman backup file` |
| `60` | fixture F, `/etc/profile.d` emptied | `not ok 16 - at least 1 script runs on a login shell`. ⭐ Without this assertion the next one passes on an empty directory |
| `60` | fixture E, a command that does not exist appended to `/etc/profile.d/gawk.sh` | `not ok 17 - a login shell writes nothing to stderr`, 80 bytes of it |
| `60` | fixture A, `/etc/machine-id` deleted | `not ok 18 - the image ships /etc/machine-id, and it is empty`, `the file is not there at all` |
| `60` | ⭐ **the published `docker.io/pkgforge/archlinux:latest`, unmodified.** It predates the Dockerfile truncating the file | `not ok 18`, `it holds 33 bytes`, and 27 of 28 still pass, so the assertion discriminates rather than failing on everything |
| `60` | fixture B, `/usr/share/i18n/locales` emptied and `/usr/share/i18n/charmaps` cut to one file | `not ok 19` counting 1 charmap, `not ok 20` counting 0 definitions, `not ok 21` to `not ok 24` for `ja_JP`, `zh_CN`, `ru_RU` and `ko_KR`, `not ok 26`, `not ok 27` reporting `ANSI_X3.4-1968`, and `not ok 28` |
| `60` | fixture G, `/usr/bin/locale-gen` removed | `not ok 25 - locale-gen runs after ja_JP.UTF-8 is appended to /etc/locale.gen` |
| `60` | fixture H, a file placed in `/etc/pacman.d/gnupg/private-keys-v1.d` | `not ok 29 - no private signing key is shipped in /etc/pacman.d/gnupg`, `private-keys-v1.d holds 1 file(s)` |
| `60` | fixture I, the hook and `/usr/local/lib/docker-archlinux` both removed | `not ok 31` through `not ok 35`, the whole of section 9 |
| `60` | fixture K, the linker left in place with mode `0644` | `not ok 32 - ... is executable`, and `not ok 33` to `not ok 35` behind it, because a linker that cannot run links nothing |
| `60` | fixture J, a linker that links every file unconditionally and never prunes | `not ok 34 - the linker never shadows a name that already resolves`, reporting `/usr/local/bin/bash`, and `not ok 35 - a link is pruned when the executable it points at goes away`. ⭐ It fails exactly those two of the 35, which is what makes them assertions about the rule rather than about the script existing |
| `60` | fixture H, `/usr/bin/awk` removed | `not ok 30 - every tool pacman-key calls out to is on PATH`, `missing: awk`. ⚠ It also takes assertions 5, 14, 15 and 26 with it, because the probe parses with awk. The messages degrade to an empty measurement rather than a wrong one |

The two fixtures for `50` are `.tmp/phased/Containerfile.faultA`, which carries
six faults at once, and `.tmp/phased/Containerfile.faultB`, which deletes every
`SigLevel` line to reach the two branches fault A cannot. All 8 assertions pass
against the published image and 6 then 2 of them fail against the fixtures:

```bash
podman build --platform linux/amd64 -f .tmp/phased/Containerfile.faultA -t localhost/faulta:test .tmp/phased
REPO_ROOT="$(pwd)" IMAGE=localhost/faulta:test PLATFORM=linux/amd64 bash tests/image/50-consumer-contract.sh
```

The eleven fixtures for `60` are `.tmp/parity/Containerfile.faultA` to
`Containerfile.faultK`, added 2026-08-27. I, J and K build on a local build of
this tree rather than the published image, because what they break is shipped
by this change and is not in a published image yet. Each is `FROM docker.io/pkgforge/archlinux:latest`
with one group of faults applied, except D which is `FROM scratch`. Between them
every one of the 35 assertions has been seen to fail. ⚠ Some faults cascade, and
that is expected rather than sloppy: removing `/var/lib/pacman/local` takes the
`%BACKUP%` lookup with it, and removing `awk` takes every fact the probe parses
with it. The counts below include those:

| fixture | what it breaks | assertions caught |
| --- | --- | --- |
| A | attributes, setuid bits, `/usr/sbin`, `PATH`, `/etc/machine-id` | 7 |
| B | the locale data and the `%BACKUP%` section | 11 |
| C | `getfattr` and `/var/lib/pacman/local` | 7 |
| D | everything, by having no shell | 1, and it stops there |
| E | one script under `/etc/profile.d` | 1 |
| F | `/etc/profile.d` itself | 1 |
| G | `/var/lib/pacman`, `locale-gen`, `passwd`, `/sbin`, `/bin` | 12 |
| H | a private key in the keyring, and `awk` | 7 |
| I | the hook and the linker, both removed | 5 |
| J | a linker that shadows and never prunes | 2 |
| K | the linker's execute bit | 4 |

⭐ **It discriminates, and it caught a real defect.** A local build of the
fixed tree passes 30 of 30 on `linux/amd64` and `linux/arm64`. The **published**
image predates this work and fails assertion 18, the `/etc/machine-id` defect,
on all four architectures, plus the five in section 9 that this change ships.
A local build of this tree passes 35 of 35 on `linux/amd64` and `linux/arm64`:

```bash
podman build --platform linux/amd64 -f .tmp/parity/Containerfile.faultA -t localhost/parity-faulta:test .tmp/parity
REPO_ROOT="$(pwd)" IMAGE=localhost/parity-faulta:test PLATFORM=linux/amd64 bash tests/image/60-defect-parity.sh
```

## The port keyring machinery

⛔ **These are not test files.** `bootstrap/any/usr/local/bin/install-port-keyring`
runs inside every ARM and loong64 build and is the only thing standing between
those builds and whatever a mirror serves, so it is fault injected the same way.
Each row ran in `docker.io/pkgforge/archlinux:latest` on `linux/amd64` against
the loong64 pin, on 2026-08-28, with `PORT_KEYRING_DIR` and
`PORT_KEYRING_PACMAN_CONF` pointed at a scratch copy.

| what | fault injected | result |
| --- | --- | --- |
| `install-port-keyring` | one character changed in the pinned `sha256` | exit 1, `checksum mismatch for archlinux-lcpu-keyring-20241126-1-any.pkg.tar.zst`, printing both hashes |
| `install-port-keyring` | one `trusted` fingerprint deleted from the pin | exit 1, `the trusted set in ... is not the set ... holds`, `in the package and not pinned : A6C02FBE730CD45859B946E15C74AE170BDA1433` |
| `install-port-keyring` | one pinned expiry moved from `2027-11-26` to `2030-01-01` | exit 1, `a pinned key's expiry is not what ... records`, `drifted: B955F201...(pinned 2030-01-01, keyring says 2027-11-26)` |
| `install-port-keyring` | ⭐ the validity lookup pointed at an empty gpg homedir, which is what a moved `GPGDir` would do | exit 1, `a key ... expects to be usable is not fully valid after populate`, naming all **8** non-expired keys and no others. The two already past their pinned expiry were correctly skipped before this check |
| `install-port-keyring` | a second pin copied in, claiming the same architecture | exit 1, `2 pins claim Architecture = loong64`, naming both files |
| control | none | `8 of 10 pinned keys are fully valid, SigLevel stays Required` |
| `check-keyring-pin` | the pinned package name changed to one the mirror never had | exit **4**, `pinned still fetchable: HTTP 404`, `result: GONE` |
| `check-keyring-pin` | ⭐ the pinned `sha256` changed while the package name still answers | exit **5**, `result: CHANGED, the pinned package name still answers and its bytes are not the pinned bytes`. This check did not exist before the port was added |
| `check-keyring-pin --apply` | a pin made stale two ways at once: an old package name and one fingerprint deleted | it rewrote the file back to exactly what the tree holds. `sha256sum` over the field lines of both is `04dd5b22d6adc732560b8e869a07020845b835010169579f3f9db677748b78af` either way |

⛔ **The injection found a defect in the checker itself.** The bump path used an
awk array named `exp`, which is an awk built-in, so the whole branch was a syntax
error rather than a shadowing. It never ran: the current-pin path returns before
reaching it, and the ARM pin has been current every time the job has run. The
`--apply` fault above is what exposed it.

## The workflow itself

| behaviour | fault injected | result |
| --- | --- | --- |
| a partial failure publishes nothing | `bootstrap/riscv64/etc/bootstrap-packages.txt` set to a package name that does not exist, on a throwaway branch | the riscv64 build fails at `Build and push by digest`, the other three still run because `fail-fast` is off, and the publish job never starts because it needs the whole matrix |
| the actionlint guard refuses a run that read nothing | pointed actionlint at a tree holding an empty `.github/workflows`, with the `2>&1` fix in place | actionlint prints `no project was found`, the `Linting .github/workflows/` line never appears, and `grep -q` exits 1 so the step fails |
| the cross-registry copy runs and is verified | run `33001089986`, `dry_run` and `dry_run_hub` both true | all six jobs succeeded. The publish job printed `verifying ghcr.io/pkgforge-dev/archlinux-ci:v2026.08.26` and `verifying pkgforge/archlinux-ci:v2026.08.26`, each with `index platforms: amd64 arm/v7 arm64 riscv64`. 26 tags landed on the Docker Hub scratch repository, which did not exist before the run |
| the rollback floor runs in the publish path | none. Dry run `33038310288`, the first run carrying the step | `Resolve inputs` printed `read 161 tags from ghcr.io/pkgforge-dev/archlinux` and `ok` for all four architectures, before anything was built. ⭐ The step had never executed in CI before this run |
| the image suite passes under docker on every architecture | none. The same dry run | all four builds green, and `60-defect-parity.sh` reported `passed 35 of 35` on `riscv64` under QEMU with `CONTAINER_RUNTIME: docker`, which is the one runtime this machine cannot exercise |
| the evidence resolves against the databases the build used | none. Dry run `33162764880`, the first run carrying the export step | all six jobs green. `gh run view 33162764880 --log \| grep "database read from"` shows every enabled repository read from `/tmp/dbsnapshot` on all four architectures, four of them on each ARM port, and no fetch anywhere. The export step took 1 to 2 seconds, `CACHED` on every layer |
| a fifth architecture builds and publishes | none. Dry run `33165970427`, the first run carrying loong64 | seven jobs green in 6m56s. ⛔ This is the measurement `HISTORY/loong64.md` could not take: `docker/setup-qemu-action` **does** register a `loongarch64` handler on `ubuntu-latest`, and the emulated stage ran without a binfmt error. `8 of 10 pinned keys are fully valid` in the build log, 137 packages recorded, 6 per architecture tags created, and `index platforms: amd64 arm/v7 arm64 loong64 riscv64` |
| a dry run cannot touch a real repository | the same run | both real repositories still hold 161 tags. `pkgforge/archlinux:latest` was last pushed at 17:18:47, by the earlier real publish; the scratch `:latest` moved at 18:47:52 |
| the index check refuses an incomplete index | ran the step's own jq and grep loop against `pkgforge/archlinux-ci:amd64`, a single-architecture tag, on the real registry | `index platforms: amd64`, then `missing arm64`, `missing riscv64`, `missing arm/v7`, exit 1. The same logic against `:v2026.08.26` exits 0, so it discriminates |

⚠ **What is still not proven this way.** The cross-registry copy is no longer in
this list: run `33001089986` exercised it against scratch repositories on both
registries. What remains unproven is a copy that fails **partway**. The index
check refuses an incomplete index, tested above against a real
single-architecture tag, but a copy interrupted midway through a multi-tag run
has not been produced deliberately.

# Review 10: a consumer whose transaction runs our hook

**Lens.** This image now ships a pacman hook that fires inside **somebody
else's** `pacman -Syu`, on their machine, in their CI. Everything it does is
done with their root, on their filesystem, on every transaction. What can it
break, and what does it break when it breaks.

**Date.** 2026-08-27.

---

## Why this lens exists now

Before today the image shipped one hook, `package-cleanup.hook`, which runs
`find` over a directory this repository owns. Today it ships a second,
`bindir-links.hook`, which runs a script this repository wrote, walks
directories packages own, and creates files on `PATH`. That is a much larger
blast radius, and none of the eight earlier reviews looked at it, because it did
not exist.

---

## What was checked

The script was run against every edge case a consumer could produce, inside the
image, rather than reasoned about.

| case | result |
| --- | --- |
| a file name with a space | linked correctly, quoting holds |
| a subdirectory inside a perl bindir | not linked, `-f` excludes it |
| a non-executable file in a perl bindir | not linked |
| `/usr/local/bin` absent | exits 0, silently, before touching anything |
| a consumer's own dangling symlink in `/usr/local/bin` | kept |
| a consumer's own real file with a name a perl bindir also has | kept, not replaced |
| a name `/usr/bin` already owns | never linked |
| a package claiming the name later | the link is pruned, the package wins |
| the target removed | the link is pruned |
| run twice, three times | no output and no change after the first |
| a tool moving between perl bindirs | the link follows it |

⭐ **The rule that matters held in every case: nothing that resolved before
resolves anywhere new.** Three assertions in section 9 of
`tests/image/60-defect-parity.sh` hold it, and fixture J, a linker that links
unconditionally and never prunes, fails exactly those and nothing else.

⭐ **A broken hook is caught before it ships.** `tests/static/55-shipped-hooks.sh`
asserts every shipped hook declares what alpm needs, both section headers, a
`When` alpm knows, a `Depends`, and that any `/usr/local` path it runs is a file
this repository actually ships. ⛔ That last one is the sharp edge: a hook in
the image whose `Exec` is not in the image aborts **every** transaction the
consumer runs, and a build that shipped it would be green.

---

## What was found and not changed

⚠ **The hook fires during this repository's own bootstrap, under emulation.**
`pacman -r` reads hooks from the target root, and `rootfs/any` is in place
before `pacstrap-docker` runs, so the hook executes a foreign architecture
`/bin/sh` on an `amd64` builder. This is not new: `package-cleanup.hook` has
always done it, and it is how `/var/cache/pacman/pkg` ends up empty in the
image. Proven rather than assumed by a `--no-cache` `linux/arm64` build: it
succeeds, the cache is empty, and the image passes 35 of 35.

⚠ **The script sets `set -eu`, so a failure fails the consumer's pacman.** A
PostTransaction hook exiting non-zero makes pacman exit non-zero after the
transaction has already been applied, which could break a consumer's `set -e`
CI. The alternative is swallowing errors, which policy 3 forbids. The reachable
failure is `ln` failing on an unwritable `/usr/local/bin`, and pacman needs
`/usr` writable to have got that far at all, so it is not reachable in a run
that reached the hook. ⛔ Kept loud deliberately.

⚠ **A read-only `/usr/local/bin` was probed and the probe was invalid.** Mode
`0555` does not stop root, so the case tested nothing. A genuinely read-only
mount was not produced. Recorded as unproven rather than claimed as passing.

⚠ **The trigger is every path under `/usr/bin`**, not only the perl
directories, so the script runs on almost every consumer transaction. That is
deliberate: a narrower trigger would leave a stale link shadowing a package that
later claims the name. The cost is three directory scans and one line of output
when something changed, and none when nothing did.

---

## What this review did NOT look at

- **Other directories that are not on `PATH`.** Only the three perl bindirs are
  handled. `/usr/lib/jvm/*/bin` and anything else a package invents is not, and
  no consumer has asked.
- **A consumer who has already put their own symlinks into `/usr/local/bin`
  pointing into a perl bindir.** Those are indistinguishable from this script's
  and would be pruned by it. Nobody was found doing this, and it was not
  measured.
- **SELinux or AppArmor labels on the created symlinks.** Not examined.
- **The hook under a pacman older than 7.1.0.** Path triggers are old, but the
  behaviour was only observed on `7.1.0.r9.g54d9411-2`.
- **What happens if a consumer removes `perl` while a link exists.** The prune
  path covers it in principle and that exact sequence was not run.

## Change summary

No code changed in this review. It is the record of what the change committed
earlier the same day was checked against.

| file | added | removed |
| --- | --- | --- |
| `HISTORY/reviews/10-a-consumer-whose-transaction-runs-our-hook.md` | new | - |

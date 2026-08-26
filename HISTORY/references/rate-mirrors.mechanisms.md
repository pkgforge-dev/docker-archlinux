# Mechanisms taken from rate-mirrors

What `scripts/gen-mirrorlist` implements, and where each part comes from. Every
citation is against `westandskif/rate-mirrors` at commit
`98ac2a2698b1c7aed4c4ad15817b710d62ef3b31`.

⛔ Its code is CC BY-NC-SA 3.0 and is not copied. These are mechanisms and
parameter values, re-implemented.

## Adopted

| mechanism | source | how it is used here |
| --- | --- | --- |
| Arch pool source | `src/target_configs/archlinux.rs:4` | `https://archlinux.org/mirrors/status/json/` |
| drop partially synced mirrors | `src/target_configs/archlinux.rs:35`, `default_value = "1"` | `completion_pct == 1` |
| drop mirrors behind on sync | `src/target_configs/archlinux.rs:42`, `default_value = "86400"` | `delay <= 86400` seconds |
| rank the pool by published score, lower first | `src/target_configs/archlinux.rs:53`, `default_value = "score_asc"` | pre-sort before probing |
| ARM pool source | `src/target_configs/archarm.rs:17` | the Arch Linux ARM `pacman-mirrorlist` source file |
| commented entries are candidates | `src/targets/archarm.rs:31` | `# Server =` lines are probed too |
| measure connection time apart from throughput | `src/speed_test.rs:157` | rank surviving mirrors by connect time |
| bound the work per mirror | `src/speed_test.rs:164`, min and max per mirror | one small request with a timeout |
| bounded concurrency | `src/speed_test.rs`, semaphore over `config.concurrency` | a fixed size probe pool |
| write the destination only on success | pull request 70, `src/main.rs` | temporary file, checked, then moved |
| exit non-zero when the job did not do its job | issue 85, maintainer's ruling | non-zero, and the shipped list is untouched |

## Deliberately not adopted

| mechanism | source | why not |
| --- | --- | --- |
| country hopping over submarine cable and internet exchange topology | `src/speed_test.rs`, `src/countries.rs` | it solves picking ten mirrors out of 1227 for an unknown end user connection in about thirty seconds. Here the pool is small and known, and the job runs on a schedule with time to probe all of it. |
| throughput ranking by downloading a large `.files` archive | `src/target_configs/archlinux.rs:63` | issue 102 measured over 3 TB a day on one mirror from that path, and issue 104 shows a mirror answering 403 for it. `core.db` is enough to prove a mirror serves the repository. |
| running on a timer | refused upstream in issues 54 and 60 | the generator is not on the daily build. It runs infrequently and opens a pull request. |

## Rules this repository adds

- ⭐ **Anchors are always kept.** Issue 56 measured a pool collapsing to 1 of
  1166 under the completion filter. A well known anchor per architecture is
  written whatever the pool does, and a dead anchor fails the job loudly.
- ⭐ **Identify the traffic.** A User-Agent naming this repository, so a mirror
  operator can see where a probe came from. Issue 102 is the reason.
- ⭐ **Refuse to shrink the list below the floor.** The generator will not write
  a list with fewer servers than the test requires.

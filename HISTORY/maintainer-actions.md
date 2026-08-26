# Actions only the maintainer can take

Five items. Each is proposed with the reason and the exact command, and none of
them has been applied. Measured 2026-08-26.

## 1. Branch protection on `main`

There is none today:

```bash
gh api repos/pkgforge-dev/docker-archlinux/branches/main/protection
```

```
Branch not protected (HTTP 404)
```

⛔ **A pull request currently reaches the repository's credentials and packages
without any review.** The publish job holds `packages: write` and the Docker Hub
token, so a merged pull request can push to both registries.

Who can review, measured rather than assumed:

```bash
gh api repos/pkgforge-dev/docker-archlinux/collaborators \
  --jq '.[] | "\(.login) \(.role_name)"'
```

| login | role | can push |
| --- | --- | --- |
| `QaidVoid` | admin | yes |
| `Samueru-sama` | admin | yes |
| `Azathothas` | admin | yes |
| `psadi` | maintain | yes |

The other 16 collaborators are `read`. So a one reviewer rule draws from four
people, which is enough for it not to block the maintainer.

⭐ **The proposal**, which requires a passing build before merge and one review
from someone who already has push access:

```bash
gh api -X PUT repos/pkgforge-dev/docker-archlinux/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Resolve inputs"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": true
}
JSON
```

Why each field:

| field | reason |
| --- | --- |
| `required_status_checks.contexts: ["Resolve inputs"]` | the static suite runs there. It is the only check that runs on every pull request quickly enough to gate one |
| `strict: true` | a branch behind `main` has to rebase, so the suite that passed is the suite for the merged tree |
| `enforce_admins: false` | ⚠ deliberate. With it on, an admin cannot merge a Dependabot pull request without a second admin, which is the opposite of very low maintenance |
| `required_approving_review_count: 1` | drawn from the four above |
| `dismiss_stale_reviews: true` | an approval is for the diff that was reviewed |
| `allow_force_pushes: false`, `allow_deletions: false` | `main` carries every published tag's source commit |
| `required_conversation_resolution: true` | a review comment cannot be merged past silently |

⚠ **What this does not do.** It does not stop an admin pushing to `main`
directly, by design. It does not require signed commits, because no contributor
here signs today and turning it on would block all four of them.

## 2. The GitGuardian secret

Secret scanning is GitGuardian, per the maintenance model. It needs a
`GITGUARDIAN_API_KEY` repository secret. The repository has two secrets today
and that is not one of them:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/secrets --jq '.secrets[].name'
```

```
DOCKERHUB_TOKEN
DOCKERHUB_USERNAME
```

⛔ **Creating the secret is the maintainer's action.** Nothing in this
repository creates it, reads it, or works around its absence.

Once it exists, the scanning workflow can be added. It is not added first,
because a workflow that fails on every run for a missing secret trains people to
ignore a red mark.

## 3. The `debug` branch

```bash
git rev-list --count origin/main..origin/debug   # 0
git merge-base --is-ancestor origin/debug origin/main && echo ancestor
```

`debug` holds **no commit that is not already in `main`**. Its tip is
`a809a22`, dated 2025-11-14, and is a keepalive commit. Deleting it loses
nothing:

```bash
git push origin --delete debug
```

⛔ Proposed, not done. A branch that costs nothing to keep is the maintainer's
call.

## 4. Actions creating pull requests

The two freshness workflows open pull requests with `gh pr create` and the
built-in token. The repository already allows it:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/permissions/workflow
```

```json
{"default_workflow_permissions":"write","can_approve_pull_request_reviews":true}
```

⚠ **No change is needed, and one is worth considering.**
`default_workflow_permissions` is `write`, which grants every workflow write
access by default. Every workflow here declares `permissions: contents: read` at
the top and elevates per job, so the default does not apply to them. Setting the
default to `read` would make that explicit for anything added later:

```bash
gh api -X PUT repos/pkgforge-dev/docker-archlinux/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

⛔ Verify the freshness jobs still open pull requests after changing it. The
per-job `pull-requests: write` should be enough, and that is untested.

## 5. Dependabot preserving hash pins

`.github/dependabot.yml` covers `github-actions` and `docker`. Whether
Dependabot updates a commit-hash pin to a new hash, rather than rewriting it
back to a tag, is **not verified here**. It cannot be: Dependabot runs
server-side and only on a branch it has been enabled for.

⭐ **The risk is guarded rather than assumed.** Three tests fail on a pin that
has become a tag, so such a change fails CI on the bot's own pull request:

| test | fails on |
| --- | --- |
| `tests/static/00-workflow-branch-buildable.sh` | `actions/checkout` at a tag |
| `tests/static/50-supply-chain.sh` | any action at a tag, and any pinned action with no version comment |
| `tests/static/10-bootstrap-not-circular.sh` | a `FROM` that is not `@sha256:` |

Seen to fail, against a tree with `actions/checkout@v7.0.1` and
`docker.io/library/archlinux:latest` substituted in:

```
not ok 1 - actions/checkout is pinned to a commit hash
not ok 1 - action is pinned to a commit hash at .github/workflows/build-deploy.yml:59
not ok 1 - every base image is pinned by digest
```

⚠ If Dependabot does rewrite pins to tags, its pull requests will be red and
that dependency belongs to a freshness job of its own instead.

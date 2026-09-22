# GitHub Repository Setup — Literal Walkthrough

Everything here is scriptable via `gh` — prefer that over clicking through the UI by hand, so the configuration is reproducible and reviewable as a script, not tribal knowledge.

## 1. Branch protection via a repository ruleset

A modern GitHub ruleset (not the older, deprecated "branch protection rules" UI) covering the default branch:

```bash
gh api repos/OWNER/REPO/rulesets -X POST -f name="main" -f target="branch" \
  -f enforcement="active" \
  -F 'conditions[ref_name][include][]=~DEFAULT_BRANCH' \
  -F 'rules[][type]=deletion' \
  -F 'rules[][type]=non_fast_forward' \
  -F 'rules[][type]=pull_request' \
  -F 'rules[][parameters][required_approving_review_count]=1' \
  -F 'rules[][parameters][dismiss_stale_reviews_on_push]=false' \
  -F 'rules[][type]=required_status_checks' \
  -F 'rules[][parameters][required_status_checks][][context]=YOUR_CHECK_NAME'
```

(The real API payload is more nested than a single flat command comfortably expresses — in practice, build this as a JSON file and pass it with `gh api repos/OWNER/REPO/rulesets -X POST --input ruleset.json`, and check `gh api repos/OWNER/REPO/rules/branches/main` afterward to confirm what actually landed — the write and read shapes aren't identical.)

At minimum, this ruleset should enforce:
- **Deletion protection** — the branch can't be deleted.
- **Non-fast-forward protection** — no force-push rewrites history.
- **At least 1 required approving review** — nothing merges on a single person's own say-so, including yours.
- **Required status checks** — name every blocking CI job from `cicd-pipeline.md` explicitly; a check that isn't required here can be silently skipped or fail without blocking merge.

## 2. GitHub Environments, one per deployment target

Create an Environment (Settings → Environments) per environment your pipeline deploys to (dev/test/staging/prod at minimum). Two things environments give you that a plain workflow doesn't:

- **Environment-scoped secrets and variables** — a role ARN or connection string that only that environment's deploy job can see, rather than one flat pool of repo-wide secrets every workflow can read.
- **Protection rules** — require manual approval before a job targeting `prod` runs. This is where "someone has to click approve before production deploys" actually lives — don't build a custom approval system for this, it's a solved, native feature.

```bash
gh api repos/OWNER/REPO/environments/prod -X PUT \
  -F 'deployment_branch_policy[protected_branches]=true'
```

Add required reviewers for the `prod` environment specifically via the UI or the `deployment_protection_rule` API — this is the one piece with a real per-account entitlement gate and less consistent CLI support, worth confirming directly against GitHub's own current API docs rather than trusting a cached example here.

## 3. OIDC trust, one identity provider trust policy per cloud

Register your cloud's identity provider to trust GitHub's OIDC issuer (`https://token.actions.githubusercontent.com`), scoped to your specific repository and, ideally, a specific GitHub Environment (not just "any workflow in this repo") — see `cicd-pipeline.md` for why the trust condition's exact match pattern matters.

## 4. Dependabot configuration

A `.github/dependabot.yml` covering every real ecosystem in the repo (each language's package manager, plus `github-actions` itself so your pinned Action versions get bumped too):

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## 5. Pin every third-party Action to a commit SHA

Not a version tag. A floating tag (`@v4`) can be repointed by the Action's own maintainer (or an attacker who compromises their account) to different, malicious code without your workflow file ever changing. A pinned SHA (`@a1b2c3...  # v4.2.1`) can't silently change under you — Dependabot still knows how to bump it correctly, so this costs nothing in maintainability.

## 6. Confirm what you actually built

`gh api repos/OWNER/REPO/rules/branches/main` and `gh api repos/OWNER/REPO/environments` are the ground truth — read them back after setup, don't just trust that the commands you ran did what you intended. The write and read API shapes for rulesets in particular are not symmetric, so a command that returns success is not the same guarantee as confirming the resulting ruleset actually matches what you meant to configure.

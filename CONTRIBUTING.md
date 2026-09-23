# Contributing to SecureFoundry

Thank you for considering a contribution. This project holds itself to the same review discipline it recommends in `skills/secure-platform-factory/reference/review-culture.md` — read that first if you haven't; everything below is that document applied to this specific repo.

## The most valuable contribution right now

**Real production experience with the GCP or Azure paths.** Both are designed carefully but have not run in a real production environment (see the README's Status section). If you adopt either path and something breaks, is missing, or is subtly wrong, that is the single highest-value thing you can report — more valuable than a stylistic PR, because it's the one thing this project cannot generate on its own.

When you file that kind of issue or PR, please include:
- What you were doing and what you expected.
- What actually happened, with the real error message.
- Which module/file, and which cloud provider version (`terraform version` output).

If you fix it yourself, please also add an entry to `reference/security-history.md` if it's a security-relevant finding (the same honest, specific format the existing three entries use — what was wrong, the fix, why it matters generally) — that's how this project stays useful to the next adopter instead of just to you.

## Review requirements

- **Every PR needs at least one approving review before merge** — this repo's own branch protection enforces it (see `reference/github-setup.md` for the exact ruleset).
- **A PR that changes a security-relevant default** (an IAM policy shape, a trust-policy condition, a default `desired_count`/`min_replicas`, an encryption setting, a network rule) **needs an independent, adversarial second review** — someone deliberately trying to find what's wrong, not confirming what looks right. This mirrors `review-culture.md`'s own escalation criteria exactly, applied to this repo's own content.
- **A new Terraform module or a change to an existing one must pass `terraform fmt -check` and `terraform validate`** (with `-backend=false` — no real cloud credentials are needed or expected for this) before it's reviewable. Run this yourself before opening the PR; a reviewer's time shouldn't be spent finding a formatting error a tool would have caught in two seconds.
- **A new reference doc or a change to an existing one should be checked against the actual repo it's describing**, not written from memory of how the pattern "usually" works. If you're documenting a real, tested pattern from your own deployment, say so and cite what you actually ran; if you're proposing something you haven't run, say that too — the whole project's credibility rests on not blurring "proven" and "designed."

## What a good PR to this repo looks like

- **Terraform changes**: include the `terraform validate` output (or note that you ran it) in the PR description. If your change fixes a real bug found during that validation (a circular dependency, a provider-version mismatch, a missing argument), say what the bug was and how you found it — that context is worth as much as the fix itself, the same way this project's own commit history does it.
- **Reference doc changes**: if you're correcting something, name what was wrong and why the correction is right, not just the replacement text — a reviewer re-deriving your reasoning needs to see the "why," not just trust the diff.
- **Workflow template changes**: every third-party GitHub Action reference must be pinned to a full commit SHA with the version as a trailing comment (see `reference/github-setup.md`) — verify the SHA yourself against the real tag (`gh api repos/OWNER/REPO/git/refs/tags/TAG --jq .object.sha`) rather than copying one from memory or an example; a wrong SHA either fails to resolve or, worse, silently pins the wrong commit.

## Scope boundaries — what this project is not

- **Not a place for application-specific business logic.** This skill bootstraps the platform a product runs on, not the product itself. If your contribution is specific to one company's domain model, it doesn't belong here even if it's well-written.
- **Not a place for a fourth cloud unless it's built with the same rigor as the first three.** A partial module set for a new provider, without validated Terraform and without the matching reference docs, creates more confusion than value — open an issue to discuss scope before starting that work.
- **Not a place to remove the honesty markers.** Don't change "work in progress" language to sound more confident than the evidence supports, even if your own deployment worked — one success doesn't retroactively make a pattern battle-tested for everyone; add your experience to `security-history.md` or a similar record instead of upgrading the claim.

## Getting help

Open an issue with your question — there's no separate chat/forum for this project. Tag it with the cloud provider (`aws`/`gcp`/`azure`) or `cross-cutting` if it's not provider-specific, so it's easy to find for someone hitting the same thing later.

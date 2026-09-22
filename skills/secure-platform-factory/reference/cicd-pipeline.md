# CI/CD Pipeline — Stage by Stage

Cloud-agnostic. Every stage below is a real gate in a real pipeline, not a suggestion — each one should either block the merge (exit non-zero) or be explicitly marked advisory, and the reasoning for which is stated per stage.

For each stage: what it catches, the open-source default, the paid alternative, and when to actually pay for the upgrade.

## 1. SAST (static analysis for first-party code)

**Catches**: injection, XSS, unsafe deserialization, and logic vulnerabilities in your own code, before merge.

- **Open-source default: Semgrep** (community ruleset). Free, no license required, integrates as a single GitHub Actions step.
- **Paid alternative: CodeQL via GitHub Advanced Security**, or Snyk Code. Deeper interprocedural dataflow analysis — catches vulnerabilities that span multiple functions/files, which pattern-matching tools like Semgrep's free tier generally miss.
- **When to upgrade**: once you're actually holding sensitive data (PII, PHI, payment data) or once a Semgrep-caught false-negative actually happens. Don't pay for this on day one of a pre-revenue project.

Make it a required, blocking status check from day one — the tool tier is negotiable, whether it blocks is not.

## 2. Secret scanning

**Catches**: credentials, API keys, and private keys committed to the repository — including in history, not just the current diff.

- **Open-source default: Gitleaks.** Run with full-history scanning (`fetch-depth: 0` in the checkout step) on every PR — a secret that leaked three commits ago and was "removed" in the next commit is still live in git history and still needs to be caught and rotated.
- **Paid alternative: GitHub secret scanning (part of GHAS)**, or TruffleHog Enterprise (adds live credential-validation — checks whether a found key is actually still active, not just pattern-shaped).
- **When to upgrade**: GHAS's live validation against known provider APIs (confirming a leaked AWS key is real and active, not a dummy) is genuinely valuable once you have enough repos that manual triage of every Gitleaks hit becomes a bottleneck.

## 3. Container image scanning (two-stage)

**Catches**: known CVEs and license violations in your dependency tree and base OS.

Run this in **two distinct stages**, not one:
- **Base image scan** (advisory) — scan the upstream base image (e.g. a language runtime's official slim image) before your own code is layered on. This is for visibility into what you're inheriting, not a gate — you often can't fix an upstream CVE yourself, only patch around it or wait.
- **Final image scan** (blocking) — scan the actual image you're about to ship, after your own dependencies are installed. This is the real gate: exit non-zero on CRITICAL/HIGH severity, scoped to library-level packages (not OS packages, which produce noisy false-positive-adjacent findings you usually can't act on directly).

- **Open-source default: Trivy.** Covers both vulnerability scanning and OSS license compliance in one tool and one gate — a copyleft or otherwise-forbidden license in your real dependency tree fails the build the same way a CVE does.
- **Paid alternative: Snyk Container, or Prisma Cloud.** Adds remediation guidance (exact version to bump to) and runtime correlation (which of these CVEs are actually reachable at runtime, reducing alert fatigue).
- **When to upgrade**: once CVE volume across your images is high enough that "which of these 40 findings actually matter" becomes a real triage problem.

## 4. Dependency vulnerability + license scanning (PR-time)

**Catches**: a *newly introduced* vulnerable or non-compliant dependency, at the moment it's added — distinct from stage 3, which scans the built image on a schedule/every merge. This stage should block the specific PR introducing the problem dependency, before it ever reaches a built image.

- **Open-source default: OSV-Scanner** (Google's Open Source Vulnerabilities scanner). Free, no license required, integrates as a PR-diff-aware check.
- **Paid alternative: GitHub's dependency-review-action (requires a GHAS license)**, or Snyk Open Source.
- **This is commonly a real gap**: a team without a GHAS license often has *no* PR-time block here at all, relying only on a weekly Dependabot sweep (see stage 7) to eventually catch it — meaning a vulnerable dependency can sit in `main` for up to a week. OSV-Scanner closes this gap at zero license cost; there's rarely a good reason to skip this stage entirely.

## 5. Infrastructure-as-code scanning

**Catches**: misconfigured cloud resources before they're ever applied — a publicly-exposed storage bucket, an overly permissive IAM policy, a database with encryption disabled.

- **Open-source default: Checkov.** Broadest built-in policy coverage across AWS, GCP, and Azure alike, plus Kubernetes and Dockerfile scanning if you need those too.
- **Alternative: tfsec** (Terraform-specific, narrower scope, sometimes faster) — a reasonable substitute if you want Terraform-only coverage and don't need Checkov's broader scope.
- **Paid alternative: Snyk IaC, or Prisma Cloud.** Adds policy-as-code authoring tools and drift detection (catching when the real cloud state has diverged from what's in the Terraform).
- **When to upgrade**: once you have several environments and want continuous drift detection, not just pre-apply scanning.

Also run `terraform fmt -check` and `terraform validate` (or your IaC tool's native equivalents) as their own fast, free, blocking check — catches malformed configuration before it ever reaches a scanning tool.

## 6. DAST (dynamic analysis against a running environment)

**Catches**: runtime web vulnerabilities static analysis can't see — misconfigured security headers, session-cookie flaws, reflected content — by actually attacking a live deployed environment.

- **Open-source default: OWASP ZAP**, baseline scan mode, run against every environment after each deploy.
- **Paid alternative: Burp Suite Enterprise, or StackHawk.** Better authenticated-scan support (crawling behind a login) and lower false-positive rates.
- **Recommendation**: run this advisory (non-blocking) at first — DAST false positives are common enough that a hard block on day one will train your team to ignore the check entirely. Make specific, confirmed finding classes blocking once you've tuned the scan against your own app for a few weeks.

## 7. Dependency updates (the ongoing sweep, not the PR-time gate)

**Catches**: everything stage 4 catches, but continuously and retroactively — including dependencies that were fine when added and became vulnerable later.

- **Open-source default: Dependabot** — free on GitHub, zero setup cost, covers both application dependencies and your CI workflow's own third-party Actions.
- **Paid alternative: Renovate Pro, or Snyk.** More configurable update batching/scheduling; rarely worth paying for unless Dependabot's update cadence is actually causing you real friction.

## Two structural patterns, regardless of tool choice

**Keyless cloud authentication (OIDC federation).** Your CI provider's own OIDC identity provider, trusted by a narrowly-scoped IAM role per environment, replaces long-lived cloud access keys stored as CI secrets entirely. This closes an entire class of vulnerability (a leaked long-lived key with standing access) at the cost of a slightly more involved one-time trust-policy setup. **Get the trust policy's subject match exact** — a wildcard match on your org/repo name is a real, previously-caught vulnerability (see `security-history.md`): it can also match an attacker-created org with a similar name. Match on the CI provider's immutable numeric IDs, not a string pattern.

**Build once, promote forward.** Build and scan your deployable artifact (container image, package) exactly once, in your first environment, then redeploy that *exact same, already-scanned* artifact to every later environment — never rebuild per environment. This is what makes "it passed the security gates" mean something: the thing that reached production is provably the same bytes that were scanned, not a different build that happened to use the same source tag.

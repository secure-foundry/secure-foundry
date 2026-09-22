# Review Culture

Tooling catches what it's programmed to catch. The gaps between tools — a design decision that's technically valid but wrong for this system, a security assumption that holds today but won't in six months, a "this works" that hasn't actually been tested — are caught by a human who actually re-derives whether the work is correct. That habit is the actual control; the PR template is just where it's recorded.

## What a real review does that a rubber stamp doesn't

A rubber-stamp review reads the diff and checks it looks plausible. A real review re-derives, independently, whether the change is correct — which means the reviewer sometimes needs to run the code, trace the actual data flow, or check the claim against the real system, not just the stated intent. If a PR says "this fixes the race condition," a real review asks: what was racing, why does this fix it, and what would still be racing if the fix were subtly wrong?

Concretely, a reviewer should be able to answer, not just believe:
- What is this change actually for, in terms the reviewer independently understands — not just the PR description's own framing of it?
- What would break if this were subtly wrong, and does the diff show that case being handled?
- Does this change what a *different* part of the system assumes to be true? (A permission check moved, a default changed, a field that used to always be non-null.)
- If there's a test, does it actually exercise the change, or does it pass regardless of whether the fix is present?

## When one review isn't enough

A single approving review is the *minimum* bar, appropriate for routine, low-risk changes. Escalate to an independent second, adversarial review pass — someone deliberately trying to find what's wrong, not just confirm what's right — for:

- Anything touching authentication, authorization, or a permission boundary.
- Anything touching how secrets or credentials are handled or where they can flow.
- A new architectural pattern being introduced for the first time (the first use sets the precedent everyone copies later — get it right once, carefully, rather than fixing it in twenty call sites afterward).
- Infrastructure changes with a real blast radius — anything that can destroy data, affect a shared environment, or change who has access to what.

This project's own development discipline treats "maker-checker" as a literal role split: the person who designed and built something is a poor judge of whether they missed something, precisely because they're the one who had the blind spot in the first place. A second, independent reviewer — ideally one who wasn't in the room for the original design discussion — is the actual mechanism, not just a policy statement.

## A documented process is itself a control

A written development process — requirements clarified before design, architecture reasoned through before code, an adversarial review pass before merge — is not just good engineering hygiene. In a SOC 2 or similar audit, this is evidence for the **change management** control family: an auditor isn't just checking that your code is good, they're checking that you have a *repeatable process* that would catch a bad change before it ships, regardless of who wrote it. Write the process down, follow it consistently, and you have that evidence already, as a byproduct of working carefully rather than as separate compliance busywork.

## Review response norms

- A review comment names a specific problem and, where possible, what would resolve it — "this doesn't handle X" is more useful than "this seems risky."
- A reviewer who finds nothing wrong says so explicitly ("no findings" or "approved") rather than staying silent — silence is ambiguous between "I checked carefully and it's fine" and "I didn't really look."
- Don't resolve your own review comments. The person who raised a concern confirms it's actually addressed, not the person being reviewed.
- A disagreement between author and reviewer that can't resolve in comments gets a third opinion, not an impasse where the more senior person's view wins by default — seniority is not the same as being right about this specific change.

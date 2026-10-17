# Task brief template (RULES.md #14, #16)

A brief without a Goal or a checkable Finish gets rejected: the bot asks for a better one before it starts.

| Field | What to write |
|---|---|
| **Goal** | The outcome, in one sentence |
| **Finish** | A checkable condition that is either true or false (not "looks good") |
| **Evidence** | What the report has to show: links, SHAs, command output |
| **Scope** | The repos, paths and branch the bot may touch |
| **Verify** | The exact commands that prove it works |
| **Forbidden** | What the bot must not do |
| **Timebox** | Maximum time or quota, and what to do when it runs out |

The report answers each field in one line.

## Example
- **Goal:** Guest cancel in Schiet only works while the guest is PENDING.
- **Finish:** A PR is open from `phoenix/guest-cancel-pending`, CI is green, and a test fails without the fix.
- **Evidence:** PR link, head SHA, and the failing-then-passing test output in `<details>`.
- **Scope:** `Mxndarijn/Schietvereniging-FullStack`, `backend/src/guests/**` and its specs only.
- **Verify:** `npm --prefix backend test -- guests` and the verify-schietvereniging skill.
- **Forbidden:** merging, pushing to main, editing `.github/workflows`, touching auth or guards.
- **Timebox:** 45 min. If it isn't done by then, report status and blockers to SuperBottie.

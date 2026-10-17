# Watching your own open PRs (RULES.md #11)

Rule 11: every bot owns its open PRs and replies to every comment, Merijn's (Mxndarijn) first. Requested changes are made with Claude Code, pushed with the bot identity, and answered with proof (commit SHA, test results). SuperBottie's check-in also runs this watch for each bot (`WATCH_USER`) hourly at :50 and pings authors with unanswered items.

## Quick check at the start of each turn
`~/.local/bin/phoenix-pr-watch [owner/repo ...]` (Phoenix; default repos: Mxndarijn/Schietvereniging-FullStack, Mxndarijn/MnLib)
- Lists open PRs authored by `app/phoenix-bot-mxndarijn`, then every Mxndarijn item that hasn't been answered yet:
  - a review comment with no phoenix-bot reply in its thread after it
  - a PR conversation comment, or a review with a body or CHANGES_REQUESTED, newer than phoenix-bot's latest activity on the PR (comment, review or thread reply)
- `WATCH_USER='gojo-bot-mxndarijn[bot]' phoenix-pr-watch` checks another commenter, e.g. a peer reviewer.
- Pass repos explicitly for others, e.g. `phoenix-pr-watch Mxndarijn/Navigator2`.
- Ends with `-- unanswered items from <user>: N`.
- Read-only: it uses `ghbot-phoenix api`/`pr list`/`pr view` GETs only.

## For another bot
Copy the script, then change `G=` to your `ghbot-<bot>` wrapper, `ME=` to `<slug>[bot]`, and the `--author app/<slug>` filter.

## Fixing
- Make the requested change with Claude Code (`~/.local/bin/cc -p ...`, rule 1), not by hand; run the relevant tests.
- Push to the PR branch with the bot identity (credential helper `ghapp-token-<bot>`). Never push to main, never merge.

## Replying
- Thread reply: `ghbot-<bot> api -X POST repos/<o>/<r>/pulls/<n>/comments/<comment_id>/replies -F body=@reply.txt`
- Conversation comment: `ghbot-<bot> pr comment <n> -R <o>/<r> --body-file reply.txt`
- Include the commit SHA and what was run. Re-run `phoenix-pr-watch` afterwards: the item should be gone.

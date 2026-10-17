# Roblox rules for AI/automated testing of our own game

Researched 2026-10-15. Every quote below was checked word for word against the page text fetched that day (whitespace and curly quotes normalised). Quotes that couldn't be found in the fetched text were dropped. This is a reading of the published rules, not legal advice. Roblox doesn't publish a "developer testing exemption" anywhere we could find.
Related: `/workspace/guides/roblox-live-testing.md` (the how-to; its "Risks" section is superseded by this file).

## Verdicts

| Option | Verdict | Why |
|---|---|---|
| **(a) Studio**: built-in MCP server, Assistant, Studio playtests, plugins, playtest subagent | **Allowed** (it's the officially supported route) | Roblox built it for this, documents it, and names Claude Code as a quick-connect client. Roblox staff actively encourage AI playtesting in Studio. |
| **(b) Open Cloud Luau Execution** on our own universe/place | **Allowed** | Documented, Stable API; its own docs list "Automated testing … CI/CD" as a use. Stay inside the documented API, rate limits and key scopes. |
| **(c) An AI driving the real Roblox client** (screen capture + synthetic input) on a test/alt account | **Grey, leaning forbidden. Don't do it on the live platform.** | No rule allows it. Bot accounts are being swept. The Community Standards ban "disruptive" automation. The ToU bans automated access "in connection with … use of … AI" (the 1 Nov 2026 wording is broader). Alt accounts can be actioned together with the main account. |

## Sources and exact quotes

### Terms of Use (current version, plus the version effective 1 Nov 2026)
- Current ToU: https://en.help.roblox.com/hc/en-us/articles/115004647846-Roblox-Terms-of-Use
  - The page **403s** to curl. We read the same article through Roblox's own Zendesk API (`https://en.help.roblox.com/api/v2/help_center/en-us/articles/115004647846.json`, updated 2026-10-07). An archive.org copy also exists: https://web.archive.org/web/20261009173713/https://en.help.roblox.com/hc/en-us/articles/115004647846-Roblox-Terms-of-Use
  - The page has a banner saying new terms take effect November 1, 2026.
- New ToU (effective 1 Nov 2026): https://en.help.roblox.com/hc/en-us/articles/14663412502676-Roblox-is-Updating-our-Terms-of-Use
  - This page also **403s**. We read it via the Zendesk API (`.../articles/14663412502676.json`, updated 2026-10-15).

Current ToU, Restrictions of Use:
> Users may not (a) lease, lend, sell, redistribute, or sublicense any part of the Services ; (b) ... (c) circumvent any technological measure designed to protect the Services or any technology associated with the Services ; (d) access the Services using any means for the purpose of using Virtual Content in connection with the training, development, or use of machine learning models or artificial intelligence;

New ToU §9.2 (from 1 Nov 2026), "you will not (and will not attempt to or permit or enable others to)":
> access the Services using any means (for example, through data mining, robots, crawlers, scrapers or other automated data gathering and extraction tools) in connection with the training, development, or use of machine learning models or AI;

> circumvent, disable, fraudulently engage with any part of the Service, or otherwise attempt to gain unauthorized access to any portion of the Service or any other systems or networks connected to the Service;

Current ToU, on alt accounts:
> Roblox reserves the right, in its sole discretion, to terminate or suspend (i) your Account and (ii) your right to use and access the Roblox Services , including by suspending or terminating any alternate account(s) you create or have created.

New ToU §3.7, Use of Roblox APIs (relevant to b):
> only access an API by the means described in the documentation of that API, and refrain from misrepresenting or masking your identity or your API Client's identity when using the APIs;

> Roblox may suspend access to the APIs by you or your API Client without notice if we reasonably believe that you are in violation of the Roblox Terms .

### Community Standards
- https://about.roblox.com/community-standards (fetched OK, HTTP 200)

Under "Misusing Roblox Systems", "Disruptive Content and Behavior":
> Using bots or other automation that is programmed to run disruptive tasks

From the same section:
> Creating or using an account to avoid enforcement action taken against another account

Under "Cheating and Scams":
> Using or sharing exploits to help yourself or others gain an unfair advantage anywhere on the platform

The automation rule targets *disruptive* tasks. A quiet test bot in our own private place arguably isn't disruptive. But Roblox decides that, and its bot detection doesn't ask what the bot was for (see below).

### Account Switching help article (multiple accounts)
- https://en.help.roblox.com/hc/en-us/articles/21037888001044-Account-Switching
  - The HTML page wasn't tried directly. We read it via the Zendesk API (`.../articles/21037888001044.json`).

> The Account Switcher enables Roblox users with multiple accounts to easily access and switch between these accounts on the web.

> if a user violates our Community Standards, we may take action on different accounts that we determine belong to the same user.

So having a second account is normal and supported. What gets punished is what the account does, and enforcement spreads across linked accounts.

### Studio MCP server (option a)
- https://create.roblox.com/docs/studio/mcp (HTTP 200)

> The Roblox Studio MCP server is built into Roblox Studio.

> execute_luau Runs Luau code in Studio.

> start_stop_play Starts or stops playtesting.

> character_navigation Moves the player character to a given position or instance path.

> MCP clients can read and modify content in your open Roblox places. Make sure to only connect clients you trust.

"Claude Code" appears in the page's list of quick-connect clients.

### Studio Assistant guide (option a)
- https://create.roblox.com/docs/assistant/guide (we used the `.md` copy at `https://create.roblox.com/docs/assistant/guide.md`)

> If you're using a third-party client via MCP or your own API key, you continue to have direct access to the underlying screenshot tool.

### DevForum staff post: "[Studio Beta] Studio Assistant & MCP Playtest Agent" (option a)
- https://devforum.roblox.com/t/studio-beta-studio-assistant-mcp-playtest-agent/4566767 (posts 1, 28 and 30, by Mirrattar, Roblox_Staff, April 2026)

> We're adding a dedicated playtest subagent to Assistant and Studio's built-in MCP Server. When triggered, it spawns a test character and runs through gameplay scenarios in its own context

> Yes, you can batch run multiple test cases consecutively that your AI agent reads from a file and assigns to the playtest subagent.

> We advise against relying solely on the playtest subagent to verify gameplay.

> The playtest agent is able to read UI and click using the Studio MCP mouse_input tool.

### Open Cloud Luau Execution (option b)
- Reference page: https://create.roblox.com/docs/cloud/reference/features/luau-execution
  - The HTML version is a JS shell. We used the official markdown copy at `https://create.roblox.com/docs/en-us/cloud/reference/features/luau-execution.md`.

> Run Luau scripts headlessly in a Roblox place via Open Cloud for automated testing, game configuration, and procedural generation

> Automated testing: Run test scripts against specific place versions as part of a CI/CD pipeline

> The script can also invoke engine APIs that read and/or modify data stored in the cloud, such as those for DataStores. Exercise caution when using these APIs.

### Bot-account enforcement (option c risk)
- Roblox announcement, 19 Aug 2026, "Actioning Against Bot Accounts On Roblox": https://devforum.roblox.com/t/actioning-against-bot-accounts-on-roblox/4820656

> Bot accounts violate our Community Standards and Terms of Use , and we work continuously to detect them using sophisticated integrity signals and machine learning.

> including account behavior and activity patterns that don't match how real people use the platform.

> During this time, detected bot accounts might be kicked from game sessions in real-time

The announcement mentions no developer or testing exemption.

## Ban cases and enforcement patterns (all user reports, not staff statements)
- **Aug 2026 bot sweep:** an ongoing, large-scale removal of bot accounts, detected by behaviour. See the announcement above.
- **Linked-account terminations:** a DevForum thread (Feb 2026) reports a main account terminated, with "We used automated systems to make this decision.", for being linked to a banned account. Many replies report the same. https://devforum.roblox.com/t/ai-automated-system-falsely-terminating-thousands-of-accounts-for-avoiding-enforcement-actions-appealing-thru-roblox-support-is-impossible/4326830
- **Experience-level alt bans:** the Ban API auto-bans detected alts unless `ExcludeAltAccounts` is set. Docs: https://create.roblox.com/docs/reference/engine/classes/Players. A user thread on false alt-flags: https://devforum.roblox.com/t/unbans-for-individuals-flagged-as-alternative-accounts/3132785
- **Studio AI false positive:** a user reports a 7-day ban after an Assistant-generated mesh was flagged. This is unverified, and the thread wasn't fetched for quotes. https://devforum.roblox.com/t/warning-using-roblox-studio-ai-assistant-can-get-your-account-banned-false-positives/4756750
- **Macros/AHK vs Hyperion:** no official statement found. Only third-party claims, which conflict. Treat as unknown.

## Practical do / don't for our team

**Do**
- Use **Studio + the built-in MCP server**, including the playtest subagent, `start_stop_play`, input simulation and `screen_capture`. This is the sanctioned way for an AI to *play* the game.
- Use **Luau Execution** for headless CI against specific place versions. That's what `ci/run.py` and the Saved-version gate already do. Keep the API key scoped to our universe only, and stay within the documented endpoints and rate limits.
- Be careful with DataStores in Luau Execution and Studio tests. Writes are real. Use a test key prefix or a separate test universe.
- If a human-like client run is ever needed: have a **human** play it (Merijn, or a teammate on their own account), or use Studio multi-client tests (`StudioTestService`).
- Keep the Studio login on a real team member's account that is in good standing, with 2FA on.

**Don't**
- Don't run an AI or script that drives the **live Roblox Player** (screen-scrape + synthetic input) on any account, main or alt. Bot detection is behavioural and has no exemption. A ban can spread to linked accounts, which includes the account that owns the game.
- Don't create multiple or bulk test accounts, and don't use them to inflate visits, likes, follows or concurrent-player counts.
- Don't put `.ROBLOSECURITY` cookies into CI, cloud runners or AI tools. Don't call undocumented web endpoints. Use Open Cloud API keys or OAuth only.
- Don't use exploit/executor tools, injectors, or anything that touches Hyperion, even "just to test our game".
- Don't scrape other games or Roblox content to feed an AI. That falls squarely under the ToU AI clause.
- Don't treat a playtest-subagent "Pass" as release sign-off. Roblox staff say not to rely on it alone. The final visual sign-off is still a human.

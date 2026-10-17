# Roblox toolchain on Linux (no sudo, no accounts)

> **Restored 2026-10-15 from workspace notes after /guides loss; verify.** Everything up to "Publishing via Open Cloud" is the original text (2026-10-14), recovered from Claude Code transcripts. The last section was re-checked against `~/.local/bin` on 2026-10-15.

Tested 2026-10-14 on the bot box (Linux x86_64) by Archer/cc. Background and the can/can't list: `/workspace/team/roblox-feasibility.md`.
Roblox Studio itself is Windows/Mac only (https://create.roblox.com/docs/studio/setup), so on Linux we work code-first.

## Install (user-local)

```bash
D=/workspace/scratch/roblox-probe/dl; mkdir -p ~/.local/bin
for t in rojo luau selene lune wally; do mkdir -p $D/$t; done
cd $D/rojo   && curl -sLO https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip && unzip -oq *.zip
cd $D/luau   && curl -sLO https://github.com/luau-lang/luau/releases/download/0.742/luau-ubuntu.zip && unzip -oq *.zip
cd $D/selene && curl -sLO https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip && unzip -oq *.zip
cd $D/lune   && curl -sLO https://github.com/lune-org/lune/releases/download/v0.11.0/lune-0.11.0-linux-x86_64.zip && unzip -oq *.zip
cd $D/wally  && curl -sLO https://github.com/UpliftGames/wally/releases/download/v0.3.2/wally-v0.3.2-linux.zip && unzip -oq *.zip
cd ~ && install -m755 $D/rojo/rojo $D/luau/luau $D/luau/luau-analyze $D/selene/selene $D/lune/lune $D/wally/wally ~/.local/bin/
export PATH=$HOME/.local/bin:$PATH
```

Already installed on the box. For newer versions, check `curl -sL https://api.github.com/repos/<owner>/<repo>/releases/latest`.
Optional: pin per repo with Rokit (https://github.com/rojo-rbx/rokit) instead of manual installs.

## Verify

```bash
rojo --version          # Rojo 7.7.1
selene --version        # selene 0.32.0
lune --version          # lune 0.11.0
wally --version         # wally 0.3.2
echo 'print(1+1)' > /tmp/t.luau && luau /tmp/t.luau   # 2   (luau has no --version flag; release 0.742)
```

## Daily use

```bash
rojo init mygame && cd mygame        # src/{server,client,shared} + default.project.json
rojo build -o game.rbxlx             # XML place file (or game.rbxl for binary)
printf 'std = "roblox"\n' > selene.toml && selene src
luau-analyze src/shared/*.luau       # type check
luau tests/course_test.luau          # pure-logic tests (no Roblox APIs in plain luau)
lune run scripts/build.luau          # scripting with fs/net/process + roblox place-file library
wally init && wally install          # packages from the public index (no account needed)
```

## Gotchas
- Plain `luau` and `lune` have **no game engine**. `game`, `workspace` and `Instance.new` in game scripts won't run there. Keep
  testable logic in pure modules and test engine-dependent code with the Open Cloud Luau Execution API
  (https://create.roblox.com/docs/cloud/reference/features/luau-execution).
- `run-in-roblox` and the Rojo Studio plugin need Studio, so they don't work on this box.
- Publishing needs Merijn's Open Cloud API key as a secret. Never commit it. See the feasibility doc §5.

## Project skeleton (2026-10-14)
Template: /workspace/roblox/speed-escape-skeleton. stylua 2.6.0 is in ~/.local/bin. Verify with: rojo build -o build.rbxlx; lune run tests (run from project root); selene src tests; stylua --check src tests. Tools are pinned in rokit.toml.

## Publishing via Open Cloud
1. `rojo build -o speed-escape.rbxl` (binary .rbxl, not .rbxlx).
2. `curl -s -o publish-response.json -w '%{http_code}' -X POST "https://apis.roblox.com/universes/v1/<UNIVERSE>/places/<PLACE>/versions?versionType=Published" -H "x-api-key: $ROBLOX_OPEN_CLOUD_API_KEY" -H "Content-Type: application/octet-stream" --data-binary @speed-escape.rbxl`
3. Expect HTTP 200 and `{"versionNumber":N}`. Never echo the key or use `set -x`.
4. Uploading meshes/models (FBX → Model asset) is a separate flow: see [roblox-assets.md](roblox-assets.md).

*[restore note]* The curl above puts the key in argv, where `ps` can see it. The newer pattern in `steal-a-slime-b0/tools/livetest/gate.sh` sends the header on stdin instead: `printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS -H @- ...`. Full flow (Saved vs Published, gate, retries): [roblox-build-and-publish.md](roblox-build-and-publish.md).

## State on the box (checked 2026-10-15)
| Binary in `~/.local/bin` | Version |
|---|---|
| `rojo` | Rojo 7.7.1 |
| `lune` | lune 0.11.0 |
| `wally` | wally 0.3.2 |
| `selene` | selene 0.32.0 |
| `stylua` | stylua 2.6.0 |
| `luau`, `luau-analyze` | release 0.742 per the feasibility doc (neither has a `--version` flag) |
| `blender` | symlink to `~/.local/opt/blender-4.5.14-linux-x64/blender` (portable 4.5.14 LTS, used for renders and meshes) |

- `rokit` is **not** installed on the box. The repos' `rokit.toml` pins match the binaries above, and CI installs them with `CompeyDev/setup-rokit`.
- These live under `/home`, which survives the root-fs reset on reboot.
- Repos using this toolchain: `/workspace/roblox/speed-escape-skeleton` (template; `VERIFY.md` has a 2026-10-14 run) and `/workspace/roblox/steal-a-slime-b0`.
- Live testing without Studio: [roblox-live-testing.md](roblox-live-testing.md).

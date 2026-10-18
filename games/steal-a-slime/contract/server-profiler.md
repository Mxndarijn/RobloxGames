# 25. v23: server performance profiler (`FEATURES.ServerProfiler`, default `false`)

**Status:** `false` = every `Profiler` call returns at once (no clock read, no table write, no log, no attribute). Server only; no remote, no State field, no save change.

- **Module (`src/server/Profiler`, pure, Lune-tested):** `record` / `time` keep the last `Config.PROFILER.WINDOW` (120) samples per system in a ring buffer (ms from `os.clock`); `stats` gives avg, nearest-rank p95 and max; `count` bumps named counters (the `Request` remote) that the summary prints per second.
- **Wired in `init.server` / `ServerLoop`:** the Heartbeat is timed as `Heartbeat` with `Rescue`, `GameLoop` (spawner, steal, income, milestones), `Players` and `View` inside it; `Request` calls are counted.
- **Output:** every `Config.PROFILER.LOG_INTERVAL` (30 s) one line, e.g. `[Profiler] | GameLoop 0.12/0.30ms | Heartbeat 0.8/1.9ms | instances=1234 | players=3 | Request=3.2/s` (avg/p95 per system; instance count is taken only when a line is due), and one `warn` per system whose p95 is over `Config.PROFILER.BUDGET_MS[name]`. The line is also set as workspace attribute `ProfilerSummary` (read-only dump; no chat command).

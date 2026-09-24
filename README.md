# StockPiler4

Clean-core Cultivation + Apothecary stock automation for Return of Reckoning.

**Version 0.4.21** — Parallel-safe sibling of StockPiler3 with GenusLadder + ClimbPlan, immutable plan snapshots, and no FrameWork bag→plan path.

## Quick start

1. Install under `Interface/AddOns/StockPiler4/` (StockPiler3 may stay installed)
2. Optional: LibSlash (`/sp4`), LibPerf (`/libperf StockPiler4 on 250`)
3. Reload UI; open with `/sp4`

## Architecture (clean core)

| Piece | Role |
| :--- | :--- |
| `GenusLadder` | Pure genus ladder merge/query |
| `ClimbPlan` | Plant-watch climb + shared cult seed economy (UpgradeSeed alias) |
| `PlantPlan` | Plant candidate → `plantIntent` |
| `PlanSnapshot` | Immutable plan; executors do not patch rows |
| `Scheduler` | 50ms storm debounce; EventBus UI refresh |
| Adapters / MaterialExceptions / XML | Ported from SP3 |

Reference docs for verification: [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md).

## Slash

| Command | Purpose |
| :--- | :--- |
| `/sp4` | Toggle window |
| `/sp4 potions` / `watch` / `plants` | Open tab |
| `/sp4 help` | Command list |
| `/sp4 debug` / `on` / `off` | Structured uilog |
| `/sp4 dumpall` | Bags + every plan/diagnostic dump (one shot) |
| `/sp4 plan` / `watchplan` / `state` / `growplan` / `brewplan` / `buyplan` / `skillplan` / `families` / `upgradeplan` | Dumps |
| `/sp4 stats` / `bags` / `events` / `mem` / `audit` / `harvest` | Diagnostics |
| `/sp4 perf` | In-addon hitch summary when LibPerf absent |

Parallel with SP3: `/sp3` remains StockPiler3; SavedVariables and macros do not share names.

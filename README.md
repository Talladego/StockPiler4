# StockPiler4

Clean-core Cultivation + Apothecary stock automation for Return of Reckoning.

**Version 0.4.36** — Parallel-safe sibling of StockPiler3 with GenusLadder + ClimbPlan, immutable plan snapshots, Watch→Footer→Macro first-paint stagger, and plant intent-refresh deferred off Orch execute frames. SkillUp is split across Gates / CultSkillPlan / ApoSkillPlan / SkillUpWatchStatus; 0.4.36 adds libperf spike phase tags (`phase=login|harvestStorm|plantQuiet|quietEnd|executePlant|dumpall|unknown` + emptyPlots/additive) for soak attribution.

## Quick start

1. Install under `Interface/AddOns/StockPiler4/` (StockPiler3 may stay installed)
2. From this repo: `.\tools\deploy.ps1` copies `StockPiler4.mod` + `Source\` to the live AddOns folder (see [`tools/README.md`](tools/README.md))
3. Optional: LibSlash (`/sp4`), LibPerf (`/libperf StockPiler4 on 250`)
4. Reload UI; open with `/sp4`

## Architecture (clean core)

| Piece | Role |
| :--- | :--- |
| `GenusLadder` | Pure genus ladder merge/query |
| `ClimbPlan` | Plant-watch climb + shared cult seed economy (UpgradeSeed alias) |
| `PlantPlan` | Plant candidate → `plantIntent` |
| `PlanSnapshot` | Immutable plan; executors do not patch rows |
| `Scheduler` | 50ms storm debounce; EventBus UI refresh |
| `SkillUpGates` / `CultSkillPlan` / `ApoSkillPlan` / `SkillUpWatchStatus` | SkillUp split (gates, cult/apo plans, watch status); WatchStatus uses Gates/CSP module APIs |
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

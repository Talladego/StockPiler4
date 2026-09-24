# StockPiler4 Feature Coverage

**Scope:** README.md intended features vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.20** (`StockPiler4.mod` / `Bootstrap.lua`) · README claims **0.4.20**  
**Method:** README feature extraction → source/symbol evidence → status + gaps

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 23 |
| Partial | 0 |
| Missing | 0 |
| **Total intended features** | **23** |

---

## 1. Product & isolation

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Cultivation + Apothecary stock automation | **Implemented** | `Orchestrator.lua` phase FSM; `Grow.lua` plant/harvest/additive; `Refine.lua`; `Brew.lua`; `Buy.lua`; `SkillUp.lua`; Watch-driven demand via `Planner` / `DemandPlan` / `BrewPlan` / `BuyPlan` | Not a single module — full pipeline is present and wired. In-game hitch/climb acceptance is out of scope for this static review. |
| Parallel-safe sibling of StockPiler3 | **Implemented** | `StockPiler4.mod` SavedVariables `StockPiler4.Settings` / `StockPiler4.Account`; slash `/sp4`; macros `StockPiler4 Harvest/Brew/Craft` (`Macro.lua`); windows `StockPiler4Window` / `SP4*` | README notes SP3 may stay installed; naming isolation matches. |
| Clean-core (no FrameWork bag→plan path) | **Implemented** | `FrameWork.EnqueueWarmHave` / `EnqueueDemand` / `EnqueueSeedLines` / `IsPrewarmBusy` are intentional no-ops (`FrameWork.lua` ~214–230). Plan path is Scheduler debounce → `PlanSnapshot.GetOrBuild` → `Planner.Build` | `FrameWork` still exists for generic frame jobs; bag→plan prewarm path is disabled as README claims. Stale comment in `Planner.lua` still mentions `FrameWork.EnqueueWarmHave`. |

---

## 2. Architecture systems (README table)

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| **GenusLadder** — pure genus ladder merge/query | **Implemented** | `Source/Knowledge/GenusLadder.lua`: `MergeGenusLadders`, `GetLadder`, `GetRung`, `BestOwnedRung`, `VendorRung`, `CultMaxNeedReq`, `LadderForPlantWatch` | — |
| **ClimbPlan** — plant-watch climb + shared cult seed economy | **Implemented** | `Source/Planner/ClimbPlan.lua`: climb pick/buy/refine (`PickPlantJob`, `SeedDeficit`, `CollectBuyJobs`, `AppendRefineIntents`, `CultMaxTierBufferFull`, watch status rows). Loaded in `.mod` before Planner. | — |
| **UpgradeSeed** alias of ClimbPlan | **Implemented** | End of `ClimbPlan.lua`: `StockPiler4.UpgradeSeed = StockPiler4.ClimbPlan`. `UpgradeSeed.lua` is a deprecated shim **not** listed in `.mod` | Call sites still name `UpgradeSeed`; behavior is ClimbPlan. |
| **PlantPlan** — plant candidate → `plantIntent` | **Implemented** | `PlantPlan.BuildPlantIntent`, `PickPlantJob`; `Planner` publishes `plan.plantIntent`; `Orchestrator.TryExecutePlant` → `Grow.ExecutePlant(intent)` only | — |
| **PlanSnapshot** — immutable plan; executors do not patch rows | **Implemented** | Cheap/Garden/Reconcile clone-then-Replace; View chips optimistic-only; public patch enqueues rebuild only | — |
| **Scheduler** — 50ms storm debounce | **Implemented** | `Scheduler.PLAN_DEBOUNCE_SEC = 0.05`; harvest storm / SkipPlan / SkipUi arm debounce (`Scheduler.lua`) | Longer quiet/storm floors coexist with 50ms coalesce — by design. |
| **EventBus** UI refresh | **Implemented** | Domain fires `FOOTER_DIRTY` / `WATCH_UI_DIRTY`; `Ui.lua` subscribes and flushes | — |
| Adapters ported from SP3 | **Implemented** | `.mod` loads adapters + `TradeSkillCaps` / `CraftChatAdapter` | — |
| MaterialExceptions ported from SP3 | **Implemented** | `Source/Knowledge/MaterialExceptions.lua` | — |
| XML UI ported / renamed for SP4 | **Implemented** | `StockPiler4Templates.xml`, tab XML + Lua | — |

---

## 3. Install / optional deps (README Quick start)

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Install under `Interface/AddOns/StockPiler4/` | **Implemented** | Live tree matches; `.mod` `UiMod name="StockPiler4"` | — |
| Optional **LibSlash** (`/sp4`) | **Implemented** | Dependency `optional="true"`; `Bootstrap.Initialize` registers `sp4` / `stockpiler4` | Without LibSlash, slash may need manual binding. |
| Optional **LibPerf** (`/libperf StockPiler4 on 250`) | **Implemented** | Optional dep; `Perf.lua` uses LibPerf when present | — |
| Open UI with `/sp4` | **Implemented** | Empty slash → `Ui.ToggleWindow` | — |

---

## 4. Slash surface (README Slash table)

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `/sp4` toggle window | **Implemented** | `Bootstrap.OnSlash` empty → `Ui.ToggleWindow` | Also accepts `open` / `show`. |
| `/sp4 potions` / `watch` / `plants` | **Implemented** | Opens tabs via `Ui.ShowWindow` | — |
| `/sp4 help` | **Implemented** | `PrintHelp()` + `enUS` `boot.help.*` | Help documents `/sp4 perf` and `/sp4 on|off`. |
| `/sp4 debug` / `on` / `off` | **Implemented** | `debug` / `debug on` / bare `on` enable; `debug off` / bare `off` disable | — |
| `/sp4 dumpall` | **Implemented** | `DumpAll()` full diagnostic dump | — |
| Dumps: `plan`, `watchplan`, `state`, `growplan`, `brewplan`, `buyplan`, `skillplan`, `families`, `upgradeplan` | **Implemented** | Individual `OnSlash` branches | — |
| Diagnostics: `stats`, `bags`, `events`, `mem`, `audit`, `harvest` | **Implemented** | Matching handlers | Extra: `stats clear`, `fingerprint`, `bags force`, `events on\|off\|dump` |
| `/sp4 perf` — in-addon hitch summary when LibPerf absent | **Implemented** | `OnSlash` → `Perf.PrintSummary()`; help advertises `/sp4 perf` | — |

---

## 5. Doc / version drift (not a runtime feature)

| Item | Notes |
| :--- | :--- |
| README **Version 0.4.20** matches live `.mod` / `StockPiler4.Version` | Closed. |
| Acceptance / refactor docs | `docs/ACCEPTANCE.md` and related docs expand product rules; this file stays README-primary. |

---

## Prioritized gap summary

1. **Minor comment/debt** — `Planner` may still mention FrameWork warm-have; `UpgradeSeed` name remains in call sites (alias OK).
2. Architecture leftovers (not README feature gaps) — SkillUp remnant, lean Grow/Planner/TabWatch, RecipeSpec buffer shims, Scheduler flags — see `ARCHITECTURE_COVERAGE.md`.

No README-named capability is entirely **missing**. PlanSnapshot immutability is **Implemented** for cheap/garden/reconcile + View.

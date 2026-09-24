# StockPiler4 Feature Coverage

**Scope:** README.md intended features vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.17** (`StockPiler4.mod` / `Bootstrap.lua`) · README claims **0.4.0**  
**Method:** README feature extraction → source/symbol evidence → status + gaps

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 20 |
| Partial | 3 |
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
| **PlanSnapshot** — immutable plan; executors do not patch rows | **Partial** | Store contract in `PlanSnapshotStore.lua` (Set/Replace/Get read-only). Executors (`Orchestrator`, `Grow.ExecutePlant`) consume snapshot intents without row edits. | **Planner** mutates the live snapshot in place: `PatchWatchRowsLiveCounts`, `RefreshPlantRefineIntents`, `TryCheapRebuild` / `TryGardenPatch` write `stale.plantIntent` / row fields then re-publish. **View** `StockPiler4TabWatch.PatchPlanSnapshotTarget` mutates `plan.rows` targets on chip edit. Contract is documented more strongly than runtime behavior. |
| **Scheduler** — 50ms storm debounce | **Implemented** | `Scheduler.PLAN_DEBOUNCE_SEC = 0.05`; harvest storm / SkipPlan / SkipUi arm debounce (`Scheduler.lua`) | Longer quiet/storm floors (e.g. harvest ≥~1.5s) exist alongside the 50ms plan coalesce — by design for storms, not a missing debounce. |
| **EventBus** UI refresh | **Implemented** | `EventBus.lua` events (`PLAN_UPDATED`, `PLAN_INVALIDATED`, inventory/garden snaps, …); `Ui.lua` subscribes and marks dirty / refreshes Watch | — |
| Adapters ported from SP3 | **Implemented** | `.mod` loads `BagAdapter`, `CultivatorAdapter`, `ApothecaryAdapter`, `VendorAdapter`, `TradeSkillCaps`, `CraftChatAdapter` | — |
| MaterialExceptions ported from SP3 | **Implemented** | `Source/Knowledge/MaterialExceptions.lua` (uid / special-mat overrides) | — |
| XML UI ported / renamed for SP4 | **Implemented** | `StockPiler4Templates.xml`, `StockPiler4Tab{Potions,Plants,Watch}.xml`, `StockPiler4Window.xml` + matching Lua tabs | — |

---

## 3. Install / optional deps (README Quick start)

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Install under `Interface/AddOns/StockPiler4/` | **Implemented** | Live tree matches; `.mod` `UiMod name="StockPiler4"` | — |
| Optional **LibSlash** (`/sp4`) | **Implemented** | Dependency `optional="true"`; `Bootstrap.Initialize` registers `sp4` / `stockpiler4`; logs if missing | Without LibSlash, slash may need manual binding (noted in code). |
| Optional **LibPerf** (`/libperf StockPiler4 on 250`) | **Implemented** | Optional dep; `Perf.lua` uses `LibPerf.Scope("StockPiler4")` when present, else in-addon hitch logger | — |
| Open UI with `/sp4` | **Implemented** | Empty slash → `Ui.ToggleWindow` | — |

---

## 4. Slash surface (README Slash table)

| Feature | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `/sp4` toggle window | **Implemented** | `Bootstrap.OnSlash` empty → `Ui.ToggleWindow` | Also accepts `open` / `show` (extra). |
| `/sp4 potions` / `watch` / `plants` | **Implemented** | Opens tabs 1 / 3 / 2 via `Ui.ShowWindow` | — |
| `/sp4 help` | **Implemented** | `PrintHelp()` + `enUS` `boot.help.*` | Help `boot.help.perf` points at `/libperf …`, not `/sp4 perf`. |
| `/sp4 debug` / `on` / `off` | **Partial** | `debug`, `debug on` → enable; `debug off` → disable | README wording suggests bare `/sp4 on` and `/sp4 off`. Those are **not** handled (fall through to unknown). |
| `/sp4 dumpall` | **Implemented** | `DumpAll()` sections: state, bags, plan, watchplan, growplan, brewplan, buyplan, skillplan, families, upgradeplan, stats, mem, audit, events | — |
| Dumps: `plan`, `watchplan`, `state`, `growplan`, `brewplan`, `buyplan`, `skillplan`, `families`, `upgradeplan` | **Implemented** | Individual branches in `OnSlash`; `upgradeplan` via `UpgradeSeed.Dump` (ClimbPlan alias) | — |
| Diagnostics: `stats`, `bags`, `events`, `mem`, `audit`, `harvest` | **Implemented** | Matching `OnSlash` handlers; `harvest` fires `CMD_HARVEST` / `Grow.PrepareHarvestPlot` | Extra: `stats clear`, `fingerprint`, `bags force`, `events on\|off\|dump` |
| `/sp4 perf` — in-addon hitch summary when LibPerf absent | **Implemented** | `OnSlash` → `Perf.PrintSummary()` | Help text does not advertise `/sp4 perf` (only LibPerf). |

---

## 5. Doc / version drift (not a runtime feature)

| Item | Notes |
| :--- | :--- |
| README **Version 0.4.0** vs live **0.4.17** | README is stale relative to `.mod` / `StockPiler4.Version`. Feature set in README still describes the live architecture; bump README version when editing. |
| Acceptance / refactor docs | `docs/ACCEPTANCE.md` and related docs expand product rules (climb buffer, SkillUp, hitch). They confirm architecture checkboxes; this coverage file stays README-primary. |

---

## Prioritized gap summary

1. **PlanSnapshot “immutability” is partial (highest architecture mismatch)** — README/store contract say executors do not patch; Cheap/Garden rebuilds and Watch target chips still mutate the cached plan object in place. Prefer replace-whole-snapshot (or explicit overlay) if strict immutability remains a goal.
2. **Slash `debug / on / off` wording vs code** — `debug` / `debug on` / `debug off` work; bare `on` / `off` do not. Align README or add aliases.
3. **Help vs `/sp4 perf`** — command exists; locale help only documents LibPerf. Mention `/sp4 perf` in help for the no-LibPerf path.
4. **README version string** — update to 0.4.17 (or current) to avoid install confusion.
5. **Minor comment/debt** — `Planner` still comments FrameWork warm-have; `UpgradeSeed` name remains in call sites (alias OK).

No README-named capability is entirely **missing** in the live tree; gaps are contract strictness, slash/help polish, and doc version drift.

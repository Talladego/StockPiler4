# StockPiler4 Architecture Coverage

**Scope:** Intended architecture from design docs vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.18** (`StockPiler4.mod`)  
**Sources of intent:** `REFACTORING_RECOMMENDATIONS.md`, `IMPLEMENTATION_PLAN.md`, `FRAME_SLICING.md`, `ACCEPTANCE.md` (architecture checkboxes), `CODE_QUALITY_REVIEW.md` (problems → redesign targets), `README.md` (clean-core table)  
**Not a target:** `FEATURE_COVERAGE.md` (prior feature review output)

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 16 |
| Partial | 9 |
| Missing | 1 |
| **Total architectural targets** | **26** |

---

## 1. Parallel safety & keep-list (Phase 0)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Distinct `StockPiler4` addon: `.mod`, SavedVariables, slash, window names | **Implemented** | `StockPiler4.mod`: `UiMod name="StockPiler4"`; SV `StockPiler4.Settings` / `StockPiler4.Account`; `OnInitialize` creates `StockPiler4Window`; `Bootstrap` registers `/sp4` / `/stockpiler4` | — |
| Keep Adapters unchanged | **Implemented** | `.mod` loads `BagAdapter`, `CultivatorAdapter`, `ApothecaryAdapter`, `VendorAdapter`, `TradeSkillCaps`, `CraftChatAdapter` | — |
| Keep MaterialExceptions / Classify / Items / Additives + View XML | **Implemented** | Knowledge files present; XML renamed `StockPiler4Templates.xml`, `StockPiler4Tab*.xml`, `StockPiler4Window.xml` | — |
| Centralize helpers in `Core/Util.lua` | **Implemented** | `Util.lua` owns `ToNarrow`, `NowSec`, `TryCall`, `T`; former local copies are thin `Util.*` delegates (Catalog, SeedMap, RecipeSpec, Planner, Grow, …) | Call sites may still use a local alias name; logic is centralized. |

---

## 2. Knowledge & ladder consolidation (Phase 1 / pillar 3.1)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `Knowledge/GenusLadder.lua` pure ladder query API | **Partial** | `GenusLadder.lua`: `MergeGenusLadders`, `GetRung`, `BestOwnedRung`, `VendorRung`, `CultMaxNeedReq`, `LadderForPlantWatch` | Most getters **delegate to `SeedMap`** (`GetGenusLadder`, `BestOwnedSeedOnLadder`, …). Heavy merge/build still lives in `SeedMap.lua` (~3k lines). Facade exists; ownership not fully extracted. |
| `Planner/ClimbPlan.lua` shared climb + cult seed economy; replace UpgradeSeed monolith | **Implemented** | `ClimbPlan.lua` (~2182 lines) loaded in `.mod`; end sets `StockPiler4.UpgradeSeed = StockPiler4.ClimbPlan`. `UpgradeSeed.lua` is a 16-line deprecated shim **not** in `.mod` | Call sites still say `UpgradeSeed`; behavior is ClimbPlan. |
| Delete & replace `SkillUp.lua` via GenusLadder + ClimbPlan | **Missing** | Disposition table in `IMPLEMENTATION_PLAN.md`: SkillUp → Delete & Replace | **SkillUp.lua still loaded** (~3802 lines). Cult deficit math **delegates** via `ClimbEconomy()` → ClimbPlan; `ClimbPlan.GetCultSkill` now calls `TradeSkillCaps` directly (no SkillUp facade). Apo SkillUp, ephemeral UI, rate samples, brew policy remain. Not deleted. |
| `TradeSkillCaps.FloorCultTier` / `FloorApoTier` canonical | **Implemented** | `TradeSkillCaps.lua` owns floors; `SkillUp` / `ClimbPlan` wrappers call Caps | Redundant wrappers remain (acceptable). |
| Harvest crit must not overwrite canonical seed↔plant; BrewLearn abort skillUpOrigin | **Implemented** | `SeedMap.RecordHarvestProduct`: `critTierUp` → `critProduct`, never primary link; `BrewLearn` skips learn when `skillUpOrigin`; `RecipeSpec.StoreLearned` rejects skillUpOrigin | LearnBridge itself is thin; invariant lives in SeedMap/BrewLearn as intended. |

---

## 3. Store integrity & plan pipeline (Phase 2 / pillars 3.3, 3.5)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `RefinePipelineStore.ExpireStuck` safe delete + consistent outstanding shape | **Implemented** | Collect `toRemove` during `pairs`, delete after; normalize scalar→`{ count, at, plantUid }` | — |
| `InventoryStore` static wipe + `ByRole` index | **Implemented** | `STATIC_*` tables + `Wipe`; `RebuildFromBags` reuses them; `CountByRoleTier` / `GetByRoleIndex` | — |
| Strict read-only `PlanSnapshot` (executors never patch rows) | **Partial** | Store contract; Brew/Buy do not patch; Orchestrator/Grow consume `plantIntent`; **TabWatch no longer mutates** snapshot on target chips (optimistic local row only) | **Planner** still mutates live snapshot: `PatchWatchRowsLiveCounts`, cheap/garden patch write `stale.plantIntent` / rows. |
| Drop FrameWork bag→plan prewarm; 50ms storm debounce | **Implemented** | `FrameWork.EnqueueWarmHave` / `EnqueueDemand` / `EnqueueSeedLines` / `IsPrewarmBusy` are no-ops returning false; `Scheduler.PLAN_DEBOUNCE_SEC = 0.05` | `FrameWork.lua` still loaded for generic `Start`/`Pump`; stale Planner comment still mentions `EnqueueWarmHave`. |
| Strip Scheduler prewarm holds / 15+ suppression flags | **Partial** | Plan path no longer gated on `IsPrewarmBusy` | Still has `_suppressInvTicks`, `_pending*AfterSuppress`, `_harvestStormUntil`, `_plantQuietUntil`, `_skipPlanThisFrame`, `_skipUiThisFrame`, `_skipUiHoldFooter`, `_skipOrchThisFrame`. Storm/quiet floors coexist with 50ms debounce (partly by design; sprawl target unmet). |
| Reserve time-slicing for catalog only (`FRAME_SLICING.md`) | **Partial** | Bag→plan slicing gone | Catalog does **not** use FrameWork; generic FW remains in core. Recommendation only half-applied. |

---

## 4. Pure planning & decoupled execution (Phase 3 / pillar 3.2)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Plant candidate selection in `PlantPlan`; publish `plantIntent` | **Implemented** | `PlantPlan.PickPlantJob` / `BuildPlantIntent`; `Planner` publishes `plan.plantIntent`; `Grow.PickPlantCandidate` → `PlantPlan.PickPlantJob` | — |
| Orchestrator single `TryExecutePlant` from snapshot intent | **Implemented** | `Orchestrator.TryExecutePlant` → `Grow.ExecutePlant(intent)` only; fillBlocked / main / refine-miss branches share helper | Still calls `Grow.MarkPlantJobProbed` / `MarkPlantJobDirty` around refine-first (private queue coupling). |
| Grow as lean pure executor (~500 lines): ExecutePlant / Additive / Harvest | **Partial** | `Grow.ExecutePlant`, `ExecuteAdditive`, `ExecuteHarvest` exist; tick plants from snapshot | **~1463 lines** remain: plant-queue cache, fillBlocked, harvest prepare/wake, diagnostics, buffer helpers. Not reduced to ~500. |
| Remove Planner shims from `RecipeSpec`; callers query Planner | **Partial** | Shims are thin delegates to `DemandPlan` / `Planner` | Shims **still present** (`RS.BuildBalancedSpecDemand`, `CollectAutoGrowFocus`, `WatchHasSeedBufferShort`, …). Callers in ClimbPlan, PlantPlan, Refine, Brew still go through RecipeSpec. |
| Decompose Planner into sub-planners; immutable intents | **Partial** | `.mod` loads `PlantPlan`, `ClimbPlan`, `DemandPlan`, `BrewPlan`, `BuyPlan` | **`Planner.lua` still ~4537 lines** (35 exports). Demand/brew/buy extraction incomplete relative to “decompose & pure” disposition. |

---

## 5. Event-driven UI & view thinness (Phase 4 / pillar 3.4)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Domain publishes EventBus; View owns window refresh | **Implemented** | `EventBus.FireFooterDirty` / `FireWatchUiDirty` + `Events.WATCH_UI_DIRTY`; Grow/Brew/Buy/Bridge/Planner publish via EventBus; `Ui` subscribes and flushes footer/Watch | Scheduler helpers remain as EventBus wrappers for Scheduler-internal use. View may still call `Ui.*` directly (OK). |
| Watch tab renders snapshot rows; ephemeral/status logic in Planner | **Partial** | Ephemeral Upgrade/SkillUp rows built in ClimbPlan/SkillUp → plan rows | **`StockPiler4TabWatch.lua` ~2283 lines**: `IsEphemeralWatchRow`, deficit math, status/chrome. Not a thin binder. |

---

## 6. Unidirectional pipeline & coupling (from CODE_QUALITY_REVIEW → redesign)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Unidirectional flow: Events → Bridge → Stores → Orch → Planner → Executors → Adapters; View via events | **Partial** | Bridge/stores/orch/planner/executors present; domain→UI now EventBus | Remaining edges: RecipeSpec↔Planner shims, SeedMap ladder ownership, Grow plant-queue probed by Orch. |
| Public APIs instead of private-field probing (`_refineDirty`, etc.) | **Partial** | `Refine.IsDirty` / `ClearDirty` / `DirtyReason` used by Orchestrator | Grow plant-queue internals (`_plantQueueDirty`, `MarkPlantJobProbed`) still cross-module. `Planner._closedLiveSnapGen` still declared. |

---

## 7. README clean-core table (architecture claims)

| Claim | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| GenusLadder + ClimbPlan + PlantPlan + PlanSnapshot + Scheduler debounce + EventBus UI | **Partial** (as a set) | All pieces exist and are wired (see §§2–5); EventBus UI exclusivity closed for domain | Individual rows: GenusLadder/SkillUp/Planner snapshot mutation remain partial/missing. |

---

## Prioritized gap summary

1. **SkillUp monolith not retired** — Design disposition was delete/replace; file remains ~3802 lines and loaded. Highest remaining architecture debt vs Phase 1 / pillar 3.1. Next safe chunk: extract rates (`SkillRates`) / Apo brew board (`ApoSkillPlan`).
2. **PlanSnapshot immutability incomplete** — View chip-edit mutation removed; **Planner** cheap/garden paths and `PatchWatchRowsLiveCounts` still mutate the live snapshot.
3. **Grow / Planner / TabWatch size** — Sub-modules exist, but Grow (~1.5k), Planner (~4.5k), TabWatch (~2.3k) are not “lean executor / decomposed / thin view” yet.
4. **RecipeSpec → Planner shims** — Thin delegates remain; callers still go through RecipeSpec.
5. **Scheduler suppression web** — 50ms debounce is in place; prewarm gate is gone; remaining skip/storm/quiet/suppress flags were not fully stripped.
6. ~~**Domain → UI coupling**~~ — **Closed** for domain executors/bridge/planner (EventBus `FOOTER_DIRTY` / `WATCH_UI_DIRTY`).
7. ~~**Util centralization**~~ — **Closed** (local helpers are Util delegates).

**Bottom line:** Parallel-safe clean-core foundations plus EventBus-only domain→UI and Util centralization are **in production**. Hardest remaining targets: **SkillUp deletion**, **Planner-side snapshot immutability**, lean Grow/Planner/View, RecipeSpec shim removal.

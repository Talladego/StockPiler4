# StockPiler4 Architecture Coverage

**Scope:** Intended architecture from design docs vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.20** (`StockPiler4.mod`)  
**Sources of intent:** `REFACTORING_RECOMMENDATIONS.md`, `IMPLEMENTATION_PLAN.md`, `FRAME_SLICING.md`, `ACCEPTANCE.md` (architecture checkboxes), `CODE_QUALITY_REVIEW.md` (problems → redesign targets), `README.md` (clean-core table)  
**Not a target:** `FEATURE_COVERAGE.md` (prior feature review output)

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 17 |
| Partial | 8 |
| Missing | 1 |
| **Total architectural targets** | **26** |

---

## 1. Parallel safety & keep-list (Phase 0)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Distinct `StockPiler4` addon: `.mod`, SavedVariables, slash, window names | **Implemented** | `StockPiler4.mod`; SV `StockPiler4.Settings` / `StockPiler4.Account`; `/sp4` | — |
| Keep Adapters unchanged | **Implemented** | Adapters loaded in `.mod` | — |
| Keep MaterialExceptions / Classify / Items / Additives + View XML | **Implemented** | Knowledge + XML present | — |
| Centralize helpers in `Core/Util.lua` | **Implemented** | Local `ToNarrow`/`NowSec` are Util delegates | — |

---

## 2. Knowledge & ladder consolidation (Phase 1 / pillar 3.1)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `Knowledge/GenusLadder.lua` pure ladder query API | **Partial** | Facade exists | Heavy merge still in `SeedMap.lua` |
| `Planner/ClimbPlan.lua` shared climb + cult seed economy | **Implemented** | ClimbPlan loaded; UpgradeSeed alias | — |
| Delete & replace `SkillUp.lua` via GenusLadder + ClimbPlan | **Partial** | **SkillRates** + **ApoSkillPlan** extracted; SkillUp re-exports; SkillUp ~2512 lines (was ~3800) | Cult idle policy, watch gates/toggles, ephemeral Watch rows, shared reserves still in SkillUp. Not unloaded. |
| `TradeSkillCaps.FloorCultTier` / `FloorApoTier` canonical | **Implemented** | Caps owns floors | — |
| Harvest crit / BrewLearn skillUpOrigin invariants | **Implemented** | SeedMap + BrewLearn | — |

---

## 3. Store integrity & plan pipeline (Phase 2 / pillars 3.3, 3.5)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `RefinePipelineStore.ExpireStuck` | **Implemented** | Safe delete + shape normalize | — |
| `InventoryStore` static wipe + `ByRole` | **Implemented** | Present | — |
| Strict read-only `PlanSnapshot` | **Implemented** | Cheap/Garden/Reconcile **clone-then-`PS.Set`**; View chips do not mutate; public `PatchWatchRowsLiveCounts` only enqueues rebuild | `PatchPlanSnapshotLiveStatus` helper remains (unused when `syncSnapshot=false` on patch paths). Nested tip tables cloned for garden notes. |
| Drop FrameWork bag→plan prewarm; 50ms debounce | **Implemented** | Prewarm no-ops; `PLAN_DEBOUNCE_SEC = 0.05` | Stale Planner comment may mention warm-have |
| Strip Scheduler suppression flags | **Partial** | Prewarm gate gone | Storm/quiet/skip/suppress flags remain |
| Reserve time-slicing for catalog only | **Partial** | Bag→plan slicing gone | Catalog unused FW; generic FW remains |

---

## 4. Pure planning & decoupled execution (Phase 3 / pillar 3.2)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Plant candidate in `PlantPlan`; `plantIntent` | **Implemented** | Wired | — |
| Orchestrator single `TryExecutePlant` | **Implemented** | Shared helper | Grow queue probing remains |
| Grow lean executor (~500 lines) | **Partial** | ExecutePlant/Additive/Harvest exist | Still ~1.5k lines |
| Remove Planner shims from `RecipeSpec` | **Partial** | ClimbPlan/PlantPlan/Refine prefer `DemandPlan.Build`; RS shims remain for back-compat | `WatchHasSeedBufferShort` / `WatchStillNeedsGrow` / focus shims still on RS; some callers still use them |
| Decompose Planner; immutable intents | **Partial** | Sub-planners loaded; cheap/garden replace-not-mutate | Planner.lua still ~4.5k |

---

## 5. Event-driven UI & view thinness (Phase 4 / pillar 3.4)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Domain publishes EventBus; View owns refresh | **Implemented** | `FireFooterDirty` / `WATCH_UI_DIRTY` | — |
| Watch tab thin binder | **Partial** | Snapshot rows rendered | TabWatch still ~2.3k with status/chrome logic |

---

## 6. Unidirectional pipeline & coupling

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Unidirectional flow; View via events | **Partial** | EventBus domain→UI done | RecipeSpec↔Planner shims soft; SeedMap ladder ownership; Grow queue probing |
| Public APIs vs private-field probing | **Partial** | Refine dirty APIs | Grow plant-queue internals cross-module |

---

## 7. README clean-core table

| Claim | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| GenusLadder + ClimbPlan + PlantPlan + PlanSnapshot + debounce + EventBus | **Partial** (as a set) | PlanSnapshot immutability + EventBus closed; SkillUp partial | GenusLadder ownership; SkillUp remnant; lean modules |

---

## Prioritized gap summary

1. **SkillUp remnant (~2.5k)** — Rates + Apo brew extracted; remaining: Cult idle policy, gates/toggles, ephemeral Watch rows, shared reserves. Next: move Cult idle → ClimbPlan; Watch rows → Planner; then unload SkillUp.
2. **Grow / Planner / TabWatch size** — Still not lean (~1.5k / ~4.5k / ~2.3k).
3. **RecipeSpec shims** — Demand callers prefer DemandPlan; shims + buffer/focus helpers remain.
4. **Scheduler suppression web** — Debounce in place; flag sprawl unmet.
5. ~~**PlanSnapshot immutability**~~ — **Closed** for cheap/garden/reconcile + View (clone-then-Replace).
6. ~~**Domain → UI / Util**~~ — Closed earlier.

**Bottom line:** SkillRates + ApoSkillPlan extractions and PlanSnapshot replace-not-mutate are **in production (0.4.20)**. SkillUp is no longer a single monolith but **not deleted**; lean-module and Scheduler-flag targets remain.

# StockPiler4 Architecture Coverage

**Scope:** Intended architecture from design docs vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.22** (`StockPiler4.mod`)  
**Sources of intent:** `REFACTORING_RECOMMENDATIONS.md`, `IMPLEMENTATION_PLAN.md`, `FRAME_SLICING.md`, `ACCEPTANCE.md`, `CODE_QUALITY_REVIEW.md`, `README.md`  
**Not a target:** `FEATURE_COVERAGE.md`

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 20 |
| Partial | 6 |
| Missing | 0 |
| **Total architectural targets** | **26** |

---

## 1. Parallel safety & keep-list (Phase 0)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Distinct `StockPiler4` addon | **Implemented** | `.mod`, SV, `/sp4` | — |
| Keep Adapters unchanged | **Implemented** | Loaded in `.mod` | — |
| Keep MaterialExceptions / Classify / Items / Additives + XML | **Implemented** | Present | — |
| Centralize helpers in `Core/Util.lua` | **Implemented** | Thin Util delegates | — |

---

## 2. Knowledge & ladder consolidation (Phase 1 / pillar 3.1)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| `GenusLadder` pure ladder API | **Partial** | Facade exists | Heavy merge still in SeedMap |
| `ClimbPlan` shared climb economy | **Implemented** | Loaded; UpgradeSeed alias | — |
| Delete & replace `SkillUp.lua` | **Implemented** | Split into **SkillUpGates**, **CultSkillPlan**, **ApoSkillPlan**, **SkillRates**, **WatchReserves**, **SkillUpWatchStatus**; callers retargeted; `SkillUp.lua` removed from `.mod`; `DumpSkillPlan` on CultSkillPlan; Sync re-exports removed | — |
| Caps floors canonical | **Implemented** | TradeSkillCaps | — |
| Harvest crit / skillUpOrigin invariants | **Implemented** | SeedMap + BrewLearn | — |

---

## 3. Store integrity & plan pipeline (Phase 2)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| RefinePipeline ExpireStuck | **Implemented** | — | — |
| Inventory static wipe + ByRole | **Implemented** | — | — |
| Strict read-only PlanSnapshot | **Implemented** | Clone-then-Replace | — |
| FrameWork bag→plan gone; 50ms debounce | **Implemented** | — | — |
| Strip Scheduler suppression flags | **Partial** | `_pendingAfterSuppress` + `_skipThisFrame` tables; public Skip* APIs unchanged | Harvest storm / plant quiet remain (cult storm safety) |
| Catalog-only time-slicing | **Partial** | Bag→plan gone | Generic FW remains |

---

## 4. Pure planning & decoupled execution (Phase 3)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| PlantPlan + plantIntent | **Implemented** | — | — |
| Orch single TryExecutePlant | **Implemented** | — | — |
| Grow lean ~500 lines | **Partial** | Execute* APIs exist | Still ~1.5k |
| Remove RecipeSpec Planner shims | **Implemented** | Focus/`CollectAutoGrow*`/`WatchHasSeedBufferShort` shims removed; owners are Planner / DemandPlan | Residual RS planner fallbacks (BuildBalancedSpecDemand, WatchStillNeedsGrow, …) may remain |
| Decompose Planner | **Partial** | Sub-planners + Cult/Apo Skill plans | Planner.lua still large |

---

## 5. Event-driven UI & view thinness (Phase 4)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Domain EventBus → View | **Implemented** | — | — |
| Watch tab thin binder | **Partial** | Ephemeral rows in SkillUpWatchStatus; SkillUp gates via SkillUpGates | TabWatch still ~2.3k chrome |

---

## 6. Unidirectional / public APIs

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Unidirectional flow | **Partial** | EventBus + SkillUp unload | SeedMap ladder ownership; Grow queue probing |
| Public APIs vs private probing | **Partial** | Refine dirty APIs | Grow plant-queue internals |

---

## 7. README clean-core set

| Claim | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Clean-core table as a set | **Partial** | SkillUp unloaded; PlanSnapshot/EventBus closed | GenusLadder ownership; lean modules |

---

## Prioritized gap summary

1. ~~Retarget callers off `StockPiler4.SkillUp.*` / unload SkillUp File~~ — **Closed** (v0.4.22).
2. **Grow / Planner / TabWatch lean-up** — still oversized vs design.
3. ~~RecipeSpec focus shims~~ — **Closed** (owners Planner / DemandPlan).
4. **Scheduler storm/quiet** — skip/pending tables consolidated; storm/quiet remain intentional.
5. ~~SkillUp monolith body~~ — **Split + unloaded**.
6. ~~PlanSnapshot / EventBus / Util~~ — Closed earlier.

**Bottom line:** SkillUp File unloaded (v0.4.22); callers use owning modules; RS focus shims removed; Scheduler skip latches tabled. Grow/Planner/TabWatch lean and GenusLadder ownership still open.

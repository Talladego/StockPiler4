# StockPiler4 Architecture Coverage

**Scope:** Intended architecture from design docs vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.21** (`StockPiler4.mod`)  
**Sources of intent:** `REFACTORING_RECOMMENDATIONS.md`, `IMPLEMENTATION_PLAN.md`, `FRAME_SLICING.md`, `ACCEPTANCE.md`, `CODE_QUALITY_REVIEW.md`, `README.md`  
**Not a target:** `FEATURE_COVERAGE.md`

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 18 |
| Partial | 8 |
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
| Delete & replace `SkillUp.lua` | **Partial** | Split into **SkillUpGates**, **CultSkillPlan**, **ApoSkillPlan**, **SkillRates**, **WatchReserves**, **SkillUpWatchStatus**; SkillUp.lua is ~326-line Sync + DumpSkillPlan facade (still in `.mod`) | Not unloaded: thin facade required for `StockPiler4.SkillUp.*` call sites. Full File removal not safe until callers retarget namespaces. |
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
| Strip Scheduler suppression flags | **Partial** | `_pendingAfterSuppress` table consolidates 3 pending bools; storm/quiet/`_skip*ThisFrame` remain (by design for cult storms) | Full “15+ flag” strip unmet; skip/storm/quiet still present |
| Catalog-only time-slicing | **Partial** | Bag→plan gone | Generic FW remains |

---

## 4. Pure planning & decoupled execution (Phase 3)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| PlantPlan + plantIntent | **Implemented** | — | — |
| Orch single TryExecutePlant | **Implemented** | — | — |
| Grow lean ~500 lines | **Partial** | Execute* APIs exist | Still ~1.5k |
| Remove RecipeSpec Planner shims | **Partial** | `WatchHasSeedBufferShort` owned by **DemandPlan**; Brew/Planner/DemandPlan prefer Planner/DemandPlan; RS shims thin | Focus/CollectAutoGrow* shims still on RS; callers may still hit RS |
| Decompose Planner | **Partial** | Sub-planners + Cult/Apo Skill plans | Planner.lua still large |

---

## 5. Event-driven UI & view thinness (Phase 4)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Domain EventBus → View | **Implemented** | — | — |
| Watch tab thin binder | **Partial** | Ephemeral rows in SkillUpWatchStatus | TabWatch still ~2.3k chrome |

---

## 6. Unidirectional / public APIs

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Unidirectional flow | **Partial** | EventBus + SkillUp split | SeedMap ladder ownership; Grow queue probing |
| Public APIs vs private probing | **Partial** | Refine dirty APIs | Grow plant-queue internals |

---

## 7. README clean-core set

| Claim | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Clean-core table as a set | **Partial** | SkillUp split; PlanSnapshot/EventBus closed | GenusLadder ownership; lean modules |

---

## Prioritized gap summary

1. **Retarget callers off `StockPiler4.SkillUp.*`** then remove SkillUp.lua File entry (facade-only today).
2. **Grow / Planner / TabWatch lean-up** — still oversized vs design.
3. **RecipeSpec focus shims** — buffer short moved; CollectAutoGrowFocus / FocusSpecKeys shims remain.
4. **Scheduler skip/storm/quiet** — pending-suppress consolidated; storm/quiet/skip-this-frame remain intentional.
5. ~~SkillUp monolith body~~ — **Split** into modules; facade remains.
6. ~~PlanSnapshot / EventBus / Util~~ — Closed earlier.

**Bottom line:** SkillUp body is **decomposed** (v0.4.21); DemandPlan owns seed-buffer-short; Scheduler pending-suppress consolidated. Unload of SkillUp File + lean Grow/Planner/TabWatch + remaining RS focus shims still open.

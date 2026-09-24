# StockPiler4 Architecture Coverage

**Scope:** Intended architecture from design docs vs live addon at `Interface/AddOns/StockPiler4`  
**Reviewed:** 2026-09-24 · Live version **0.4.29** (`StockPiler4.mod`)  
**Sources of intent:** `REFACTORING_RECOMMENDATIONS.md`, `IMPLEMENTATION_PLAN.md`, `FRAME_SLICING.md`, `ACCEPTANCE.md`, `CODE_QUALITY_REVIEW.md`, `README.md`  
**Not a target:** `FEATURE_COVERAGE.md`

---

## Summary counts

| Status | Count |
| :--- | ---: |
| Implemented | 21 |
| Partial | 5 |
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
| `GenusLadder` pure ladder API | **Partial** | Facade + family wrappers; Climb/Cult prefer GL | `BuildAllFamilyLadders` / `BestOwnedSeedOnLadder` body still in SeedMap (GrowsTable/BagSample locals) |
| `ClimbPlan` shared climb economy | **Implemented** | Loaded; UpgradeSeed alias | — |
| Delete & replace `SkillUp.lua` | **Implemented** | Unloaded in 0.4.22 | — |
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
| Strip Scheduler suppression flags | **Partial** | `_pendingAfterSuppress` + `_skipThisFrame` | Storm/quiet remain (cult safety) |
| Catalog-only time-slicing | **Partial** | Plant list cached by knowledge gen; stock-only tab refresh; bag→plan gone | Generic FW remains |

---

## 4. Pure planning & decoupled execution (Phase 3)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| PlantPlan + plantIntent | **Implemented** | — | — |
| Orch single TryExecutePlant | **Implemented** | — | — |
| Grow lean ~500 lines | **Partial** | `GrowDump.lua` extracted; Execute* APIs | Core still ~1.4k (harvest/plant locals tightly coupled) |
| Remove RecipeSpec Planner shims | **Implemented** | Planner shims removed; `Watch.ShouldAutoGrowPotion`; demand/seed-lines via DemandPlan/Planner | — |
| Decompose Planner | **Partial** | Sub-planners + Skill plans | Planner.lua still ~4.6k (focus/status paint) |

---

## 5. Event-driven UI & view thinness (Phase 4)

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Domain EventBus → View | **Implemented** | — | — |
| Watch tab thin binder | **Partial** | `StockPiler4TabWatchTips.lua` (~750 tip builders); binder ~1.5k | Row paint / chrome still large |

---

## 6. Unidirectional / public APIs

| Target | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Unidirectional flow | **Partial** | EventBus + SkillUp unload + RS shim removal | SeedMap still owns ladder build |
| Public APIs vs private probing | **Partial** | Refine dirty APIs | Grow plant-queue internals |

---

## 7. README clean-core set

| Claim | Status | Evidence | Gaps / mismatches |
| :--- | :--- | :--- | :--- |
| Clean-core table as a set | **Partial** | SkillUp unloaded; RS planner shims gone; tips/dump extracts | SeedMap ladder build; Planner/Grow size |

---

## Prioritized gap summary

1. ~~SkillUp unload~~ — Closed 0.4.22.
2. ~~RecipeSpec planner/focus shims~~ — Closed 0.4.23 (`Watch.ShouldAutoGrowPotion`; DemandPlan/Planner owners).
3. **Grow / Planner lean** — Dump/tips extracted; core bodies still over design size (deferred: high local coupling).
4. **GenusLadder ownership** — Call sites prefer GL; BuildAllFamilyLadders stays in SeedMap until BagSample/GrowsTable can move without behavior risk.
5. **Scheduler storm/quiet** — Intentional; skip/pending tables consolidated.

**Bottom line:** Live **0.4.23** is coherent for `/reload` soak. Remaining gaps are size/ownership of SeedMap ladder build and Grow/Planner cores — deferred with rationale above.

# StockPiler4 Acceptance Checklist

Verify against the reference docs in this folder:

- [CODE_QUALITY_REVIEW.md](CODE_QUALITY_REVIEW.md)
- [REFACTORING_RECOMMENDATIONS.md](REFACTORING_RECOMMENDATIONS.md)
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- [FRAME_SLICING.md](FRAME_SLICING.md)

Static gap-fix verify: `tools/_verify_sp4_gap_fixes.py` (must pass).

## 5.1 Gameplay

| Test | How | Pass criteria |
| :--- | :--- | :--- |
| Hitch | `/reloadui` then `/libperf StockPiler4 on 250` during 4-plot harvest+plant | No **attributed** StockPiler4 trails ≥250ms (ignore empty-trail / client floor ~140ms) |
| Climb | Multi-family short mats; plant watches + Upgrade Seeds | L1 buy, highest plantable rung, refine without starving sibling genus; Cult-max **seed buffer** full ends plant-watch climb |
| SkillUp | Cult/Apo from low skill | Tier ladder advances; Apo only HIGH stability; no `skillUpOrigin` in `Account.recipes` |
| Parallel | Enable StockPiler3 + StockPiler4 same session | `/sp3` and `/sp4` separate windows, macros (`StockPiler3 …` vs `StockPiler4 …`), SavedVariables |

Carry forward SP3 0.3.214–0.3.220 product rules: ephemeral Upgrade rows, plant watch stock UI vs climb status, Cult-max buffer arrival, orphan L50 plant ≠ done, tooltip padding.

## 5.2 Architecture (static — gap fixes)

Against **CODE_QUALITY_REVIEW.md**:

- [x] Unidirectional pipeline: domain publishes EventBus / Scheduler; View owns window calls
- [x] Climb engine is `ClimbPlan` (not UpgradeSeed monolith in `.mod`); GenusLadder for ladder queries
- [x] `Grow.ExecutePlant` + `PlantPlan.PickPlantJob`; Orchestrator `TryExecutePlant` uses **snapshot plantIntent only**
- [x] RefinePipeline `ExpireStuck` deletes after `pairs`; Inventory wipe + `ByRole` index
- [x] No View `PatchWatchRowsLiveCounts`; `Refine.IsDirty` / `ClearDirty` public API
- [x] Plan rebuild builds demand once; CollectIntents / PlantPlan reuse snapshot demand

Against **REFACTORING_RECOMMENDATIONS.md**:

- [x] Keep-list: Adapters, MaterialExceptions, Classify, Items, Additives, XML (renamed)
- [x] Five pillars: GenusLadder+ClimbPlan, Planner intents (`DemandPlan`/`BrewPlan`/`BuyPlan`/`PlantPlan`), immutable PlanSnapshot, event UI, no FrameWork core
- [x] SkillUp cult deficit math delegates to ClimbPlan (`ClimbEconomy`)

Against **FRAME_SLICING.md**:

- [x] `FrameWork.IsPrewarmBusy` not used to gate Watch flush
- [x] Scheduler: plan/bag wait on **50ms debounce only**; SkipPlan/SkipUi/storm arm debounce (not multi-second plan holds)

Against **IMPLEMENTATION_PLAN.md**:

- [x] Parallel-safe `StockPiler4` SavedVariables / `/sp4` / window names
- [x] Phase 0–4 exits + gap-fix pass on static checks

## 5.3 Slash smoke (in-game)

```
/reloadui
/sp4
/libperf StockPiler4 on 250
# 4-plot harvest + plant storm
/libperf StockPiler4 summary
/sp3
```

Confirm SP3 still responds to `/sp3` with no shared SavedVariable writes.

**Note:** A thr=100 capture at 23:35 showed Orch.Tick + `BuildBalancedSpecDemand` / `PickPlantCandidate` / `CollectIntents` up to ~778ms and Macro.Appearance ~2.3s cold. Gap fixes now reuse snapshot demand on tick; re-run at thr 250 after `/reloadui`.

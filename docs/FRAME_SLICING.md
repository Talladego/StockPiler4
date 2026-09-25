# Frame slicing policy (StockPiler4)

## Goal

Cut plant / additive / harvest FPS spikes without AutoGrow↔Watch desync.
Quiet/coalesce alone (0.4.31) was not enough; controlled FrameWork prewarm
(0.4.32) still left cult-frame Footer/RefreshWatch and post-quiet
PlanRebuild+WarmHave.miss. **0.4.33** hardens cult quiet + pump order +
cheap rebuild so plant/additive frames stay light. **0.4.34** splits
settle/first-paint UI (Watch → Footer → Macro) and moves plant intent-refresh
off the Orch execute frame under one-heavy after quiet.

## Architecture

```
UPDATE_PROCESSED
  → bag flush (coalesced; deferred in plant quiet / harvest storm)
  → FrameWork.Pump  (≤1 prewarm step / frame)
  → PlanRebuild     (held while IsPrewarmBusy / quiet / storm)
  → IntentRefresh   (EnqueuePlantIntentRefresh; one-heavy after quiet)
  → Orchestrator.Tick  (plant/additive; nested CultivationUpdated arms quiet)
  → Watch UI flush  (held while IsPrewarmBusy / quiet / storm / orch just ran)
  → Footer coalesce (held while SkipUiHoldFooter / quiet / storm / Watch stagger)
  → Macro.Appearance drain (held while quiet / settle / Footer stagger)
```

### Prewarm jobs (FrameWork)

| Job id | Resume / step | Purpose |
| :--- | :--- | :--- |
| `prewarm-warm-have` | collect → bag (2+ frames) | WarmHave slice; **restart** if snapGen moves mid-slice |
| `prewarm-demand` | StartOnce | `BuildBalancedSpecDemand({ cacheOnly })` |
| `prewarm-seed-lines` | StartOnce | `CollectAutoGrowSeedLines` cache |

- **Budget:** `DEFAULT_FRAME_BUDGET = 1` — at most one job step per Pump.
- **Resume token:** `gen = snapGen:reason`. Same id+gen no-ops (no mid-flight mutation).
- **Ownership:** only `Scheduler.RequestCachePrewarm` enqueues; `FrameWork.Pump` drains.
- **Never slice** engine craft APIs (`PlantSeed` / `BuyItem` / `PerformCrafting`).

### Quiet / storm gates (0.4.33)

| Gate | Effect |
| :--- | :--- |
| **Every** `CultivationUpdated` | `ArmPlantQuiet` + `SkipPlan` + `SkipUi` (not only cultBusy) |
| Cult handler | Never `FireFooterDirty` on the cult stack |
| Harvest-ready / op-lock | Coalesce Footer only — **no** `immediate` SyncActionReadiness |
| `OnFooterDirty` immediate | Ignored while quiet / storm / SkipUiHoldFooter |
| Quiet / storm | Skip Pump; defer bag flush; hold PlanRebuild + Watch; latch `_pendingPrewarmAfterQuiet` |
| Quiet / storm end | `FlushPendingPrewarmAfterQuiet` → invalidate have-cache → `RequestCachePrewarm` |
| Orch before Watch | Plant/additive nested cult sets SkipUi **before** RefreshWatch |
| Orch ran this frame | Skip Watch Flatten (one heavy) |
| `IsPrewarmBusy` | Hold PlanRebuild + Watch until collect/bag/demand/seeds finish |

### Settle / first-paint stagger (0.4.34)

| Frame | Work |
| :--- | :--- |
| N | `RefreshWatch` only (`NoteUiHeavy("watch")` → defer Footer +1, Macro +2) |
| N+1 | Footer chrome **without** Macro (`RequestEnabledSync` only) |
| N+2+ | `Macro.DrainEnabledSync` → `Macro.Appearance` on idle |

- Footer never inlines `RefreshMacroButtonAppearance` (settle/quiet/first open).
- Bridge order: Scheduler → Footer flush → Macro drain (so Footer request cannot Appearance same frame).
- `OnShow`: mark Watch dirty + request Footer; no sync RefreshActiveTab / immediate Macro.

### Intent refresh (0.4.34)

| Rule | Detail |
| :--- | :--- |
| Never on execute frame | Orch / snap / settle / GetOrBuild cache-hit **enqueue** via `Sch.EnqueuePlantIntentRefresh` |
| Drain | After quiet, under one-heavy **before** Orch (blocks plant/additive same frame) |
| Perf marks | `IntentRefresh` / `IntentRefresh.PickPlant` / `IntentRefresh.Collect` / `IntentRefresh.Now` |

### Plan rebuild after quiet

| Path | Policy |
| :--- | :--- |
| CheapRebuild | `allowWarmHave = false` (no sync `WarmHave.miss`) |
| RefreshPlantRefineIntents | Skip `PickPlantCandidate` when plots full + seeded intent; skip `CollectIntents` unless buffer pending / refine dirty |
| BuildFull | Same plant/refine skips; WarmHave only if prewarm miss and not quiet |
| BufferFlags | Sticky across invalidate; peek uses sticky under quiet |

## Safety rules (deterministic, clear ownership)

1. **No mid-plan mutation.** Prewarm jobs never write `PlanSnapshot`. Publish only in `Planner.GetOrBuild` after prewarm completes (or warm-hold timeout).
2. **Stable resume tokens.** Replacing a job requires a new `snapGen:reason`. Snap mid-slice → restart collect (same job), not partial publish.
3. **Hold Watch while busy / orch / quiet.** Never Flatten/RefreshWatch on the same frame as WarmHave bag walk, PlanRebuild, or PlantSeed/AddAdditive.
4. **Defer under CultivationUpdated.** Always quiet; never Footer/WarmHave bag work on the cult stack.
5. **AutoGrow ownership unchanged.** Orch still plants/additives from `PlanSnapshot` / garden state. Quiet holds UI+plan only; `SetAutoGrowIdle(false)` keeps the 1s additive tick.
6. **Warm-hold cap.** `PLAN_WARM_HOLD_MAX_SEC` (5s) then cold PlanRebuild so Watch cannot stall forever.
7. **One heavy per frame.** Bag flush OR Pump OR PlanRebuild OR IntentRefresh OR Orch OR Watch — never stack Watch with orch; never IntentRefresh with ExecutePlant/TryAdditive.
8. **UI stagger.** RefreshWatch, Footer, and Macro.Appearance never share one frame at settle / first Watch open.

## Libperf expectations

### Before (0.4.32 soak)

| Spike | Trail |
| :--- | :--- |
| ~10353ms | `Footer x2, Macro.Appearance x2, RefreshWatch x2, CultivationUpdated x4` |
| ~349ms | `Footer, FrameWork.Pump x4, WarmHave.miss, PlanRebuild, Planner.Build, Build.WarmHave, … Status.Craftable x5, Refine.BufferFlags, PickPlantCandidate` |
| ~250ms | `PlanRebuild, CheapRebuild, WarmHave.miss, BufferFlags, PickPlantCandidate` |

### After (0.4.33 target)

| Former hotspot | Mitigation |
| :--- | :--- |
| Footer/Macro/RefreshWatch on cult x4 | Always quiet + no immediate Footer + Orch-before-Watch |
| PlanRebuild + sync WarmHave.miss | Prewarm restart on snap move; CheapRebuild never sync-warms |
| BufferFlags + PickPlantCandidate on cheap | Skip unless empty plots / buffer pending |
| Pump then cold Build | Hold PlanRebuild while `IsPrewarmBusy`; quiet 2.5s |

### After (0.4.34 target)

| Former hotspot | Mitigation |
| :--- | :--- |
| ~1363ms settle Footer+Macro+RefreshWatch | Watch → Footer (no Macro) → Macro idle drain |
| ~450–520ms lone Orchestrator.Tick | Intent refresh enqueued; Perf `IntentRefresh*` children |

## 0.4.36 — Spike phase tags (instrumentation only)

Hitch lines (≥250ms) and `/sp4 perf` summary include
`phase=login|harvestStorm|plantQuiet|quietEnd|executePlant|dumpall|unknown`
plus `emptyPlots=N additive=N`. Phase is set/cleared at existing arm/disarm
points only — no quiet/warm-hold or Watch→Footer→Macro / IntentRefresh changes.
`Grow.ExecutePlant` emits an always-on uilog breadcrumb.

## Retest notes

1. `/reload` → **v0.4.36**. `/libperf StockPiler4 on 250`.
2. Login/settle and first `/sp4` Watch open: expect RefreshWatch, Footer, Macro.Appearance on **separate** frames; spikes show `phase=login` while settling.
3. AutoGrow plant → soil/water/nutrient → additive cycle with window open on Watch; expect `grow| ExecutePlant` breadcrumbs and spikes tagged `executePlant` / `plantQuiet` / `harvestStorm` / `quietEnd`.
4. Expect: cult frames without `RefreshWatch`/`Macro.Appearance`; Orch execute frames without `IntentRefresh*`; post-quiet intent drain as named child or Orch.Tick under thr.
5. `/libperf StockPiler4 summary` and `/sp4 perf` — confirm phase + emptyPlots/additive on spike lines (including `trail=(none)` when a phase is active).
6. Watch craftable / plantIntent catch up within ~5s after quiet (warm-hold); planting resumes on the tick after intent drain.

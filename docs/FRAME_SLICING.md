# Frame slicing policy (StockPiler4)

## Goal

Cut plant / additive / harvest FPS spikes without AutoGrow↔Watch desync.
Quiet/coalesce alone (0.4.31) was not enough; libperf still showed
`PlanRebuild`+`Build.WarmHave`, `Refine.BufferFlags`+`Grow.TryAdditive`, and
`Footer`/`RefreshWatch` trails. StockPiler3 largely eliminated these with
**controlled FrameWork prewarm**. 0.4.32 restores that pattern under strict
safety rules.

## Architecture

```
UPDATE_PROCESSED
  → bag flush (coalesced; deferred in plant quiet / harvest storm)
  → FrameWork.Pump  (≤1 prewarm step / frame)
  → PlanRebuild     (held while IsPrewarmBusy)
  → Watch UI flush  (held while IsPrewarmBusy / quiet / storm)
  → Orchestrator.Tick (not on the same frame as heavy work)
```

### Prewarm jobs (FrameWork)

| Job id | Resume / step | Purpose |
| :--- | :--- | :--- |
| `prewarm-warm-have` | collect → bag (2 frames) | WarmHave slice: CountByUid then bag walk |
| `prewarm-demand` | StartOnce | `BuildBalancedSpecDemand({ cacheOnly })` |
| `prewarm-seed-lines` | StartOnce | `CollectAutoGrowSeedLines` cache |

- **Budget:** `DEFAULT_FRAME_BUDGET = 1` — at most one job step per Pump.
- **Resume token:** `gen = snapGen:reason`. Same id+gen no-ops (no mid-flight mutation).
- **Ownership:** only `Scheduler.RequestCachePrewarm` enqueues; `FrameWork.Pump` drains.
- **Never slice** engine craft APIs (`PlantSeed` / `BuyItem` / `PerformCrafting`).

### Quiet / storm gates

| Gate | Effect |
| :--- | :--- |
| `IsPlantQuiet` / `IsHarvestStorm` | Skip Pump; defer bag flush; hold PlanRebuild + Watch; latch `_pendingPrewarmAfterQuiet` |
| Quiet / storm end | `FlushPendingPrewarmAfterQuiet` → invalidate have-cache after quiet → `RequestCachePrewarm` |
| `SkipPlanThisFrame` | Hold PlanRebuild + Pump this frame |
| `IsPrewarmBusy` | Hold PlanRebuild + Watch until collect/bag/demand/seeds finish |

### BufferFlags during quiet

`InvalidateBufferFlags` keeps a **sticky** last-good table. While quiet/storm,
`EnsureBufferFlagsCached` reuses live or sticky flags instead of rebuilding
(avoids `CollectAutoGrowSeedLines` under CultivationUpdated / additive).

## Safety rules (deterministic, clear ownership)

1. **No mid-plan mutation.** Prewarm jobs never write `PlanSnapshot`. Publish only in `Planner.GetOrBuild` after prewarm completes (or warm-hold timeout).
2. **Stable resume tokens.** Replacing a job requires a new `snapGen:reason`. In-flight slice with matching gen is left alone.
3. **Hold Watch while busy.** Never Flatten/RefreshWatch on the same frame as WarmHave bag walk or PlanRebuild.
4. **Defer under CultivationUpdated.** Plant quiet and harvest storm never run WarmHave/Demand bag work; prewarm is queued for quiet-end.
5. **AutoGrow ownership unchanged.** Orch still plants/additives from `PlanSnapshot` / garden state. Quiet holds UI+plan only; `SetAutoGrowIdle(false)` keeps the 1s additive tick. Do not `InvalidatePlantQueue` from snap or storm-end.
6. **Warm-hold cap.** If Have cache stays cold, `PLAN_WARM_HOLD_MAX_SEC` (3s) allows a cold PlanRebuild so Watch cannot stall forever.
7. **One heavy per frame.** Bag flush OR Pump OR PlanRebuild OR Orch — never stack.

## What we still do *not* slice

- Catalog browse / Plants list build (separate cache; rarity resolve is O(1) sample).
- Engine craft / plant / harvest APIs.
- Orch intent issue (`IssueOne`) — quiet + BufferFlags sticky instead.

## Libperf expectations (0.4.32)

| Former spike | Mitigation |
| :--- | :--- |
| `PlanRebuild` + `Build.WarmHave` / `WarmHave.miss` | WarmHave sliced across Pump frames; PlanRebuild held until warm |
| `Refine.BufferFlags` + `Grow.TryAdditive` | SeedLines prewarm + sticky BufferFlags under quiet |
| `Footer` / `RefreshWatch` under CultivationUpdated | Quiet holds Watch; SkipUi after PlanRebuild |
| Sync `Build.Demand` on PlanRebuild | Demand prewarm (`cacheOnly`) before rebuild |

## Retest notes

1. Enable libperf (`/sp4 perf` or prior soak path). Plant → soil/water/nutrient → harvest cycle with AutoGrow on.
2. Expect FrameWork.Pump marks across quiet-end frames; PlanRebuild should not share a frame with WarmHave bag.
3. Spikes over ~250ms on `BufferFlags`+`TryAdditive` / `Build.WarmHave` should drop vs 0.4.31 soak.
4. Watch craftable / plantIntent must catch up within ~3s after quiet (warm-hold), not freeze indefinitely.
5. Plants tab: names show tier colors (green/blue/purple/orange) again — not uniform light grey.

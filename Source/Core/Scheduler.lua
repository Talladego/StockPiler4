----------------------------------------------------------------
-- StockPiler4 Core/Scheduler -- coalesce heavy work, frame budgets
-- UPDATE_PROCESSED pump: bag flush -> FrameWork.Pump -> PlanRebuild
-- -> Watch UI (one heavy). Orch tick on interval.
-- Controlled prewarm (WarmHave/Demand/SeedLines) with snapGen tokens;
-- hold PlanRebuild/Watch while IsPrewarmBusy (no AutoGrow/Watch desync).
-- Wake vs snap: only wake forces plant-queue invalidate.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Scheduler = StockPiler4.Scheduler or {}

local Sch = StockPiler4.Scheduler

Sch.BAG_COALESCE_SEC = 2.0
Sch.PLAN_MAX_WAIT_SEC = 0.5
Sch.PLAN_COALESCE_WHEN_AWAKE_SEC = 3.0
Sch.PLAN_MIN_GAP_SEC = 2.0
Sch.PLAN_WARM_HOLD_MAX_SEC = 5.0
Sch.SESSION_SETTLE_SEC = 2.5
Sch.AUTO_TICK_SEC = 1.0
Sch.AUTO_TICK_IDLE_SEC = 5.0
Sch.HARVEST_STORM_MIN_SEC = 1.5
-- Cover plant/refine inventory + CultivationUpdated lag (soil/water/nutrient x4).
Sch.PLANT_QUIET_BASE_SEC = 2.5
Sch.PLAN_DEBOUNCE_SEC = 0.05

Sch._bagDue = false
Sch._planDebounceUntil = 0
Sch._bagAt = 0
Sch._bagNeedQueue = false
Sch._planDue = false
Sch._planAt = 0
Sch._lastPlanBuiltAt = 0
Sch._planWarmHoldAt = 0
Sch._autoAccum = 0
Sch._autoGrowFast = true
Sch._suppressInvTicks = 0
Sch._pendingAfterSuppress = { bagFlush = false, bagQueue = false, plan = false }
Sch._pendingPrewarmAfterQuiet = false
Sch._pendingPrewarmReason = nil
Sch._initialized = false
Sch._harvestStormUntil = 0
Sch._plantQuietUntil = 0
-- One-frame skip latch (plan / ui / orch). Cult storm + plant quiet stay separate.
Sch._skipThisFrame = { plan = false, ui = false, uiHoldFooter = false, orch = false }
Sch._busTokens = nil

local function Now()
    if type(GetGameTime) == "function" then
        return tonumber(GetGameTime()) or 0
    end
    return 0
end

local function TrackBus(token)
    if token == nil then
        return
    end
    Sch._busTokens = Sch._busTokens or {}
    Sch._busTokens[#Sch._busTokens + 1] = token
end

local function InvalidatePlantQueue(reason)
    local Grow = StockPiler4.Grow
    if not Grow then
        return
    end
    if Grow.InvalidatePlantQueue then
        Grow.InvalidatePlantQueue(reason)
    elseif Grow.MarkPlantJobDirty then
        Grow.MarkPlantJobDirty(reason)
    end
end

local function ArmPipelineDebounce()
    local debounce = tonumber(Sch.PLAN_DEBOUNCE_SEC) or 0.05
    Sch._planDebounceUntil = Now() + debounce
end

local function PipelineDebounceActive()
    local untilT = tonumber(Sch._planDebounceUntil) or 0
    if untilT <= 0 then
        return false
    end
    local now = Now()
    if now <= 0 then
        return false
    end
    return now < untilT
end

--- Enqueue FrameWork prewarm jobs (WarmHave collect/bag, Demand, SeedLines).
--- Deferred during plant quiet / harvest storm — never bag-walk under CultivationUpdated.
local function RequestCachePrewarm(reason)
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        Sch._pendingPrewarmAfterQuiet = true
        Sch._pendingPrewarmReason = reason
        return
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        Sch._pendingPrewarmAfterQuiet = true
        Sch._pendingPrewarmReason = reason
        return
    end
    local FW = StockPiler4.FrameWork
    if not FW or not FW.StartOnce then
        return
    end
    local snapGen = 0
    if StockPiler4.Inventory and StockPiler4.Inventory.GetSnapGen then
        snapGen = tonumber(StockPiler4.Inventory.GetSnapGen()) or 0
    end
    local genKey = tostring(snapGen) .. ":" .. tostring(reason or "")
    if FW.EnqueueWarmHave then
        FW.EnqueueWarmHave(genKey)
    end
    if FW.EnqueueDemand then
        FW.EnqueueDemand(genKey)
    end
    if FW.EnqueueSeedLines then
        FW.EnqueueSeedLines(genKey)
    end
end

local function FlushPendingPrewarmAfterQuiet()
    if Sch._pendingPrewarmAfterQuiet ~= true then
        return
    end
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        return
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        return
    end
    Sch._pendingPrewarmAfterQuiet = false
    local reason = Sch._pendingPrewarmReason or "quiet-end"
    Sch._pendingPrewarmReason = nil
    local Planner = StockPiler4.Planner
    if Planner and Planner.InvalidateHaveCacheAfterQuiet then
        Planner.InvalidateHaveCacheAfterQuiet()
    end
    RequestCachePrewarm(reason)
end

local function DecaySuppressInventorySideEffects()
    local n = tonumber(Sch._suppressInvTicks) or 0
    if n <= 0 then
        return
    end
    Sch._suppressInvTicks = n - 1
    if Sch._suppressInvTicks > 0 then
        return
    end
    Sch._suppressInvTicks = 0
    if StockPiler4.Inventory and StockPiler4.Inventory.FlushPendingSnapGen then
        StockPiler4.Inventory.FlushPendingSnapGen()
    end
    local pending = Sch._pendingAfterSuppress
    if type(pending) ~= "table" then
        pending = { bagFlush = false, bagQueue = false, plan = false }
        Sch._pendingAfterSuppress = pending
    end
    local needBag = pending.bagFlush == true
    local needQueue = pending.bagQueue == true
    local needPlan = pending.plan == true
    pending.bagFlush = false
    pending.bagQueue = false
    pending.plan = false
    if needBag then
        Sch.EnqueueBagFlush(needQueue)
    elseif needQueue then
        Sch._bagNeedQueue = true
    end
    if needPlan then
        Sch.EnqueuePlanRebuild()
    end
end

local function FlushBagIfDue()
    if Sch._bagDue ~= true then
        return false
    end
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        Sch._bagAt = Now() + Sch.BAG_COALESCE_SEC
        return false
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        Sch._bagAt = Now() + Sch.BAG_COALESCE_SEC
        return false
    end
    if Now() < (tonumber(Sch._bagAt) or 0) then
        return false
    end
    if PipelineDebounceActive() then
        return false
    end
    Sch._bagDue = false
    local needQueue = Sch._bagNeedQueue == true
    Sch._bagNeedQueue = false
    local Inv = StockPiler4.Inventory
    if Inv and Inv.Flush then
        if StockPiler4.Perf and StockPiler4.Perf.Begin then
            StockPiler4.Perf.Begin("BagFlush")
        end
        Inv.Flush({ forceEngine = false })
        if StockPiler4.Perf and StockPiler4.Perf.End then
            StockPiler4.Perf.End("BagFlush")
        end
    end
    if needQueue then
        Sch.EnqueuePlanRebuild()
    end
    RequestCachePrewarm("bag-flush")
    return true
end

local function RebuildPlanIfDue()
    if Sch._planDue ~= true then
        return false
    end
    if Sch.SkipPlanThisFrameActive and Sch.SkipPlanThisFrameActive() == true then
        return false
    end
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        return false
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        return false
    end
    local Orch = StockPiler4.Orchestrator
    if Orch and Orch.IsBrewSessionActive and Orch.IsBrewSessionActive() == true then
        return false
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() == true then
        return false
    end
    if Now() < (tonumber(Sch._planAt) or 0) then
        return false
    end
    if PipelineDebounceActive() then
        return false
    end
    local Planner = StockPiler4.Planner
    local FW = StockPiler4.FrameWork
    -- Hold full rebuild while FrameWork prewarm is mid-flight (collect/bag/demand/seeds).
    if FW and FW.IsPrewarmBusy and FW.IsPrewarmBusy() == true then
        return false
    end
    if FW and FW.Busy and FW.Busy() == true then
        return false
    end
    -- Hold full rebuild until WarmHave prewarm finishes (never publish partial plan).
    if Planner and Planner.CanCheapOrGardenPatch and Planner.CanCheapOrGardenPatch() ~= true then
        local warm = Planner.IsHaveCacheWarmForSnap and Planner.IsHaveCacheWarmForSnap() == true
        if not warm then
            RequestCachePrewarm("plan-hold-warm")
            if FW and FW.IsPrewarmBusy and FW.IsPrewarmBusy() == true then
                return false
            end
            local holdMax = tonumber(Sch.PLAN_WARM_HOLD_MAX_SEC) or 3.0
            local holdStart = tonumber(Sch._planWarmHoldAt) or 0
            if holdStart <= 0 then
                Sch._planWarmHoldAt = Now()
                holdStart = Sch._planWarmHoldAt
            end
            if (Now() - holdStart) < holdMax then
                return false
            end
        end
    end
    Sch._planWarmHoldAt = 0
    Sch._planDue = false
    Sch._planAt = 0
    Sch._lastPlanBuiltAt = Now()
    if Planner and Planner.GetOrBuild then
        if StockPiler4.Perf and StockPiler4.Perf.Begin then
            StockPiler4.Perf.Begin("PlanRebuild")
        end
        Planner.GetOrBuild(true)
        if StockPiler4.Perf and StockPiler4.Perf.End then
            StockPiler4.Perf.End("PlanRebuild")
        end
        -- Never paint Watch on the same frame as a full Build (WarmHave hitch).
        Sch.SkipUiThisFrame()
        Sch.MarkWatchUiDirty()
        return true
    end
    return false
end

local function FlushWatchUiIfDue(didHeavy)
    if didHeavy == true then
        return false
    end
    if Sch.SkipUiThisFrameActive and Sch.SkipUiThisFrameActive() == true then
        return false
    end
    if Sch.IsSessionSettling and Sch.IsSessionSettling() == true then
        return false
    end
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        return false
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        return false
    end
    local FW = StockPiler4.FrameWork
    if FW and FW.IsPrewarmBusy and FW.IsPrewarmBusy() == true then
        return false
    end
    if FW and FW.Busy and FW.Busy() == true then
        return false
    end
    local Ui = StockPiler4.Ui
    if Ui and Ui.FlushWatchUiIfDirty then
        return Ui.FlushWatchUiIfDirty() == true
    end
    return false
end

local function AutoTickIntervalSec()
    if StockPiler4.Buy and StockPiler4.Buy.NeedsTick and StockPiler4.Buy.NeedsTick() == true then
        return Sch.AUTO_TICK_SEC
    end
    local Watch = StockPiler4.Watch
    if Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true then
        local Orch = StockPiler4.Orchestrator
        if Orch and Orch.IsFillBlocked and Orch.IsFillBlocked() == true then
            return Sch.AUTO_TICK_IDLE_SEC
        end
        if Sch._autoGrowFast == true then
            return Sch.AUTO_TICK_SEC
        end
        return Sch.AUTO_TICK_IDLE_SEC
    end
    return Sch.AUTO_TICK_SEC
end

local function ShouldWakeAutoGrowUrgent()
    local Watch = StockPiler4.Watch
    if not Watch or not Watch.IsAutoGrowEnabled or Watch.IsAutoGrowEnabled() ~= true then
        return false
    end
    local Grow = StockPiler4.Grow
    if Grow and Grow.NeedsCurrentStageAdditive and Grow.NeedsCurrentStageAdditive() then
        return true
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() then
        return true
    end
    local Refine = StockPiler4.Refine
    if Refine and Refine.IsDirty and Refine.IsDirty() == true then
        return true
    end
    if Refine and Refine.PeekCachedBufferPending and Refine.PeekCachedBufferPending() == true then
        return true
    end
    return false
end

local function OnInventorySnapshot()
    -- Snap path: avoid full WakeAutoGrow (snap-wake storm risk), but clear a
    -- soft fill-block when empty plots are waiting for bag seeds after refine.
    if StockPiler4.Buy and StockPiler4.Buy.OnInventorySnapshot then
        StockPiler4.Buy.OnInventorySnapshot()
    end
    local Refine = StockPiler4.Refine
    -- Peek cached pending before invalidate so wake does not rebuild BufferFlags.
    local pendingBuffer = Refine and Refine.PeekCachedBufferPending
        and Refine.PeekCachedBufferPending() == true
    local plantQuiet = Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true
    local storm = Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true
    local Orch = StockPiler4.Orchestrator
    local brewSession = Orch and Orch.IsBrewSessionActive and Orch.IsBrewSessionActive() == true
    if not plantQuiet and not storm and not brewSession then
        local Watch = StockPiler4.Watch
        local autoGrowOn = Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true
        local Grow = StockPiler4.Grow
        local hasPlantWork = false
        if autoGrowOn and Grow then
            if Grow.HasEmptyPlot and Grow.HasEmptyPlot() == true then
                hasPlantWork = true
            elseif Grow.NeedsCurrentStageAdditive and Grow.NeedsCurrentStageAdditive() == true then
                hasPlantWork = true
            elseif pendingBuffer then
                hasPlantWork = true
            end
        end
        -- Soft dirty only; do not force plant-queue invalidate on snap.
        if hasPlantWork and Grow and Grow.MarkPlantJobDirty then
            Grow.MarkPlantJobDirty("snap")
        end
        if hasPlantWork and Orch and Orch.IsFillBlocked and Orch.IsFillBlocked() == true
            and Orch.ClearFillBlocked
        then
            Orch.ClearFillBlocked()
        end
        if hasPlantWork or ShouldWakeAutoGrowUrgent() then
            Sch._autoGrowFast = true
        end
        -- Orch plants from PlanSnapshot.plantIntent only. Snap used to dirty the
        -- Grow probe cache without refreshing the snapshot, so empty plots sat
        -- idle until /sp4 dumpall force-Built a new plantIntent.
        if hasPlantWork then
            local Planner = StockPiler4.Planner
            if Planner and Planner.NeedsPlantIntentRefresh
                and Planner.NeedsPlantIntentRefresh() == true
            then
                if Planner.RefreshPlantRefineIntentsNow then
                    Planner.RefreshPlantRefineIntentsNow()
                elseif Sch.EnqueuePlanRebuild then
                    Sch.EnqueuePlanRebuild({ nudge = true })
                end
            end
        end
        -- BufferFlags only when not quiet/storm — snap invalidates during
        -- plant/refine forced BufferFlags rebuild every orch tick (libperf).
        if Refine and Refine.InvalidateBufferFlags then
            Refine.InvalidateBufferFlags()
        end
    end
    Sch.MarkWatchUiDirty()
end

local function OnGardenDirty(payload)
    -- Soft (stage-only) pulses: refresh Watch UI, do not wake AutoGrow / plan rebuild.
    if type(payload) == "table" and payload.soft == true then
        Sch.MarkWatchUiDirty()
        return
    end
    -- Harvest storm / plant quiet / refine outstanding: never WakeAutoGrow /
    -- EnqueuePlanRebuild from garden dirty (SP2 Flatten on plant/refine).
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        Sch.MarkWatchUiDirty()
        return
    end
    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        Sch.MarkWatchUiDirty()
        return
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() == true then
        Sch.MarkWatchUiDirty()
        return
    end
    if Sch.IsSessionSettling and Sch.IsSessionSettling() == true then
        Sch.MarkWatchUiDirty()
        return
    end
    if Sch.ShouldWakeAutoGrow and Sch.ShouldWakeAutoGrow() == true then
        if Sch._planDue == true then
            Sch._autoGrowFast = true
            return
        end
        Sch.WakeAutoGrow()
        -- Only rebuild when plot contents changed for planning (seed plant/harvest).
        -- Empty-plot wake alone looped full Builds every PLAN_MIN_GAP with Upgrade on.
        if type(payload) == "table" and payload.planChanged == true then
            Sch.EnqueuePlanRebuild()
        else
            Sch.MarkWatchUiDirty()
        end
    else
        Sch.MarkWatchUiDirty()
    end
end

local function OnPlanUpdated()
    if StockPiler4.Buy and StockPiler4.Buy.OnPlanUpdated then
        StockPiler4.Buy.OnPlanUpdated()
    end
end

local function OnSessionLoaded()
    if Sch.BeginSessionSettle then
        Sch.BeginSessionSettle()
    end
    Sch.SkipUiThisFrame()
    Sch.EnqueueBagFlush(true)
    -- Soft Invalidate on mid-session LOADING_END (zone/scenario). Hard Clear only when
    -- character identity changes (or first plan with no prior key) - never serve another
    -- character's stale plan via GetOrBuild(false).
    local charKey = ""
    if StockPiler4.Persistence and StockPiler4.Persistence.GetCharacterKey then
        charKey = tostring(StockPiler4.Persistence.GetCharacterKey() or "")
    elseif StockPiler4.Watch and StockPiler4.Watch.GetCharacterKey then
        charKey = tostring(StockPiler4.Watch.GetCharacterKey() or "")
    end
    local prevKey = tostring(Sch._planSessionCharKey or "")
    local charChanged = charKey ~= "" and prevKey ~= "" and charKey ~= prevKey
    local PS = StockPiler4.PlanSnapshot
    local firstPlan = PS == nil or PS.Get == nil or type(PS.Get()) ~= "table"
    if PS then
        if charChanged or (firstPlan and prevKey == "") then
            if PS.Clear then
                PS.Clear()
            elseif PS.Invalidate then
                PS.Invalidate()
            end
        elseif PS.Invalidate then
            PS.Invalidate()
        elseif PS.Clear then
            PS.Clear()
        end
    end
    if charKey ~= "" then
        Sch._planSessionCharKey = charKey
    end
    Sch.EnqueuePlanRebuild()
    Sch.MarkWatchUiDirty()
end

function Sch.IsInventorySideEffectsSuppressed()
    return (tonumber(Sch._suppressInvTicks) or 0) > 0
end

function Sch.SuppressInventorySideEffects(ticks)
    ticks = tonumber(ticks) or 2
    if ticks < 1 then
        ticks = 1
    end
    local cur = tonumber(Sch._suppressInvTicks) or 0
    if ticks > cur then
        Sch._suppressInvTicks = ticks
    end
end

function Sch.ArmHarvestStorm(seconds)
    ArmPipelineDebounce()
    seconds = tonumber(seconds) or Sch.HARVEST_STORM_MIN_SEC or 1.5
    local minSec = tonumber(Sch.HARVEST_STORM_MIN_SEC) or 1.5
    if seconds < minSec then
        seconds = minSec
    end
    local untilT = Now() + seconds
    local cur = tonumber(Sch._harvestStormUntil) or 0
    if untilT > cur then
        Sch._harvestStormUntil = untilT
    end
    -- Plant quiet >= storm floor.
    local quietSec = math.max(seconds, minSec)
    local quietUntil = Now() + quietSec
    local curQuiet = tonumber(Sch._plantQuietUntil) or 0
    if quietUntil > curQuiet then
        Sch._plantQuietUntil = quietUntil
    end
end

function Sch.IsHarvestStorm()
    local untilT = tonumber(Sch._harvestStormUntil) or 0
    if untilT <= 0 then
        return false
    end
    local now = Now()
    if now > 0 and now < untilT then
        return true
    end
    if now >= untilT then
        Sch._harvestStormUntil = 0
        -- Storm end: skip plan+UI this frame; enqueue coalesced rebuild for later.
        -- Do not InvalidatePlantQueue here (that piled WarmHave + Build
        -- + Watch flush into the first post-harvest / replant hitch).
        Sch.SkipPlanThisFrame()
        Sch.SkipUiThisFrame()
        if Sch.EnqueuePlanRebuild then
            Sch.EnqueuePlanRebuild({ nudge = true })
        end
        Sch.MarkWatchUiDirty()
        FlushPendingPrewarmAfterQuiet()
    end
    return false
end

function Sch.IsPlantQuiet()
    local untilT = tonumber(Sch._plantQuietUntil) or 0
    if untilT <= 0 then
        return false
    end
    local now = Now()
    if now > 0 and now < untilT then
        return true
    end
    if now >= untilT then
        Sch._plantQuietUntil = 0
        FlushPendingPrewarmAfterQuiet()
    end
    return false
end

-- Aliases used by other modules / SP2-shaped call sites.
Sch.IsHarvestStormActive = Sch.IsHarvestStorm
Sch.BeginHarvestStorm = Sch.ArmHarvestStorm

function Sch.ArmPlantQuiet(seconds)
    ArmPipelineDebounce()
    seconds = tonumber(seconds) or Sch.PLANT_QUIET_BASE_SEC or 0.75
    local minSec = tonumber(Sch.HARVEST_STORM_MIN_SEC) or 1.5
    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true and seconds < minSec then
        seconds = minSec
    end
    local untilT = Now() + seconds
    local cur = tonumber(Sch._plantQuietUntil) or 0
    if untilT > cur then
        Sch._plantQuietUntil = untilT
    end
end

local function SkipFlags()
    local skip = Sch._skipThisFrame
    if type(skip) ~= "table" then
        skip = { plan = false, ui = false, uiHoldFooter = false, orch = false }
        Sch._skipThisFrame = skip
    end
    return skip
end

function Sch.SkipPlanThisFrame()
    ArmPipelineDebounce()
    SkipFlags().plan = true
end

function Sch.SkipUiThisFrame()
    ArmPipelineDebounce()
    local skip = SkipFlags()
    skip.ui = true
    skip.uiHoldFooter = true
end

function Sch.SkipOrchThisFrame()
    SkipFlags().orch = true
end

function Sch.SkipPlanThisFrameActive()
    return SkipFlags().plan == true
end

function Sch.SkipUiThisFrameActive()
    return SkipFlags().ui == true
end

--- Hold Watch paint for a short window after reload / loading-end so FrameWork
--- prewarm + first PlanRebuild finish before SelectTab/RefreshWatch can Flatten.
function Sch.BeginSessionSettle(seconds)
    seconds = tonumber(seconds) or Sch.SESSION_SETTLE_SEC or 2.5
    local untilT = Now() + seconds
    local cur = tonumber(Sch._sessionSettleUntil) or 0
    if untilT > cur then
        Sch._sessionSettleUntil = untilT
    end
    -- Frame-based fallback: GetGameTime can be 0 during early reload.
    local fc = tonumber(StockPiler4.FrameCounter) or 0
    local frames = math.max(45, math.floor(seconds * 30))
    local untilFrame = fc + frames
    local curFrame = tonumber(Sch._sessionSettleUntilFrame) or 0
    if untilFrame > curFrame then
        Sch._sessionSettleUntilFrame = untilFrame
    end
    Sch._sessionSettleArmed = true
end

function Sch.IsSessionSettling()
    local fc = tonumber(StockPiler4.FrameCounter) or 0
    local untilFrame = tonumber(Sch._sessionSettleUntilFrame) or 0
    if untilFrame > 0 and fc < untilFrame then
        return true
    end
    if untilFrame > 0 and fc >= untilFrame then
        Sch._sessionSettleUntilFrame = 0
    end
    local untilT = tonumber(Sch._sessionSettleUntil) or 0
    if untilT <= 0 then
        return false
    end
    local now = Now()
    -- now==0: trust frame gate above; clear stale time gate once time is valid.
    if now <= 0 then
        return untilFrame > 0
    end
    if now < untilT then
        return true
    end
    Sch._sessionSettleUntil = 0
    return false
end

--- One-shot after reload settle: refresh plantIntent + wake AutoGrow so upgrade
--- planting does not wait for /sp4 dumpall.
local function MaybeFinishSessionSettle()
    if Sch._sessionSettleArmed ~= true then
        return
    end
    if Sch.IsSessionSettling() == true then
        return
    end
    Sch._sessionSettleArmed = false
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true) then
        return
    end
    local Planner = StockPiler4.Planner
    if Planner and Planner.NeedsPlantIntentRefresh
        and Planner.NeedsPlantIntentRefresh() == true
        and Planner.RefreshPlantRefineIntentsNow
    then
        Planner.RefreshPlantRefineIntentsNow()
    elseif Sch.EnqueuePlanRebuild then
        Sch.EnqueuePlanRebuild({ nudge = true })
    end
    if Sch.WakeAutoGrow then
        Sch.WakeAutoGrow()
    end
end

function Sch.SkipUiHoldFooter()
    return SkipFlags().uiHoldFooter == true
end

function Sch.ClearSkipUiHoldFooter()
    SkipFlags().uiHoldFooter = false
end

function Sch.EnqueueBagFlush(needQueue)
    ArmPipelineDebounce()
    if Sch.IsInventorySideEffectsSuppressed() then
        local pending = Sch._pendingAfterSuppress
        if type(pending) ~= "table" then
            pending = { bagFlush = false, bagQueue = false, plan = false }
            Sch._pendingAfterSuppress = pending
        end
        pending.bagFlush = true
        if needQueue == true then
            pending.bagQueue = true
        end
        return
    end
    local now = Now()
    if Sch._bagDue == true then
        if needQueue == true then
            Sch._bagNeedQueue = true
        end
        return
    end
    Sch._bagDue = true
    Sch._bagAt = now + Sch.BAG_COALESCE_SEC
    if needQueue == true then
        Sch._bagNeedQueue = true
    end
end

function Sch.EnqueuePlanRebuild(opts)
    opts = type(opts) == "table" and opts or {}
    local nudge = opts.nudge == true
    ArmPipelineDebounce()
    if Sch.IsInventorySideEffectsSuppressed() then
        local pending = Sch._pendingAfterSuppress
        if type(pending) ~= "table" then
            pending = { bagFlush = false, bagQueue = false, plan = false }
            Sch._pendingAfterSuppress = pending
        end
        pending.plan = true
        return
    end
    if Sch._bagDue == true then
        Sch._bagNeedQueue = true
        return
    end
    if nudge == true and Sch._planDue == true and (tonumber(Sch._planAt) or 0) > 0 then
        return
    end
    local now = Now()
    local wait = tonumber(Sch.PLAN_MAX_WAIT_SEC) or 0.5
    if Sch.ShouldWakeAutoGrow and Sch.ShouldWakeAutoGrow() == true and nudge ~= true then
        wait = tonumber(Sch.PLAN_COALESCE_WHEN_AWAKE_SEC) or 3.0
    end
    local at = now + wait
    local minGap = tonumber(Sch.PLAN_MIN_GAP_SEC) or 2.0
    local lastBuilt = tonumber(Sch._lastPlanBuiltAt) or 0
    if lastBuilt > 0 and minGap > 0 then
        local gapAt = lastBuilt + minGap
        if gapAt > at then
            at = gapAt
        end
    end
    Sch._planDue = true
    if Sch._planAt <= 0 then
        Sch._planAt = at
    elseif at > Sch._planAt and nudge ~= true then
        Sch._planAt = at
    end
end

function Sch.IsPlanRebuildPending()
    return Sch._planDue == true
end

function Sch.MarkWatchUiDirty()
    local B = StockPiler4.EventBus
    if B and B.FireWatchUiDirty then
        B.FireWatchUiDirty()
        return
    end
    local Ui = StockPiler4.Ui
    if Ui and Ui.MarkWatchUiDirty then
        Ui.MarkWatchUiDirty()
    end
end

function Sch.RequestFooterRefresh(payload)
    local B = StockPiler4.EventBus
    if B and B.FireFooterDirty then
        B.FireFooterDirty(payload)
        return
    end
    local E = StockPiler4.Events
    if B and B.Fire and E and E.FOOTER_DIRTY then
        B.Fire(E.FOOTER_DIRTY, type(payload) == "table" and payload or {})
    end
end

function Sch.FlushPendingFooterRefresh()
    local Ui = StockPiler4.Ui
    if Ui and Ui.FlushPendingFooterRefresh then
        Ui.FlushPendingFooterRefresh()
    end
end

function Sch.ShouldWakeAutoGrow()
    local Watch = StockPiler4.Watch
    if not Watch or not Watch.IsAutoGrowEnabled or Watch.IsAutoGrowEnabled() ~= true then
        return false
    end
    local Grow = StockPiler4.Grow
    if Grow and Grow.NeedsCurrentStageAdditive and Grow.NeedsCurrentStageAdditive() then
        return true
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() then
        return true
    end
    if Grow and Grow.HasEmptyPlot and Grow.HasEmptyPlot() then
        return true
    end
    local Refine = StockPiler4.Refine
    if Refine and Refine.IsDirty and Refine.IsDirty() == true then
        return true
    end
    -- Peek only: HasPendingBufferRefine rebuilds BufferFlags (harvest hitch amplifier).
    if Refine and Refine.PeekCachedBufferPending and Refine.PeekCachedBufferPending() == true then
        return true
    end
    return false
end

--- Intentional wake: clear fill-block + force plant-queue invalidate + fast ticks.
function Sch.WakeAutoGrow()
    local Orch = StockPiler4.Orchestrator
    if Orch and Orch.ClearFillBlocked then
        Orch.ClearFillBlocked()
    end
    local Grow = StockPiler4.Grow
    if Grow and Grow.ClearFillBlocked then
        Grow.ClearFillBlocked()
    end
    InvalidatePlantQueue("wake")
    Sch._autoGrowFast = true
end

function Sch.WakeAutoBuy()
    Sch._autoAccum = math.max(tonumber(Sch._autoAccum) or 0, AutoTickIntervalSec())
end

function Sch.SetAutoGrowIdle(idle)
    Sch._autoGrowFast = idle ~= true
end

function Sch.ShouldDeferAutoGrowPlant()
    local Watch = StockPiler4.Watch
    if Watch and Watch.IsCombatPauseEnabled and Watch.IsCombatPauseEnabled() ~= true then
        return false, nil
    end
    local player = GameData and GameData.Player
    if type(player) ~= "table" then
        return false, nil
    end
    if player.inCombat == true then
        return true, "combat"
    end
    if player.isInScenario == true then
        return true, "scenario"
    end
    return false, nil
end

function Sch.OnUpdate(timeElapsed)
    if StockPiler4.Buy and StockPiler4.Buy.PollStorePresence then
        StockPiler4.Buy.PollStorePresence()
    end
    if StockPiler4.Grow and StockPiler4.Grow.ExpireStalePending then
        StockPiler4.Grow.ExpireStalePending()
    end
    if StockPiler4.Brew and StockPiler4.Brew.OnUpdate then
        StockPiler4.Brew.OnUpdate(timeElapsed)
    end
    DecaySuppressInventorySideEffects()
    if Sch.IsHarvestStorm then
        Sch.IsHarvestStorm()
    end
    if Sch.IsPlantQuiet then
        Sch.IsPlantQuiet()
    end
    MaybeFinishSessionSettle()

    local didHeavy = false
    if FlushBagIfDue() then
        didHeavy = true
    end
    local Orch = StockPiler4.Orchestrator
    local brewSession = Orch and Orch.IsBrewSessionActive and Orch.IsBrewSessionActive() == true
    local skip = SkipFlags()
    local skipPump = brewSession
        or skip.plan == true
        or (Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true)
        or (Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true)
    if not didHeavy and not skipPump
        and StockPiler4.FrameWork and StockPiler4.FrameWork.Pump
        and StockPiler4.FrameWork.Pump() == true
    then
        didHeavy = true
    end
    if not didHeavy and RebuildPlanIfDue() then
        didHeavy = true
    end

    -- Orch before Watch flush so PlantSeed/AddAdditive nested CultivationUpdated
    -- can SkipUi before RefreshWatch (was: flush then plant → Watch painted first).
    Sch._autoAccum = (tonumber(Sch._autoAccum) or 0) + (tonumber(timeElapsed) or 0)
    local tickSec = AutoTickIntervalSec()
    local didOrch = false
    if Sch._autoAccum >= tickSec then
        Sch._autoAccum = Sch._autoAccum - tickSec
        if StockPiler4.Refine and StockPiler4.Refine.DecayRefineWaitTicks then
            StockPiler4.Refine.DecayRefineWaitTicks()
        end
        if StockPiler4.Grow and StockPiler4.Grow.DecayPlantWaitTicks then
            StockPiler4.Grow.DecayPlantWaitTicks()
        end
        if StockPiler4.Grow and StockPiler4.Grow.DecayHarvestOpLock then
            StockPiler4.Grow.DecayHarvestOpLock()
        end
        if StockPiler4.Orchestrator and StockPiler4.Orchestrator.DecayFillBlocked then
            StockPiler4.Orchestrator.DecayFillBlocked()
        end
        local skipOrch = skip.orch == true
        skip.orch = false
        if not didHeavy and not skipOrch
            and StockPiler4.Orchestrator and StockPiler4.Orchestrator.Tick
        then
            StockPiler4.Orchestrator.Tick()
            didOrch = true
            -- Plant/additive nested cult may have armed SkipUi; keep hold for Watch/Footer.
            if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
                Sch.SkipUiThisFrame()
                Sch.SkipPlanThisFrame()
            end
        end
    else
        skip.orch = false
    end

    -- One heavy: if orch ran, do not also Flatten Watch this frame.
    skip.plan = false
    FlushWatchUiIfDue(didHeavy or didOrch)
    skip.ui = false
end

function Sch.Initialize()
    if Sch._initialized == true then
        return
    end
    Sch._initialized = true
    local E = StockPiler4.Events
    local B = StockPiler4.EventBus
    if not (B and E) then
        return
    end
    TrackBus(B.Subscribe(E.INVENTORY_SNAPSHOT, OnInventorySnapshot))
    TrackBus(B.Subscribe(E.GARDEN_DIRTY, OnGardenDirty))
    TrackBus(B.Subscribe(E.SESSION_LOADED, OnSessionLoaded))
    if E.PLAN_UPDATED then
        TrackBus(B.Subscribe(E.PLAN_UPDATED, OnPlanUpdated))
    end
end

function Sch.Shutdown()
    local B = StockPiler4.EventBus
    local tokens = Sch._busTokens
    if B and B.Unsubscribe and type(tokens) == "table" then
        for i = 1, #tokens do
            B.Unsubscribe(tokens[i])
        end
    end
    Sch._busTokens = nil
    Sch._initialized = false
    Sch._bagDue = false
    Sch._planDue = false
    Sch._harvestStormUntil = 0
    Sch._plantQuietUntil = 0
end

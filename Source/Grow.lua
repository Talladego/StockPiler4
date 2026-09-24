----------------------------------------------------------------
-- StockPiler4 Grow -- ExecutePlant (snapshot intent) + plant cache + harvest
-- Policy and executor live here (no separate Executors folder).
-- Callees above callers (RoR Lua local-order).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Grow = StockPiler4.Grow or {}
local Grow = StockPiler4.Grow

Grow.PENDING_TTL_SEC = 10
Grow.PENDING_EMPTY_GRACE_SEC = 5.0
Grow.UNCONFIRMED_PLANT_COOLDOWN_SEC = 6.0
Grow.UNCONFIRMED_GARDEN_QUIET_SEC = 8.0
Grow.POST_HARVEST_PLANT_DELAY_SEC = 0.75
Grow.HARVEST_FORCE_DEBOUNCE_SEC = 1.5
Grow.HARVEST_OP_LOCK_SEC = 1.0

Grow._pendingPlant = Grow._pendingPlant or {}
Grow._pendingPlantAt = Grow._pendingPlantAt or {}
Grow._pendingSeedUid = Grow._pendingSeedUid or {}
-- True while _seedCommitted still counts this plot's in-flight plant.
Grow._pendingSeedHeld = Grow._pendingSeedHeld or {}
Grow._seedCommitted = Grow._seedCommitted or {}
Grow._wavePlantedBySeed = Grow._wavePlantedBySeed or {}
Grow._plantFailCooldownUntil = Grow._plantFailCooldownUntil or {}
Grow._pendingAdditive = Grow._pendingAdditive or {}
Grow._pendingAdditiveAt = Grow._pendingAdditiveAt or {}
Grow._fillCursor = Grow._fillCursor or 1
Grow._additiveCursor = Grow._additiveCursor or 1
Grow._lastPlantedSeedUid = 0
Grow._fillBlocked = false
Grow._plantWaitTicks = 0
Grow._plantQueueDirty = true
Grow._cachedPlantJob = nil
Grow._plantJobProbed = false
Grow._plantQuietUntil = 0
Grow._lastHarvestForceAt = 0
Grow._harvestOpLockUntil = 0
Grow._lastPreparedHarvestPlot = 0
Grow._autoGrowStallKeys = Grow._autoGrowStallKeys or {}
Grow._skillSkipByUid = Grow._skillSkipByUid or {}
Grow._skillSkipSnapGen = -1
Grow._lastSkipKey = nil
Grow._lastPickLogKey = nil
Grow._commitForceCleared = false
Grow._chatHarvestNeedsForce = false
Grow._additiveDirty = false

local ROLE_PICK_ORDER = {
    main = 1,
    stabilizer = 2,
    goldweed = 2,
    extender = 3,
    multiplier = 4,
    stimulant = 4,
    container = 5,
    ingredient = 6,
}

----------------------------------------------------------------
-- Helpers (callees first)
----------------------------------------------------------------

local function NowSec()
    return StockPiler4.Util.NowSec()
end

local function LogGrow(msg)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("grow", msg)
    end
end

local function LogOnce(key, msg)
    key = tostring(key or "")
    if Grow._lastSkipKey == key then
        return
    end
    Grow._lastSkipKey = key
    LogGrow(msg)
end

local function StageEmpty()
    if GameData and GameData.CultivationStage then
        return GameData.CultivationStage.EMPTY or 0
    end
    return 0
end

local function StageGrown()
    if GameData and GameData.CultivationStage then
        return GameData.CultivationStage.GROWN
            or GameData.CultivationStage.HARVESTABLE
            or 4
    end
    return 4
end

local function StageHarvesting()
    if GameData and GameData.CultivationStage then
        return GameData.CultivationStage.HARVESTING or 5
    end
    return 5
end

local function NormalizeStage(stage)
    return tonumber(stage) or 0
end

local function SpecRole(spec)
    if type(spec) ~= "table" then
        return "ingredient"
    end
    local role = tostring(spec.role or spec.materialRole or "")
    if role == "" then
        return "ingredient"
    end
    return role
end

local function RoleRank(role)
    return ROLE_PICK_ORDER[tostring(role or "")] or 99
end

local function IsPlotLocked(row, plotNum)
    if type(row) == "table" and row.locked == true then
        return true
    end
    local CA = StockPiler4.CultivatorAdapter
    if CA and CA.IsPlotLocked then
        return CA.IsPlotLocked(plotNum, CA.GetCultSkill and CA.GetCultSkill()) == true
    end
    return false
end

local function IsPlotEmptyRow(row)
    if type(row) ~= "table" then
        return false
    end
    if row.locked == true then
        return false
    end
    return NormalizeStage(row.stage) == StageEmpty()
end

local function IsPlotGrownStage(stage)
    local s = NormalizeStage(stage)
    local grown = StageGrown()
    if grown ~= nil and s == grown then
        return true
    end
    -- Some clients use HARVESTABLE alias.
    if GameData and GameData.CultivationStage and GameData.CultivationStage.HARVESTABLE then
        return s == GameData.CultivationStage.HARVESTABLE
    end
    return false
end

local function CanUseSeedUid(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return false
    end
    local Inv = StockPiler4.Inventory
    local snapGen = Inv and Inv.GetSnapGen and Inv.GetSnapGen() or 0
    if Grow._skillSkipSnapGen ~= snapGen then
        Grow._skillSkipByUid = {}
        Grow._skillSkipSnapGen = snapGen
    end
    if Grow._skillSkipByUid[seedUid] == true then
        return false
    end
    local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
    if type(sample) == "table" and Inv and Inv.CanUseCraftingItem then
        if Inv.CanUseCraftingItem(sample) ~= true then
            Grow._skillSkipByUid[seedUid] = true
            return false
        end
    end
    return true
end

local function CountInGroundSeeds(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return 0
    end
    local n = 0
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return 0
    end
    for _, row in pairs(plots) do
        if type(row) == "table" and (tonumber(row.seedUid) or 0) == seedUid then
            if not IsPlotEmptyRow(row) then
                n = n + 1
            end
        end
    end
    return n
end

--- Unique plots for this seed: in-flight pending and/or established garden rows.
--- Pending alone covers the gap after PlantSeed releases bag commit before Garden updates.
local function CountSeedPlotCredit(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return 0
    end
    local seen = {}
    local n = 0
    for plotNum, flag in pairs(Grow._pendingPlant) do
        plotNum = tonumber(plotNum) or 0
        if plotNum > 0 and (tonumber(flag) or 0) > 0
            and (tonumber(Grow._pendingSeedUid[plotNum]) or 0) == seedUid
        then
            seen[plotNum] = true
            n = n + 1
        end
    end
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) == "table" then
        for key, row in pairs(plots) do
            if type(row) == "table" and (tonumber(row.seedUid) or 0) == seedUid
                and not IsPlotEmptyRow(row)
            then
                local pn = tonumber(row.plotNum) or tonumber(key) or 0
                if pn > 0 then
                    if not seen[pn] then
                        seen[pn] = true
                        n = n + 1
                    end
                else
                    n = n + 1
                end
            end
        end
    end
    return n
end

local function ClearPendingPlot(plotNum, opts)
    plotNum = tonumber(plotNum) or 0
    opts = type(opts) == "table" and opts or {}
    if plotNum <= 0 then
        return
    end
    if opts.rollbackCommit == true and Grow._pendingSeedHeld[plotNum] == true then
        local seedUid = tonumber(Grow._pendingSeedUid[plotNum]) or 0
        if seedUid > 0 then
            local n = (tonumber(Grow._seedCommitted[seedUid]) or 0) - 1
            Grow._seedCommitted[seedUid] = n > 0 and n or nil
            local w = (tonumber(Grow._wavePlantedBySeed[seedUid]) or 0) - 1
            Grow._wavePlantedBySeed[seedUid] = w > 0 and w or nil
        end
    end
    Grow._pendingSeedHeld[plotNum] = nil
    Grow._pendingPlant[plotNum] = nil
    Grow._pendingPlantAt[plotNum] = nil
    Grow._pendingSeedUid[plotNum] = nil
end

--- After PlantSeed succeeds: bag is truth - drop seed bag reservation but keep plot
--- reserved until soil confirms so FindNextEmptyPlot cannot double-plant.
--- Keep _wavePlantedBySeed until rollback/force clear (do not drop it with bag commit).
local function ReleaseSeedReservation(plotNum)
    plotNum = tonumber(plotNum) or 0
    if plotNum <= 0 or Grow._pendingSeedHeld[plotNum] ~= true then
        return
    end
    local seedUid = tonumber(Grow._pendingSeedUid[plotNum]) or 0
    if seedUid > 0 then
        local n = (tonumber(Grow._seedCommitted[seedUid]) or 0) - 1
        Grow._seedCommitted[seedUid] = n > 0 and n or nil
    end
    Grow._pendingSeedHeld[plotNum] = false
end

local function ReleaseCommit(plotNum, ok)
    plotNum = tonumber(plotNum) or 0
    if plotNum <= 0 then
        return
    end
    -- ok==true: soil confirmed (seed commit already released after PlantSeed).
    -- ok==false: plant failed or pending expired - roll back commit only if still held.
    ClearPendingPlot(plotNum, { rollbackCommit = (ok ~= true) })
end

local function GetReadyHarvestPlots()
    local ready = {}
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return ready
    end
    for plotNum, row in pairs(plots) do
        plotNum = tonumber(plotNum) or 0
        if plotNum > 0 and type(row) == "table" and not IsPlotLocked(row, plotNum) then
            if IsPlotGrownStage(row.stage) then
                ready[#ready + 1] = plotNum
            end
        end
    end
    table.sort(ready)
    return ready
end

local function HasPlotGrowing()
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return false
    end
    local empty = StageEmpty()
    local grown = StageGrown()
    local harvesting = StageHarvesting()
    for plotNum, row in pairs(plots) do
        if type(row) == "table" and not IsPlotLocked(row, tonumber(plotNum) or 0) then
            local s = NormalizeStage(row.stage)
            if s ~= empty and s ~= grown and s ~= harvesting then
                return true
            end
        end
    end
    return false
end

local function AllPlantedPlotsHarvestReady()
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return false
    end
    local anyPlanted = false
    for plotNum, row in pairs(plots) do
        if type(row) == "table" and not IsPlotLocked(row, tonumber(plotNum) or 0) then
            if not IsPlotEmptyRow(row) then
                anyPlanted = true
                if not IsPlotGrownStage(row.stage)
                    and NormalizeStage(row.stage) ~= StageHarvesting()
                then
                    return false
                end
            end
        end
    end
    return anyPlanted
end

----------------------------------------------------------------
-- Public: buffer / fill / plots
----------------------------------------------------------------

function Grow.StageEmpty()
    return StageEmpty()
end

function Grow.IsEnabled()
    local Watch = StockPiler4.Watch
    if not Watch or not Watch.IsAutoGrowEnabled or Watch.IsAutoGrowEnabled() ~= true then
        return false
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return false
    end
    return true
end

function Grow.HasEmptyPlot()
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return false
    end
    for plotNum, row in pairs(plots) do
        if not IsPlotLocked(row, tonumber(plotNum) or 0) and IsPlotEmptyRow(row) then
            if (tonumber(Grow._pendingPlant[plotNum]) or 0) <= 0 then
                return true
            end
        end
    end
    return false
end

function Grow.CountEmptyPlots()
    local CA = StockPiler4.CultivatorAdapter
    local maxPlots = CA and CA.NumPlots and tonumber(CA.NumPlots()) or 4
    if maxPlots < 1 then
        maxPlots = 4
    end
    local n = 0
    for plotNum = 1, maxPlots do
        local row = StockPiler4.Garden and StockPiler4.Garden.GetPlot and StockPiler4.Garden.GetPlot(plotNum)
        if not IsPlotLocked(row, plotNum) and IsPlotEmptyRow(row) then
            if (tonumber(Grow._pendingPlant[plotNum]) or 0) <= 0 then
                n = n + 1
            end
        end
    end
    return n
end

function Grow.FindNextEmptyPlot()
    local CA = StockPiler4.CultivatorAdapter
    local maxPlots = CA and CA.NumPlots and CA.NumPlots() or 4
    local start = tonumber(Grow._fillCursor) or 1
    if start < 1 or start > maxPlots then
        start = 1
    end
    for i = 0, maxPlots - 1 do
        local plotNum = ((start - 1 + i) % maxPlots) + 1
        local row = StockPiler4.Garden and StockPiler4.Garden.GetPlot and StockPiler4.Garden.GetPlot(plotNum)
        if not IsPlotLocked(row, plotNum) and IsPlotEmptyRow(row) then
            if (tonumber(Grow._pendingPlant[plotNum]) or 0) <= 0 then
                Grow._fillCursor = plotNum + 1
                return plotNum
            end
        end
    end
    return 0
end

function Grow.CountInGroundSeeds(seedUid)
    return CountInGroundSeeds(seedUid)
end

function Grow.CountSeedPlotCredit(seedUid)
    return CountSeedPlotCredit(seedUid)
end

function Grow.HasPendingBufferRefine()
    local Refine = StockPiler4.Refine
    if Refine and Refine.HasPendingBufferRefine then
        return Refine.HasPendingBufferRefine() == true
    end
    return false
end

function Grow.HasAnyBufferShort()
    local Refine = StockPiler4.Refine
    if Refine and Refine.HasAnyBufferShort then
        return Refine.HasAnyBufferShort() == true
    end
    return false
end

function Grow.IsSeedBufferSatisfied()
    local Refine = StockPiler4.Refine
    if Refine and Refine.IsSeedBufferSatisfied then
        return Refine.IsSeedBufferSatisfied() == true
    end
    return true
end

function Grow.SetFillBlocked(blocked, waitTicks)
    if blocked == true then
        Grow._fillBlocked = true
        waitTicks = tonumber(waitTicks) or 0
        local cur = tonumber(Grow._plantWaitTicks) or 0
        if waitTicks > cur then
            Grow._plantWaitTicks = waitTicks
        end
        -- Mirror Orch wait without calling Orch.SetFillBlocked (that re-enters Grow).
        local Orch = StockPiler4.Orchestrator
        if Orch then
            Orch._fillBlocked = true
            local ow = tonumber(Orch._fillBlockedWait) or 0
            local gw = tonumber(Grow._plantWaitTicks) or 0
            if gw > ow then
                Orch._fillBlockedWait = gw
            end
        end
    else
        Grow.ClearFillBlocked()
    end
end

function Grow.ClearFillBlocked()
    Grow._fillBlocked = false
    Grow._plantWaitTicks = 0
end

function Grow.IsFillBlocked()
    return Grow._fillBlocked == true
end

function Grow.DecayPlantWaitTicks()
    local wait = tonumber(Grow._plantWaitTicks) or 0
    if wait > 0 then
        Grow._plantWaitTicks = wait - 1
        if Grow._plantWaitTicks <= 0 then
            Grow._fillBlocked = false
            Grow._plantWaitTicks = 0
        end
    end
end

--- Plant job cache (GetPlantJob / MarkPlantJobProbed / InvalidatePlantQueue) is for
--- Planner.BuildFull and diagnostics/UI. Orchestrator tick plants via PlanSnapshot.plantIntent only.

function Grow.InvalidatePlantQueue(opts)
    opts = type(opts) == "table" and opts or {}
    Grow._plantQueueDirty = true
    Grow._cachedPlantJob = nil
    Grow._plantJobProbed = false
    local US = StockPiler4.UpgradeSeed
    if US and US.InvalidateUpgradeTargetsCache then
        US.InvalidateUpgradeTargetsCache()
    end
    if opts.force == true then
        Grow._seedCommitted = {}
        Grow._wavePlantedBySeed = {}
        if opts.keepCommitForceCleared ~= true then
            Grow._commitForceCleared = false
        end
    end
end

function Grow.MarkPlantJobDirty(reason)
    Grow.InvalidatePlantQueue({ reason = reason })
end

--- Record a plant-queue probe result without re-running PickPlantCandidate.
--- Used by Orchestrator refine-first to clear plant-probe-pending cheaply.
function Grow.MarkPlantJobProbed(job)
    if type(job) == "table" then
        Grow._cachedPlantJob = job
    else
        Grow._cachedPlantJob = nil
    end
    Grow._plantJobProbed = true
    Grow._plantQueueDirty = false
end

----------------------------------------------------------------
-- Plant pick (Phase 3: Planner/PlantPlan.lua)
----------------------------------------------------------------

function Grow.ClampSeedCommitsToBag()
    local Inv = StockPiler4.Inventory
    if not (Inv and Inv.CountByUid) then
        return
    end
    for seedUid, committed in pairs(Grow._seedCommitted) do
        seedUid = tonumber(seedUid) or 0
        committed = tonumber(committed) or 0
        if seedUid > 0 and committed > 0 then
            local bag = tonumber(Inv.CountByUid(seedUid)) or 0
            if committed > bag then
                if bag <= 0 then
                    Grow._seedCommitted[seedUid] = nil
                else
                    Grow._seedCommitted[seedUid] = bag
                end
            end
        end
    end
end


function Grow.PickPlantCandidate()
    local PP = StockPiler4.PlantPlan
    if PP and PP.PickPlantJob then
        return PP.PickPlantJob()
    end
    return nil
end

function Grow.GetPlantJob()
    if Grow._plantQueueDirty ~= true and Grow._plantJobProbed == true then
        return Grow._cachedPlantJob
    end
    local job = Grow.PickPlantCandidate()
    Grow.MarkPlantJobProbed(job)
    return job
end

function Grow.PeekSeedsForNextPlant()
    if Grow._plantQueueDirty == true then
        return false, "dirty"
    end
    local job = Grow._cachedPlantJob
    if type(job) == "table" and (tonumber(job.seedUid) or 0) > 0 then
        return true, job
    end
    if Grow._plantJobProbed == true and Grow._cachedPlantJob == nil then
        return false, "none"
    end
    if Grow._plantQueueDirty ~= true and Grow._cachedPlantJob == nil then
        return false, "none"
    end
    return false, "unprobed"
end

function Grow.HasSeedsForNextPlant()
    local job = Grow.GetPlantJob()
    return type(job) == "table" and (tonumber(job.seedUid) or 0) > 0
end

function Grow.HasPendingPlant()
    for _, n in pairs(Grow._pendingPlant) do
        if (tonumber(n) or 0) > 0 then
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- IssuePlantOne
----------------------------------------------------------------

function Grow.LogSkipPlant(reason)
    LogOnce("skip-" .. tostring(reason or "?"), "skip plant reason=" .. tostring(reason or "?"))
end

local function ResolvePlantJob(intent)
    if type(intent) ~= "table" or (tonumber(intent.seedUid) or 0) <= 0 then
        return nil
    end
    return {
        seedUid = tonumber(intent.seedUid) or 0,
        plantUid = tonumber(intent.plantUid) or 0,
        watchKey = intent.watchKey,
        role = intent.role,
        plantReason = intent.plantReason or intent.reason or intent.pickMode,
        pickMode = intent.pickMode,
    }
end

--- Execute a plant intent (plot validation + CultivatorAdapter.PlantSeed).
function Grow.ExecutePlant(intent, opId)
    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("Grow.ExecutePlant")
    end
    local function done(ok)
        if Perf and Perf.End then
            Perf.End("Grow.ExecutePlant")
        end
        return ok == true
    end

    local plotNum = 0
    if type(intent) == "table" then
        plotNum = tonumber(intent.plotNum) or 0
    end
    local CA = StockPiler4.CultivatorAdapter
    local BA = StockPiler4.BagAdapter
    if not CA or not CA.PlantSeed then
        Grow.LogSkipPlant("no-cult-adapter")
        return done(false)
    end
    -- Stale baked plotNum (from an older full Build) must not abort the wave.
    if plotNum > 0 and CA.ReadPlot then
        local live = CA.ReadPlot(plotNum)
        if type(live) ~= "table"
            or live.locked == true
            or NormalizeStage(live.stage) ~= StageEmpty()
        then
            plotNum = 0
        end
    end
    if plotNum <= 0 then
        plotNum = Grow.FindNextEmptyPlot()
    end
    if plotNum <= 0 then
        Grow.LogSkipPlant("no-empty-plot")
        return done(false)
    end
    if CA.ReadPlot then
        local live = CA.ReadPlot(plotNum)
        if type(live) == "table" then
            if live.locked == true or NormalizeStage(live.stage) ~= StageEmpty() then
                Grow.LogSkipPlant("plot-not-empty-live P" .. tostring(plotNum))
                if StockPiler4.Garden and StockPiler4.Garden.MarkSyncAllDue then
                    StockPiler4.Garden.MarkSyncAllDue()
                end
                -- Prefer next empty over latching fillBlocked on a stale intent plot.
                local nextPlot = Grow.FindNextEmptyPlot()
                if nextPlot > 0 and nextPlot ~= plotNum then
                    plotNum = nextPlot
                    live = CA.ReadPlot(plotNum)
                    if type(live) == "table"
                        and (live.locked == true or NormalizeStage(live.stage) ~= StageEmpty())
                    then
                        return done(false)
                    end
                else
                    return done(false)
                end
            end
        end
    end

    local job = ResolvePlantJob(intent)
    if type(job) ~= "table" then
        if Grow.HasPendingBufferRefine() then
            if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                StockPiler4.Refine.MarkRefineDue("seed-buffer")
            end
            Grow.ClearFillBlocked()
        else
            Grow.SetFillBlocked(true, 5)
            Grow.LogSkipPlant("no-plant-job")
        end
        return done(false)
    end

    local seedUid = tonumber(job.seedUid) or 0
    local slot, item, backpackType = 0, nil, nil
    if BA and BA.FindSeedSlot then
        slot, item, backpackType = BA.FindSeedSlot(seedUid)
    end
    if slot <= 0 or type(item) ~= "table" then
        local Sch = StockPiler4.Scheduler
        if Sch and Sch.SetAutoGrowIdle then
            Sch.SetAutoGrowIdle(false)
        end
        Grow.SetFillBlocked(true, 1)
        Grow.LogSkipPlant("no-seed-slot uid=" .. tostring(seedUid))
        return done(false)
    end

    Grow._pendingPlant[plotNum] = 1
    Grow._pendingPlantAt[plotNum] = NowSec()
    Grow._pendingSeedUid[plotNum] = seedUid
    Grow._pendingSeedHeld[plotNum] = true
    Grow._seedCommitted[seedUid] = (tonumber(Grow._seedCommitted[seedUid]) or 0) + 1
    Grow._wavePlantedBySeed[seedUid] = (tonumber(Grow._wavePlantedBySeed[seedUid]) or 0) + 1

    local CC = StockPiler4.CraftChatAdapter
    if CC and CC.StashSoilPending then
        CC.StashSoilPending(plotNum, {
            reason = tostring(job.plantReason or "potion_stock"),
            name = item.name,
            seedUid = seedUid,
        })
    end

    CA.SetCurrentPlot(plotNum)
    local ok = CA.PlantSeed(plotNum, slot, backpackType)
    if ok ~= true then
        ReleaseCommit(plotNum, false)
        if CC and CC.ClearSoilPending then
            CC.ClearSoilPending(plotNum)
        end
        Grow.SetFillBlocked(true, 2)
        Grow.LogSkipPlant("plant-seed-api-fail P" .. tostring(plotNum))
        return done(false)
    end

    -- Drop baked plot on the live intent so the next tick re-resolves empties
    -- even if a cheap/garden plan patch reuses this plantIntent.
    if type(intent) == "table" then
        intent.plotNum = 0
    end

    ReleaseSeedReservation(plotNum)
    Grow._lastPlantedSeedUid = seedUid
    Grow._commitForceCleared = false
    Grow.InvalidatePlantQueue({})
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.ArmPlantQuiet then
        Sch.ArmPlantQuiet()
    end
    if Sch and Sch.SkipPlanThisFrame then
        Sch.SkipPlanThisFrame()
    end
    if Sch and Sch.SkipUiThisFrame then
        Sch.SkipUiThisFrame()
    end
    if Sch and Sch.SuppressInventorySideEffects then
        Sch.SuppressInventorySideEffects(2)
    end
    LogGrow(string.format(
        "plant P%d seedUid=%d role=%s watch=%s reason=%s opId=%s",
        plotNum,
        seedUid,
        tostring(job.role or "?"),
        tostring(job.watchKey or "?"),
        tostring(job.plantReason or ""),
        tostring(opId or "?")
    ))
    if tostring(job.plantReason or "") == "skill_up" then
        local Rates = StockPiler4.SkillRates
        local Gates = StockPiler4.SkillUpGates
        if Rates and Rates.NoteCultAttempt
            and Gates and Gates.IsCultEnabled and Gates.IsCultEnabled() == true
        then
            Rates.NoteCultAttempt({ seedUid = seedUid })
        end
    end
    return done(true)
end

function Grow.IssuePlantOne(opId)
    if Grow._chatHarvestNeedsForce == true then
        local now = NowSec()
        local lastForce = tonumber(Grow._lastHarvestForceAt) or 0
        local debounce = tonumber(Grow.HARVEST_FORCE_DEBOUNCE_SEC) or 1.5
        Grow._chatHarvestNeedsForce = false
        if lastForce <= 0 or now <= 0 or (now - lastForce) >= debounce then
            Grow.WakeAfterHarvest(0)
        end
    end
    if StockPiler4.Orchestrator and StockPiler4.Orchestrator.IsBrewSessionActive
        and StockPiler4.Orchestrator.IsBrewSessionActive() == true
    then
        return false
    end
    if not Grow.IsEnabled() then
        return false
    end
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.ShouldDeferAutoGrowPlant then
        local deferPlant, deferReason = Sch.ShouldDeferAutoGrowPlant()
        if deferPlant == true then
            Grow.LogSkipPlant(tostring(deferReason or "combat"))
            return false
        end
    end
    local quietUntil = tonumber(Grow._plantQuietUntil) or 0
    if quietUntil > 0 then
        local now = NowSec()
        if now > 0 and now < quietUntil then
            Grow.LogSkipPlant("grow-quiet")
            return false
        end
        Grow._plantQuietUntil = 0
    end
    if Grow.ShouldHoldPlantForReadyHarvest() == true then
        Grow.LogSkipPlant("hold-harvest-batch")
        return false
    end

    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get()
    local intent = type(plan) == "table" and plan.plantIntent or nil
    if type(intent) ~= "table" or (tonumber(intent.seedUid) or 0) <= 0 then
        return false
    end
    return Grow.ExecutePlant(intent, opId)
end

function Grow.TryPlantOne(opId)
    return Grow.IssuePlantOne(opId)
end

----------------------------------------------------------------
-- Additives
----------------------------------------------------------------

function Grow.ClearPendingAdditive(plotNum)
    plotNum = tonumber(plotNum) or 0
    if plotNum <= 0 then
        return
    end
    Grow._pendingAdditive[plotNum] = nil
    Grow._pendingAdditiveAt[plotNum] = nil
end

function Grow.ClearPendingAdditiveIfFilled(plotNum, row)
    plotNum = tonumber(plotNum) or 0
    if plotNum <= 0 or (tonumber(Grow._pendingAdditive[plotNum]) or 0) < 1 then
        return
    end
    local AD = StockPiler4.Additives
    if not AD or not AD.CultTypeForStage or not AD.PlotHasAdditive then
        return
    end
    local stage = NormalizeStage(type(row) == "table" and row.stage or 0)
    local cultType = AD.CultTypeForStage(stage)
    if cultType and AD.PlotHasAdditive(row, cultType) then
        Grow.ClearPendingAdditive(plotNum)
    end
end

--- True when AutoGrow can apply an additive right now (need + bag stock).
--- Plot-need alone must not keep the 1s AutoGrow tick during grow-wait.
function Grow.NeedsCurrentStageAdditive()
    if Grow.IsEnabled() ~= true then
        return false
    end
    local AD = StockPiler4.Additives
    if not AD or not AD.IsEnabled or AD.IsEnabled() ~= true then
        return false
    end
    if AD.CanApplyCurrentStage then
        return AD.CanApplyCurrentStage() == true
    end
    if AD.NeedsCurrentStage then
        return AD.NeedsCurrentStage() == true
    end
    return Grow._additiveDirty == true
end

function Grow.ExecuteAdditive(opId)
    return Grow.TryAdditive(opId)
end

function Grow.TryAdditive(opId)
    if Grow.NeedsCurrentStageAdditive() ~= true then
        return false
    end
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.ShouldDeferAutoGrowPlant then
        local deferPlant = Sch.ShouldDeferAutoGrowPlant()
        if deferPlant == true then
            return false
        end
    end
    local AD = StockPiler4.Additives
    local CA = StockPiler4.CultivatorAdapter
    if not (AD and AD.PickNext and CA and CA.AddAdditive) then
        Grow._additiveDirty = false
        return false
    end
    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("Grow.TryAdditive")
    end

    local now = NowSec()
    local ttl = tonumber(Grow.PENDING_TTL_SEC) or 10
    for plotNum, at in pairs(Grow._pendingAdditiveAt) do
        at = tonumber(at) or 0
        if at > 0 and (now - at) >= ttl then
            Grow.ClearPendingAdditive(plotNum)
        end
    end

    local pick = AD.PickNext({
        cursor = Grow._additiveCursor,
        pendingAdditive = Grow._pendingAdditive,
    })
    local ok = false
    if type(pick) == "table" and (tonumber(pick.plotNum) or 0) > 0 and (tonumber(pick.slot) or 0) > 0 then
        local plotNum = tonumber(pick.plotNum) or 0
        if CA.SetCurrentPlot then
            CA.SetCurrentPlot(plotNum)
        end
        Grow._pendingAdditive[plotNum] = (tonumber(Grow._pendingAdditive[plotNum]) or 0) + 1
        Grow._pendingAdditiveAt[plotNum] = now
        ok = CA.AddAdditive(plotNum, pick.slot, pick.backpackType) == true
        if ok then
            local n = CA.NumPlots and CA.NumPlots() or 4
            Grow._additiveCursor = (plotNum % n) + 1
            Grow._additiveDirty = true
            LogGrow(string.format(
                "additive P%d role=%s uid=%s slot=%s opId=%s",
                plotNum,
                tostring(pick.role or "?"),
                tostring(pick.uniqueID or 0),
                tostring(pick.slot),
                tostring(opId or "?")
            ))
            if Sch and Sch.WakeAutoGrow then
                Sch.WakeAutoGrow()
            end
        else
            Grow.ClearPendingAdditive(plotNum)
            LogGrow("additive failed P" .. tostring(plotNum) .. " opId=" .. tostring(opId or "?"))
        end
    else
        Grow._additiveDirty = false
    end
    if Perf and Perf.End then
        Perf.End("Grow.TryAdditive")
    end
    return ok
end

function Grow.MarkAdditiveDue()
    Grow._additiveDirty = true
end

----------------------------------------------------------------
-- Harvest
----------------------------------------------------------------

function Grow.GetReadyHarvestPlots()
    return GetReadyHarvestPlots()
end

function Grow.ShouldHoldPlantForReadyHarvest()
    local ready = GetReadyHarvestPlots()
    if #ready <= 0 then
        return false
    end
    if HasPlotGrowing() then
        return false
    end
    return true
end

local function NudgeHarvestReadiness()
    local Sch = StockPiler4.Scheduler
    local hold = (Sch and Sch.SkipUiThisFrameActive and Sch.SkipUiThisFrameActive() == true)
        or (Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true)
        or (Sch and Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true)
        or (Sch and Sch.IsSessionSettling and Sch.IsSessionSettling() == true)
    local Bus = StockPiler4.EventBus
    if Bus and Bus.FireFooterDirty then
        if hold then
            Bus.FireFooterDirty()
        else
            Bus.FireFooterDirty({ immediate = true })
        end
    end
    if hold then
        return
    end
end

function Grow.ArmHarvestOpLock(seconds)
    seconds = tonumber(seconds) or Grow.HARVEST_OP_LOCK_SEC
    local untilT = NowSec() + seconds
    local cur = tonumber(Grow._harvestOpLockUntil) or 0
    local wasActive = cur > 0 and NowSec() < cur
    if untilT > cur then
        Grow._harvestOpLockUntil = untilT
    end
    -- Grey Harvest macro while op-lock is active (CanHarvestNow -> false).
    if not wasActive then
        NudgeHarvestReadiness()
    end
end

--- Clear expired op-lock and re-lit Harvest (Scheduler tick; avoid CanHarvestNow recursion).
function Grow.DecayHarvestOpLock()
    local untilT = tonumber(Grow._harvestOpLockUntil) or 0
    if untilT <= 0 then
        return
    end
    if NowSec() < untilT then
        return
    end
    Grow._harvestOpLockUntil = 0
    NudgeHarvestReadiness()
end

function Grow.IsHarvestOpActive()
    local untilT = tonumber(Grow._harvestOpLockUntil) or 0
    if untilT <= 0 then
        return false
    end
    if NowSec() < untilT then
        return true
    end
    Grow._harvestOpLockUntil = 0
    return false
end

function Grow.CanHarvestNow()
    -- Op-lock: button must grey; PrepareHarvest alone returned false while lit.
    if Grow.IsHarvestOpActive() then
        return false
    end
    if StockPiler4.Brew and StockPiler4.Brew.BlocksHarvest and StockPiler4.Brew.BlocksHarvest() == true then
        return false
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return false
    end
    local ready = GetReadyHarvestPlots()
    return #ready > 0
end

--- True when every planted plot is grown (empty ignored). Mid-batch stays lit without re-chime.
function Grow.AllPlantedPlotsHarvestReady()
    local plots = StockPiler4.Garden and StockPiler4.Garden.GetPlots and StockPiler4.Garden.GetPlots()
    if type(plots) ~= "table" then
        return false, 0, 0
    end
    local planted = 0
    local ready = 0
    for i = 1, #plots do
        local row = plots[i]
        if type(row) == "table" and not IsPlotEmptyRow(row) then
            planted = planted + 1
            if IsPlotGrownStage(row.stage) then
                ready = ready + 1
            end
        end
    end
    return planted > 0 and ready == planted, ready, planted
end

--- User chat for one plot harvest (main plant only).
function Grow.NotifyHarvestOutcome(plotNum, opts)
    opts = type(opts) == "table" and opts or {}
    plotNum = tonumber(plotNum) or 0
    local function NotifyChat(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Notify then
            StockPiler4.Debug.Notify(msg)
        elseif StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    local function T(key, tokens)
        return StockPiler4.Util.T(key, tokens)
    end
    if opts.critFail == true then
        NotifyChat(T("grow.harvest_crit_fail", { plot = tostring(plotNum) }))
        return
    end
    local count = tonumber(opts.count) or 0
    local name = opts.name
    if name == nil or name == L"" or name == "" then
        return
    end
    local uid = tonumber(opts.uniqueID) or 0
    local CC = StockPiler4.CraftChatAdapter
    if CC and CC.ItemLink and uid > 0 then
        name = CC.ItemLink(uid, name)
    elseif type(name) == "string" then
        name = towstring(name)
    end
    NotifyChat(T("grow.harvest_outcome", {
        plot = tostring(plotNum),
        count = tostring(math.max(1, count)),
        name = name,
    }))
    if opts.specialMoment == true then
        NotifyChat(T("grow.harvest_special_moment", {
            plot = tostring(plotNum),
            name = name,
        }))
    end
end

--- One-shot harvest-ready chat + HELP_TIPS_NEW; clear latch when not ready.
function Grow.MaybeNotifyHarvestReady()
    local allReady, readyN = Grow.AllPlantedPlotsHarvestReady()
    local canHarvest = Grow.CanHarvestNow() == true
    local ready = allReady == true and canHarvest == true
    local wasReady = Grow._harvestReadyLatched == true
    local Sch = StockPiler4.Scheduler
    -- Never SyncActionReadiness (CanBrewNow + Macro.Appearance) during cult storms —
    -- that was the 10s Footer/Macro trail piled on CultivationUpdated x4.
    local holdFooter = (Sch and Sch.SkipUiThisFrameActive and Sch.SkipUiThisFrameActive() == true)
        or (Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true)
        or (Sch and Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true)
        or (Sch and Sch.IsSessionSettling and Sch.IsSessionSettling() == true)
    local function NudgeFooter(forceImmediate)
        local Bus = StockPiler4.EventBus
        if not Bus or not Bus.FireFooterDirty then
            return
        end
        if holdFooter or forceImmediate ~= true then
            Bus.FireFooterDirty()
            return
        end
        Bus.FireFooterDirty({ immediate = true })
    end
    -- Enable Harvest as soon as any plot is harvestable (not only all-planted latch).
    if canHarvest then
        if Grow._canHarvestLatched ~= true then
            NudgeFooter(true)
            Grow._canHarvestLatched = true
        else
            NudgeFooter(false)
        end
    elseif Grow._canHarvestLatched == true then
        Grow._canHarvestLatched = false
        NudgeFooter(false)
    end
    if ready then
        if not wasReady then
            NudgeFooter(true)
        else
            NudgeFooter(false)
        end
        Grow._harvestReadyLatched = true
        if Grow._harvestReadyChatSent ~= true then
            Grow._harvestReadyChatSent = true
            local msg = L"<icon02486> Ready - " .. towstring(tostring(readyN)) .. L" plot(s)."
            if StockPiler4.T then
                msg = StockPiler4.T("grow.harvest_ready", { count = tostring(readyN) })
            end
            if StockPiler4.Debug and StockPiler4.Debug.Print then
                StockPiler4.Debug.Print(msg)
            end
            local soundId = GameData and GameData.Sound and GameData.Sound.HELP_TIPS_NEW
            if soundId and Sound and Sound.Play then
                Sound.Play(soundId)
            end
        end
    else
        if wasReady then
            NudgeFooter(false)
        end
        Grow._harvestReadyLatched = false
        Grow._harvestReadyChatSent = false
    end
end

--- Red Status column keys that AutoGrow cannot clear without the player.
local AUTOGROW_STALL_STATUS = {
    buy_ingredients = true,
    no_recipe = true,
    need_skill = true,
}

local function AutoGrowStallBuyInProgress()
    local Buy = StockPiler4.Buy
    if not (Buy and Buy.IsEnabled and Buy.IsEnabled() == true) then
        return false
    end
    local VA = StockPiler4.VendorAdapter
    return VA and VA.IsStoreOpen and VA.IsStoreOpen() == true
end

local function RowArmedForAutoGrow(row)
    if type(row) ~= "table" then
        return false
    end
    local Watch = StockPiler4.Watch
    if not Watch then
        return false
    end
    if row.kind == "plant" or row.isPlantWatch == true then
        return Watch.ShouldAutoGrowPlant
            and Watch.ShouldAutoGrowPlant(row.plantKey or row.id) == true
    end
    local pk = tostring(row.potionKey or row.potionRecipeKey or row.id or "")
    if pk == "" then
        return false
    end
    local RS = StockPiler4.RecipeSpec
    if RS and RS.ShouldAutoGrowPotion then
        return RS.ShouldAutoGrowPotion(pk, nil) == true
    end
    local w = Watch.GetWatch and Watch.GetWatch(pk)
    return type(w) == "table" and w.enabled == true and w.autoGrow == true
end

--- One-shot chat when AutoGrow is on but a watch is red (buy / learn / skill).
--- Latches per watch; first observe seeds silently (same pattern as brew-ready).
function Grow.MaybeNotifyAutoGrowStall()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true) then
        Grow._autoGrowStallKeys = nil
        return
    end
    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get()
    local rows = plan and plan.rows
    local nowKeys = {}
    local newly = {}
    local skipBuy = AutoGrowStallBuyInProgress()
    local prev = Grow._autoGrowStallKeys
    if type(rows) == "table" then
        for i = 1, #rows do
            local row = rows[i]
            if type(row) == "table" and RowArmedForAutoGrow(row) then
                local sk = tostring(row.statusKey or "")
                if AUTOGROW_STALL_STATUS[sk] == true then
                    local id = tostring(row.potionKey or row.plantKey or row.id or i)
                    if sk == "buy_ingredients" and skipBuy then
                        -- Vendor buying: keep an existing latch, do not arm a new silent one.
                        if type(prev) == "table" and prev[id] == true then
                            nowKeys[id] = true
                        end
                    else
                        nowKeys[id] = row
                    end
                end
            end
        end
    end

    -- First observe after load / AutoGrow on: seed without chat.
    if prev == nil then
        local seeded = {}
        for id, _ in pairs(nowKeys) do
            seeded[id] = true
        end
        Grow._autoGrowStallKeys = seeded
        return
    end

    for id, row in pairs(nowKeys) do
        if prev[id] ~= true and type(row) == "table" then
            newly[#newly + 1] = row
        end
    end
    local nextKeys = {}
    for id, _ in pairs(nowKeys) do
        nextKeys[id] = true
    end
    Grow._autoGrowStallKeys = nextKeys
    if #newly == 0 then
        return
    end
    local row = newly[1]
    local status = row.statusText
    if status == nil or status == L"" then
        local key = "plan.status." .. tostring(row.statusKey or "buy_ingredients")
        if StockPiler4.T then
            status = StockPiler4.T(key)
        else
            status = towstring(tostring(row.statusKey or "buy"))
        end
    elseif type(status) ~= "wstring" then
        status = towstring(tostring(status))
    end
    local name = row.name
    if name == nil or name == L"" then
        name = L"watch"
        if StockPiler4.T then
            name = StockPiler4.T("watch.fallback")
        end
    elseif type(name) ~= "wstring" then
        name = towstring(tostring(name))
    end
    local extra = #newly - 1
    local msg
    if StockPiler4.T then
        if extra > 0 then
            msg = StockPiler4.T("grow.autogrow_stalled_more", {
                status = status,
                name = name,
                count = tostring(extra),
            })
        else
            msg = StockPiler4.T("grow.autogrow_stalled", {
                status = status,
                name = name,
            })
        end
    else
        msg = L"<icon02486> AutoGrow stalled - " .. status .. L" (" .. name .. L")."
    end
    if StockPiler4.Debug and StockPiler4.Debug.Print then
        StockPiler4.Debug.Print(msg)
    end
    local soundId = GameData and GameData.Sound and GameData.Sound.RESPAWN
    if soundId == nil then
        soundId = 216
    end
    if soundId and Sound and Sound.Play then
        Sound.Play(soundId)
    end
end

function Grow.PrepareHarvest(manual)
    if Grow.IsHarvestOpActive() then
        return false
    end
    local ready = GetReadyHarvestPlots()
    if #ready <= 0 then
        return false
    end
    local plotNum = ready[1]
    local last = tonumber(Grow._lastPreparedHarvestPlot) or 0
    if last == plotNum and manual ~= true then
        return true
    end
    local CA = StockPiler4.CultivatorAdapter
    if CA and CA.SetCurrentPlot then
        CA.SetCurrentPlot(plotNum)
    end
    Grow._lastPreparedHarvestPlot = plotNum
    return true
end

function Grow.PrepareHarvestPlot(manual)
    return Grow.PrepareHarvest(manual)
end

function Grow.HarvestClick()
    if not Grow.CanHarvestNow() then
        return false
    end
    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("Grow.HarvestClick")
    end
    Grow.ArmHarvestOpLock(Grow.HARVEST_OP_LOCK_SEC)
    local ok = Grow.PrepareHarvest(true)
    if ok then
        local plotNum = tonumber(Grow._lastPreparedHarvestPlot) or 0
        local CA = StockPiler4.CultivatorAdapter
        if CA and CA.HarvestPlot and plotNum > 0 then
            ok = CA.HarvestPlot(plotNum) == true
        end
    end
    if Perf and Perf.End then
        Perf.End("Grow.HarvestClick")
    end
    return ok == true
end

function Grow.ExecuteHarvest(plotNum, opId)
    plotNum = tonumber(plotNum) or 0
    if plotNum > 0 and StockPiler4.CultivatorAdapter and StockPiler4.CultivatorAdapter.HarvestPlot then
        return StockPiler4.CultivatorAdapter.HarvestPlot(plotNum) == true
    end
    return Grow.HarvestNext(opId)
end

function Grow.HarvestNext(opId)
    return Grow.HarvestClick()
end

function Grow.WakeAfterHarvest(plotNum, opts)
    opts = type(opts) == "table" and opts or {}
    local now = NowSec()
    local plantDelay = tonumber(Grow.POST_HARVEST_PLANT_DELAY_SEC) or 0.75
    local Sch = StockPiler4.Scheduler
    local stormFloor = (Sch and tonumber(Sch.HARVEST_STORM_MIN_SEC)) or 1.5
    local stormSec = math.max(plantDelay, stormFloor)
    -- Storm + skip first so any same-frame knowledge/UI path cannot Flatten.
    if Sch and Sch.ArmHarvestStorm then
        Sch.ArmHarvestStorm(stormSec)
    end
    if Sch and Sch.ArmPlantQuiet then
        Sch.ArmPlantQuiet(stormSec)
    end
    if Sch and Sch.SkipPlanThisFrame then
        Sch.SkipPlanThisFrame()
    end
    if Sch and Sch.SkipUiThisFrame then
        Sch.SkipUiThisFrame()
    end
    local quietUntil = now + stormSec
    if quietUntil > (tonumber(Grow._plantQuietUntil) or 0) then
        Grow._plantQuietUntil = quietUntil
    end
    Grow.ClearFillBlocked()
    if opts.soft == true then
        Grow._chatHarvestNeedsForce = true
        if Sch and Sch.WakeAutoGrow then
            Sch.WakeAutoGrow()
        end
        return
    end
    local debounce = tonumber(Grow.HARVEST_FORCE_DEBOUNCE_SEC) or 1.5
    local lastForce = tonumber(Grow._lastHarvestForceAt) or 0
    local doForce = lastForce <= 0 or now <= 0 or (now - lastForce) >= debounce
    if doForce then
        Grow._lastHarvestForceAt = now
        -- Single force plant-queue invalidate across multi-plot wake.
        Grow.InvalidatePlantQueue({ force = true, keepPlanCache = true })
        if Sch and Sch.EnqueuePlanRebuild then
            Sch.EnqueuePlanRebuild()
        end
        if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
            StockPiler4.Refine.MarkRefineDue("harvest")
        end
    end
    Grow._chatHarvestNeedsForce = false
    if Sch and Sch.WakeAutoGrow then
        Sch.WakeAutoGrow()
    end
    -- Extend Cult skill-up pending window after harvest (skill may tick then).
    -- extendOnly: do not start a new attempt if plant-arm pending expired.
    local Rates = StockPiler4.SkillRates
    local Gates = StockPiler4.SkillUpGates
    if Rates and Rates.NoteCultAttempt and Gates and Gates.IsCultEnabled and Gates.IsCultEnabled() then
        local seedUid = 0
        local Garden = StockPiler4.Garden
        if Garden and Garden.GetPlot then
            local plot = Garden.GetPlot(plotNum)
            if type(plot) ~= "table" and Grow.CachedPlot then
                plot = Grow.CachedPlot(plotNum)
            end
            if type(plot) == "table" then
                seedUid = tonumber(plot.seedUid) or 0
                if seedUid <= 0 and type(plot.seed) == "table" then
                    seedUid = tonumber(plot.seed.uniqueID) or 0
                end
            end
        end
        Rates.NoteCultAttempt({ seedUid = seedUid, extendOnly = true })
    end
    LogOnce(
        "harvest-wake-" .. tostring(plotNum or 0),
        string.format("harvest-wake P%s force=%s", tostring(plotNum or "?"), tostring(doForce))
    )
end

function Grow.WakeAfterHarvestChat()
    Grow.WakeAfterHarvest(0, { soft = true })
end

function Grow.ExpireStalePending()
    local now = NowSec()
    local ttl = tonumber(Grow.PENDING_TTL_SEC) or 10
    local grace = tonumber(Grow.PENDING_EMPTY_GRACE_SEC) or 5
    for plotNum, at in pairs(Grow._pendingPlantAt) do
        at = tonumber(at) or 0
        if at > 0 and now > 0 and (now - at) > (ttl + grace) then
            ReleaseCommit(plotNum, false)
            local untilT = now + (tonumber(Grow.UNCONFIRMED_PLANT_COOLDOWN_SEC) or 6)
            Grow._plantFailCooldownUntil[plotNum] = untilT
            local quiet = now + (tonumber(Grow.UNCONFIRMED_GARDEN_QUIET_SEC) or 8)
            if quiet > (tonumber(Grow._plantQuietUntil) or 0) then
                Grow._plantQuietUntil = quiet
            end
        end
    end
    local CC = StockPiler4.CraftChatAdapter
    if CC and CC.ExpireStaleChatMeta then
        CC.ExpireStaleChatMeta()
    end
end

function Grow.OnCultivationUpdated(plotNum)
    plotNum = tonumber(plotNum) or 0
    local row = StockPiler4.Garden and StockPiler4.Garden.GetPlot and StockPiler4.Garden.GetPlot(plotNum)
    local CC = StockPiler4.CraftChatAdapter
    if CC and CC.TryConfirmFromPlot then
        CC.TryConfirmFromPlot(plotNum, row)
    end
    if type(row) == "table" and not IsPlotEmptyRow(row) then
        if (tonumber(Grow._pendingPlant[plotNum]) or 0) > 0 then
            ReleaseCommit(plotNum, true)
        end
    elseif type(row) == "table" and IsPlotEmptyRow(row) then
        if CC and CC.OnSoilStillEmpty then
            CC.OnSoilStillEmpty(plotNum, {})
        end
    end
    Grow.MaybeNotifyHarvestReady()
end

----------------------------------------------------------------
-- Dump
----------------------------------------------------------------

function Grow.DumpDiagnostics(emit)
    emit = type(emit) == "function" and emit or function(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    emit("=== grow plan ===")
    emit("enabled=" .. tostring(Grow.IsEnabled()))
    emit("fillBlocked=" .. tostring(Grow.IsFillBlocked())
        .. " wait=" .. tostring(Grow._plantWaitTicks or 0))
    emit("emptyPlot=" .. tostring(Grow.HasEmptyPlot())
        .. " seeds=" .. tostring(Grow.HasSeedsForNextPlant()))
    emit("bufferSatisfied=" .. tostring(Grow.IsSeedBufferSatisfied())
        .. " pendingRefine=" .. tostring(Grow.HasPendingBufferRefine())
        .. " bufferShort=" .. tostring(Grow.HasAnyBufferShort()))
    emit("holdHarvestBatch=" .. tostring(Grow.ShouldHoldPlantForReadyHarvest())
        .. " canHarvest=" .. tostring(Grow.CanHarvestNow()))
    emit("lastPlantedSeedUid=" .. tostring(Grow._lastPlantedSeedUid or 0))
    local job = Grow._cachedPlantJob
    if type(job) == "table" then
        emit(string.format(
            "job seedUid=%s role=%s watch=%s deficit=%s reason=%s mode=%s",
            tostring(job.seedUid),
            tostring(job.role),
            tostring(job.watchKey),
            tostring(job.potionDeficit or job.deficit),
            tostring(job.plantReason),
            tostring(job.pickMode)
        ))
    else
        emit("job=(none)")
    end
    local ready = GetReadyHarvestPlots()
    emit("readyPlots=" .. table.concat(ready, ","))
    emit("=== end grow plan ===")
end

function Grow.DumpGrowPlan(emit)
    Grow.DumpDiagnostics(emit)
end

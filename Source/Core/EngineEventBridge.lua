----------------------------------------------------------------
-- StockPiler4 Core/EngineEventBridge -- SystemData.Events -> stores
-- Host: StockPiler4Window (WindowRegisterEventHandler).
-- UPDATE_PROCESSED: Perf.OnFrame -> ApplySlots -> snapGen ->
-- LearnBridge -> Refine.OnUpdate -> Scheduler.OnUpdate (Orch due).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.EngineEventBridge = StockPiler4.EngineEventBridge or {}

local Bridge = StockPiler4.EngineEventBridge

Bridge._registered = false
Bridge._host = "StockPiler4Window"
Bridge._handlers = Bridge._handlers or {}

StockPiler4.FrameCounter = tonumber(StockPiler4.FrameCounter) or 0

local function Events()
    return SystemData and SystemData.Events
end

local function BusFire(name, payload)
    local B = StockPiler4.EventBus
    if B and B.Fire then
        B.Fire(name, payload)
    end
end

local function HostWindow()
    local host = Bridge._host or "StockPiler4Window"
    if DoesWindowExist and DoesWindowExist(host) then
        return host
    end
    return host
end

local function TrackHandler(eventId, handlerName)
    Bridge._handlers[#Bridge._handlers + 1] = {
        event = eventId,
        handler = handlerName,
    }
end

local function CoalesceSlots(pendingList, pendingSet, updatedSlots)
    if type(updatedSlots) ~= "table" then
        return
    end
    local n = 0
    for _, v in ipairs(updatedSlots) do
        local slot = tonumber(v) or 0
        if slot > 0 and pendingSet[slot] ~= true then
            pendingSet[slot] = true
            pendingList[#pendingList + 1] = slot
            n = n + 1
        end
    end
    if n > 0 then
        return
    end
    for k, v in pairs(updatedSlots) do
        local slot = tonumber(k)
        if slot == nil or slot <= 0 then
            slot = tonumber(v) or 0
        end
        if slot > 0 and pendingSet[slot] ~= true then
            pendingSet[slot] = true
            pendingList[#pendingList + 1] = slot
        end
    end
end

local function ApplyInventorySlots(bagKind, slots, reason)
    local Inv = StockPiler4.Inventory
    if not Inv then
        return
    end
    if type(slots) == "table" and #slots > 0 and Inv.ApplySlotUpdates then
        Inv.ApplySlotUpdates(bagKind, slots, reason)
    elseif Inv.MarkDirty then
        Inv.MarkDirty({ reason = reason, full = true })
    end
end

function Bridge.OnInventoryUpdated(updatedSlots)
    Bridge._pendingMainSlots = Bridge._pendingMainSlots or {}
    Bridge._pendingMainSlotSet = Bridge._pendingMainSlotSet or {}
    CoalesceSlots(Bridge._pendingMainSlots, Bridge._pendingMainSlotSet, updatedSlots)
    Bridge._pendingMainApply = true
end

function Bridge.OnCraftingSlotUpdated(updatedSlots)
    Bridge._pendingCraftSlots = Bridge._pendingCraftSlots or {}
    Bridge._pendingCraftSlotSet = Bridge._pendingCraftSlotSet or {}
    CoalesceSlots(Bridge._pendingCraftSlots, Bridge._pendingCraftSlotSet, updatedSlots)
    Bridge._pendingCraftApply = true
    local Grow = StockPiler4.Grow
    if Grow and Grow.NeedsCurrentStageAdditive and Grow.NeedsCurrentStageAdditive()
        and StockPiler4.Scheduler and StockPiler4.Scheduler.WakeAutoGrow
    then
        StockPiler4.Scheduler.WakeAutoGrow()
    end
end

function Bridge.FlushPendingMainSlots()
    if Bridge._pendingMainApply ~= true then
        return false
    end
    Bridge._pendingMainApply = false
    local slots = Bridge._pendingMainSlots
    Bridge._pendingMainSlots = {}
    Bridge._pendingMainSlotSet = {}
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("Inv.ApplySlots")
    end
    ApplyInventorySlots("main", slots, "engine-inventory")
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("Inv.ApplySlots")
    end
    return true
end

function Bridge.FlushPendingCraftSlots()
    if Bridge._pendingCraftApply ~= true then
        return false
    end
    Bridge._pendingCraftApply = false
    local slots = Bridge._pendingCraftSlots
    Bridge._pendingCraftSlots = {}
    Bridge._pendingCraftSlotSet = {}
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("Inv.ApplySlots")
    end
    ApplyInventorySlots("craft", slots, "engine-crafting-slot")
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("Inv.ApplySlots")
    end
    return true
end

function Bridge.OnCraftingUpdated()
    if StockPiler4.LearnBridge and StockPiler4.LearnBridge.OnCraftingUpdated then
        StockPiler4.LearnBridge.OnCraftingUpdated()
    end
    if StockPiler4.Brew and StockPiler4.Brew.OnCraftingUpdated then
        StockPiler4.Brew.OnCraftingUpdated()
    end
    local Bus = StockPiler4.EventBus
    if Bus and Bus.FireFooterDirty then
        Bus.FireFooterDirty()
    end
end

function Bridge.OnCultivationUpdated()
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("CultivationUpdated")
    end
    local plotNum = 0
    if GameData and GameData.Player and GameData.Player.Cultivation then
        plotNum = tonumber(GameData.Player.Cultivation.UpdatedIndex) or 0
    end
    -- Harvest macro op-lock: arm storm before Garden dirty fans out so
    -- OnGardenDirty / Watch flush cannot sync Planner.Build this frame.
    local Grow = StockPiler4.Grow
    local Sch = StockPiler4.Scheduler
    -- Always hold Watch paint on cult updates (plot storms pile RefreshWatch).
    if Sch and Sch.SkipUiThisFrame then
        Sch.SkipUiThisFrame()
    end
    if Sch and Sch.SkipPlanThisFrame then
        Sch.SkipPlanThisFrame()
    end
    if Grow and Grow.IsHarvestOpActive and Grow.IsHarvestOpActive() == true then
        if Sch and Sch.ArmHarvestStorm then
            Sch.ArmHarvestStorm()
        end
    end
    -- Always arm plant quiet on ANY CultivationUpdated (soil/water/nutrient after
    -- pending clear still piled Footer/RefreshWatch when gated on cultBusy only).
    if Sch and Sch.ArmPlantQuiet then
        Sch.ArmPlantQuiet()
    end
    if StockPiler4.Garden and StockPiler4.Garden.OnCultivationUpdated then
        StockPiler4.Garden.OnCultivationUpdated(plotNum)
    elseif StockPiler4.Garden and StockPiler4.Garden.SyncAll then
        StockPiler4.Garden.SyncAll()
    end
    if StockPiler4.Grow and StockPiler4.Grow.OnCultivationUpdated then
        StockPiler4.Grow.OnCultivationUpdated(plotNum)
    end
    if StockPiler4.LearnBridge and StockPiler4.LearnBridge.OnCultivationUpdated then
        StockPiler4.LearnBridge.OnCultivationUpdated()
    end
    -- Never Footer on cult frames — quiet holds coalesce until quiet-end.
    local storm = Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true
    if Grow and Grow.NeedsCurrentStageAdditive and Grow.NeedsCurrentStageAdditive()
        and Sch and Sch.SetAutoGrowIdle
        and not storm
    then
        -- Fast ticks for next additive; Quiet already holds plan/UI.
        Sch.SetAutoGrowIdle(false)
    end
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("CultivationUpdated")
    end
end

function Bridge.OnTradeSkillUpdated()
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.MarkTradeSkillsReady then
        Caps.MarkTradeSkillsReady()
    end
    local cult = Caps and Caps.GetCultSkill and Caps.GetCultSkill() or 0
    local apo = Caps and Caps.GetApoSkill and Caps.GetApoSkill() or 0
    local levelsHash = Caps and Caps.LevelsHash and Caps.LevelsHash()
        or (tostring(cult) .. ":" .. tostring(apo))
    local prevHash = Bridge._skillLevelsHash
    local hashChanged = prevHash ~= levelsHash
    local firstSkillsReady = Bridge._skillsWereReady ~= true
        and (cult > 0 or apo > 0)
    Bridge._skillLevelsHash = levelsHash
    if cult > 0 or apo > 0 then
        Bridge._skillsWereReady = true
    end
    -- Cult often arrives one TRADE_SKILL_UPDATED before Apo. Scrubbing potion
    -- watches while apo still reads 0 was wiping every marked L1–L200 watch.
    if apo > 0 then
        Bridge._apoSkillSeen = true
    end
    if cult > 0 then
        Bridge._cultSkillSeen = true
    end

    local prev = Bridge._skillPrev
    if type(prev) ~= "table" then
        Bridge._skillPrev = { cult = cult, apo = apo }
        hashChanged = true
    else
        local dCult = cult - (tonumber(prev.cult) or cult)
        local dApo = apo - (tonumber(prev.apo) or apo)
        prev.cult = cult
        prev.apo = apo
        -- Logout / char switch: ignore large negative jumps.
        if dCult <= -5 or dApo <= -5 then
            if Caps and Caps.ResetTradeSkillsReady then
                Caps.ResetTradeSkillsReady()
            end
            Bridge._skillsWereReady = false
            Bridge._apoSkillSeen = false
            Bridge._cultSkillSeen = false
            Bridge._skillLevelsHash = nil
            Bridge._skillPrev = nil
            return
        end
        local Rates = StockPiler4.SkillRates
        if dCult > 0 and Rates and Rates.OnCultSkillDelta then
            Rates.OnCultSkillDelta(dCult)
        end
        if dApo > 0 and Rates and Rates.OnApoSkillDelta then
            Rates.OnApoSkillDelta(dApo)
        end

    end

    if hashChanged or firstSkillsReady then
        -- Defer over-skill scrub until the skill we need has been observed.
        -- DisableOverSkillWatches itself also no-ops potion/plant sides at 0.
        local canScrub = (Bridge._apoSkillSeen == true) or (Bridge._cultSkillSeen == true)
        if canScrub and StockPiler4.Watch and StockPiler4.Watch.DisableOverSkillWatches then
            StockPiler4.Watch.DisableOverSkillWatches({ notify = firstSkillsReady and apo > 0 })
        end
        if StockPiler4.Scheduler and StockPiler4.Scheduler.EnqueuePlanRebuild then
            StockPiler4.Scheduler.EnqueuePlanRebuild()
        end
        if StockPiler4TabWatch and StockPiler4TabWatch.RefreshSkillGates then
            -- Force gate key rebuild (cult/apo visibility just changed).
            StockPiler4TabWatch._skillGatesKey = nil
            StockPiler4TabWatch.RefreshSkillGates()
        end
        if StockPiler4TabPotions and StockPiler4TabPotions.UpdateRows then
            StockPiler4TabPotions.UpdateRows()
        end
        if StockPiler4TabPlants and StockPiler4TabPlants.UpdateRows then
            StockPiler4TabPlants.UpdateRows()
        end
        local Bus = StockPiler4.EventBus
        if Bus and Bus.FireFooterDirty then
            Bus.FireFooterDirty()
        end
        if firstSkillsReady and cult > 0
            and StockPiler4.Scheduler and StockPiler4.Scheduler.WakeAutoGrow
        then
            StockPiler4.Scheduler.WakeAutoGrow()
        end
        if StockPiler4.Debug and StockPiler4.Debug.LogOp then
            StockPiler4.Debug.LogOp("caps", string.format(
                "trade-skill-updated cult=%d apo=%d first=%s",
                cult, apo, tostring(firstSkillsReady)
            ))
        end
    end
end

--- Trainer / interact closed: GameData may update a tick after TRADE_SKILL_UPDATED.
function Bridge.OnInteractDone()
    Bridge.OnTradeSkillUpdated()
end

function Bridge.OnStoreShow()
    if StockPiler4.VendorAdapter then
        if StockPiler4.VendorAdapter.EnsureStoreHook then
            StockPiler4.VendorAdapter.EnsureStoreHook()
        end
        if StockPiler4.VendorAdapter.OnStoreShow then
            StockPiler4.VendorAdapter.OnStoreShow()
        end
    end
    if StockPiler4.Buy and StockPiler4.Buy.OnStoreShow then
        StockPiler4.Buy.OnStoreShow()
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.WakeAutoBuy then
        StockPiler4.Scheduler.WakeAutoBuy()
    end
end

function Bridge.OnLoadingEnd()
    if StockPiler4.TradeSkillCaps and StockPiler4.TradeSkillCaps.ResetTradeSkillsReady then
        StockPiler4.TradeSkillCaps.ResetTradeSkillsReady()
    end
    Bridge._skillLevelsHash = nil
    Bridge._skillPrev = nil
    Bridge._skillsWereReady = false
    Bridge._apoSkillSeen = false
    Bridge._cultSkillSeen = false
    local Sch = StockPiler4.Scheduler
    -- Defer SyncAll + skip plan/UI this frame so SESSION_LOADED cannot pile
    -- CultivationUpdated x4 with Planner.Build / RefreshWatch (10s hitch).
    if Sch and Sch.SkipPlanThisFrame then
        Sch.SkipPlanThisFrame()
    end
    if Sch and Sch.SkipUiThisFrame then
        Sch.SkipUiThisFrame()
    end
    if StockPiler4.Garden then
        if StockPiler4.Garden.MarkSyncAllDue then
            StockPiler4.Garden.MarkSyncAllDue()
        elseif StockPiler4.Garden._syncAllDue ~= nil then
            StockPiler4.Garden._syncAllDue = true
        elseif StockPiler4.Garden.SyncAll then
            StockPiler4.Garden.SyncAll()
        end
    end
    if StockPiler4.Inventory and StockPiler4.Inventory.ForceFullRefresh then
        StockPiler4.Inventory.ForceFullRefresh()
    elseif StockPiler4.Inventory and StockPiler4.Inventory.MarkDirty then
        StockPiler4.Inventory.MarkDirty({ reason = "loading-end", full = true })
    end
    local E = StockPiler4.Events
    if E and E.SESSION_LOADED then
        BusFire(E.SESSION_LOADED, { reason = "loading-end" })
    end
end

function Bridge.OnCombatFlagUpdated()
    -- Light: combat pause is consulted on Orch plant path; dirty footer readiness only.
    local Bus = StockPiler4.EventBus
    if Bus and Bus.FireFooterDirty then
        Bus.FireFooterDirty()
    end
end

function Bridge.OnUpdateProcessed(timeElapsed)
    if Bridge._inUpdate == true then
        return
    end
    Bridge._inUpdate = true
    local ok, err = pcall(function()
        StockPiler4.FrameCounter = (tonumber(StockPiler4.FrameCounter) or 0) + 1

        -- Perf.OnFrame first when in-addon hitch logger (LibPerf sets Available=true).
        local Perf = StockPiler4.Perf
        if Perf and Perf.OnFrame and Perf.Available ~= true then
            Perf.OnFrame(timeElapsed)
        end

        if StockPiler4.Garden and StockPiler4.Garden.FlushPendingSyncAll then
            StockPiler4.Garden.FlushPendingSyncAll()
        end

        -- Coalesced Inv.ApplySlots (main + craft)
        Bridge.FlushPendingMainSlots()
        Bridge.FlushPendingCraftSlots()

        -- Flush pending snapGen
        if StockPiler4.Inventory and StockPiler4.Inventory.FlushPendingSnapGen then
            StockPiler4.Inventory.FlushPendingSnapGen()
        end

        -- LearnBridge drain
        if StockPiler4.LearnBridge and StockPiler4.LearnBridge.OnUpdateProcessed then
            StockPiler4.LearnBridge.OnUpdateProcessed()
        end

        -- Refine OnUpdate
        if StockPiler4.Refine and StockPiler4.Refine.OnUpdateProcessed then
            StockPiler4.Refine.OnUpdateProcessed(timeElapsed)
        elseif StockPiler4.Refine and StockPiler4.Refine.OnUpdate then
            StockPiler4.Refine.OnUpdate(timeElapsed)
        end

        -- Scheduler pump (bag -> FrameWork -> Plan -> Watch UI; Orch tick due)
        if StockPiler4.Scheduler and StockPiler4.Scheduler.OnUpdate then
            StockPiler4.Scheduler.OnUpdate(timeElapsed)
        end

        -- Coalesced macro enable sync (footer/cultivation storms).
        if StockPiler4.Macro and StockPiler4.Macro.DrainEnabledSync then
            StockPiler4.Macro.DrainEnabledSync()
        end

        -- Footer after Scheduler so SkipUiHoldFooter can hold this frame.
        local Sch = StockPiler4.Scheduler
        local holdFooter = Sch and Sch.SkipUiHoldFooter and Sch.SkipUiHoldFooter() == true
        if not holdFooter and Sch and Sch.FlushPendingFooterRefresh then
            Sch.FlushPendingFooterRefresh()
        end
        if Sch and Sch.ClearSkipUiHoldFooter then
            Sch.ClearSkipUiHoldFooter()
        end
    end)
    Bridge._inUpdate = false
    if ok ~= true and StockPiler4.Debug and StockPiler4.Debug.ReportProtectedCallFailure then
        StockPiler4.Debug.ReportProtectedCallFailure("Bridge.OnUpdateProcessed", err, true)
    end
end

local function RegisterOne(ev, eventKey, handlerName)
    local eventId = ev[eventKey]
    if eventId == nil then
        return
    end
    local host = HostWindow()
    if type(WindowRegisterEventHandler) == "function" then
        WindowRegisterEventHandler(host, eventId, handlerName)
        TrackHandler(eventId, handlerName)
    elseif type(RegisterEventHandler) == "function" then
        RegisterEventHandler(eventId, handlerName)
        TrackHandler(eventId, handlerName)
    end
end

function Bridge.Register()
    if Bridge._registered == true then
        return
    end
    local ev = Events()
    if type(ev) ~= "table" then
        return
    end
    Bridge._handlers = {}
    local prefix = "StockPiler4.EngineEventBridge."
    RegisterOne(ev, "PLAYER_INVENTORY_SLOT_UPDATED", prefix .. "OnInventoryUpdated")
    RegisterOne(ev, "PLAYER_CRAFTING_SLOT_UPDATED", prefix .. "OnCraftingSlotUpdated")
    RegisterOne(ev, "PLAYER_CRAFTING_UPDATED", prefix .. "OnCraftingUpdated")
    RegisterOne(ev, "PLAYER_CULTIVATION_UPDATED", prefix .. "OnCultivationUpdated")
    RegisterOne(ev, "TRADE_SKILL_UPDATED", prefix .. "OnTradeSkillUpdated")
    RegisterOne(ev, "INTERACT_DONE", prefix .. "OnInteractDone")
    RegisterOne(ev, "LOADING_END", prefix .. "OnLoadingEnd")
    RegisterOne(ev, "INTERACT_SHOW_STORE", prefix .. "OnStoreShow")
    RegisterOne(ev, "UPDATE_PROCESSED", prefix .. "OnUpdateProcessed")
    RegisterOne(ev, "PLAYER_COMBAT_FLAG_UPDATED", prefix .. "OnCombatFlagUpdated")
    Bridge._registered = true
    if StockPiler4.Debug and StockPiler4.Debug.LogAlways then
        StockPiler4.Debug.LogAlways("init engine event bridge registered")
    end
end

function Bridge.Unregister()
    if Bridge._registered ~= true then
        return
    end
    local host = HostWindow()
    local handlers = Bridge._handlers
    if type(handlers) == "table" then
        for i = 1, #handlers do
            local entry = handlers[i]
            if type(entry) == "table" and entry.event ~= nil and entry.handler then
                if type(WindowUnregisterEventHandler) == "function" then
                    WindowUnregisterEventHandler(host, entry.event)
                elseif type(UnregisterEventHandler) == "function" then
                    UnregisterEventHandler(entry.event, entry.handler)
                end
            end
        end
    end
    Bridge._handlers = {}
    Bridge._registered = false
    Bridge._pendingMainApply = false
    Bridge._pendingCraftApply = false
    Bridge._pendingMainSlots = nil
    Bridge._pendingCraftSlots = nil
    Bridge._pendingMainSlotSet = nil
    Bridge._pendingCraftSlotSet = nil
end

function Bridge.Initialize()
    Bridge.Register()
end

function Bridge.Shutdown()
    Bridge.Unregister()
end

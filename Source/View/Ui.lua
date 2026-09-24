----------------------------------------------------------------
-- StockPiler4 View/Ui -- window show/hide + coalesced Watch flush
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Ui = StockPiler4.Ui or {}
local Ui = StockPiler4.Ui

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

Ui.WATCH_UI_MIN_INTERVAL_SEC = 5.0
Ui.BREW_WATCH_CATCHUP_SEC = 1.0
Ui._watchUiDirty = false
Ui._watchUiFlushedAt = 0
Ui._watchUiBrewCatchupAt = 0
Ui._watchUiLastKey = nil
Ui._watchUiLastKnowledgeGen = 0
Ui._watchUiLastPlanGen = 0
Ui._watchUiLastBrewKey = nil

function Ui.Print(msg)
    if StockPiler4.Debug and StockPiler4.Debug.Print then
        StockPiler4.Debug.Print(msg)
    end
end

function Ui.ToggleWindow()
    if not DoesWindowExist("StockPiler4Window") then
        Ui.Print(T("ui.window_missing"))
        return
    end
    if WindowUtils and WindowUtils.ToggleShowing then
        WindowUtils.ToggleShowing("StockPiler4Window")
        return
    end
    local showing = WindowGetShowing("StockPiler4Window") == true
    WindowSetShowing("StockPiler4Window", not showing)
end

function Ui.ShowWindow(tabId)
    if not DoesWindowExist("StockPiler4Window") then
        return
    end
    WindowSetShowing("StockPiler4Window", true)
    if tabId and StockPiler4Window and StockPiler4Window.SelectTab then
        StockPiler4Window.SelectTab(tabId)
    end
end

local function CurrentPlanGen()
    if StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get then
        local plan = StockPiler4.PlanSnapshot.Get()
        if type(plan) == "table" then
            return tonumber(plan.planGen) or 0
        end
    end
    return 0
end

local function BrewChromeKey()
    local Brew = StockPiler4.Brew
    if not Brew or not Brew.GetSession then
        return "idle"
    end
    local session = Brew.GetSession()
    if type(session) ~= "table" then
        return "idle"
    end
    return tostring(session.phase or "idle")
        .. ":" .. tostring(session.potionRecipeKey or session.potionKey or "")
        .. ":" .. tostring(session.rowId or "")
        .. ":" .. tostring(Brew._loadSource or "")
end

local function WatchContentKey()
    local snapGen = 0
    if StockPiler4.Inventory and StockPiler4.Inventory.GetSnapGen then
        snapGen = tonumber(StockPiler4.Inventory.GetSnapGen()) or 0
    end
    local planGen = CurrentPlanGen()
    local knowledgeGen = 0
    if StockPiler4.Knowledge and StockPiler4.Knowledge.GetGen then
        knowledgeGen = tonumber(StockPiler4.Knowledge.GetGen()) or 0
    end
    local watchGen = 0
    if StockPiler4.Watch and StockPiler4.Watch.GetGen then
        watchGen = tonumber(StockPiler4.Watch.GetGen()) or 0
    end
    local autoGrowOn = false
    if StockPiler4.Watch and StockPiler4.Watch.IsAutoGrowEnabled then
        autoGrowOn = StockPiler4.Watch.IsAutoGrowEnabled() == true
    end
    return tostring(snapGen)
        .. ":" .. tostring(planGen)
        .. ":" .. tostring(knowledgeGen)
        .. ":" .. tostring(watchGen)
        .. ":" .. tostring(autoGrowOn)
        .. ":" .. BrewChromeKey()
end

local function IsWatchPlanStale()
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.IsPlanRebuildPending and Sch.IsPlanRebuildPending() == true then
        return true
    end
    local Planner = StockPiler4.Planner
    if not Planner or not Planner.CacheKeyFromGens then
        return false
    end
    local wantKey = Planner.CacheKeyFromGens()
    local plan = StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get and StockPiler4.PlanSnapshot.Get()
    if type(plan) ~= "table" then
        return false
    end
    return tostring(plan.cacheKey or "") ~= tostring(wantKey or "")
end

--- Hold Watch paint during harvest storm, refine outstanding, buffer refine,
--- AutoBuy visit, or FrameWork busy. Session settle only defers while the
--- window is closed (open must paint immediately — settle used to leave
--- footer Harvest/Brew overlapping Clear Watches for ~2.5s).
local function ShouldDeferWatchFlush()
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.SkipUiThisFrameActive and Sch.SkipUiThisFrameActive() == true then
        return true
    end
    if Sch and Sch._skipUiThisFrame == true then
        return true
    end
    local windowOpen = DoesWindowExist("StockPiler4Window")
        and WindowGetShowing("StockPiler4Window") == true
    if not windowOpen
        and Sch and Sch.IsSessionSettling and Sch.IsSessionSettling() == true
    then
        return true
    end
    if Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
        return true
    end
    if Sch and Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
        return true
    end
    if Sch and Sch.IsPlanRebuildPending and Sch.IsPlanRebuildPending() == true then
        return true
    end
    local FW = StockPiler4.FrameWork
    if FW and FW.Busy and FW.Busy() == true then
        return true
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() == true then
        return true
    end
    -- Peek only: HasPendingBufferRefine rebuilds BufferFlags after every snap invalidate.
    local Refine = StockPiler4.Refine
    if Refine and Refine.PeekCachedBufferPending and Refine.PeekCachedBufferPending() == true then
        return true
    end
    local Buy = StockPiler4.Buy
    local VA = StockPiler4.VendorAdapter
    if Buy and Buy.IsEnabled and Buy.IsEnabled() == true
        and VA and VA.IsStoreOpen and VA.IsStoreOpen() == true
    then
        return true
    end
    return false
end

function Ui.ClearWatchTipCaches()
    if StockPiler4TabWatch then
        StockPiler4TabWatch._statusTipCache = nil
        StockPiler4TabWatch._seedBufferTipCache = nil
    end
end

function Ui.MarkWatchUiDirty()
    Ui._watchUiDirty = true
end

function Ui.RequestFooterRefresh()
    if StockPiler4Window and StockPiler4Window.RequestFooterRefresh then
        StockPiler4Window.RequestFooterRefresh()
    end
end

function Ui.FlushPendingFooterRefresh()
    if StockPiler4Window and StockPiler4Window.FlushPendingFooterRefresh then
        StockPiler4Window.FlushPendingFooterRefresh()
    end
end

local function OnFooterDirty(payload)
    Ui.RequestFooterRefresh()
    if type(payload) ~= "table" or payload.immediate ~= true then
        return
    end
    if StockPiler4Window and StockPiler4Window.SyncActionReadiness then
        StockPiler4Window.SyncActionReadiness({ immediate = true })
    elseif payload.syncMacro == true then
        local Brew = StockPiler4.Brew
        if StockPiler4.Macro and StockPiler4.Macro.RefreshMacroButtonAppearance then
            StockPiler4.Macro.RefreshMacroButtonAppearance({
                canBrew = Brew and Brew.CanBrewNow and Brew.CanBrewNow() == true,
            })
        end
    end
end

function Ui.RefreshIfOpen(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.force ~= true then
        Ui.MarkWatchUiDirty()
        return
    end
    if DoesWindowExist("StockPiler4Window")
        and WindowGetShowing("StockPiler4Window") == true
        and StockPiler4Window
        and StockPiler4Window.RefreshActiveTab
    then
        StockPiler4Window.RefreshActiveTab()
    end
end

function Ui.FlushWatchUiIfDirty()
    if Ui._watchUiDirty ~= true then
        return
    end
    local windowOpen = DoesWindowExist("StockPiler4Window")
        and WindowGetShowing("StockPiler4Window") == true
    -- Ready wake must run even while AutoBuy visit defers full Watch paint
    -- (flask fills clear Shared/Buy-flasks without a potion craftable delta).
    local function WakeReadyFromLiveStatus()
        if StockPiler4.Planner and StockPiler4.Planner.SyncLiveStatusClosedWindow then
            StockPiler4.Planner.SyncLiveStatusClosedWindow()
        elseif StockPiler4.Brew and StockPiler4.Brew.SyncLiveStatusClosedWindow then
            StockPiler4.Brew.SyncLiveStatusClosedWindow()
        end
        if StockPiler4.Brew and StockPiler4.Brew.MaybeNotifyBrewReady then
            StockPiler4.Brew.MaybeNotifyBrewReady()
        end
    end
    if not windowOpen then
        WakeReadyFromLiveStatus()
        if ShouldDeferWatchFlush() then
            return
        end
        -- Closed-window: Ready wake done; keep dirty for next open paint.
        return
    end
    if ShouldDeferWatchFlush() then
        WakeReadyFromLiveStatus()
        -- While settle/prewarm holds full paint, kill the white ListBox flash.
        if StockPiler4TabWatch and StockPiler4TabWatch.PrimeRowChrome then
            StockPiler4TabWatch.PrimeRowChrome()
        end
        return
    end

    local Orch = StockPiler4.Orchestrator
    local brewSessionActive = Orch and Orch.IsBrewSessionActive and Orch.IsBrewSessionActive() == true
    -- Mid-brew: hold full RefreshWatch; chrome via ForceBrewUiRefresh; ~1s Stock/Status catch-up.
    if brewSessionActive then
        local brewKey = BrewChromeKey()
        local brewChanged = brewKey ~= tostring(Ui._watchUiLastBrewKey or "")
        local now = 0
        if type(GetGameTime) == "function" then
            now = tonumber(GetGameTime()) or 0
        end
        if brewChanged then
            Ui._watchUiLastBrewKey = brewKey
            if StockPiler4TabWatch and StockPiler4TabWatch.UpdateRows then
                StockPiler4TabWatch.UpdateRows()
            end
            -- Keep dirty so a full flush runs when the session ends.
            return
        end
        local catchupSec = tonumber(Ui.BREW_WATCH_CATCHUP_SEC) or 1.0
        local lastCatchup = tonumber(Ui._watchUiBrewCatchupAt) or 0
        if lastCatchup > 0 and (now - lastCatchup) < catchupSec then
            return
        end
        Ui._watchUiBrewCatchupAt = now
        local Sch = StockPiler4.Scheduler
        if Sch and Sch.EnqueuePlanRebuild then
            if StockPiler4.Perf and StockPiler4.Perf.Begin then
                StockPiler4.Perf.Begin("UiFlush.BrewCatchup")
            end
            Sch.EnqueuePlanRebuild({ nudge = true })
            if StockPiler4TabWatch and StockPiler4TabWatch.UpdateRows then
                StockPiler4TabWatch.UpdateRows()
            end
            if StockPiler4.Perf and StockPiler4.Perf.End then
                StockPiler4.Perf.End("UiFlush.BrewCatchup")
            end
        end
        -- Keep dirty for post-session full Watch refresh.
        return
    end

    local knowledgeGen = 0
    if StockPiler4.Knowledge and StockPiler4.Knowledge.GetGen then
        knowledgeGen = tonumber(StockPiler4.Knowledge.GetGen()) or 0
    end
    local planGen = CurrentPlanGen()
    local brewKey = BrewChromeKey()
    local contentKey = WatchContentKey()
    local planChanged = planGen ~= (tonumber(Ui._watchUiLastPlanGen) or 0)
    -- Plan status can change without stock/craftable deltas; never skip when planGen moved.
    if Ui._watchUiLastKey == contentKey and not planChanged then
        Ui._watchUiDirty = false
        return
    end
    local now = 0
    if type(GetGameTime) == "function" then
        now = tonumber(GetGameTime()) or 0
    end
    local last = tonumber(Ui._watchUiFlushedAt) or 0
    local knowledgeChanged = knowledgeGen ~= (tonumber(Ui._watchUiLastKnowledgeGen) or 0)
    local brewChanged = brewKey ~= tostring(Ui._watchUiLastBrewKey or "")
    local interval = Ui.WATCH_UI_MIN_INTERVAL_SEC
    if not knowledgeChanged and not planChanged and not brewChanged and IsWatchPlanStale() then
        interval = math.min(interval, 1.0)
    end
    if not knowledgeChanged
        and not planChanged
        and not brewChanged
        and last > 0
        and (now - last) < interval
    then
        return
    end

    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("UiFlush")
    end
    Ui._watchUiDirty = false
    Ui._watchUiFlushedAt = now
    Ui._watchUiBrewCatchupAt = 0
    Ui._watchUiLastKey = contentKey
    Ui._watchUiLastKnowledgeGen = knowledgeGen
    Ui._watchUiLastPlanGen = planGen
    Ui._watchUiLastBrewKey = brewKey
    if StockPiler4Window and StockPiler4Window.RefreshActiveTab then
        StockPiler4Window.RefreshActiveTab()
    end
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("UiFlush")
    end
    return true
end

function Ui.InitializeWindow()
    if StockPiler4Window and StockPiler4Window.Initialize then
        StockPiler4Window.Initialize()
    end
end

function Ui.RegisterEventRefresh()
    if Ui._eventsRegistered == true then
        return
    end
    local B = StockPiler4.EventBus
    local E = StockPiler4.Events
    if not B or not E then
        return
    end
    Ui._busTokens = Ui._busTokens or {}
    local tokens = Ui._busTokens
    local function track(token)
        if token then
            tokens[#tokens + 1] = token
        end
    end
    local function markDirty()
        Ui.MarkWatchUiDirty()
    end
    track(B.Subscribe(E.PLAN_UPDATED, function()
        Ui.ClearWatchTipCaches()
        Ui.MarkWatchUiDirty()
        Ui.RequestFooterRefresh()
    end))
    track(B.Subscribe(E.PLAN_INVALIDATED, markDirty))
    track(B.Subscribe(E.INVENTORY_SNAPSHOT, markDirty))
    track(B.Subscribe(E.GARDEN_SNAPSHOT, markDirty))
    if E.GARDEN_DIRTY then
        track(B.Subscribe(E.GARDEN_DIRTY, markDirty))
    end
    if E.CRAFT_READY_CHANGED then
        track(B.Subscribe(E.CRAFT_READY_CHANGED, function()
            Ui.RequestFooterRefresh()
            Ui.MarkWatchUiDirty()
        end))
    end
    if E.FOOTER_DIRTY then
        track(B.Subscribe(E.FOOTER_DIRTY, OnFooterDirty))
    end
    if E.KNOWLEDGE_UPDATED then
        track(B.Subscribe(E.KNOWLEDGE_UPDATED, function()
            -- Knowledge can land after an inventory flush already painted Potions.
            -- Bypass Watch throttle for the next coalesced flush - never sync paint
            -- (WarmHave used to hide inside WatchRows on the same frame as CultivationUpdated).
            Ui._watchUiLastKey = nil
            Ui._watchUiLastKnowledgeGen = 0
            Ui._watchUiFlushedAt = 0
            Ui.MarkWatchUiDirty()
        end))
    end
    if E.SESSION_LOADED then
        track(B.Subscribe(E.SESSION_LOADED, function()
            if StockPiler4TabWatch and StockPiler4TabWatch.RefreshSkillGates then
                StockPiler4TabWatch.RefreshSkillGates()
            end
            -- Session load: mark dirty only. Sync RefreshActiveTab here caused the
            -- SP2 Flatten hitch (Planner.Build + WarmHave + WatchRows + CultivationUpdated
            -- x4 on the same frame as Garden.SyncAll / first plan rebuild).
            Ui._watchUiLastKey = nil
            Ui._watchUiLastBrewKey = nil
            Ui._watchUiFlushedAt = 0
            Ui._watchUiLastPlanGen = 0
            Ui._watchUiLastKnowledgeGen = 0
            Ui.ClearWatchTipCaches()
            Ui.MarkWatchUiDirty()
        end))
    end
    Ui._eventsRegistered = true
end

function Ui.UnregisterEventRefresh()
    local B = StockPiler4.EventBus
    local tokens = Ui._busTokens
    if B and B.Unsubscribe and type(tokens) == "table" then
        for i = 1, #tokens do
            B.Unsubscribe(tokens[i])
        end
    end
    Ui._busTokens = nil
    Ui._eventsRegistered = false
end

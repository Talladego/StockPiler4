----------------------------------------------------------------
-- StockPiler4Window -- settings-style chrome
----------------------------------------------------------------

StockPiler4Window = {}

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

StockPiler4Window.TABS_POTIONS = 1
StockPiler4Window.TABS_PLANTS = 2
StockPiler4Window.TABS_WATCH = 3
StockPiler4Window.TABS_MAX = 3
StockPiler4Window.SelectedTab = StockPiler4Window.TABS_POTIONS

local CLEAR_WATCHES_WIN = "StockPiler4WindowClearWatches"
local HARVEST_WIN = "StockPiler4WindowHarvest"
local BREW_WIN = "StockPiler4WindowBrew"

StockPiler4Window.Tabs = {
    [1] = {
        window = "SP4TabPotions",
        name = "StockPiler4WindowTabButtonsPotions",
        labelKey = "ui.tab_potions",
        refresh = function()
            if StockPiler4TabPotions and StockPiler4TabPotions.Refresh then
                StockPiler4TabPotions.Refresh()
            end
        end,
    },
    [2] = {
        window = "SP4TabPlants",
        name = "StockPiler4WindowTabButtonsPlants",
        labelKey = "ui.tab_plants",
        refresh = function()
            if StockPiler4TabPlants and StockPiler4TabPlants.Refresh then
                StockPiler4TabPlants.Refresh()
            end
        end,
    },
    [3] = {
        window = "SP4TabWatch",
        name = "StockPiler4WindowTabButtonsWatch",
        labelKey = "ui.tab_watch",
        refresh = function()
            if StockPiler4TabWatch and StockPiler4TabWatch.Refresh then
                StockPiler4TabWatch.Refresh()
            end
        end,
    },
}

function StockPiler4Window.OnInitialize()
    local selected = StockPiler4Window.SelectedTab or StockPiler4Window.TABS_POTIONS
    for index, tab in ipairs(StockPiler4Window.Tabs) do
        if DoesWindowExist(tab.window) then
            WindowSetShowing(tab.window, index == selected)
        end
        if DoesWindowExist(tab.name) then
            ButtonSetPressedFlag(tab.name, index == selected)
        end
    end
end

function StockPiler4Window.RequestFooterRefresh()
    StockPiler4Window._footerRefreshPending = true
end

--- Sync Harvest/Brew readiness: macros always; footer chrome only when window is open.
function StockPiler4Window.SyncActionReadiness(opts)
    opts = type(opts) == "table" and opts or {}
    local immediate = opts.immediate == true
    local Perf = StockPiler4.Perf

    local windowOpen = DoesWindowExist("StockPiler4Window")
        and WindowGetShowing("StockPiler4Window") == true
    local onWatch = StockPiler4Window.SelectedTab == StockPiler4Window.TABS_WATCH
    local onPotions = StockPiler4Window.SelectedTab == StockPiler4Window.TABS_POTIONS
    local onPlants = StockPiler4Window.SelectedTab == StockPiler4Window.TABS_PLANTS
    local showClearWatches = onPotions or onPlants

    local canHarvest = StockPiler4.Grow and StockPiler4.Grow.CanHarvestNow
        and StockPiler4.Grow.CanHarvestNow() == true
    local canBrew = StockPiler4.Brew and StockPiler4.Brew.CanBrewNow
        and StockPiler4.Brew.CanBrewNow() == true
    local enabledWatches = 0
    if onPlants then
        if StockPiler4.Watch and StockPiler4.Watch.CountEnabledPlantWatches then
            enabledWatches = tonumber(StockPiler4.Watch.CountEnabledPlantWatches()) or 0
        end
    elseif StockPiler4.Watch and StockPiler4.Watch.CountEnabled then
        enabledWatches = tonumber(StockPiler4.Watch.CountEnabled()) or 0
    end
    local canClearWatches = enabledWatches > 0

    local appearanceKey = tostring(canHarvest) .. ":" .. tostring(canBrew) .. ":"
        .. tostring(canClearWatches) .. ":" .. tostring(showClearWatches)
    local unchanged = StockPiler4Window._footerWindowOpen == windowOpen
        and StockPiler4Window._footerOnWatch == onWatch
        and StockPiler4Window._footerOnPotions == onPotions
        and StockPiler4Window._footerOnPlants == onPlants
        and StockPiler4Window._footerCanHarvest == canHarvest
        and StockPiler4Window._footerCanBrew == canBrew
        and StockPiler4Window._footerCanClearWatches == canClearWatches
    -- `immediate` must re-apply macro tint: ActionButton.UpdateEnabledState greys
    -- our macros mid-craft while CanBrewNow can stay true, so appearanceKey is unchanged.
    if unchanged and not immediate then
        if StockPiler4.Macro == nil
            or StockPiler4.Macro._lastAppearanceKey == nil
            or StockPiler4.Macro._lastAppearanceKey == appearanceKey
        then
            return canHarvest, canBrew
        end
    end

    if Perf and Perf.Begin then
        Perf.Begin("Footer")
    end

    if windowOpen then
        if DoesWindowExist(CLEAR_WATCHES_WIN) then
            WindowSetShowing(CLEAR_WATCHES_WIN, showClearWatches)
            if showClearWatches and ButtonSetDisabledFlag then
                ButtonSetDisabledFlag(CLEAR_WATCHES_WIN, not canClearWatches)
            end
        end
        if DoesWindowExist(HARVEST_WIN) then
            WindowSetShowing(HARVEST_WIN, onWatch)
            if onWatch then
                if StockPiler4.HarvestChrome and StockPiler4.HarvestChrome.SetFooterHarvestClickable then
                    StockPiler4.HarvestChrome.SetFooterHarvestClickable(canHarvest)
                else
                    ButtonSetDisabledFlag(HARVEST_WIN, not canHarvest)
                end
            elseif StockPiler4.HarvestChrome and StockPiler4.HarvestChrome.ClearHarvestActionBound then
                StockPiler4.HarvestChrome.ClearHarvestActionBound()
            end
        end
        if DoesWindowExist(BREW_WIN) then
            WindowSetShowing(BREW_WIN, onWatch)
            if onWatch then
                ButtonSetDisabledFlag(BREW_WIN, not canBrew)
            end
        end
    end

    local prevOnWatch = StockPiler4Window._footerOnWatch
    local prevHarvest = StockPiler4Window._footerCanHarvest
    local prevBrew = StockPiler4Window._footerCanBrew
    StockPiler4Window._footerWindowOpen = windowOpen
    StockPiler4Window._footerOnWatch = onWatch
    StockPiler4Window._footerOnPotions = onPotions
    StockPiler4Window._footerOnPlants = onPlants
    StockPiler4Window._footerCanHarvest = canHarvest
    StockPiler4Window._footerCanBrew = canBrew
    StockPiler4Window._footerCanClearWatches = canClearWatches
    local readinessChanged = prevOnWatch ~= onWatch
        or prevHarvest ~= canHarvest
        or prevBrew ~= canBrew

    if not readinessChanged and StockPiler4.Macro then
        local skipDrift = false
        if StockPiler4.Brew then
            if StockPiler4.Brew.IsBusy and StockPiler4.Brew.IsBusy() == true then
                skipDrift = true
            else
                local session = StockPiler4.Brew.GetSession and StockPiler4.Brew.GetSession()
                if type(session) == "table" and session.phase == "loading" then
                    skipDrift = true
                end
            end
        end
        if not skipDrift then
            if StockPiler4.Macro._lastAppearanceKey ~= nil
                and StockPiler4.Macro._lastAppearanceKey ~= appearanceKey
            then
                readinessChanged = true
            end
        end
    end

    if readinessChanged or immediate then
        if StockPiler4.Macro then
            if immediate and StockPiler4.Macro.RefreshMacroButtonAppearance then
                StockPiler4.Macro._enabledSyncPending = false
                StockPiler4.Macro._pendingCanHarvest = nil
                StockPiler4.Macro._pendingCanBrew = nil
                StockPiler4.Macro.RefreshMacroButtonAppearance({
                    canHarvest = canHarvest,
                    canBrew = canBrew,
                })
            elseif StockPiler4.Macro.RequestEnabledSync then
                StockPiler4.Macro.RequestEnabledSync(canHarvest, canBrew)
            elseif StockPiler4.Macro.SyncEnabledState then
                StockPiler4.Macro.SyncEnabledState(canHarvest, canBrew)
            end
        end
    end

    if Perf and Perf.End then
        Perf.End("Footer")
    end
    return canHarvest, canBrew
end

function StockPiler4Window.FlushPendingFooterRefresh()
    if StockPiler4Window._footerRefreshPending ~= true then
        return
    end
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.SkipUiHoldFooter and Sch.SkipUiHoldFooter() == true then
        return
    end
    if Sch and Sch.IsSessionSettling and Sch.IsSessionSettling() == true then
        return
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.HasOutstanding and RP.HasOutstanding() == true then
        return
    end
    local brewJob = StockPiler4.Brew and type(StockPiler4.Brew._job) == "table"
    if not brewJob then
        if Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then
            return
        end
        if Sch and Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then
            return
        end
    end
    StockPiler4Window._footerRefreshPending = false
    StockPiler4Window.SyncActionReadiness()
    if StockPiler4.HarvestTooltip and StockPiler4.HarvestTooltip.TickLive then
        StockPiler4.HarvestTooltip.TickLive()
    end
    if StockPiler4.BrewTooltip and StockPiler4.BrewTooltip.TickLive then
        StockPiler4.BrewTooltip.TickLive()
    end
    if StockPiler4.CraftTooltip and StockPiler4.CraftTooltip.TickLive then
        StockPiler4.CraftTooltip.TickLive()
    end
end

function StockPiler4Window.RefreshFooterButtons()
    StockPiler4Window.RequestFooterRefresh()
end

function StockPiler4Window.Initialize()
    if not DoesWindowExist("StockPiler4Window") then
        return
    end
    local version = StockPiler4.Version or L""
    if version ~= L"" then
        LabelSetText("StockPiler4WindowTitleBarText", T("ui.title_version", { version = version }))
    else
        LabelSetText("StockPiler4WindowTitleBarText", T("ui.title"))
    end
    if DoesWindowExist(CLEAR_WATCHES_WIN) then
        ButtonSetText(CLEAR_WATCHES_WIN, T("ui.clear_watches"))
    end
    if DoesWindowExist(HARVEST_WIN) then
        ButtonSetText(HARVEST_WIN, T("ui.harvest"))
        if StockPiler4.HarvestChrome and StockPiler4.HarvestChrome.EnsureHarvestActionBound then
            StockPiler4.HarvestChrome.EnsureHarvestActionBound()
        end
    end
    if DoesWindowExist(BREW_WIN) then
        ButtonSetText(BREW_WIN, T("ui.brew"))
    end
    for _, tab in ipairs(StockPiler4Window.Tabs) do
        ButtonSetText(tab.name, T(tab.labelKey))
    end
    -- Defer Watch paint: sync SelectTab->RefreshActiveTab Flattened with WarmHave
    -- inside PatchWatchRowsLiveCounts on the same frame as CultivationUpdated x4.
    StockPiler4Window.SelectTab(StockPiler4Window.SelectedTab, { deferRefresh = true })
end

function StockPiler4Window.RefreshActiveTab()
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("RefreshWatch")
    end
    local tab = StockPiler4Window.Tabs[StockPiler4Window.SelectedTab]
    if tab and tab.refresh then
        tab.refresh()
    end
    StockPiler4Window.RefreshFooterButtons()
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("RefreshWatch")
    end
end

function StockPiler4Window.RequestListRepopulate()
    StockPiler4Window._repopulatePending = true
end

function StockPiler4Window.FlushPendingListRepopulate()
    if StockPiler4Window._repopulatePending ~= true then
        return
    end
    if not DoesWindowExist("StockPiler4Window") then
        return
    end
    if WindowGetShowing("StockPiler4Window") ~= true then
        return
    end
    StockPiler4Window._repopulatePending = false
    if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
        StockPiler4.Ui.MarkWatchUiDirty()
        return
    end
    StockPiler4Window.RefreshActiveTab()
end

function StockPiler4Window.PrimeTabListsIfNeeded()
    if StockPiler4Window._tabListsPrimed == true then
        return
    end
    if not DoesWindowExist("StockPiler4Window") then
        return
    end
    if WindowGetShowing("StockPiler4Window") ~= true then
        return
    end
    StockPiler4Window._tabListsPrimed = true
    local selected = StockPiler4Window.SelectedTab or StockPiler4Window.TABS_POTIONS
    -- Layout only. Never call tab.refresh here — that ran WarmHave inside WatchRows
    -- on the same frame as SelectTab/OnShow (SP2 Flatten).
    for index, tab in ipairs(StockPiler4Window.Tabs) do
        if DoesWindowExist(tab.name) then
            ButtonSetPressedFlag(tab.name, index == selected)
        end
        if DoesWindowExist(tab.window) then
            WindowSetShowing(tab.window, index == selected)
            if index == selected and type(WindowForceProcessAnchors) == "function" then
                if StockPiler4.Debug and StockPiler4.Debug.TryCall then
                    StockPiler4.Debug.TryCall("WindowForceProcessAnchors", WindowForceProcessAnchors, tab.window)
                else
                    pcall(WindowForceProcessAnchors, tab.window)
                end
            end
        end
    end
end

function StockPiler4Window.OnShow()
    WindowUtils.OnShown()
    if StockPiler4.Inventory and StockPiler4.Inventory.RefreshAllIfNeeded then
        StockPiler4.Inventory.RefreshAllIfNeeded({
            force = StockPiler4.Inventory.IsDirty and StockPiler4.Inventory.IsDirty(),
        })
    end
    if StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Invalidate then
        StockPiler4.PlanSnapshot.Invalidate()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.RefreshSkillGates then
        StockPiler4TabWatch.RefreshSkillGates()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.ClearRowPaintCache then
        StockPiler4TabWatch.ClearRowPaintCache()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.PrimeRowChrome then
        StockPiler4TabWatch.PrimeRowChrome()
    end
    StockPiler4Window.PrimeTabListsIfNeeded()
    -- Coalesced paint after FrameWork prewarm + PlanRebuild (never sync Flatten).
    if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
        StockPiler4.Ui.MarkWatchUiDirty()
    else
        StockPiler4Window.RequestListRepopulate()
    end
    StockPiler4Window.RequestFooterRefresh()
end

function StockPiler4Window.OnClose()
    WindowSetShowing("StockPiler4Window", false)
end

function StockPiler4Window.ConfirmClearWatches()
    local onPlants = StockPiler4Window.SelectedTab == StockPiler4Window.TABS_PLANTS
    local n = 0
    if onPlants then
        if StockPiler4.Catalog and StockPiler4.Catalog.ClearPlantWatchList then
            n = tonumber(StockPiler4.Catalog.ClearPlantWatchList()) or 0
        end
        if StockPiler4.Ui and StockPiler4.Ui.Print then
            StockPiler4.Ui.Print(T("ui.plant_watches_cleared", { count = tostring(n) }))
        end
        if StockPiler4TabPlants and StockPiler4TabPlants.Refresh then
            StockPiler4TabPlants.Refresh()
        end
    else
        if StockPiler4.Catalog and StockPiler4.Catalog.ClearWatchList then
            n = tonumber(StockPiler4.Catalog.ClearWatchList()) or 0
        end
        if StockPiler4.Ui and StockPiler4.Ui.Print then
            StockPiler4.Ui.Print(T("ui.watches_cleared", { count = tostring(n) }))
        end
        if StockPiler4TabPotions and StockPiler4TabPotions.Refresh then
            StockPiler4TabPotions.Refresh()
        end
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.Refresh then
        StockPiler4TabWatch.Refresh({ forcePlan = true })
    end
    StockPiler4Window.RefreshFooterButtons()
end

function StockPiler4Window.OnClearWatches()
    local onPlants = StockPiler4Window.SelectedTab == StockPiler4Window.TABS_PLANTS
    local count = 0
    if onPlants then
        if StockPiler4.Watch and StockPiler4.Watch.CountEnabledPlantWatches then
            count = tonumber(StockPiler4.Watch.CountEnabledPlantWatches()) or 0
        end
        if count <= 0 then
            if StockPiler4.Ui and StockPiler4.Ui.Print then
                StockPiler4.Ui.Print(T("ui.no_plant_watches"))
            end
            StockPiler4Window.RefreshFooterButtons()
            return
        end
        StockPiler4.ViewList.ConfirmTwoButton(
            T("ui.clear_plant_watches_confirm", { count = tostring(count) }),
            StockPiler4Window.ConfirmClearWatches
        )
        return
    end
    if StockPiler4.Watch and StockPiler4.Watch.CountEnabled then
        count = tonumber(StockPiler4.Watch.CountEnabled()) or 0
    end
    if count <= 0 then
        if StockPiler4.Ui and StockPiler4.Ui.Print then
            StockPiler4.Ui.Print(T("ui.no_watches"))
        end
        StockPiler4Window.RefreshFooterButtons()
        return
    end
    StockPiler4.ViewList.ConfirmTwoButton(
        T("ui.clear_watches_confirm", { count = tostring(count) }),
        StockPiler4Window.ConfirmClearWatches
    )
end

function StockPiler4Window.OnMouseOverClearWatches()
    local tip = T("ui.clear_watches_tip")
    if StockPiler4Window.SelectedTab == StockPiler4Window.TABS_PLANTS then
        tip = T("ui.clear_plant_watches_tip")
    end
    StockPiler4.ViewList.ShowTextTip(SystemData.ActiveWindow.name, tip)
end

function StockPiler4Window.OnHarvestPrepare()
    if StockPiler4.Grow and StockPiler4.Grow.CanHarvestNow then
        if StockPiler4.Grow.CanHarvestNow() ~= true then
            return
        end
    else
        local ready = 0
        if StockPiler4.Grow and StockPiler4.Grow.GetReadyHarvestPlots then
            local plots = StockPiler4.Grow.GetReadyHarvestPlots()
            ready = type(plots) == "table" and #plots or 0
        end
        if ready <= 0 then
            return
        end
    end
    if DoesWindowExist(HARVEST_WIN) and ButtonGetDisabledFlag(HARVEST_WIN) == true then
        return
    end
    local prepared = false
    if StockPiler4.Grow and StockPiler4.Grow.PrepareHarvestPlot then
        prepared = StockPiler4.Grow.PrepareHarvestPlot(true) == true
    end
    if prepared then
        if Sound and Sound.Play and Sound.CULTIVATING_HARVEST_CROP then
            Sound.Play(Sound.CULTIVATING_HARVEST_CROP)
        end
    end
end

function StockPiler4Window.OnHarvest()
end

function StockPiler4Window.OnMouseOverHarvest()
    if StockPiler4.HarvestTooltip and StockPiler4.HarvestTooltip.Show then
        StockPiler4.HarvestTooltip.Show(
            SystemData.ActiveWindow.name,
            Tooltips.ANCHOR_WINDOW_TOP
        )
        return
    end
    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, T("ui.harvest_tip_none"))
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_RIGHT)
end

function StockPiler4Window.OnBrew()
    if DoesWindowExist(BREW_WIN) and ButtonGetDisabledFlag(BREW_WIN) == true then
        return
    end
    if not StockPiler4.Brew then
        return
    end
    local result = nil
    if StockPiler4.Brew.TryBrewClick then
        result = StockPiler4.Brew.TryBrewClick()
    end
    if result == "go" and StockPiler4.Brew.FirePerform then
        StockPiler4.Brew.FirePerform()
    end
    StockPiler4Window.RefreshFooterButtons()
end

function StockPiler4Window.OnBrewRightClick()
    if StockPiler4.Brew and StockPiler4.Brew.ClearLoadedSession then
        StockPiler4.Brew.ClearLoadedSession()
    end
    StockPiler4Window.RefreshFooterButtons()
end

function StockPiler4Window.OnMouseOverBrew()
    if StockPiler4.BrewTooltip and StockPiler4.BrewTooltip.Show then
        StockPiler4.BrewTooltip.Show(
            SystemData.ActiveWindow.name,
            Tooltips.ANCHOR_WINDOW_TOP
        )
        return
    end
    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, T("brew.none_ready"))
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_TOP)
end

function StockPiler4Window.SelectTab(tabNumber, opts)
    opts = type(opts) == "table" and opts or {}
    tabNumber = tonumber(tabNumber)
    if tabNumber == nil or tabNumber < StockPiler4Window.TABS_POTIONS or tabNumber > StockPiler4Window.TABS_MAX then
        return
    end
    StockPiler4Window.SelectedTab = tabNumber
    local s = StockPiler4.Persistence and StockPiler4.Persistence.EnsureSettings
        and StockPiler4.Persistence.EnsureSettings()
    if type(s) == "table" then
        s.selectedTab = tabNumber
    end
    for index, tab in ipairs(StockPiler4Window.Tabs) do
        local selected = (index == tabNumber)
        ButtonSetPressedFlag(tab.name, selected)
        if DoesWindowExist(tab.window) then
            WindowSetShowing(tab.window, selected)
            if selected and type(WindowForceProcessAnchors) == "function" then
                if StockPiler4.Debug and StockPiler4.Debug.TryCall then
                    StockPiler4.Debug.TryCall("WindowForceProcessAnchors", WindowForceProcessAnchors, tab.window)
                else
                    pcall(WindowForceProcessAnchors, tab.window)
                end
            end
        end
    end
    if opts.deferRefresh == true then
        if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
            StockPiler4.Ui.MarkWatchUiDirty()
        end
        if tabNumber == StockPiler4Window.TABS_WATCH
            and StockPiler4TabWatch
            and StockPiler4TabWatch.PrimeRowChrome
        then
            StockPiler4TabWatch.PrimeRowChrome()
        end
        StockPiler4Window.RequestListRepopulate()
        return
    end
    StockPiler4Window.RefreshActiveTab()
    StockPiler4Window.RequestListRepopulate()
end

function StockPiler4Window.OnLButtonUpTab()
    local tabId = WindowGetId(SystemData.ActiveWindow.name)
    StockPiler4Window.SelectTab(tabId)
end

----------------------------------------------------------------
-- StockPiler4 Bootstrap -- init, shutdown, slash commands
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Version = L"0.4.28"

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

local function EmitLog(msg)
    if StockPiler4.Debug and StockPiler4.Debug.LogAlways then
        StockPiler4.Debug.LogAlways(msg)
    end
end

local function Print(msg)
    if StockPiler4.Debug and StockPiler4.Debug.Print then
        StockPiler4.Debug.Print(msg)
    end
end

local function OnOff(on)
    return on and T("boot.on") or T("boot.off")
end

local function SetDebugEnabled(on)
    local s = StockPiler4.Persistence.EnsureSettings()
    s.debugEnabled = on == true
    StockPiler4.Debug.Enabled = s.debugEnabled
    EmitLog("settings| debug=" .. (StockPiler4.Debug.Enabled and "ON" or "OFF"))
    Print(T("boot.debug", { state = OnOff(StockPiler4.Debug.Enabled) }))
end

local function SetEventTrace(on)
    local s = StockPiler4.Persistence.EnsureSettings()
    s.eventTrace = on == true
    StockPiler4.Debug.EventTrace = s.eventTrace
    Print(T("boot.event_trace", { state = OnOff(s.eventTrace) }))
end

local function PrintHelp()
    Print(T("boot.help.header"))
    Print(T("boot.help.open"))
    Print(T("boot.help.help"))
    Print(T("boot.help.tabs"))
    Print(T("boot.help.debug"))
    Print(T("boot.help.dumps"))
    Print(T("boot.help.dumpall"))
    Print(T("boot.help.bags"))
    Print(T("boot.help.fingerprint"))
    Print(T("boot.help.events"))
    Print(T("boot.help.perf"))
    Print(T("boot.help.audit"))
    Print(T("boot.help.mem"))
    Print(T("boot.help.harvest"))
end

local function DumpMem(emit)
    emit = emit or EmitLog
    local function count(t)
        if StockPiler4.Debug and StockPiler4.Debug.SafeKeyCount then
            return StockPiler4.Debug.SafeKeyCount(t, 0, {})
        end
        if type(t) ~= "table" then
            return 0
        end
        local n = 0
        for _ in pairs(t) do
            n = n + 1
        end
        return n
    end
    emit("mem| StockPiler4 top keys=" .. tostring(count(StockPiler4)))
    if type(StockPiler4.Account) == "table" then
        emit("mem| Account keys=" .. tostring(count(StockPiler4.Account)))
        for _, name in ipairs({ "items", "grows", "refines", "recipes", "potions", "additives", "vendorItems" }) do
            emit("mem| Account." .. name .. "=" .. tostring(count(StockPiler4.Account[name])))
        end
    end
    if type(StockPiler4.Settings) == "table" then
        emit("mem| Settings keys=" .. tostring(count(StockPiler4.Settings)))
        emit("mem| Settings.characters=" .. tostring(count(StockPiler4.Settings.characters)))
    end
end

local function DumpAudit(emit)
    emit = emit or EmitLog
    local unexpected = {}
    if StockPiler4.Persistence and StockPiler4.Persistence.AuditAccountKeys then
        unexpected = StockPiler4.Persistence.AuditAccountKeys() or {}
    end
    emit("audit| unexpected Account keys=" .. tostring(#unexpected))
    for i = 1, #unexpected do
        emit("audit|  " .. tostring(unexpected[i]))
    end
end

--- One-shot dump of every plan / bag / diagnostic into uilog (/sp4 dumpall).
local function DumpAll()
    local emit = function(msg)
        EmitLog(msg)
    end
    local function section(name)
        emit("--- dumpall: " .. tostring(name) .. " ---")
    end

    emit("=== dumpall begin v" .. tostring(StockPiler4.Version) .. " ===")

    section("state")
    if StockPiler4.Orchestrator and StockPiler4.Orchestrator.DumpState then
        StockPiler4.Orchestrator.DumpState(emit)
    end

    section("bags")
    if StockPiler4.BagAdapter and StockPiler4.BagAdapter.Dump then
        StockPiler4.BagAdapter.Dump(emit, { force = true })
    elseif StockPiler4.Inventory and StockPiler4.Inventory.RefreshAllIfNeeded then
        StockPiler4.Inventory.RefreshAllIfNeeded({ force = true })
        emit("bags| refresh forced (BagAdapter.Dump unavailable)")
    end

    section("plan")
    if StockPiler4.Planner and StockPiler4.Planner.Dump then
        StockPiler4.Planner.Dump(emit)
    end

    section("watchplan")
    if StockPiler4.Planner and StockPiler4.Planner.DumpWatchPlan then
        StockPiler4.Planner.DumpWatchPlan(emit)
    end

    section("growplan")
    if StockPiler4.Planner and StockPiler4.Planner.DumpGrowPlan then
        StockPiler4.Planner.DumpGrowPlan(emit)
    elseif StockPiler4.Grow and StockPiler4.Grow.DumpGrowPlan then
        StockPiler4.Grow.DumpGrowPlan(emit)
    end

    section("brewplan")
    if StockPiler4.Planner and StockPiler4.Planner.DumpBrewPlan then
        StockPiler4.Planner.DumpBrewPlan(emit)
    elseif StockPiler4.Brew and StockPiler4.Brew.DumpPlan then
        StockPiler4.Brew.DumpPlan(emit)
    end

    section("buyplan")
    if StockPiler4.Buy and StockPiler4.Buy.DumpBuyPlan then
        StockPiler4.Buy.DumpBuyPlan({ force = true })
    end

    section("skillplan")
    if StockPiler4.CultSkillPlan and StockPiler4.CultSkillPlan.DumpSkillPlan then
        StockPiler4.CultSkillPlan.DumpSkillPlan(emit)
    else
        emit("skillplan| dump unavailable")
    end

    section("families")
    if StockPiler4.SeedMap and StockPiler4.SeedMap.DumpFamilies then
        StockPiler4.SeedMap.DumpFamilies(emit)
    else
        emit("families| dump unavailable")
    end

    section("upgradeplan")
    if StockPiler4.ClimbPlan and StockPiler4.ClimbPlan.Dump then
        StockPiler4.ClimbPlan.Dump(emit)
    elseif StockPiler4.UpgradeSeed and StockPiler4.UpgradeSeed.Dump then
        StockPiler4.UpgradeSeed.Dump(emit)
    else
        emit("upgradeplan| dump unavailable")
    end

    section("stats")
    if StockPiler4.SeedMap and StockPiler4.SeedMap.DumpCraftCycleStats then
        StockPiler4.SeedMap.DumpCraftCycleStats(emit)
    else
        emit("stats| craft-cycle dump unavailable")
    end

    section("mem")
    DumpMem(emit)

    section("audit")
    DumpAudit(emit)

    section("events")
    if StockPiler4.Debug and StockPiler4.Debug.DumpEventRing then
        StockPiler4.Debug.DumpEventRing(emit)
    end

    emit("=== dumpall end ===")
    Print(T("boot.dumpall_dumped"))
end

function StockPiler4.OnSlash(input)
    local text = ""
    if input ~= nil then
        text = tostring(input)
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    local lower = string.lower(text)

    if lower == "" then
        if StockPiler4.Ui and StockPiler4.Ui.ToggleWindow then
            StockPiler4.Ui.ToggleWindow()
        end
        return
    end
    if lower == "help" then
        PrintHelp()
        return
    end
    if lower == "potions" then
        if StockPiler4.Ui and StockPiler4.Ui.ShowWindow then
            StockPiler4.Ui.ShowWindow(1)
        end
        return
    end
    if lower == "plants" then
        if StockPiler4.Ui and StockPiler4.Ui.ShowWindow then
            StockPiler4.Ui.ShowWindow(2)
        end
        return
    end
    if lower == "watch" then
        if StockPiler4.Ui and StockPiler4.Ui.ShowWindow then
            StockPiler4.Ui.ShowWindow(3)
        end
        return
    end
    if lower == "open" or lower == "show" then
        if StockPiler4.Ui and StockPiler4.Ui.ToggleWindow then
            StockPiler4.Ui.ToggleWindow()
        end
        return
    end
    if lower == "debug" or lower == "debug on" or lower == "on" then
        SetDebugEnabled(true)
        return
    end
    if lower == "debug off" or lower == "off" then
        SetDebugEnabled(false)
        return
    end
    if lower == "dumpall" or lower == "dump all" or lower == "all" then
        DumpAll()
        return
    end
    if lower == "plan" then
        if StockPiler4.Planner and StockPiler4.Planner.Dump then
            StockPiler4.Planner.Dump(function(msg) EmitLog(msg) end)
            Print(T("boot.plan_dumped"))
        end
        return
    end
    if lower == "watchplan" then
        if StockPiler4.Planner and StockPiler4.Planner.DumpWatchPlan then
            StockPiler4.Planner.DumpWatchPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.watchplan_dumped"))
        end
        return
    end
    if lower == "state" then
        if StockPiler4.Orchestrator and StockPiler4.Orchestrator.DumpState then
            StockPiler4.Orchestrator.DumpState(function(msg) EmitLog(msg) end)
            Print(T("boot.state_dumped"))
        end
        return
    end
    if lower == "growplan" then
        if StockPiler4.Planner and StockPiler4.Planner.DumpGrowPlan then
            StockPiler4.Planner.DumpGrowPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.growplan_dumped"))
        elseif StockPiler4.Grow and StockPiler4.Grow.DumpGrowPlan then
            StockPiler4.Grow.DumpGrowPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.growplan_dumped"))
        end
        return
    end
    if lower == "brewplan" then
        if StockPiler4.Planner and StockPiler4.Planner.DumpBrewPlan then
            StockPiler4.Planner.DumpBrewPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.brewplan_dumped"))
        elseif StockPiler4.Brew and StockPiler4.Brew.DumpPlan then
            StockPiler4.Brew.DumpPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.brewplan_dumped"))
        end
        return
    end
    if lower == "buyplan" then
        if StockPiler4.Buy and StockPiler4.Buy.DumpBuyPlan then
            StockPiler4.Buy.DumpBuyPlan({ force = true })
            Print(T("boot.buyplan_dumped"))
        end
        return
    end
    if lower == "skillplan" then
        local CSP = StockPiler4.CultSkillPlan
        if CSP and CSP.DumpSkillPlan then
            CSP.DumpSkillPlan(function(msg) EmitLog(msg) end)
            Print(T("boot.skillplan_dumped"))
        else
            EmitLog("skillplan| dump unavailable")
            Print(T("boot.skillplan_dumped"))
        end
        return
    end
    if lower == "families" then
        local SM = StockPiler4.SeedMap
        if SM and SM.DumpFamilies then
            SM.DumpFamilies(function(msg) EmitLog(msg) end)
            Print(T("boot.families_dumped"))
        else
            EmitLog("families| dump unavailable")
            Print(T("boot.families_dumped"))
        end
        return
    end
    if lower == "upgradeplan" then
        local US = StockPiler4.UpgradeSeed
        if US and US.Dump then
            US.Dump(function(msg) EmitLog(msg) end)
            Print(T("boot.upgrade_dumped"))
        else
            EmitLog("upgradeplan| dump unavailable")
            Print(T("boot.upgrade_dumped"))
        end
        return
    end
    if lower == "stats" then
        if StockPiler4.SeedMap and StockPiler4.SeedMap.DumpCraftCycleStats then
            StockPiler4.SeedMap.DumpCraftCycleStats(function(msg) EmitLog(msg) end)
            Print(T("boot.stats_dumped"))
        else
            EmitLog("stats| craft-cycle dump unavailable")
            Print(T("boot.stats_dumped"))
        end
        return
    end
    if lower == "stats clear" or lower == "clearstats" then
        local Rates = StockPiler4.SkillRates
        if Rates and Rates.ClearRates and Rates.ClearRates() then
            EmitLog("stats| skill-up rates cleared")
            Print(T("boot.stats_cleared"))
        else
            EmitLog("stats| clear unavailable")
            Print(T("boot.unknown_cmd"))
        end
        return
    end
    if lower == "bags" or lower == "bags force" then
        if StockPiler4.BagAdapter and StockPiler4.BagAdapter.Dump then
            local force = string.find(lower, "force", 1, true) ~= nil
            StockPiler4.BagAdapter.Dump(function(msg) EmitLog(msg) end, { force = force })
            Print(T("boot.bags_dumped"))
        elseif StockPiler4.Inventory and StockPiler4.Inventory.RefreshAllIfNeeded then
            StockPiler4.Inventory.RefreshAllIfNeeded({ force = true })
            Print(T("boot.bags_dumped"))
        end
        return
    end
    -- /sp4 fingerprint <uidA> [uidB] - ProductKey + ProductMatches (butcher twin check).
    local fpA, fpB = string.match(lower, "^fingerprint%s+(%d+)%s*(%d*)$")
    if fpA then
        if StockPiler4.MaterialSpec and StockPiler4.MaterialSpec.DumpFingerprintCompare then
            StockPiler4.MaterialSpec.DumpFingerprintCompare(
                tonumber(fpA),
                (fpB ~= nil and fpB ~= "") and tonumber(fpB) or nil,
                function(msg) EmitLog(msg) end
            )
            Print(T("boot.fingerprint_dumped"))
        end
        return
    end
    if lower == "events on" then
        SetEventTrace(true)
        return
    end
    if lower == "events off" then
        SetEventTrace(false)
        return
    end
    if lower == "events dump" then
        if StockPiler4.Debug and StockPiler4.Debug.DumpEventRing then
            StockPiler4.Debug.DumpEventRing(function(msg) EmitLog(msg) end)
            Print(T("boot.events_dumped"))
        end
        return
    end
    if lower == "events" then
        local s = StockPiler4.Persistence.EnsureSettings()
        SetEventTrace(not (s.eventTrace == true))
        return
    end
    if lower == "mem" then
        DumpMem(function(msg) EmitLog(msg) end)
        Print(T("boot.mem_dumped"))
        return
    end
    if lower == "audit" then
        DumpAudit(function(msg) EmitLog(msg) end)
        Print(T("boot.audit_dumped"))
        return
    end
    if lower == "harvest" then
        local B = StockPiler4.EventBus
        local E = StockPiler4.Events
        if B and E and E.CMD_HARVEST then
            B.Fire(E.CMD_HARVEST, {})
        elseif StockPiler4.Grow and StockPiler4.Grow.PrepareHarvestPlot then
            StockPiler4.Grow.PrepareHarvestPlot(true)
        end
        return
    end
    if lower == "perf" or string.sub(lower, 1, 5) == "perf " then
        if StockPiler4.Perf and StockPiler4.Perf.PrintSummary then
            StockPiler4.Perf.PrintSummary()
        else
            Print(T("boot.help.perf"))
        end
        return
    end
    Print(T("boot.unknown_cmd"))
end

function StockPiler4.Initialize()
    StockPiler4.Persistence.EnsureSettings()
    if StockPiler4.Locale and StockPiler4.Locale.Initialize then
        StockPiler4.Locale.Initialize()
    end
    StockPiler4.T = StockPiler4.Locale and StockPiler4.Locale.Format or StockPiler4.T
    StockPiler4.Persistence.EnsureAccount()
    if StockPiler4.Knowledge and StockPiler4.Knowledge.Ensure then
        StockPiler4.Knowledge.Ensure()
    end
    -- After Account exists: fingerprint migrate (must not run inside EnsureAccount).
    if StockPiler4.Knowledge and StockPiler4.Knowledge.MigrateFingerprints then
        StockPiler4.Knowledge.MigrateFingerprints()
    elseif StockPiler4.RecipeSpec and StockPiler4.RecipeSpec.MigrateRecipeFingerprintsV2 then
        StockPiler4.RecipeSpec.MigrateRecipeFingerprintsV2()
    end
    if StockPiler4.Watch and StockPiler4.Watch.MigratePriorityTiersIfNeeded then
        StockPiler4.Watch.MigratePriorityTiersIfNeeded()
    end
    local s = StockPiler4.Settings
    if type(s) == "table" and StockPiler4Window then
        -- 0.3.89 inserted Plants as tab 2; bump old Watch (2) -> 3 once.
        if s._sp4WatchTabBump ~= true then
            if tonumber(s.selectedTab) == 2 then
                s.selectedTab = 3
            end
            s._sp4WatchTabBump = true
        end
        local tab = tonumber(s.selectedTab) or 1
        if tab < 1 or tab > 3 then
            tab = 1
        end
        StockPiler4Window.SelectedTab = tab
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.Initialize then
        StockPiler4.Scheduler.Initialize()
    end
    if StockPiler4.Orchestrator and StockPiler4.Orchestrator.Initialize then
        StockPiler4.Orchestrator.Initialize()
    end
    if StockPiler4.Macro and StockPiler4.Macro.Initialize then
        StockPiler4.Macro.Initialize()
    end
    if StockPiler4.EngineEventBridge and StockPiler4.EngineEventBridge.Register then
        StockPiler4.EngineEventBridge.Register()
    end
    if StockPiler4.CraftChatAdapter and StockPiler4.CraftChatAdapter.RegisterChat then
        StockPiler4.CraftChatAdapter.RegisterChat()
    end
    if StockPiler4.VendorAdapter and StockPiler4.VendorAdapter.EnsureStoreHook then
        StockPiler4.VendorAdapter.EnsureStoreHook()
    end
    if StockPiler4.LearnBridge and StockPiler4.LearnBridge.Initialize then
        StockPiler4.LearnBridge.Initialize()
    end
    if StockPiler4.Ui and StockPiler4.Ui.InitializeWindow then
        StockPiler4.Ui.InitializeWindow()
    end
    if StockPiler4.Ui and StockPiler4.Ui.RegisterEventRefresh then
        StockPiler4.Ui.RegisterEventRefresh()
    end
    if StockPiler4.Brew and StockPiler4.Brew.RegisterEventHandlers then
        StockPiler4.Brew.RegisterEventHandlers()
    end
    if StockPiler4.Debug and StockPiler4.Debug.InstallChatLinkHook then
        StockPiler4.Debug.InstallChatLinkHook()
    end
    if LibSlash and LibSlash.RegisterWSlashCmd then
        LibSlash.RegisterWSlashCmd("sp4", StockPiler4.OnSlash)
        LibSlash.RegisterWSlashCmd("stockpiler4", StockPiler4.OnSlash)
    else
        EmitLog("init LibSlash missing - /sp4 may need manual binding; addon still loads")
    end
    EmitLog("init v" .. tostring(StockPiler4.Version)
        .. " debug=" .. tostring(StockPiler4.Debug and StockPiler4.Debug.Enabled == true))
    Print(T("boot.loaded", { version = StockPiler4.Version }))
    if StockPiler4.Scheduler and StockPiler4.Scheduler.BeginSessionSettle then
        StockPiler4.Scheduler.BeginSessionSettle()
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.SkipUiThisFrame then
        StockPiler4.Scheduler.SkipUiThisFrame()
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.EnqueueBagFlush then
        StockPiler4.Scheduler.EnqueueBagFlush(true)
    end
end

function StockPiler4.Shutdown()
    if StockPiler4.Debug and StockPiler4.Debug.UninstallChatLinkHook then
        StockPiler4.Debug.UninstallChatLinkHook()
    end
    if StockPiler4.Macro and StockPiler4.Macro.Shutdown then
        StockPiler4.Macro.Shutdown()
    end
    if StockPiler4.Brew and StockPiler4.Brew.UnregisterEventHandlers then
        StockPiler4.Brew.UnregisterEventHandlers()
    end
    if StockPiler4.Ui and StockPiler4.Ui.UnregisterEventRefresh then
        StockPiler4.Ui.UnregisterEventRefresh()
    end
    if StockPiler4.Orchestrator and StockPiler4.Orchestrator.Shutdown then
        StockPiler4.Orchestrator.Shutdown()
    end
    if StockPiler4.LearnBridge and StockPiler4.LearnBridge.Shutdown then
        StockPiler4.LearnBridge.Shutdown()
    end
    if StockPiler4.EngineEventBridge and StockPiler4.EngineEventBridge.Unregister then
        StockPiler4.EngineEventBridge.Unregister()
    end
    if StockPiler4.CraftChatAdapter and StockPiler4.CraftChatAdapter.UnregisterChat then
        StockPiler4.CraftChatAdapter.UnregisterChat()
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.Shutdown then
        StockPiler4.Scheduler.Shutdown()
    end
    if StockPiler4.RecipeSpec and StockPiler4.RecipeSpec.SlimAllRecipesForStorage then
        StockPiler4.RecipeSpec.SlimAllRecipesForStorage()
    end
    if StockPiler4.Persistence and StockPiler4.Persistence.StripUnexpectedAccountKeys then
        StockPiler4.Persistence.StripUnexpectedAccountKeys()
    end
    EmitLog("shutdown")
end

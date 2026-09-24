----------------------------------------------------------------
-- StockPiler4 Planner/SkillUpWatchStatus - ephemeral Watch rows
-- Extracted from SkillUp; SkillUp re-exports for callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.SkillUpWatchStatus = StockPiler4.SkillUpWatchStatus or {}
local SWS = StockPiler4.SkillUpWatchStatus

local function Gates()
    return StockPiler4.SkillUpGates
end

local function CSP()
    return StockPiler4.CultSkillPlan
end

local function ASP()
    return StockPiler4.ApoSkillPlan
end

----------------------------------------------------------------
-- Ephemeral Watch-tab status rows (never SavedVariables watches)
----------------------------------------------------------------

local function TOr(key, fallback)
    local Locale = StockPiler4.Locale
    if Locale and Locale.ResolveTemplate then
        local s = Locale.ResolveTemplate(key)
        if s ~= nil then
            return s
        end
    elseif StockPiler4.T then
        local s = StockPiler4.T(key)
        if s ~= nil then
            return s
        end
    end
    return fallback
end

local function TFmt(key, tokens, fallback)
    if StockPiler4.T then
        local s = StockPiler4.T(key, tokens)
        if s ~= nil then
            return s
        end
    end
    return fallback
end

--- Why SkillUp is idle while watches still need work (for ephemeral Watch status).
--- Returns statusKey, statusText, statusLines (or nil,nil,nil when WatchesDone).
--- When short watches are all progress-blocked, returns fallback_blocked so UI can
--- show that SkillUp is allowed to act without consuming watch mats.
local function WaitingWatchesStatus(kind)
    if Gates().WatchesDone() == true then
        return nil, nil, nil
    end
    local Watch = StockPiler4.Watch
    local potionShort = Watch and Watch.AllEnabledPotionWatchesStocked
        and Watch.AllEnabledPotionWatchesStocked() ~= true
    local plantShort = AllEnabledPlantWatchesStocked() ~= true
    local bufferShort = SeedBufferOk() ~= true

    if bufferShort ~= true and Gates().AllShortWatchesProgressBlocked() == true then
        local lines = {
            TOr(
                kind == "apo" and "skillup.watch.apo_fallback_tip" or "skillup.watch.cult_fallback_tip",
                L"Watches cannot progress (AutoGrow/vendor/skill). Skill up uses surplus only."
            ),
        }
        if potionShort then
            lines[#lines + 1] = TOr("skillup.watch.waiting_detail_potions", L"Potion watches still short.")
        end
        if plantShort then
            lines[#lines + 1] = TOr("skillup.watch.waiting_detail_plants", L"Plant watches still short.")
        end
        return "fallback_blocked",
            TOr("skillup.watch.fallback_blocked", L"Skill up while watches blocked"),
            lines
    end

    local key = "waiting_watches"
    local text
    if potionShort and not plantShort and not bufferShort then
        key = "waiting_potions"
        text = TOr("skillup.watch.waiting_potions", L"Waiting - potion watches first")
    elseif plantShort and not potionShort and not bufferShort then
        key = "waiting_plants"
        text = TOr("skillup.watch.waiting_plants", L"Waiting - plant watches first")
    elseif bufferShort and not potionShort and not plantShort then
        key = "waiting_seed_buffer"
        text = TOr("skillup.watch.waiting_seed_buffer", L"Waiting - seed buffer first")
    else
        text = TOr("skillup.watch.waiting_watches", L"Waiting - watches / seed buffer first")
    end
    local lines = {
        TOr(
            kind == "apo" and "skillup.watch.apo_waiting_tip" or "skillup.watch.cult_waiting_tip",
            L"Skill up stays idle until enabled watches are stocked and the seed buffer is met."
        ),
    }
    if potionShort then
        lines[#lines + 1] = TOr("skillup.watch.waiting_detail_potions", L"Potion watches still short.")
    end
    if plantShort then
        lines[#lines + 1] = TOr("skillup.watch.waiting_detail_plants", L"Plant watches still short.")
    end
    if bufferShort then
        lines[#lines + 1] = TOr("skillup.watch.waiting_detail_buffer", L"Seed buffer still short.")
    end
    return key, text, lines
end

local function CultStatusKeyAndText()
    if CSP().HasUpgradePlant() == true or CSP().HasRefinablePlants() == true then
        local pick = CSP().PickBestBagSeed()
        local budget = pick and SeedBudget(tonumber(pick.seedUid) or 0) or nil
        local headroom = type(budget) == "table" and (tonumber(budget.headroom) or 0) or 0
        if headroom > 0 or CSP().HasUpgradePlant() == true then
            return "refining", TOr("skillup.watch.cult_refining", L"Refining for seeds")
        end
    end
    local job = CSP().PickPlantJob and CSP().PickPlantJob() or nil
    if type(job) == "table" and (tonumber(job.plantable) or 0) >= 1 then
        local budget = SeedBudget(tonumber(job.seedUid) or 0)
        local headroom = tonumber(budget.headroom) or 0
        if headroom > 0 then
            return "buffer_plant", TOr("skillup.watch.cult_buffer", L"Planting for seed buffer")
        end
        return "planting", TOr("skillup.watch.cult_planting", L"Planting Skill up seeds")
    end
    local latch = tostring(CSP()._stallLatch or "")
    if latch ~= "" then
        local short = TOr("skillup.watch.cult_" .. latch, nil)
        if short ~= nil then
            return latch, short
        end
        return latch, TOr("skillup.stall." .. latch, L"Skill up Culti stalled")
    end
    if CSP().CountEmptyPlots() <= 0 then
        return "growing", TOr("skillup.watch.cult_growing", L"Plots full - waiting harvest")
    end
    return "idle", TOr("skillup.watch.cult_idle", L"Skill up Culti idle")
end

--- Highest-skillReq seed currently growing (garden plots + Grow pending).
--- Used for Cult SkillUp watch icon/tooltip so it matches what is in the ground.
local function HighestInGroundSkillUpSeed()
    local bestUid, bestReq, bestPlant, bestIcon, bestItem = 0, -1, 0, 0, nil
    local function consider(seedUid, plantUid, iconNum, item)
        seedUid = tonumber(seedUid) or 0
        if seedUid <= 0 then
            return
        end
        local req = 0
        if type(item) == "table" then
            req = SeedSkillReq(item)
        end
        if req <= 0 then
            local Inv = StockPiler4.Inventory
            if Inv and Inv.GetSample then
                local sample = Inv.GetSample(seedUid)
                if type(sample) == "table" then
                    req = SeedSkillReq(sample)
                    if type(item) ~= "table" then
                        item = sample
                    end
                    if (tonumber(iconNum) or 0) <= 0 then
                        iconNum = tonumber(sample.iconNum) or 0
                    end
                end
            end
        end
        if req <= 0 and StockPiler4.Items and StockPiler4.Items.GetByUid then
            local row = StockPiler4.Items.GetByUid(seedUid)
            if type(row) == "table" then
                req = SeedSkillReq(row)
                if type(item) ~= "table" then
                    item = row
                end
            end
        end
        if req > bestReq or (req == bestReq and seedUid > bestUid) then
            bestReq = req
            bestUid = seedUid
            bestPlant = tonumber(plantUid) or 0
            bestIcon = tonumber(iconNum) or 0
            bestItem = item
        end
    end

    local Garden = StockPiler4.Garden
    local plots = Garden and Garden.GetPlots and Garden.GetPlots() or nil
    if type(plots) == "table" then
        for _, row in pairs(plots) do
            if type(row) == "table" then
                local stage = tonumber(row.stage) or 0
                -- Empty plots use stage 0 / 255; skip empty.
                if stage ~= 0 and stage ~= 255 and (tonumber(row.seedUid) or 0) > 0 then
                    consider(
                        row.seedUid,
                        row.plantUid,
                        row.seedIconNum,
                        type(row.seed) == "table" and row.seed or nil
                    )
                end
            end
        end
    end

    local Grow = StockPiler4.Grow
    if Grow and type(Grow._pendingPlant) == "table" and type(Grow._pendingSeedUid) == "table" then
        for plotNum, flag in pairs(Grow._pendingPlant) do
            if (tonumber(flag) or 0) > 0 then
                consider(Grow._pendingSeedUid[plotNum], 0, 0, nil)
            end
        end
    end

    if bestUid <= 0 then
        return nil
    end
    return {
        seedUid = bestUid,
        plantUid = bestPlant,
        skillReq = bestReq,
        iconNum = bestIcon,
        item = bestItem,
    }
end

local function TradeSkillIcon(kind)
    local Caps = StockPiler4.TradeSkillCaps
    if kind == "apo" then
        return Caps and Caps.GetApothecaryIcon and tonumber(Caps.GetApothecaryIcon()) or 0
    end
    return Caps and Caps.GetCultivationIcon and tonumber(Caps.GetCultivationIcon()) or 0
end

local function BuildCultWatchStatusRow()
    local cult = Gates().GetCultSkill()
    if cult <= 0 then
        return nil
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return nil
    end
    -- Show while Cult SkillUp is on, or while Apo SkillUp needs Cult assist.
    if Gates().IsCultEnabled() ~= true and Gates().IsApoEnabled() ~= true then
        return nil
    end

    local Watch = StockPiler4.Watch
    local agOn = Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true

    -- Internals still track the active seed line (highest in plots, else bag pick).
    local growing = HighestInGroundSkillUpSeed()
    local pick = CSP().PickBestBagSeed()
    local seedUid = 0
    local plantUid = 0
    if type(growing) == "table" and (tonumber(growing.seedUid) or 0) > 0 then
        seedUid = tonumber(growing.seedUid) or 0
        plantUid = tonumber(growing.plantUid) or 0
    end
    if seedUid <= 0 and type(pick) == "table" then
        seedUid = tonumber(pick.seedUid) or 0
        plantUid = tonumber(pick.plantUid) or 0
    end
    if plantUid <= 0 and seedUid > 0 then
        local SM = StockPiler4.SeedMap
        if SM and SM.PrimaryPlantForSeed then
            plantUid = tonumber(SM.PrimaryPlantForSeed(seedUid)) or 0
        end
    end
    local budget = SeedBudget(seedUid)
    local live = tonumber(budget.live) or 0
    local buffer = tonumber(budget.bufferMin) or 0
    local statusKey, statusText, waitingLines
    statusKey, statusText, waitingLines = WaitingWatchesStatus("cult")
    if statusKey == "fallback_blocked" then
        if agOn ~= true then
            -- Master AG off still blocks Cult planting; keep fallback label.
        else
            local activeKey, activeText = CultStatusKeyAndText()
            if activeKey ~= nil and activeKey ~= "idle" and activeKey ~= "need_mats"
                and activeKey ~= "need_seeds" and activeKey ~= "autobuy_off"
            then
                statusKey, statusText = activeKey, activeText
            end
        end
    elseif statusKey == nil then
        if agOn ~= true then
            statusKey = "enable_autogrow"
            statusText = TOr("plan.status.enable_autogrow", L"Enable AutoGrow")
        else
            statusKey, statusText = CultStatusKeyAndText()
        end
    end
    local displayReq = type(growing) == "table" and (tonumber(growing.skillReq) or 0) or 0
    if displayReq < 1 and type(pick) == "table" then
        displayReq = tonumber(pick.skillReq) or 0
    end
    local tier = Gates().TargetMaxSkill()
    if displayReq > 0 then
        tier = displayReq
    end
    local dash = TOr("ui.dash", L"-")
    local statusLines = {
        TOr("skillup.watch.cult_tip", L"Addon-controlled Cultivating Skill up (not a saved watch)."),
        TOr("skillup.watch.cult_ag_tip", L"Uses master AutoGrow to plant and refine. Per-row toggle is display-only."),
        TFmt("skillup.watch.cult_tier_line", { tier = tostring(tier) },
            towstring(string.format("Planting tier: %d", tier))),
        TFmt("skillup.watch.cult_buffer_line", {
            have = tostring(live),
            need = tostring(buffer),
        }, towstring(string.format("Seed buffer: %d / %d (live / min)", live, buffer))),
    }
    if type(waitingLines) == "table" then
        for i = 1, #waitingLines do
            statusLines[#statusLines + 1] = waitingLines[i]
        end
    end
    return {
        id = "skill_up_cult",
        potionKey = "skill_up_cult",
        potionRecipeKey = "skill_up_cult",
        kind = "skillup",
        skillUp = true,
        addonOwned = true,
        skillUpKind = "cult",
        isPlantWatch = true,
        name = TOr("watch.skillup_cult", L"Cultivating"),
        iconNum = TradeSkillIcon("cult"),
        itemData = nil,
        uniqueID = 0,
        seedUid = seedUid,
        plantUid = plantUid,
        -- Stock/Craftable/Target are potion-watch columns; blank on SkillUp rows.
        potionHave = live,
        stockText = dash,
        target = buffer,
        potionMin = buffer,
        potionDeficit = math.max(0, buffer - live),
        targetText = dash,
        priorityTier = 0,
        priorityTierText = L"-",
        plantPrioSentinel = true,
        -- Read-only mirror of master AutoGrow (Cult SkillUp planting requires it).
        autoGrow = agOn == true,
        hideAutoGrow = false,
        hideBrew = true,
        hideCraftable = true,
        craftable = 0,
        craftableText = L"",
        statusKey = statusKey,
        statusText = statusText,
        statusLines = statusLines,
        skillReq = tier,
        nameR = 255,
        nameG = 255,
        nameB = 255,
    }
end

local function ApoStatusFromWhy(why)
    why = tostring(why or "need_mats")
    if why == "" then
        why = "need_mats"
    end
    local text = TOr("skillup.watch.apo_" .. why, nil)
    if text == nil then
        text = TOr("skillup.apo.stall." .. why, L"Skill up Apo waiting")
    end
    return why, text
end

local function BuildApoWatchStatusRow()
    if Gates().IsApoEnabled() ~= true then
        return nil
    end
    local tier = ASP().ApoTargetTier()
    local waitingKey, waitingText, waitingLines = WaitingWatchesStatus("apo")
    local brewRow = nil
    local statusKey, statusText, craftable, target, recipe
    if waitingKey == "fallback_blocked" then
        if ASP().ShouldApoBrew() == true and ASP().BuildApoBrewRow then
            brewRow = ASP().BuildApoBrewRow({ quiet = true })
        end
        if type(brewRow) == "table" then
            statusKey = "ready_to_craft"
            statusText = TOr("plan.status.ready_to_craft", L"Ready to brew")
            craftable = tonumber(brewRow.craftable) or 0
            target = tonumber(brewRow.target) or (craftable * 5)
            recipe = brewRow.recipe
        else
            statusKey = waitingKey
            statusText = waitingText
            craftable = 0
            target = 0
            recipe = nil
        end
    elseif waitingKey ~= nil then
        statusKey = waitingKey
        statusText = waitingText
        craftable = 0
        target = 0
        recipe = nil
    else
        if ASP().ShouldApoBrew() == true and ASP().BuildApoBrewRow then
            brewRow = ASP().BuildApoBrewRow({ quiet = true })
        end
        if type(brewRow) == "table" then
            statusKey = "ready_to_craft"
            statusText = TOr("plan.status.ready_to_craft", L"Ready to brew")
            craftable = tonumber(brewRow.craftable) or 0
            target = tonumber(brewRow.target) or (craftable * 5)
            recipe = brewRow.recipe
        else
            local latch = tostring(ASP()._apoStallLatch or "need_mats")
            statusKey, statusText = ApoStatusFromWhy(latch)
            craftable = 0
            target = 0
            recipe = nil
        end
    end

    local name = TOr("watch.skillup_apo", L"Apothecary")
    local dash = TOr("ui.dash", L"-")
    local statusLines = {
        TOr("skillup.watch.apo_tip", L"Addon-controlled Apothecary Skill up (not a saved watch)."),
        TOr("skillup.watch.apo_brew_tip", L"Does not use AutoGrow. Use Brew when ready (or the Brew macro)."),
        TFmt("skillup.watch.apo_tier_line", { tier = tostring(tier) },
            towstring(string.format("Brewing at Apo skill %d", tier))),
        TFmt("skillup.watch.apo_craftable_line", { n = tostring(craftable or 0) },
            towstring(string.format("Craftable batches now: %d", craftable or 0))),
    }
    if type(waitingLines) == "table" then
        for i = 1, #waitingLines do
            statusLines[#statusLines + 1] = waitingLines[i]
        end
    end
    return {
        id = "skill_up_apo",
        potionKey = "skill_up_apo",
        potionRecipeKey = "skill_up_apo",
        kind = "skillup",
        skillUp = true,
        addonOwned = true,
        skillUpKind = "apo",
        name = name,
        iconNum = TradeSkillIcon("apo"),
        itemData = nil,
        uniqueID = 0,
        mainUid = type(brewRow) == "table" and (tonumber(brewRow.mainUid) or 0) or 0,
        -- Stock/Craftable/Target are potion-watch columns; blank on SkillUp rows.
        potionHave = 0,
        stockText = dash,
        target = target or 0,
        potionMin = target or 0,
        potionDeficit = target or 0,
        targetText = dash,
        priorityTier = 0,
        priorityTierText = L"-",
        -- Apo SkillUp brews without AutoGrow; Cult assist (mats) uses master AutoGrow separately.
        autoGrow = false,
        hideAutoGrow = true,
        hideBrew = statusKey ~= "ready_to_craft",
        craftable = craftable or 0,
        craftableText = L"",
        craftableSafe = statusKey == "ready_to_craft",
        statusKey = statusKey,
        statusText = statusText,
        statusLines = statusLines,
        skillReq = tier,
        recipe = recipe,
        recipeYield = type(brewRow) == "table" and brewRow.recipeYield or 5,
        nameR = 255,
        nameG = 255,
        nameB = 255,
    }
end

--- True when ephemeral SkillUp rows should appear on the Watch tab.
--- Visibility follows Cult/Apo toggles; action uses WatchesAllowIdleSkillUp().
function SWS.ShouldShowWatchStatus()
    local Caps = StockPiler4.TradeSkillCaps
    if Gates().IsCultEnabled() == true
        and Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() == true
    then
        return true
    end
    -- Apo-only: Cult assist row still useful when Apo is on and Cult can grow.
    if Gates().IsApoEnabled() == true
        and Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() == true
        and Gates().GetCultSkill() > 0
    then
        return true
    end
    if Gates().IsApoEnabled() == true then
        return true
    end
    return false
end

--- 0-2 ephemeral Watch-tab rows (Cult / Apo). Never written to WatchStore.
--- Always built when the matching toggle is on; Status shows waiting vs active.
function SWS.BuildWatchStatusRows()
    local rows = {}
    local cult = BuildCultWatchStatusRow()
    if type(cult) == "table" then
        rows[#rows + 1] = cult
    end
    local apo = BuildApoWatchStatusRow()
    if type(apo) == "table" then
        rows[#rows + 1] = apo
    end
    return rows
end


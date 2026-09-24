----------------------------------------------------------------
-- StockPiler4 SkillUp - thin facade (re-exports extracted modules)
--
-- Ownership:
--   SkillUpGates      - toggles, idle gates, Caps facades
--   CultSkillPlan     - idle Cult plant/refine/buy
--   ApoSkillPlan      - idle Apo brew/resin/vials
--   SkillRates        - empirical rate samples
--   WatchReserves     - short-watch mat reserves
--   SkillUpWatchStatus - ephemeral Watch rows
--
-- Call sites keep StockPiler4.SkillUp.*; Sync*Exports bind at load end.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.SkillUp = StockPiler4.SkillUp or {}
local SkillUp = StockPiler4.SkillUp

function SkillUp.DumpSkillPlan(emit)
    emit = type(emit) == "function" and emit or function(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    local function yn(v)
        return v == true and "yes" or "no"
    end
    local function narrow(v)
        if v == nil then
            return ""
        end
        if type(v) == "wstring" then
            return tostring(WStringToString and WStringToString(v) or v)
        end
        return tostring(v)
    end

    local function SeedBudget(seedUid)
        local CE = StockPiler4.ClimbPlan or StockPiler4.UpgradeSeed
        if CE and CE.GetSeedBudget then
            return CE.GetSeedBudget(seedUid)
        end
        local Refine = StockPiler4.Refine
        if Refine and Refine.GetSeedBudget then
            local b = Refine.GetSeedBudget(seedUid)
            if type(b) == "table" then
                return b
            end
        end
        return {
            live = 0, ground = 0, outstanding = 0, credit = 0, headroom = 0, bufferMin = 0,
        }
    end

    emit("=== StockPiler4 skillplan ===")

    local Watch = StockPiler4.Watch
    local Caps = StockPiler4.TradeSkillCaps
    local cult = SkillUp.GetCultSkill()
    local apo = SkillUp.GetApoSkill()
    emit(string.format(
        "  skills cult=%d (floor=%d targetMax=%d) apo=%d (floor=%d next=%d)",
        cult,
        SkillUp.FloorCultTier(cult),
        SkillUp.TargetMaxSkill(),
        apo,
        SkillUp.FloorApoTier(apo),
        SkillUp.NextApoTier(apo)
    ))
    emit(string.format(
        "  toggles cultOn=%s apoOn=%s cultVis=%s apoVis=%s watchesDone=%s allowIdle=%s blocked=%s showStatus=%s",
        yn(SkillUp.IsCultEnabled()),
        yn(SkillUp.IsApoEnabled()),
        yn(SkillUp.IsCultVisible()),
        yn(SkillUp.IsApoVisible()),
        yn(SkillUp.WatchesDone()),
        yn(SkillUp.WatchesAllowIdleSkillUp()),
        yn(SkillUp.AllShortWatchesProgressBlocked()),
        yn(SkillUp.ShouldShowWatchStatus and SkillUp.ShouldShowWatchStatus())
    ))
    emit(string.format(
        "  gates shouldCultGrow=%s shouldCultPlant=%s shouldApoBrew=%s canAutoGrow=%s autoGrowMaster=%s autoBuy=%s",
        yn(SkillUp.ShouldCultGrowForSkillUp()),
        yn(SkillUp.ShouldCultPlant()),
        yn(SkillUp.ShouldApoBrew()),
        yn(Caps and Caps.CanAutoGrow and Caps.CanAutoGrow()),
        yn(Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled()),
        yn(Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled())
    ))
    emit(string.format(
        "  latches cult=%s apo=%s pendingCult=%s pendingApo=%s",
        tostring(SkillUp._stallLatch or "-"),
        tostring(SkillUp._apoStallLatch or "-"),
        SkillUp._pendingCult and string.format("lvl=%s until=%.0f",
            tostring(SkillUp._pendingCult.level),
            tonumber(SkillUp._pendingCult.untilTime) or 0) or "-",
        SkillUp._pendingApo and string.format("lvl=%s until=%.0f",
            tostring(SkillUp._pendingApo.level),
            tonumber(SkillUp._pendingApo.untilTime) or 0) or "-"
    ))

    -- Garden plots
    emit("--- garden ---")
    local empty = SkillUp.CountEmptyPlots()
    emit(string.format("  emptyPlots=%d", empty))
    local Garden = StockPiler4.Garden
    local plots = Garden and Garden.GetPlots and Garden.GetPlots() or nil
    if type(plots) == "table" then
        for plotNum, row in pairs(plots) do
            if type(row) == "table" then
                local stage = tonumber(row.stage) or 0
                local seedUid = tonumber(row.seedUid) or 0
                local plantUid = tonumber(row.plantUid) or 0
                emit(string.format(
                    "  plot[%s] stage=%s seedUid=%d plantUid=%d empty=%s",
                    tostring(plotNum),
                    tostring(stage),
                    seedUid,
                    plantUid,
                    tostring(stage == 0 or stage == 255)
                ))
            end
        end
    else
        emit("  plots=(unavailable)")
    end
    local Grow = StockPiler4.Grow
    if Grow and type(Grow._pendingPlant) == "table" then
        for plotNum, flag in pairs(Grow._pendingPlant) do
            if (tonumber(flag) or 0) > 0 then
                local su = Grow._pendingSeedUid and Grow._pendingSeedUid[plotNum] or 0
                emit(string.format("  pendingPlant plot=%s seedUid=%s", tostring(plotNum), tostring(su)))
            end
        end
    end

    -- Cult plant / refine
    emit("--- cult plant/refine ---")
    local pick = SkillUp.PickBestBagSeed and SkillUp.PickBestBagSeed() or nil
    if type(pick) == "table" then
        local seedUid = tonumber(pick.seedUid) or 0
        local budget = SeedBudget(seedUid)
        emit(string.format(
            "  pick seedUid=%d plantUid=%d req=%d bag=%d name=%s",
            seedUid,
            tonumber(pick.plantUid) or 0,
            tonumber(pick.skillReq) or 0,
            tonumber(pick.count) or 0,
            narrow(pick.item and pick.item.name)
        ))
        emit(string.format(
            "  budget live=%s ground=%s outstanding=%s credit=%s buffer=%s headroom=%s",
            tostring(budget.live),
            tostring(budget.ground),
            tostring(budget.outstanding),
            tostring(budget.credit),
            tostring(budget.bufferMin),
            tostring(budget.headroom)
        ))
        emit(string.format(
            "  seedDeficit=%d hasUpgrade=%s hasRefinable=%s",
            tonumber(SkillUp.SeedDeficit and SkillUp.SeedDeficit(seedUid)) or 0,
            yn(SkillUp.HasUpgradePlant and SkillUp.HasUpgradePlant()),
            yn(SkillUp.HasRefinablePlants and SkillUp.HasRefinablePlants())
        ))
    else
        emit("  pick=(none)")
    end
    local job = SkillUp.PickPlantJob and SkillUp.PickPlantJob() or nil
    if type(job) == "table" then
        emit(string.format(
            "  plantJob seedUid=%d plantable=%d reason=%s req=%d",
            tonumber(job.seedUid) or 0,
            tonumber(job.plantable) or 0,
            tostring(job.plantReason or job.pickMode or "?"),
            tonumber(job.skillReq) or 0
        ))
    else
        emit("  plantJob=(nil) - see hold/no-plant logs; empty=" .. tostring(empty))
    end
    local refine = SkillUp.ScanBestRefinePlant and SkillUp.ScanBestRefinePlant() or nil
    if type(refine) == "table" then
        emit(string.format(
            "  refineBest plantUid=%d seedUid=%d req=%d count=%s upgrade=%s",
            tonumber(refine.plantUid) or 0,
            tonumber(refine.seedUid) or 0,
            tonumber(refine.skillReq) or 0,
            tostring(refine.count or refine.uses or "?"),
            yn(refine.upgrade == true or SkillUp.HasUpgradePlant())
        ))
    else
        emit("  refineBest=(none)")
    end
    local buySeed = SkillUp.ShouldCultBuy and SkillUp.ShouldCultBuy() == true
    emit(string.format("  shouldCultBuy=%s", yn(buySeed)))
    if SkillUp.CollectBuyJobs then
        local seedJobs = SkillUp.CollectBuyJobs() or {}
        emit(string.format("  cultBuyJobs=%d", #seedJobs))
        for i = 1, #seedJobs do
            local j = seedJobs[i]
            emit(string.format(
                "    buy[%d] uid=%s deficit=%s role=%s skillUp=%s",
                i,
                tostring(j.uid or j.uniqueID),
                tostring(j.deficit),
                tostring(j.role),
                yn(j.skillUp == true)
            ))
        end
    end

    -- Apo brew / vials
    emit("--- apo brew/vials ---")
    emit(string.format(
        "  apoTier=%d vials have=%d want=%d shouldBuy=%s",
        SkillUp.ApoTargetTier(),
        SkillUp.CountApoContainers and SkillUp.CountApoContainers() or 0,
        SkillUp.ApoContainerBuyTarget and SkillUp.ApoContainerBuyTarget() or 0,
        yn(SkillUp.ShouldApoBuyContainer and SkillUp.ShouldApoBuyContainer())
    ))
    local vialTarget = SkillUp.ResolveBuyContainerTarget and SkillUp.ResolveBuyContainerTarget() or nil
    if type(vialTarget) == "table" then
        emit(string.format(
            "  vialTarget uid=%d skillReq=%d",
            tonumber(vialTarget.uid) or 0,
            tonumber(vialTarget.skillReq) or 0
        ))
    end
    if SkillUp.CollectContainerBuyJobs then
        local cJobs = SkillUp.CollectContainerBuyJobs() or {}
        emit(string.format("  containerBuyJobs=%d", #cJobs))
        for i = 1, #cJobs do
            local j = cJobs[i]
            emit(string.format(
                "    vialBuy[%d] uid=%s deficit=%s skillReq=%s",
                i,
                tostring(j.uid or j.uniqueID),
                tostring(j.deficit),
                tostring(j.skillReq)
            ))
        end
    end
    for _, role in ipairs({ "main", "container", "stabilizer" }) do
        local mats = SkillUp.ListApoBagMaterials and SkillUp.ListApoBagMaterials(role) or {}
        emit(string.format("  mats[%s] candidates=%d", role, type(mats) == "table" and #mats or 0))
        if type(mats) == "table" then
            local lim = math.min(#mats, 5)
            for i = 1, lim do
                local m = mats[i]
                emit(string.format(
                    "    [%d] uid=%d count=%s stab=%s req=%s surplus=%s name=%s",
                    i,
                    tonumber(m.uid) or 0,
                    tostring(m.count),
                    tostring(m.stability),
                    tostring(m.skillReq or m.skillLevel),
                    tostring(m.surplus),
                    narrow(m.item and m.item.name)
                ))
            end
        end
    end
    local brewRow = SkillUp.BuildApoBrewRow and SkillUp.BuildApoBrewRow({ quiet = true }) or nil
    if type(brewRow) == "table" then
        emit(string.format(
            "  brewRow craftable=%s mainUid=%s status=%s name=%s",
            tostring(brewRow.craftable),
            tostring(brewRow.mainUid),
            tostring(brewRow.statusKey),
            narrow(brewRow.name)
        ))
    else
        emit(string.format(
            "  brewRow=(nil) stall=%s",
            tostring(SkillUp._apoStallLatch or "-")
        ))
    end

    -- Watch status rows
    emit("--- watch status rows ---")
    local rows = SkillUp.BuildWatchStatusRows and SkillUp.BuildWatchStatusRows() or {}
    emit(string.format("  rows=%d", #rows))
    for i = 1, #rows do
        local r = rows[i]
        emit(string.format(
            "  row[%d] kind=%s name=%s status=%s stock=%s craftable=%s hideAg=%s hideBrew=%s",
            i,
            tostring(r.skillUpKind),
            narrow(r.name),
            tostring(r.statusKey),
            narrow(r.stockText),
            tostring(r.craftable),
            yn(r.hideAutoGrow == true),
            yn(r.hideBrew == true)
        ))
        if type(r.statusLines) == "table" then
            for li = 1, #r.statusLines do
                emit("    tip: " .. narrow(r.statusLines[li]))
            end
        end
    end

    -- Rates (reuse)
    SkillUp.DumpRates(emit)

    emit("=== end skillplan ===")
end

local function SyncAll()
    local order = {
        StockPiler4.SkillUpGates,
        StockPiler4.WatchReserves,
        StockPiler4.CultSkillPlan,
        StockPiler4.SkillRates,
        StockPiler4.ApoSkillPlan,
        StockPiler4.SkillUpWatchStatus,
    }
    for i = 1, #order do
        local mod = order[i]
        if mod and mod.SyncSkillUpExports then
            mod.SyncSkillUpExports()
        end
    end
end

SyncAll()
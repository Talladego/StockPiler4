----------------------------------------------------------------
-- StockPiler4 Planner/PlantPlan -- plant candidate selection
-- Absorbed from Grow.PickPlantCandidate (Phase 3).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.PlantPlan = StockPiler4.PlantPlan or {}
local PlantPlan = StockPiler4.PlantPlan

local function GrowRef()
    return StockPiler4.Grow
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

local function RoleRank(role)
    return ROLE_PICK_ORDER[tostring(role or "")] or 99
end

local function NormalizeStage(stage)
    return tonumber(stage) or 0
end

local function StageEmpty()
    if GameData and GameData.CultivationStage then
        return GameData.CultivationStage.EMPTY or 0
    end
    return 0
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

local function CountInGroundSeeds(seedUid)
    if GrowRef().CountInGroundSeeds then
        return GrowRef().CountInGroundSeeds(seedUid)
    end
    return 0
end

local function CountSeedPlotCredit(seedUid)
    if GrowRef().CountSeedPlotCredit then
        return GrowRef().CountSeedPlotCredit(seedUid)
    end
    return 0
end

local function CanUseSeedUid(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return false
    end
    local Inv = StockPiler4.Inventory
    local snapGen = Inv and Inv.GetSnapGen and Inv.GetSnapGen() or 0
    if GrowRef()._skillSkipSnapGen ~= snapGen then
        GrowRef()._skillSkipByUid = {}
        GrowRef()._skillSkipSnapGen = snapGen
    end
    if GrowRef()._skillSkipByUid[seedUid] == true then
        return false
    end
    local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
    if type(sample) == "table" and Inv and Inv.CanUseCraftingItem then
        if Inv.CanUseCraftingItem(sample) ~= true then
            GrowRef()._skillSkipByUid[seedUid] = true
            return false
        end
    end
    return true
end

local function LogGrow(msg)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("grow", msg)
    end
end


function PlantPlan.ReasonFromJob(job)
    if type(job) ~= "table" then
        return nil
    end
    local pr = tostring(job.plantReason or "")
    local pm = tostring(job.pickMode or "")
    if pr == "skill_up" then
        return "skillup"
    end
    if pr == "seed_buffer" or pm == "buffer" then
        return "buffer_fill"
    end
    if pr == "upgrade" or pm == "upgrade" or job.upgradeClimb == true then
        return "upgrade_climb"
    end
    if pm == "watch-lift" or pr == "potion_stock" then
        return "watch_deficit"
    end
    if pr == "plant_stock" or pm == "plant_stock" then
        return "watch_deficit"
    end
    if pr == "surplus" or pm == "surplus" then
        return "buffer_fill"
    end
    return "watch_deficit"
end

function PlantPlan.BuildPlantIntent(job)
    if type(job) ~= "table" then
        return nil
    end
    local seedUid = tonumber(job.seedUid) or 0
    if seedUid <= 0 then
        return nil
    end
    -- Never bake plotNum here. Cheap/garden plan patches reuse plantIntent; a
    -- filled plot stalls multi-plot fill until a force Build (/sp4 dumpall).
    return {
        seedUid = seedUid,
        plotNum = 0,
        reason = PlantPlan.ReasonFromJob(job),
        plantUid = tonumber(job.plantUid) or nil,
        watchKey = job.watchKey,
        pickMode = job.pickMode or job.plantReason,
        role = job.role,
        plantReason = job.plantReason,
        specKey = job.specKey,
    }
end

local function OpaqueSeedCredit(seedUid, bagCount)
    seedUid = tonumber(seedUid) or 0
    bagCount = tonumber(bagCount) or 0
    if seedUid <= 0 or bagCount <= 0 then
        return bagCount
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.EffectiveSeedCredit then
        return tonumber(SM.EffectiveSeedCredit(seedUid, bagCount)) or bagCount
    end
    local Inv = StockPiler4.Inventory
    local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
    local name = ""
    if type(sample) == "table" and sample.name ~= nil then
        if type(sample.name) == "wstring" and type(WStringToString) == "function" then
            local ok, text = pcall(WStringToString, sample.name)
            if ok then
                name = tostring(text or "")
            end
        else
            name = tostring(sample.name)
        end
    end
    local lower = string.lower(name)
    if string.find(lower, "eternal", 1, true) or string.find(lower, "exceptional", 1, true) then
        local plots = 1
        local CA = StockPiler4.CultivatorAdapter
        if CA and CA.NumPlots then
            plots = math.max(1, tonumber(CA.NumPlots()) or 1)
        end
        if bagCount < plots then
            return plots
        end
    end
    return bagCount
end

local function LiveSeedBag(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return 0
    end
    local Inv = StockPiler4.Inventory
    if Inv and Inv.CountByUid then
        return tonumber(Inv.CountByUid(seedUid)) or 0
    end
    return 0
end

local function BufferCredit(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return 0
    end
    local Refine = StockPiler4.Refine
    if Refine and Refine.GetSeedBudget then
        local b = Refine.GetSeedBudget(seedUid)
        if type(b) == "table" and b.credit ~= nil then
            return tonumber(b.credit) or 0
        end
    end
    local bag = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
    local ground = CountSeedPlotCredit(seedUid)
    local outstanding = 0
    local RP = StockPiler4.RefinePipeline
    if RP and RP.GetOutstanding then
        outstanding = tonumber(RP.GetOutstanding(seedUid)) or 0
    end
    return bag + ground + outstanding
end

local function PreferJob(job, best, bestScore, bestShare, bestCrafts, bestPlots, bestRole, useFocus)
    if type(job) ~= "table" then
        return best, bestScore, bestShare, bestCrafts, bestPlots, bestRole
    end
    local crafts = tonumber(job.craftsShort) or 0
    local role = RoleRank(job.role)
    local plots = tonumber(job.plotCount) or CountInGroundSeeds(job.seedUid)
    job.plotCount = plots
    job.roleRank = role
    local better = false
    if useFocus then
        local score = tonumber(job.bottleneckScore) or 0
        local share = tonumber(job.focusShare) or 999
        if best == nil then
            better = true
        elseif score > bestScore then
            better = true
        elseif score == bestScore then
            if share < bestShare then
                better = true
            elseif share == bestShare then
                if crafts > bestCrafts then
                    better = true
                elseif crafts == bestCrafts then
                    if role < bestRole then
                        better = true
                    elseif role == bestRole
                        and (tonumber(job.seedUid) or 0) ~= (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
                        and (tonumber(best.seedUid) or 0) == (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
                    then
                        better = true
                    end
                end
            end
        end
        if better then
            return job, score, share, crafts, plots, role
        end
        return best, bestScore, bestShare, bestCrafts, bestPlots, bestRole
    end
    if best == nil then
        better = true
    elseif crafts > bestCrafts then
        better = true
    elseif crafts == bestCrafts then
        if plots < bestPlots then
            better = true
        elseif plots == bestPlots and role < bestRole then
            better = true
        elseif plots == bestPlots and role == bestRole
            and (tonumber(job.seedUid) or 0) ~= (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
            and (tonumber(best.seedUid) or 0) == (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
        then
            better = true
        end
    end
    if better then
        return job, bestScore, bestShare, crafts, plots, role
    end
    return best, bestScore, bestShare, bestCrafts, bestPlots, bestRole
end

local function JobFromDemandRow(row, SM)
    if type(row) ~= "table" or type(SM) ~= "table" then
        return nil
    end
    local deficit = tonumber(row.deficit) or 0
    local craftsShort = tonumber(row.craftsShort)
    if craftsShort == nil then
        craftsShort = deficit
    end
    local spec = row.spec
    if deficit <= 0 or craftsShort <= 0 or type(spec) ~= "table" then
        return nil
    end
    if SM.IsGrowableSpec and SM.IsGrowableSpec(spec) ~= true then
        return nil
    end
    local seed = SM.ResolveSeedForSpec and SM.ResolveSeedForSpec(spec)
    if type(seed) ~= "table" then
        return nil
    end
    local seedUid = tonumber(seed.uniqueID) or 0
    if seedUid <= 0 then
        return nil
    end
    if not CanUseSeedUid(seedUid) then
        return nil
    end
    local bag = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
    if SM.CountSeedsInBagsForSpec then
        local n = tonumber(SM.CountSeedsInBagsForSpec(spec)) or 0
        if n > bag then
            bag = OpaqueSeedCredit(seedUid, n)
        end
    end
    local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
    local avail = bag - committed
    if avail < 1 then
        return nil
    end
    local plantable = math.min(avail, craftsShort)
    if plantable < 1 then
        return nil
    end
    return {
        spec = spec,
        specKey = row.specKey,
        seed = seed,
        seedUid = seedUid,
        plantUid = tonumber(row.plantUid) or tonumber(spec.plantUid) or 0,
        seedHave = bag,
        plantable = plantable,
        deficit = deficit,
        craftsShort = craftsShort,
        role = SpecRole(spec),
        plantReason = "potion_stock",
        plotCount = CountInGroundSeeds(seedUid),
    }
end

local function PotionStockNeedsRefineFirst(demand, SM)
    if type(demand) ~= "table" or type(SM) ~= "table" then
        return false
    end
    local Refine = StockPiler4.Refine
    for _, row in pairs(demand) do
        if type(row) == "table" and (tonumber(row.deficit) or 0) > 0 and type(row.spec) == "table" then
            if SM.IsGrowableSpec and SM.IsGrowableSpec(row.spec) == true then
                local seed = SM.ResolveSeedForSpec and SM.ResolveSeedForSpec(row.spec)
                local seedUid = type(seed) == "table" and (tonumber(seed.uniqueID) or 0) or 0
                local have = seedUid > 0 and LiveSeedBag(seedUid) or 0
                local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
                if (have - committed) <= 0 then
                    local plantUid = tonumber(row.plantUid) or 0
                    local refinable = 0
                    if Refine and Refine.CountRefinablePlants then
                        refinable = tonumber(Refine.CountRefinablePlants(plantUid, row.spec)) or 0
                    end
                    if refinable > 0 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function PickBufferGrowCandidate(lines, SM, focusKeys, demand, focusGap)
    if type(lines) ~= "table" then
        return nil
    end
    focusGap = tonumber(focusGap) or 0
    -- While focus still needs bottles, only buffer seeds for short demand mats
    -- (never covered main/extender from the same recipe).
    local restrictToShorts = focusGap > 0
    local shortDemandKeys = nil
    if restrictToShorts and type(demand) == "table" then
        shortDemandKeys = {}
        for specKey, row in pairs(demand) do
            if type(row) == "table" and (tonumber(row.craftsShort) or 0) > 0 then
                shortDemandKeys[tostring(specKey)] = true
                if row.specKey then
                    shortDemandKeys[tostring(row.specKey)] = true
                end
            end
        end
    end
    local function LineAllowedForFocus(line)
        if not restrictToShorts then
            return true
        end
        if type(shortDemandKeys) ~= "table" then
            return false
        end
        local sk = tostring(line.specKey or "")
        if sk ~= "" and shortDemandKeys[sk] == true then
            return true
        end
        if type(line.spec) == "table" then
            local MS = StockPiler4.MaterialSpec
            local pk = ""
            if MS and MS.ProductKey then
                pk = tostring(MS.ProductKey(line.spec) or "")
            elseif MS and MS.Key then
                pk = tostring(MS.Key(line.spec) or "")
            end
            if pk ~= "" and shortDemandKeys[pk] == true then
                return true
            end
        end
        return false
    end
    local Watch = StockPiler4.Watch
    local buffer = Watch and Watch.GetSeedBufferMin and Watch.GetSeedBufferMin() or 5
    local Refine = StockPiler4.Refine
    local best, bestWant = nil, -1
    for i = 1, #lines do
        local line = lines[i]
        local seedUid = tonumber(line.seedUid) or 0
        if seedUid > 0 and CanUseSeedUid(seedUid) and LineAllowedForFocus(line) then
            -- Never buffer-plant a lower-tier seed for a higher plant (e.g. Dusty L1
            -- after Majestic L200 exists but is short of the buffer).
            local plantReq = 0
            if type(line.spec) == "table" then
                plantReq = tonumber(line.spec.skillLevel) or tonumber(line.spec.skillReq) or 0
            end
            if plantReq <= 0 and (tonumber(line.plantUid) or 0) > 0 then
                local Items = StockPiler4.Items
                if Items and Items.ToSpec then
                    local pSpec = Items.ToSpec(line.plantUid)
                    plantReq = tonumber(pSpec and pSpec.skillLevel) or 0
                end
            end
            local seedReq = 0
            if plantReq > 0 then
                local sample = StockPiler4.Inventory and StockPiler4.Inventory.GetSample
                    and StockPiler4.Inventory.GetSample(seedUid)
                if type(sample) == "table" then
                    seedReq = tonumber(sample.craftingSkillRequirement) or tonumber(sample.skillReq) or 0
                    if seedReq <= 0 and type(sample.bonuses) == "table" then
                        seedReq = tonumber(sample.bonuses[9]) or 0
                    end
                end
                if seedReq <= 0 and StockPiler4.Items and StockPiler4.Items.GetByUid then
                    local row = StockPiler4.Items.GetByUid(seedUid)
                    seedReq = tonumber(row and (row.craftingSkillRequirement or row.skillReq or row.skillLevel)) or 0
                    if seedReq <= 0 and type(row) == "table" and type(row.bonuses) == "table" then
                        seedReq = tonumber(row.bonuses[9]) or 0
                    end
                end
            end
            if plantReq > 0 and seedReq > 0 and seedReq < plantReq then
                seedUid = 0
            end
        end
        if seedUid > 0 and CanUseSeedUid(seedUid) and LineAllowedForFocus(line) then
            -- Upgrade Seed owns short plant watches until the target tier exists;
            -- do not seed_buffer intermediate genus rungs into the craft bag.
            local US = StockPiler4.UpgradeSeed
            local climbOwns = false
            if US and US.IsEnabled and US.IsEnabled() == true and US.StatusForPlant then
                local plantUid = tonumber(line.plantUid) or 0
                local climb = nil
                if plantUid > 0 then
                    climb = US.StatusForPlant(plantUid, line.spec)
                elseif line.plantStock == true and type(line.spec) == "table" then
                    climb = US.StatusForPlant(0, line.spec)
                end
                if type(climb) == "table" and tostring(climb.why or "") ~= "need_cult" then
                    climbOwns = true
                end
            end
            if not climbOwns then
                local credit = BufferCredit(seedUid)
                local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
                local bag = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
                local avail = bag - committed
                if avail > 0 and credit < buffer then
                    local refinable = 0
                    if Refine and Refine.CountRefinablePlants then
                        refinable = tonumber(Refine.CountRefinablePlants(line.plantUid, line.spec)) or 0
                    end
                    -- Must not buffer-grow while refinable plants remain.
                    if refinable <= 0 then
                        local want = buffer - credit
                        if want > bestWant then
                            bestWant = want
                            best = {
                                spec = line.spec,
                                specKey = line.specKey,
                                seed = line.seed or { uniqueID = seedUid },
                                seedUid = seedUid,
                                plantUid = tonumber(line.plantUid) or 0,
                                seedHave = bag,
                                plantable = math.min(avail, want),
                                deficit = want,
                                craftsShort = want,
                                role = SpecRole(line.spec),
                                plantReason = "seed_buffer",
                            }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function PickSurplusCandidate(lines)
    local Refine = StockPiler4.Refine
    -- SHORT surplus block when buffer SHORT or buffer refine pending.
    if Refine then
        if Refine.HasAnyBufferShort and Refine.HasAnyBufferShort() == true then
            return nil
        end
        if Refine.HasPendingBufferRefine and Refine.HasPendingBufferRefine() == true then
            return nil
        end
    end
    local Watch = StockPiler4.Watch
    local buffer = Watch and Watch.GetSeedBufferMin and Watch.GetSeedBufferMin() or 5
    local best, bestSurplus = nil, -1
    if type(lines) ~= "table" then
        return nil
    end
    for i = 1, #lines do
        local line = lines[i]
        local seedUid = tonumber(line.seedUid) or 0
        if seedUid > 0 and CanUseSeedUid(seedUid) then
            local live = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
            local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
            if Refine and Refine.GetSeedBudget then
                local b = Refine.GetSeedBudget(seedUid)
                if type(b) == "table" then
                    if (tonumber(b.headroom) or 0) > 0 then
                        live = -1
                    else
                        live = tonumber(b.live) or live
                    end
                end
            end
            if live >= 0 then
                local surplus = live - buffer - committed
                if surplus > bestSurplus and surplus > 0 then
                    bestSurplus = surplus
                    best = {
                        spec = line.spec,
                        specKey = line.specKey,
                        seed = line.seed or { uniqueID = seedUid },
                        seedUid = seedUid,
                        plantUid = tonumber(line.plantUid) or 0,
                        seedHave = live,
                        plantable = surplus,
                        deficit = surplus,
                        craftsShort = surplus,
                        role = SpecRole(line.spec),
                        plantReason = "surplus",
                    }
                end
            end
        end
    end
    return best
end

--- Soft gate: plant floors while potions only need buy/brew; block while they need Cult grow.
local function PickPlantStockCandidate(SM)
    local Watch = StockPiler4.Watch
    if Watch and Watch.EnabledPotionWatchesNeedCultGrow then
        if Watch.EnabledPotionWatchesNeedCultGrow() == true then
            return nil
        end
    elseif not (Watch and Watch.AllEnabledPotionWatchesStocked
        and Watch.AllEnabledPotionWatchesStocked() == true)
    then
        return nil
    end
    if Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() ~= true then
        return nil
    end
    local plantWatches = Watch.GetPlantWatches and Watch.GetPlantWatches() or nil
    if type(plantWatches) ~= "table" or type(SM) ~= "table" then
        return nil
    end
    local Catalog = StockPiler4.Catalog
    local Items = StockPiler4.Items
    local MS = StockPiler4.MaterialSpec
    local best, bestNeed = nil, -1
    for plantKey, watch in pairs(plantWatches) do
        if type(watch) == "table" and watch.enabled == true
            and (Watch.ShouldAutoGrowPlant == nil or Watch.ShouldAutoGrowPlant(plantKey) == true)
        then
            local plantUid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
            plantUid = tonumber(plantUid) or 0
            if plantUid > 0 then
                local have = 0
                if Catalog and Catalog.PlantHave then
                    have = tonumber(Catalog.PlantHave(plantUid)) or 0
                elseif StockPiler4.Inventory and StockPiler4.Inventory.CountByUid then
                    have = tonumber(StockPiler4.Inventory.CountByUid(plantUid)) or 0
                end
                local target = tonumber(watch.targetStock) or 40
                local need = target - have
                if need > 0 then
                    local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
                    if type(spec) ~= "table" and MS and MS.FromUid then
                        spec = MS.FromUid(plantUid)
                    end
                    if type(spec) == "table" and SM.IsGrowableSpec and SM.IsGrowableSpec(spec) == true then
                        -- Upgrade Seed owns the genus only after watched stock is met
                        -- (Phase B); plant_stock must not burn seeds mid-climb.
                        local US = StockPiler4.UpgradeSeed
                        local climb = US and US.IsEnabled and US.IsEnabled() == true
                            and US.StatusForPlant and US.StatusForPlant(plantUid, spec) or nil
                        local climbOwns = type(climb) == "table"
                            and tostring(climb.why or "") ~= "need_cult"
                        if not climbOwns then
                            local seedUid = 0
                            local seed = nil
                            if SM.ResolveSeedUidForPlant then
                                seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, spec)) or 0
                            end
                            if seedUid <= 0 and SM.ResolveSeedForSpec then
                                seed = SM.ResolveSeedForSpec(spec)
                                if type(seed) == "table" then
                                    seedUid = tonumber(seed.uniqueID) or 0
                                end
                            end
                            if seedUid <= 0 and SM.GetSeedUidsForPlant then
                                local seeds = SM.GetSeedUidsForPlant(plantUid)
                                if type(seeds) == "table" and #seeds > 0 then
                                    seedUid = tonumber(seeds[1]) or 0
                                end
                            end
                            if seedUid > 0 then
                                seed = seed or { uniqueID = seedUid }
                            end
                            if seedUid > 0 and CanUseSeedUid(seedUid) then
                                -- Plant watches plant buffer seeds toward the plant
                                -- target, then Refine tops the seed buffer back up.
                                -- Do not hold the buffer cushion here (0.3.142 Upgrade
                                -- Seed "never plant into buffer" broke that cycle).
                                local bag = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
                                local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
                                local avail = bag - committed
                                if avail >= 1 and need > bestNeed then
                                    bestNeed = need
                                    best = {
                                        spec = spec,
                                        specKey = (MS and MS.ProductKey and MS.ProductKey(spec))
                                            or ("plant:" .. tostring(plantUid)),
                                        seed = seed or { uniqueID = seedUid },
                                        seedUid = seedUid,
                                        plantUid = plantUid,
                                        seedHave = bag,
                                        plantable = math.min(avail, need),
                                        deficit = need,
                                        craftsShort = need,
                                        role = SpecRole(spec),
                                        plantReason = "plant_stock",
                                        watchKey = tostring(plantKey),
                                        pickMode = "plant_stock",
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end
----------------------------------------------------------------
-- Plant pick - watch deficit -> craftable-lift bottlenecks -> spare plots
----------------------------------------------------------------

--- AutoGrow watches with potion deficit (target - have), largest first.
local function CollectPlantWatchOrder(RS)
    local list = {}
    local Watch = StockPiler4.Watch
    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get() or nil
    local planRows = type(plan) == "table" and plan.rows or nil
    local BottleGap = StockPiler4.Planner and StockPiler4.Planner.BottleGap

    local function push(potionKey, name, deficit, recipe, have, target, craftable, bottleGap, priorityTier)
        potionKey = tostring(potionKey or "")
        deficit = tonumber(deficit) or 0
        if potionKey == "" or deficit <= 0 or type(recipe) ~= "table" then
            return
        end
        if RS.ShouldAutoGrowPotion and RS.ShouldAutoGrowPotion(potionKey, nil) ~= true then
            return
        end
        have = tonumber(have) or 0
        target = tonumber(target) or 0
        craftable = tonumber(craftable) or 0
        local gap = tonumber(bottleGap)
        if gap == nil and type(BottleGap) == "function" then
            gap = BottleGap(target, have, craftable)
        end
        gap = tonumber(gap) or math.max(0, target - have - craftable)
        local tier = tonumber(priorityTier)
        if tier == nil and Watch and Watch.GetPriorityTier then
            tier = Watch.GetPriorityTier(potionKey)
        end
        list[#list + 1] = {
            potionKey = potionKey,
            name = name,
            deficit = deficit,
            recipe = recipe,
            have = have,
            target = target,
            craftable = craftable,
            bottleGap = gap,
            priorityTier = tonumber(tier) or 1,
        }
    end

    if type(planRows) == "table" and #planRows > 0 then
        for i = 1, #planRows do
            local row = planRows[i]
            if type(row) == "table" and row.kind ~= "plant" and row.isPlantWatch ~= true then
                local key = tostring(row.potionKey or row.potionRecipeKey or row.id or "")
                local target = tonumber(row.potionMin) or tonumber(row.target) or 0
                local have = tonumber(row.potionHave) or 0
                local deficit = tonumber(row.potionDeficit)
                if deficit == nil then
                    deficit = math.max(0, target - have)
                end
                local recipe = row.recipe
                if type(recipe) ~= "table" and RS.RecipeSpecForPotion then
                    recipe = RS.RecipeSpecForPotion(key)
                end
                push(
                    key,
                    row.name,
                    deficit,
                    recipe,
                    have,
                    target,
                    row.craftable,
                    row.bottleGap,
                    row.priorityTier
                )
            end
        end
    else
        local watches = Watch and Watch.GetWatches and Watch.GetWatches() or {}
        if type(watches) == "table" then
            for watchKey, watch in pairs(watches) do
                if RS.ShouldAutoGrowPotion and RS.ShouldAutoGrowPotion(watchKey, watch) == true then
                    local resolved = RS.ResolveWatchPotion and RS.ResolveWatchPotion(watchKey)
                    local potion = resolved and resolved.potion
                    local recipe = RS.RecipeSpecForPotion and RS.RecipeSpecForPotion(watchKey)
                    if type(potion) == "table" and type(recipe) == "table" then
                        local target = tonumber(watch.targetStock) or 0
                        local have = 0
                        if RS.PotionHaveCombined then
                            have = tonumber(RS.PotionHaveCombined(potion)) or 0
                        end
                        local craftable = 0
                        if RS.CountCraftsPossible then
                            local n = tonumber(RS.CountCraftsPossible(recipe)) or 0
                            local yield = tonumber(recipe.recipeYield) or 5
                            craftable = math.max(0, math.floor(n * yield + 0.5))
                        end
                        push(
                            watchKey,
                            potion.name,
                            math.max(0, target - have),
                            recipe,
                            have,
                            target,
                            craftable,
                            nil,
                            watch.priorityTier
                        )
                    end
                end
            end
        end
    end

    -- Match CollectFocus: best priority tier first, then max bottleGap, then lowest craftable.
    table.sort(list, function(a, b)
        local ta = tonumber(a.priorityTier) or 1
        local tb = tonumber(b.priorityTier) or 1
        if ta ~= tb then
            return ta < tb
        end
        local ga = tonumber(a.bottleGap) or 0
        local gb = tonumber(b.bottleGap) or 0
        if ga ~= gb then
            return ga > gb
        end
        local ca = tonumber(a.craftable) or 0
        local cb = tonumber(b.craftable) or 0
        if ca ~= cb then
            return ca < cb
        end
        local da = tonumber(a.deficit) or 0
        local db = tonumber(b.deficit) or 0
        if da ~= db then
            return da > db
        end
        return tostring(a.potionKey) < tostring(b.potionKey)
    end)
    return list
end

local function ResolveSeedForLiftSpec(spec, SM, demandRow)
    local plantUid = 0
    local seedUid = 0
    local seed = nil
    if type(demandRow) == "table" then
        plantUid = tonumber(demandRow.plantUid) or 0
        seedUid = tonumber(demandRow.seedUid) or 0
    end
    if SM.FindPlantUidForSpec and type(spec) == "table" then
        local found = tonumber(SM.FindPlantUidForSpec(spec)) or 0
        if found > 0 then
            plantUid = found
        end
    end
    -- Prefer skill-matched plant->seed; demand seedUid may be a stale L1 vendor id.
    if plantUid > 0 and SM.ResolveSeedUidForPlant then
        local matched = tonumber(SM.ResolveSeedUidForPlant(plantUid, spec)) or 0
        if matched > 0 then
            seedUid = matched
            seed = { uniqueID = matched, plantUid = plantUid }
        end
    end
    if seedUid <= 0 and SM.ResolveSeedForSpec and type(spec) == "table" then
        seed = SM.ResolveSeedForSpec(spec)
        if type(seed) == "table" then
            seedUid = tonumber(seed.uniqueID or seed.uid) or 0
            if plantUid <= 0 then
                plantUid = tonumber(seed.plantUid) or 0
            end
        end
    end
    -- Plant known but seed unmapped: still try PickBestSeedUid (learned grows / bag).
    if seedUid <= 0 and plantUid > 0 and SM.PickBestSeedUid then
        seedUid = tonumber(SM.PickBestSeedUid(plantUid, nil, spec)) or 0
        if seedUid > 0 then
            seed = { uniqueID = seedUid, plantUid = plantUid }
        end
    end
    if type(seed) ~= "table" and seedUid > 0 then
        seed = { uniqueID = seedUid, plantUid = plantUid }
    end
    return seed, seedUid, plantUid
end

--- Pick one seed that raises craftable for this watch, or why it cannot.
--- Returns job, why - why is nil on success; "refine-first" | "non-growable" | "no-seed" | "none".
local function PickCraftableLiftJobForWatch(watch, SM, RS, demand)
    if type(watch) ~= "table" or type(watch.recipe) ~= "table" then
        return nil, "none"
    end
    local recipe = watch.recipe
    if RS.HydrateRecipeSlots then
        RS.HydrateRecipeSlots(recipe)
    end
    local slots = recipe.slots
    if type(slots) ~= "table" or #slots == 0 then
        return nil, "none"
    end

    local snaps = {}
    local minCrafts = nil
    for i = 1, #slots do
        local slot = slots[i]
        if type(slot) == "table" then
            local spec = slot.spec
            if type(spec) ~= "table" and RS.ResolveSlotSpec then
                spec = RS.ResolveSlotSpec(slot)
            end
            if type(spec) == "table" then
                local perCraft = 1
                if RS.EffectiveSpecPerCraft then
                    perCraft = math.max(1, tonumber(RS.EffectiveSpecPerCraft(slot, slots)) or 1)
                else
                    perCraft = math.max(1, tonumber(slot.perCraft) or 1)
                end
                local specKey = nil
                local MS = StockPiler4.MaterialSpec
                if MS and MS.Key then
                    local bound = nil
                    if spec.incomplete == true then
                        bound = tonumber(spec.boundUid) or tonumber(spec.uid) or nil
                    end
                    specKey = MS.Key(spec, bound)
                end
                if (specKey == nil or specKey == "") and MS and MS.ProductKey then
                    specKey = MS.ProductKey(spec)
                end
                local demandRow = nil
                if type(demand) == "table" and specKey ~= nil and tostring(specKey) ~= "" then
                    demandRow = demand[specKey] or demand[tostring(specKey)]
                end
                local seed, seedUid, plantUid = ResolveSeedForLiftSpec(spec, SM, demandRow)
                local bag = 0
                if RS.CountItemsMatchingSpec then
                    bag = tonumber(RS.CountItemsMatchingSpec(spec)) or 0
                end
                local ground = CountSeedPlotCredit(seedUid)
                -- Pending plots are not always in Garden yet; after ReleaseSeedReservation
                -- _seedCommitted is 0 - still count _pendingPlant or we overfill one role.
                local have = bag + ground
                local craftsHave = math.floor(have / perCraft)
                if craftsHave < 0 then
                    craftsHave = 0
                end
                local growable = SM.IsGrowableSpec and SM.IsGrowableSpec(spec) == true
                local isByproduct = SM.IsHarvestByproduct and SM.IsHarvestByproduct(spec) == true
                -- Remaining item short vs absolute demand, using in-flight credit (not stale
                -- demandRow.craftsShort alone - that ignores plants just issued).
                local absNeed = 0
                if type(demandRow) == "table" then
                    absNeed = tonumber(demandRow.absolute) or tonumber(demandRow.brewAbsolute) or 0
                end
                local itemShort = math.max(0, absNeed - have)
                local demandShort = itemShort
                snaps[#snaps + 1] = {
                    spec = spec,
                    specKey = specKey,
                    role = tostring(slot.role or SpecRole(spec)),
                    perCraft = perCraft,
                    seed = seed,
                    seedUid = seedUid,
                    plantUid = plantUid,
                    have = have,
                    craftsHave = craftsHave,
                    growable = growable == true,
                    isByproduct = isByproduct == true,
                    demandShort = demandShort,
                    itemShort = itemShort,
                    demandRow = demandRow,
                }
                -- Only demand-short growables set the lift floor (ignore buy-only and stocked plants).
                if growable == true and itemShort > 0 then
                    if minCrafts == nil or craftsHave < minCrafts then
                        minCrafts = craftsHave
                    end
                end
            end
        end
    end
    -- No growable demand-short on this watch -> hand off (buy/convert-only or fully stocked plants).
    if minCrafts == nil then
        return nil, "non-growable"
    end
    minCrafts = tonumber(minCrafts) or 0

    local plantable = {}
    local needsRefine = false
    local Refine = StockPiler4.Refine
    for i = 1, #snaps do
        local s = snaps[i]
        if s.growable == true and (tonumber(s.itemShort) or 0) > 0 and s.craftsHave <= minCrafts then
            local seedUid = tonumber(s.seedUid) or 0
            local bag = OpaqueSeedCredit(seedUid, LiveSeedBag(seedUid))
            local committed = tonumber(GrowRef()._seedCommitted[seedUid]) or 0
            local avail = bag - committed
            if seedUid > 0 and CanUseSeedUid(seedUid) and avail >= 1 then
                -- Upgrade Seed owns mid-rung climbs: do not potion_stock-plant a seed
                -- that is not the skill-matched seed for this mat (L150 Spumepetal was
                -- filling plots for L200 demand; Items.skillReq is often 0 on bag shells).
                local US = StockPiler4.UpgradeSeed
                local underTier = false
                if US and US.IsEnabled and US.IsEnabled() == true and SM then
                    local plantUid = tonumber(s.plantUid) or 0
                    local matched = 0
                    if plantUid > 0 and SM.ResolveSeedUidForPlant then
                        matched = tonumber(SM.ResolveSeedUidForPlant(plantUid, s.spec)) or 0
                    end
                    if matched > 0 and seedUid ~= matched then
                        underTier = true
                    else
                        local needReq = tonumber(s.spec and s.spec.skillLevel) or 0
                        local seedReq = 0
                        local Inv = StockPiler4.Inventory
                        if Inv and Inv.GetSample then
                            local sample = Inv.GetSample(seedUid)
                            if type(sample) == "table" then
                                seedReq = tonumber(sample.craftingSkillRequirement)
                                    or tonumber(sample.skillReq) or 0
                            end
                        end
                        if seedReq <= 0 and StockPiler4.Items and StockPiler4.Items.GetByUid then
                            local row = StockPiler4.Items.GetByUid(seedUid)
                            if type(row) == "table" then
                                seedReq = tonumber(row.skillReq) or tonumber(row.skillLevel)
                                    or tonumber(row.craftingSkillRequirement) or 0
                            end
                        end
                        if needReq > 0 and seedReq > 0 and seedReq < needReq then
                            underTier = true
                        end
                    end
                end
                if underTier ~= true then
                    plantable[#plantable + 1] = s
                end
            else
                local refinable = 0
                if Refine and Refine.CountRefinablePlants then
                    refinable = tonumber(Refine.CountRefinablePlants(s.plantUid, s.spec)) or 0
                end
                if refinable > 0 then
                    needsRefine = true
                end
            end
        end
    end

    if #plantable <= 0 then
        if needsRefine then
            return nil, "refine-first"
        end
        return nil, "no-seed"
    end

    -- Among growable bottlenecks: cover remaining item short first (largest remaining),
    -- then fewest plants to next craft, then role, then diversify seed.
    local best = nil
    local bestRemain = -1
    local bestNeed = 999
    local bestRole = 99
    for i = 1, #plantable do
        local s = plantable[i]
        local remain = tonumber(s.itemShort) or 0
        local rem = s.have % s.perCraft
        local needToNext = (rem == 0) and s.perCraft or (s.perCraft - rem)
        if needToNext > remain then
            needToNext = remain
        end
        local role = RoleRank(s.role)
        local better = false
        if best == nil then
            better = true
        elseif remain > bestRemain then
            better = true
        elseif remain == bestRemain then
            if needToNext < bestNeed then
                better = true
            elseif needToNext == bestNeed then
                if role < bestRole then
                    better = true
                elseif role == bestRole
                    and (tonumber(s.seedUid) or 0) ~= (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
                    and (tonumber(best.seedUid) or 0) == (tonumber(GrowRef()._lastPlantedSeedUid) or 0)
                then
                    better = true
                end
            end
        end
        if better then
            best = s
            bestRemain = remain
            bestNeed = needToNext
            bestRole = role
        end
    end
    if best == nil then
        return nil, "none"
    end

    local craftsShort = math.max(1, bestNeed)
    return {
        spec = best.spec,
        specKey = best.specKey,
        seed = best.seed or { uniqueID = best.seedUid },
        seedUid = best.seedUid,
        plantUid = best.plantUid,
        seedHave = OpaqueSeedCredit(best.seedUid, LiveSeedBag(best.seedUid)),
        plantable = craftsShort,
        deficit = tonumber(watch.deficit) or 0,
        craftsShort = craftsShort,
        role = best.role,
        plantReason = "potion_stock",
        plotCount = CountInGroundSeeds(best.seedUid),
        pickMode = "watch-lift",
        watchKey = watch.potionKey,
        watchName = watch.name,
        potionDeficit = tonumber(watch.deficit) or 0,
    }, nil
end

local function LogPlantPick(job)
    if type(job) ~= "table" then
        return
    end
    local key = string.format(
        "%s:%s:%s",
        tostring(job.watchKey or ""),
        tostring(job.seedUid or 0),
        tostring(job.role or "")
    )
    if GrowRef()._lastPickLogKey == key then
        return
    end
    GrowRef()._lastPickLogKey = key
    LogGrow(string.format(
        "pick watch=%s deficit=%s role=%s seedUid=%s",
        tostring(job.watchKey or "?"),
        tostring(job.potionDeficit or job.deficit or 0),
        tostring(job.role or "?"),
        tostring(job.seedUid or 0)
    ))
end

function PlantPlan.PickPlantJob(opts)
    opts = type(opts) == "table" and opts or {}
    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("PickPlantCandidate")
    end
    local function done(job)
        if Perf and Perf.End then
            Perf.End("PickPlantCandidate")
        end
        return job
    end
    if GrowRef().ClampSeedCommitsToBag then GrowRef().ClampSeedCommitsToBag() end
    local RS = StockPiler4.RecipeSpec
    local SM = StockPiler4.SeedMap
    if type(RS) ~= "table" or type(SM) ~= "table"
        or not SM.IsGrowableSpec or not SM.ResolveSeedForSpec
    then
        return done(nil)
    end

    -- Upgrade Seed refine-first: skip BuildBalancedSpecDemand (WarmHave.miss) —
    -- orch trails showed PickPlantCandidate + CollectIntents on every refine tick.
    local US = StockPiler4.UpgradeSeed
    if US and US.IsEnabled and US.IsEnabled() == true then
        if US.NeedsRefineFirst and US.NeedsRefineFirst() == true then
            if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                StockPiler4.Refine.MarkRefineDue("upgrade-seed")
            end
            return done(nil)
        end
    end

    local demand = opts.demand
    if type(demand) ~= "table" then
        local PS = StockPiler4.PlanSnapshot
        local plan = PS and PS.Get and PS.Get()
        if type(plan) == "table" and type(plan.demand) == "table" then
            demand = plan.demand
        end
    end
    if type(demand) ~= "table" then
        local DP = StockPiler4.DemandPlan
        if DP and DP.Build then
            demand = DP.Build()
        elseif RS.BuildBalancedSpecDemand then
            demand = RS.BuildBalancedSpecDemand()
        end
    end
    local watches = CollectPlantWatchOrder(RS)
    local maxGap = 0
    for i = 1, #watches do
        local g = tonumber(watches[i].bottleGap) or 0
        if g > maxGap then
            maxGap = g
        end
    end
    local needsRefine = false
    for i = 1, #watches do
        local watch = watches[i]
        local job, why = PickCraftableLiftJobForWatch(watch, SM, RS, demand)
        if type(job) == "table" then
            LogPlantPick(job)
            return done(job)
        end
        if why == "refine-first" then
            -- Focus watch has plants to convert - idle plots until refine, do not fill
            -- lower-gap watches while those seeds are pending.
            needsRefine = true
            break
        end
        -- no-seed / non-growable -> fall back to next watch (lower bottleGap OK).
        -- Bottle-gap order already preferred focus; empty plots should not idle when
        -- another watch has plantable seeds.
    end
    if needsRefine then
        return done(nil)
    end

    -- Upgrade Seed: climb lower family rungs toward short watch mats (before buffer /
    -- SkillUp). Must run for plant-only watches too - gating on potion #watches
    -- skipped Taut Gobswort while SkillUp filled plots with spiderfrond (3010015).
    if US and US.IsEnabled and US.IsEnabled() == true then
        local uj = US.PickPlantJob and US.PickPlantJob() or nil
        if type(uj) == "table" and (tonumber(uj.seedUid) or 0) > 0 then
            uj.upgradeClimb = true
            uj.pickMode = uj.pickMode or "upgrade"
            LogPlantPick(uj)
            return done(uj)
        end
        -- Climb still progressing: hold only when no upgrade target has
        -- plantable seeds or refinable plants (climbing/need_buy must not
        -- starve another genus's refine or plant).
        local climb = US.StatusForWatch and US.StatusForWatch() or nil
        if type(climb) ~= "table" and US.GetActiveStatus then
            climb = US.GetActiveStatus()
        end
        if type(climb) == "table" then
            local why = tostring(climb.why or "")
            if why == "need_cult" then
                if US.MaybeNotifyStall then
                    US.MaybeNotifyStall()
                end
                -- fall through - cannot climb further until Cult rises
            elseif US.ShouldHoldEmptyPlots and US.ShouldHoldEmptyPlots(climb) == true then
                if US.MaybeNotifyStall then
                    US.MaybeNotifyStall()
                end
                return done(nil)
            elseif US.MaybeNotifyStall then
                US.MaybeNotifyStall()
            end
        elseif US.MaybeNotifyStall then
            US.MaybeNotifyStall()
        end
    end

    if type(demand) == "table" and PotionStockNeedsRefineFirst(demand, SM) then
        return done(nil)
    end

    local Watch = StockPiler4.Watch
    local lines = {}
    local focusGap = maxGap
    if Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true
        and RS.CollectAutoGrowSeedLines
    then
        lines = RS.CollectAutoGrowSeedLines() or {}
        if focusGap <= 0 then
            for i = 1, #watches do
                local d = tonumber(watches[i].deficit) or 0
                if d > focusGap then
                    focusGap = d
                end
            end
        end
        local best = PickBufferGrowCandidate(lines, SM, nil, demand, focusGap)
        if best ~= nil then
            best.pickMode = "buffer"
            LogPlantPick(best)
            return done(best)
        end
        -- focusGap > 0 with no buffer job: do NOT idle here. plant_stock is soft-gated
        -- (buy/brew shorts do not block); SkillUp remains gated by ShouldCultPlant.
    elseif #watches > 0 then
        -- Buffer off, watches still short: same fall-through to plant_stock / SkillUp.
    end

    local best = PickPlantStockCandidate(SM)
    if best ~= nil then
        best.pickMode = "plant_stock"
        LogPlantPick(best)
        return done(best)
    end
    best = PickSurplusCandidate(lines)
    if best ~= nil then
        best.pickMode = "surplus"
        LogPlantPick(best)
        return done(best)
    end

    -- Idle SkillUp Cult: only after watches are done (SkillUp.ShouldCultPlant gates).
    local SkillUp = StockPiler4.SkillUp
    if SkillUp and SkillUp.ShouldCultPlant and SkillUp.ShouldCultPlant() == true then
        local job = SkillUp.PickPlantJob and SkillUp.PickPlantJob()
        if type(job) == "table" and (tonumber(job.seedUid) or 0) > 0 then
            LogPlantPick(job)
            return done(job)
        end
        if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
            StockPiler4.Refine.MarkRefineDue("skill-up")
        end
        if SkillUp.MaybeNotifyStall then
            SkillUp.MaybeNotifyStall()
        end
    end
    return done(nil)
end

function PlantPlan.BuildPlantIntentFromCached()
    local grow = GrowRef()
    local job = grow and grow.GetPlantJob and grow.GetPlantJob() or nil
    return PlantPlan.BuildPlantIntent(job)
end

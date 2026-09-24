----------------------------------------------------------------
-- StockPiler4 Planner/CultSkillPlan - idle Cult plant/refine/buy
-- Extracted from SkillUp; SkillUp re-exports for callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.CultSkillPlan = StockPiler4.CultSkillPlan or {}
local CSP = StockPiler4.CultSkillPlan

local function Gates()
    return StockPiler4.SkillUpGates
end

local function WR()
    return StockPiler4.WatchReserves
end

local function ASP()
    return StockPiler4.ApoSkillPlan
end

local function ClimbEconomy()
    return StockPiler4.ClimbPlan or StockPiler4.UpgradeSeed
end

local function MirrorStallToSkillUp()
    -- Stall latch lives on CSP.
end

CSP._stallLatch = nil

local function SeedSkillReq(item)
    if type(item) ~= "table" then
        return 0
    end
    local req = tonumber(item.craftingSkillRequirement) or tonumber(item.skillReq) or 0
    if req <= 0 and type(item.bonuses) == "table" then
        req = tonumber(item.bonuses[9]) or 0
    end
    return req
end

local function LooksNonMainSeed(item, plantSpec)
    local role = tostring(plantSpec and plantSpec.role or "")
    if role == "stabilizer" or role == "extender" or role == "multiplier"
        or role == "stimulant" or role == "goldweed" or role == "container"
    then
        return true
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.SpecHasGoldweedMultiplier and type(plantSpec) == "table"
        and SM.SpecHasGoldweedMultiplier(plantSpec) == true
    then
        return true
    end
    if SM and SM.IsHarvestByproduct and type(plantSpec) == "table"
        and SM.IsHarvestByproduct(plantSpec) == true
    then
        return true
    end
    local n = ""
    if type(item) == "table" and item.name ~= nil then
        if type(item.name) == "wstring" and type(WStringToString) == "function" then
            n = string.lower(WStringToString(item.name) or "")
        else
            n = string.lower(tostring(item.name or ""))
        end
    end
    if string.find(n, "goldweed", 1, true) or string.find(n, "gobswort", 1, true)
        or string.find(n, "resin", 1, true)
    then
        return true
    end
    return false
end

local function IsMainIngredientSeed(seedUid, item)
    seedUid = tonumber(seedUid) or 0
    local SM = StockPiler4.SeedMap
    local plantUid = 0
    if SM and SM.PrimaryPlantForSeed then
        plantUid = tonumber(SM.PrimaryPlantForSeed(seedUid)) or 0
    end
    local plantSpec = nil
    if plantUid > 0 then
        local Items = StockPiler4.Items
        if Items and Items.ToSpec then
            plantSpec = Items.ToSpec(plantUid)
        end
        if type(plantSpec) ~= "table" then
            local MS = StockPiler4.MaterialSpec
            if MS and MS.FromUid then
                plantSpec = MS.FromUid(plantUid)
            end
        end
    end
    if type(plantSpec) == "table" then
        local role = tostring(plantSpec.role or "")
        if role == "main" then
            return true
        end
        if LooksNonMainSeed(item, plantSpec) then
            return false
        end
    end
    -- Unlinked: prefer seeds that look like mains (EFFECT bonus / Grows *).
    local MS = StockPiler4.MaterialSpec
    if MS and MS.FromItemData and type(item) == "table" then
        local hinted = MS.FromItemData(item, "main")
        if type(hinted) == "table" then
            local fx = tonumber(hinted.effectId) or 0
            if fx > 0 and not LooksNonMainSeed(item, hinted) then
                return true
            end
        end
    end
    if type(plantSpec) == "table" and tostring(plantSpec.role or "") == "" then
        return not LooksNonMainSeed(item, plantSpec)
    end
    -- Unknown linkage: allow if not obviously non-main.
    return not LooksNonMainSeed(item, plantSpec)
end

local function CanUseCraftingSample(sample)
    local Inv = StockPiler4.Inventory
    if type(sample) ~= "table" then
        return false
    end
    if Inv and Inv.CanUseCraftingItem then
        return Inv.CanUseCraftingItem(sample) == true
    end
    return true
end

--- Best plantable main seed for Cult SkillUp (nil if none in bags).
--- Prefers highest skillReq <= TargetMaxSkill; else next-best lower tier.
--- Cult 200 + Apo SkillUp: still plant Apo-tier seeds (assist).
local function ScoreBagSeedPick(pick, targetMax, SM, Refine, Items)
    if type(pick) ~= "table" or (tonumber(pick.seedUid) or 0) <= 0 then
        return -1
    end
    local uid = tonumber(pick.seedUid) or 0
    local req = tonumber(pick.skillReq) or 0
    local plantUid = tonumber(pick.plantUid) or 0
    local count = tonumber(pick.count) or 0
    local refinable = 0
    if plantUid > 0 and Refine and Refine.CountRefinablePlants then
        local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
        refinable = tonumber(Refine.CountRefinablePlants(plantUid, spec)) or 0
    end
    local deficit = tonumber(CSP.SeedDeficit(uid)) or 0
    local settleBonus = 0
    if deficit <= 0 then
        settleBonus = 50000000
    elseif refinable >= deficit then
        settleBonus = 30000000
    elseif refinable > 0 then
        settleBonus = 10000000 + math.min(refinable, 99) * 1000
    else
        settleBonus = math.max(0, 5000 - deficit * 10)
    end
    local tier = 1
    if SM and SM.SeedReplantTier then
        tier = tonumber(SM.SeedReplantTier(uid)) or 1
    end
    local exactBonus = (req == targetMax) and 100000000 or 0
    return exactBonus + (req * 1000000) + settleBonus + (tier * 10000) + count
end

local function PickBestBagSeedViaClimbPlan(targetMax)
    local CE = ClimbEconomy()
    local SM = StockPiler4.SeedMap
    local Inv = StockPiler4.Inventory
    local Refine = StockPiler4.Refine
    local Items = StockPiler4.Items
    local GL = StockPiler4.GenusLadder
    if not (CE and CE.PickBestOwnedSeed and ((GL and GL.GetLadder) or (SM and SM.GetGenusLadder)) and Inv and Inv.ForEachItem) then
        return nil
    end
    local genera = {}
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        local uid = tonumber(item.uniqueID) or 0
        if uid <= 0 then
            return
        end
        if SM.IsSeedPacketUid and SM.IsSeedPacketUid(uid) then
            return
        end
        if not (SM.IsBagSeedOrSpore and SM.IsBagSeedOrSpore(item)) then
            return
        end
        if not CanUseCraftingSample(item) then
            return
        end
        local req = SeedSkillReq(item)
        if req > targetMax or req < 1 then
            return
        end
        if not IsMainIngredientSeed(uid, item) then
            return
        end
        local genus = SM.GenusKeyFromName and SM.GenusKeyFromName(item.name) or nil
        if genus and genus ~= "" then
            genera[genus] = true
        end
    end)
    local best = nil
    local bestScore = -1
    for genus, _ in pairs(genera) do
        local ladder = (GL and GL.GetLadder and GL.GetLadder(genus))
            or (SM.GetGenusLadder and SM.GetGenusLadder(genus))
        if type(ladder) == "table" then
            local pick = CE.PickBestOwnedSeed({
                ladder = ladder,
                climbCap = targetMax,
                mainsOnly = true,
            })
            if type(pick) == "table" and (tonumber(pick.seedUid) or 0) > 0 then
                if pick.item == nil and Inv.GetSample then
                    pick.item = Inv.GetSample(pick.seedUid)
                end
                local score = ScoreBagSeedPick(pick, targetMax, SM, Refine, Items)
                if score > bestScore then
                    bestScore = score
                    best = pick
                end
            end
        end
    end
    return best
end

function CSP.PickBestBagSeed()
    local cult = Gates().GetCultSkill()
    if cult <= 0 then
        return nil
    end
    if cult >= (Gates().CULT_MAX or 200) and Gates().IsApoEnabled() ~= true then
        return nil
    end
    local targetMax = Gates().TargetMaxSkill()
    if targetMax < 1 then
        targetMax = 1
    end
    local viaClimb = PickBestBagSeedViaClimbPlan(targetMax)
    local SM = StockPiler4.SeedMap
    local Inv = StockPiler4.Inventory
    local Refine = StockPiler4.Refine
    local Items = StockPiler4.Items
    if not (SM and Inv and Inv.ForEachItem) then
        return viaClimb
    end
    local best = viaClimb
    local bestScore = ScoreBagSeedPick(viaClimb, targetMax, SM, Refine, Items)
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        local uid = tonumber(item.uniqueID) or 0
        if uid <= 0 then
            return
        end
        if SM.IsSeedPacketUid and SM.IsSeedPacketUid(uid) then
            return
        end
        if not (SM.IsBagSeedOrSpore and SM.IsBagSeedOrSpore(item)) then
            return
        end
        if not CanUseCraftingSample(item) then
            return
        end
        local req = SeedSkillReq(item)
        if req > targetMax then
            return
        end
        if not IsMainIngredientSeed(uid, item) then
            return
        end
        local count = Inv.CountByUid and tonumber(Inv.CountByUid(uid)) or 0
        if count <= 0 then
            return
        end
        local plantUid = 0
        if SM.PrimaryPlantForSeed then
            plantUid = tonumber(SM.PrimaryPlantForSeed(uid)) or 0
        end
        local score = ScoreBagSeedPick({
            seedUid = uid,
            skillReq = req,
            plantUid = plantUid,
            count = count,
            item = item,
        }, targetMax, SM, Refine, Items)
        if score > bestScore then
            bestScore = score
            best = {
                seedUid = uid,
                skillReq = req,
                plantUid = plantUid,
                count = count,
                item = item,
            }
        end
    end)
    return best
end

--- Seed budget - ClimbPlan facade over Refine.GetSeedBudget.
local function SeedBudget(seedUid)
    local CE = ClimbEconomy()
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
        live = 0,
        ground = 0,
        outstanding = 0,
        credit = 0,
        headroom = 0,
        bufferMin = 0,
    }
end

--- True when SkillUp should refine before planting (upgrade or buffer fill).
--- Used by PickPlantJob hold and Refine.ShouldAllowRefineNow so plant-first
--- cannot starve a live refine path.
function CSP.PreferRefineOverPlant()
    if Gates().ShouldCultPlant() ~= true then
        return false
    end
    if CSP.HasUpgradePlant() == true then
        return true
    end
    local target = CSP.PickRefineTarget()
    if type(target) ~= "table" or target.upgrade == true then
        return false
    end
    local seedUid = tonumber(target.seedUid) or 0
    if seedUid <= 0 then
        return false
    end
    local budget = SeedBudget(seedUid)
    local buffer = tonumber(budget.bufferMin) or 0
    local headroom = tonumber(budget.headroom) or 0
    if buffer <= 0 or headroom <= 0 then
        return false
    end
    local uses = CSP.RefineUsesForTarget(target)
    return (tonumber(uses) or 0) >= 1
end

function CSP.PickPlantJob()
    if Gates().ShouldCultPlant() ~= true then
        return nil
    end
    -- Hold planting while refine can make progress (upgrade or buffer fill).
    if CSP.PreferRefineOverPlant() == true then
        if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
            if CSP.HasUpgradePlant() == true then
                StockPiler4.Refine.MarkRefineDue("skill-up")
            else
                StockPiler4.Refine.MarkRefineDue("skill-up-buffer")
            end
        end
        if StockPiler4.Debug and StockPiler4.Debug.LogOp then
            local pick = CSP.PickBestBagSeed()
            local seedUid = type(pick) == "table" and (tonumber(pick.seedUid) or 0) or 0
            local budget = SeedBudget(seedUid)
            StockPiler4.Debug.LogOp("skillup", string.format(
                "hold-plant seedUid=%d headroom=%d upgrade=%s (prefer refine)",
                seedUid,
                tonumber(budget.headroom) or 0,
                tostring(CSP.HasUpgradePlant() == true)
            ))
        end
        return nil
    end
    local pick = CSP.PickBestBagSeed()
    if type(pick) ~= "table" or (tonumber(pick.seedUid) or 0) <= 0 then
        return nil
    end
    local seedUid = tonumber(pick.seedUid) or 0
    local plantUid = tonumber(pick.plantUid) or 0
    local budget = SeedBudget(seedUid)
    local buffer = tonumber(budget.bufferMin) or 0
    local live = tonumber(budget.live) or 0
    local headroom = tonumber(budget.headroom) or 0
    local empty = CSP.CountEmptyPlots()
    local bagSeeds = tonumber(pick.count) or 0

    local refinable = 0
    if plantUid > 0 and StockPiler4.Refine and StockPiler4.Refine.CountRefinablePlants then
        local Items = StockPiler4.Items
        local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
        refinable = tonumber(StockPiler4.Refine.CountRefinablePlants(plantUid, spec)) or 0
    end

    -- Fill empty plots whenever bag has seeds (ClimbPlan PlantableSurplus skillup mode).
    local CE = ClimbEconomy()
    local plantable = 0
    if CE and CE.PlantableSurplus then
        plantable = tonumber(CE.PlantableSurplus(seedUid, bagSeeds, empty, { mode = "skillup" })) or 0
    elseif empty > 0 and bagSeeds > 0 then
        if buffer > 0 and headroom > 0 then
            plantable = math.min(bagSeeds, empty, headroom)
        else
            plantable = math.min(bagSeeds, empty)
        end
    end
    -- Never plant seeds still claimed by short enabled watches.
    local watchSeedNeed = WR().WatchDemandReserve(seedUid)
    if plantUid > 0 then
        local plantNeed = WR().WatchDemandReserve(plantUid)
        if plantNeed > watchSeedNeed then
            watchSeedNeed = plantNeed
        end
    end
    if watchSeedNeed > 0 then
        local freeSeeds = bagSeeds - watchSeedNeed
        if freeSeeds < 1 then
            plantable = 0
        elseif plantable > freeSeeds then
            plantable = freeSeeds
        end
    end

    if plantable < 1 then
        if StockPiler4.Debug and StockPiler4.Debug.LogOp then
            StockPiler4.Debug.LogOp("skillup", string.format(
                "no-plant-job seedUid=%d live=%d buffer=%d headroom=%d empty=%d refinable=%d bag=%d",
                seedUid, live, buffer, headroom, empty, refinable, bagSeeds
            ))
        end
        return nil
    end
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "plant-job seedUid=%d live=%d headroom=%d empty=%d plantable=%d",
            seedUid, live, headroom, empty, plantable
        ))
    end
    CSP._lastSeedUid = seedUid
    CSP._lastPlantUid = plantUid
    return {
        seedUid = seedUid,
        plantUid = plantUid,
        seed = pick.item or { uniqueID = seedUid },
        seedHave = bagSeeds,
        plantable = plantable,
        deficit = plantable,
        craftsShort = plantable,
        skillReq = tonumber(pick.skillReq) or 0,
        pickMode = "skill_up",
        plantReason = "skill_up",
        role = "main",
    }
end

function CSP.CountEmptyPlots()
    local CE = ClimbEconomy()
    if CE and CE.CountEmptyPlots then
        return CE.CountEmptyPlots()
    end
    local Grow = StockPiler4.Grow
    if Grow and Grow.CountEmptyPlots then
        return tonumber(Grow.CountEmptyPlots()) or 0
    end
    return 0
end

--- Seeds still needed for buffer headroom and/or empty-plot planting.
--- Delegates to ClimbPlan.SeedDeficit(..., "skillup").
function CSP.SeedDeficit(seedUid)
    local CE = ClimbEconomy()
    if CE and CE.SeedDeficit then
        return CE.SeedDeficit(seedUid, "skillup")
    end
    seedUid = tonumber(seedUid) or 0
    local empty = CSP.CountEmptyPlots()
    local budget = SeedBudget(seedUid)
    local headroom = tonumber(budget.headroom) or 0
    local live = tonumber(budget.live) or 0
    local needPlots = empty
    if live >= empty then
        needPlots = 0
    else
        needPlots = empty - live
    end
    return math.max(headroom, needPlots)
end

--- Best refinable main plant under Cult skill floor (nil if none).
--- Uses FloorCultTier (not TargetMaxSkill) so lucky crits above the Apo pace
--- can still be refined into seeds; planting stays capped by TargetMaxSkill.
function CSP.ScanBestRefinePlant()
    local cult = Gates().GetCultSkill()
    local targetMax = Gates().FloorCultTier(cult)
    if targetMax < 1 then
        targetMax = Gates().TargetMaxSkill()
    end
    if targetMax < 1 then
        targetMax = 1
    end
    local CE = ClimbEconomy()
    if CE and CE.ScanUpgradePlant then
        local seed = CSP.PickBestBagSeed and CSP.PickBestBagSeed() or nil
        local ownedReq = type(seed) == "table" and (tonumber(seed.skillReq) or 0) or 0
        return CE.ScanUpgradePlant({
            climbCap = targetMax,
            ownedSeedReq = ownedReq,
            mainsOnly = true,
        })
    end
    return nil
end

--- True when a higher-tier plant can *actually* refine into seeds now.
--- A lone upgrade plant that fails PlantRefineSurplus must not block planting.
function CSP.HasUpgradePlant()
    if Gates().ShouldCultPlant() ~= true then
        return false
    end
    local plant = CSP.ScanBestRefinePlant()
    if type(plant) ~= "table" then
        return false
    end
    local plantReq = tonumber(plant.skillReq) or 0
    if plantReq < 1 then
        return false
    end
    local seed = CSP.PickBestBagSeed()
    local seedReq = type(seed) == "table" and (tonumber(seed.skillReq) or 0) or 0
    if plantReq <= seedReq then
        return false
    end
    local uses = CSP.RefineUsesForTarget({
        seedUid = tonumber(plant.seedUid) or 0,
        plantUid = tonumber(plant.plantUid) or 0,
        skillReq = plantReq,
        upgrade = true,
    })
    return (tonumber(uses) or 0) >= 1
end

--- Resolve seed/plant for SkillUp refine (replant + tier graduation).
--- Prefers upgrade only when RefineUsesForTarget >= 1; else same-tier.
function CSP.PickRefineTarget()
    local SM = StockPiler4.SeedMap

    -- Prefer graduating when the upgrade plant can refine now.
    local upgrade = CSP.ScanBestRefinePlant()
    if type(upgrade) == "table" then
        local plantReq = tonumber(upgrade.skillReq) or 0
        local seed = CSP.PickBestBagSeed()
        local seedReq = type(seed) == "table" and (tonumber(seed.skillReq) or 0) or 0
        if plantReq > seedReq then
            local target = {
                seedUid = tonumber(upgrade.seedUid) or 0,
                plantUid = tonumber(upgrade.plantUid) or 0,
                skillReq = plantReq,
                upgrade = true,
            }
            local uses = CSP.RefineUsesForTarget(target)
            if (tonumber(uses) or 0) >= 1 then
                return target
            end
            if StockPiler4.Debug and StockPiler4.Debug.LogOp then
                StockPiler4.Debug.LogOp("skillup", string.format(
                    "upgrade-skip plantUid=%d req=%d (no refine uses; fall through)",
                    tonumber(upgrade.plantUid) or 0, plantReq
                ))
            end
        end
    end

    local pick = CSP.PickBestBagSeed()
    if type(pick) == "table" and (tonumber(pick.seedUid) or 0) > 0 then
        local plantUid = tonumber(pick.plantUid) or 0
        if plantUid <= 0 and SM and SM.PrimaryPlantForSeed then
            plantUid = tonumber(SM.PrimaryPlantForSeed(pick.seedUid)) or 0
        end
        -- Prefer an in-bag harvest product for this seed when available.
        if SM and SM.HarvestProducts and (tonumber(pick.seedUid) or 0) > 0 then
            local Refine = StockPiler4.Refine
            local products = SM.HarvestProducts(pick.seedUid) or {}
            for i = 1, #products do
                local pUid = tonumber(products[i] and products[i].uid) or 0
                if pUid > 0 and Refine and Refine.CountRefinablePlants
                    and (tonumber(Refine.CountRefinablePlants(pUid, nil)) or 0) > 0
                then
                    plantUid = pUid
                    break
                end
            end
        end
        return {
            seedUid = tonumber(pick.seedUid) or 0,
            plantUid = plantUid,
            skillReq = tonumber(pick.skillReq) or 0,
        }
    end

    local seedUid = tonumber(CSP._lastSeedUid) or 0
    local plantUid = tonumber(CSP._lastPlantUid) or 0
    if seedUid > 0 then
        if plantUid <= 0 and SM and SM.PrimaryPlantForSeed then
            plantUid = tonumber(SM.PrimaryPlantForSeed(seedUid)) or 0
        end
        if plantUid > 0 then
            return { seedUid = seedUid, plantUid = plantUid }
        end
        if SM and SM.HarvestProducts then
            local Refine = StockPiler4.Refine
            local products = SM.HarvestProducts(seedUid) or {}
            local fallback = nil
            for i = 1, #products do
                local pUid = tonumber(products[i] and products[i].uid) or 0
                if pUid > 0 then
                    local refinable = 0
                    if Refine and Refine.CountRefinablePlants then
                        refinable = tonumber(Refine.CountRefinablePlants(pUid, nil)) or 0
                    end
                    if refinable > 0 then
                        return { seedUid = seedUid, plantUid = pUid }
                    end
                    if fallback == nil then
                        fallback = pUid
                    end
                end
            end
            if fallback ~= nil then
                return { seedUid = seedUid, plantUid = fallback }
            end
        end
    end

    return nil
end

--- How many SkillUp refine uses a PickRefineTarget-shaped row can issue (0 if none).
--- Shared by HasUpgradePlant / PickRefineTarget / AppendRefineIntents / HasRefinablePlants.
function CSP.RefineUsesForTarget(target)
    if type(target) ~= "table" then
        return 0, nil
    end
    local seedUid = tonumber(target.seedUid) or 0
    local plantUid = tonumber(target.plantUid) or 0
    if seedUid <= 0 or plantUid <= 0 then
        return 0, nil
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.ResolveSeedUidForPlant then
        local resolved = tonumber(SM.ResolveSeedUidForPlant(plantUid, nil)) or 0
        if resolved > 0 then
            seedUid = resolved
        end
    end
    local budget = SeedBudget(seedUid)
    local deficit = CSP.SeedDeficit(seedUid)
    local isUpgrade = target.upgrade == true
    -- Tier graduation must refine even when SeedDeficit is 0.
    if deficit <= 0 and not isUpgrade then
        return 0, nil
    end
    local headroom = tonumber(budget.headroom) or 0
    local usesCap = deficit
    if isUpgrade and usesCap < 1 then
        usesCap = 5
    end
    if headroom > 0 and headroom < usesCap then
        usesCap = headroom
    elseif headroom <= 0 and deficit > 0 and not isUpgrade then
        usesCap = deficit
    end
    if isUpgrade and usesCap < 1 then
        usesCap = 5
    end
    local Inv = StockPiler4.Inventory
    local bagCount = 0
    if plantUid > 0 and Inv and Inv.CountByUid then
        bagCount = tonumber(Inv.CountByUid(plantUid)) or 0
    end
    local surplus = WR().PlantRefineSurplus(plantUid, seedUid, bagCount)
    if surplus < 1 then
        return 0, nil
    end
    if surplus < usesCap then
        usesCap = surplus
    end
    local Items = StockPiler4.Items
    local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
    local Refine = StockPiler4.Refine
    local refinable = 0
    if Refine and Refine.CountRefinablePlants then
        refinable = tonumber(Refine.CountRefinablePlants(plantUid, spec)) or 0
    end
    if refinable <= 0 then
        return 0, nil
    end
    local uses = math.min(refinable, usesCap, 5)
    if uses < 1 then
        return 0, nil
    end
    return uses, {
        seedUid = seedUid,
        plantUid = plantUid,
        spec = spec,
        budget = budget,
        isUpgrade = isUpgrade,
        headroom = headroom,
        deficit = deficit,
        skillReq = tonumber(target.skillReq) or 0,
        refinable = refinable,
    }
end

--- Refine intent: convert plants for buffer headroom / empty-plot gaps / upgrades.
--- SkillUp policy (PickRefineTarget / RefineUsesForTarget); economy via ClimbPlan.
function CSP.AppendRefineIntents(intents, appendFn)
    if type(intents) ~= "table" or type(appendFn) ~= "function" then
        return
    end
    if Gates().ShouldCultPlant() ~= true then
        return
    end
    local target = CSP.PickRefineTarget()
    local uses, info = CSP.RefineUsesForTarget(target)
    if (tonumber(uses) or 0) < 1 or type(info) ~= "table" then
        return
    end
    CSP._lastSeedUid = info.seedUid
    CSP._lastPlantUid = info.plantUid
    appendFn({
        spec = info.spec,
        seedUid = info.seedUid,
        plantUid = info.plantUid,
        specKey = "skill_up:" .. tostring(info.seedUid),
    }, "skill-up", uses, info.budget)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "refine-intent seedUid=%d plantUid=%d uses=%d empty=%d refinable=%d upgrade=%s req=%d headroom=%d deficit=%d",
            info.seedUid, info.plantUid, uses, CSP.CountEmptyPlots(), info.refinable,
            tostring(info.isUpgrade), info.skillReq,
            info.headroom, info.deficit
        ))
    end
end

--- Preferred vendor seed for AutoBuy: same line as bag pick / refine plants when possible.
function CSP.ResolveBuySeedTarget()
    -- Top up the SkillUp line already chosen from bags.
    local pick = CSP.PickBestBagSeed and CSP.PickBestBagSeed() or nil
    if type(pick) == "table" and (tonumber(pick.seedUid) or 0) > 0 then
        return {
            seedUid = tonumber(pick.seedUid) or 0,
            skillReq = tonumber(pick.skillReq) or 0,
            targetMax = Gates().TargetMaxSkill(),
        }
    end

    local targetMax = Gates().TargetMaxSkill()
    if targetMax < 1 then
        targetMax = 1
    end
    -- Prefer the seed linked to refinable plants already in bags.
    local preferUid = 0
    local plant = CSP.ScanBestRefinePlant and CSP.ScanBestRefinePlant() or nil
    if type(plant) == "table" then
        preferUid = tonumber(plant.seedUid) or 0
    end

    local bestUid, bestReq, bestScore = 0, -1, -1
    local function consider(uid, item)
        uid = tonumber(uid) or 0
        if uid <= 0 or type(item) ~= "table" then
            return
        end
        local SM = StockPiler4.SeedMap
        if SM and SM.IsSeedPacketUid and SM.IsSeedPacketUid(uid) then
            return
        end
        if SM and SM.IsBagSeedOrSpore and not SM.IsBagSeedOrSpore(item) then
            return
        end
        local req = SeedSkillReq(item)
        if req <= 0 or req > targetMax then
            return
        end
        if not IsMainIngredientSeed(uid, item) then
            return
        end
        local tier = SM and SM.SeedReplantTier and tonumber(SM.SeedReplantTier(uid)) or 1
        local exactBonus = (req == targetMax) and 100000000 or 0
        local preferBonus = (preferUid > 0 and uid == preferUid) and 50000000 or 0
        local score = exactBonus + preferBonus + (req * 1000000) + (tier * 10000)
        if score > bestScore then
            bestScore = score
            bestReq = req
            bestUid = uid
        end
    end

    -- Learned items (may include seeds not in bags).
    local items = StockPiler4.Account and StockPiler4.Account.items
    if type(items) == "table" then
        for key, row in pairs(items) do
            if type(row) == "table" then
                local uid = tonumber(row.uniqueID) or tonumber(key) or 0
                consider(uid, row)
            end
        end
    end

    -- Open vendor rows.
    local VA = StockPiler4.VendorAdapter
    if VA and VA.GetMatchIndex then
        local index = VA.GetMatchIndex()
        if type(index) == "table" and type(index.rows) == "table" then
            for i = 1, #index.rows do
                local row = index.rows[i]
                local item = row and row.item
                if type(item) == "table" then
                    consider(item.uniqueID, item)
                end
            end
        end
    end

    if bestUid <= 0 then
        return nil
    end
    return {
        seedUid = bestUid,
        skillReq = bestReq,
        targetMax = targetMax,
    }
end

--- True when SkillUp can issue at least one refine use right now.
function CSP.HasRefinablePlants()
    local target = CSP.PickRefineTarget()
    local uses = CSP.RefineUsesForTarget(target)
    return (tonumber(uses) or 0) >= 1
end

--- Buy when SeedDeficit >= 1 for the chosen line (plots + buffer), even if bags
--- already hold some seeds. Refine-before-buy when plants can cover that line.
function CSP.ShouldCultBuy()
    if Gates().ShouldCultPlant() ~= true then
        return false
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
        return false
    end

    local pick = CSP.PickBestBagSeed()
    local seedUid = 0
    local plantUid = 0
    if type(pick) == "table" then
        seedUid = tonumber(pick.seedUid) or 0
        plantUid = tonumber(pick.plantUid) or 0
    else
        -- Empty bags: refine leftover plants before opening the vendor.
        if CSP.HasRefinablePlants() == true or CSP.HasUpgradePlant() == true then
            return false
        end
        local target = CSP.ResolveBuySeedTarget()
        if type(target) ~= "table" then
            return false
        end
        seedUid = tonumber(target.seedUid) or 0
    end
    if seedUid <= 0 then
        return false
    end

    local deficit = CSP.SeedDeficit(seedUid)
    if deficit < 1 then
        return false
    end

    -- Plants for this seed: refine before AutoBuy only when refine can run.
    if plantUid <= 0 then
        local SM = StockPiler4.SeedMap
        if SM and SM.PrimaryPlantForSeed then
            plantUid = tonumber(SM.PrimaryPlantForSeed(seedUid)) or 0
        end
    end
    if plantUid > 0 then
        local uses = CSP.RefineUsesForTarget({
            seedUid = seedUid,
            plantUid = plantUid,
            upgrade = false,
        })
        if (tonumber(uses) or 0) >= 1 then
            return false
        end
    end
    return true
end

function CSP.CollectBuyJobs()
    local jobs = {}
    -- Cult SkillUp seed top-up (SeedDeficit via ClimbPlan); climb L1 buys stay on UpgradeSeed path in Buy.lua.
    if CSP.ShouldCultBuy() == true then
        local target = CSP.ResolveBuySeedTarget()
        if type(target) == "table" and (tonumber(target.seedUid) or 0) > 0 then
            local seedUid = tonumber(target.seedUid) or 0
            local deficit = CSP.SeedDeficit(seedUid)
            if deficit >= 1 then
                local MS = StockPiler4.MaterialSpec
                local Inv = StockPiler4.Inventory
                local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
                local spec = nil
                if MS and MS.FromItemData and type(sample) == "table" then
                    spec = MS.FromItemData(sample, "main")
                elseif MS and MS.FromUid then
                    spec = MS.FromUid(seedUid)
                end
                jobs[#jobs + 1] = {
                    uid = seedUid,
                    uniqueID = seedUid,
                    deficit = deficit,
                    skillUp = true,
                    growable = true,
                    isGrowable = true,
                    role = "main",
                    spec = spec,
                    specKey = "skill_up_seed:" .. tostring(seedUid),
                    acquireKey = "skill_up_seed:" .. tostring(seedUid),
                    skillReq = tonumber(target.skillReq) or 0,
                }
            end
        end
    end
    local containerJobs = ASP().CollectContainerBuyJobs() or {}
    for i = 1, #containerJobs do
        jobs[#jobs + 1] = containerJobs[i]
    end
    return jobs
end

--- Notify once per Cult stall reason; clear latch when condition lifts.
function CSP.MaybeNotifyStall()
    if Gates().ShouldCultPlant() ~= true then
        CSP._stallLatch = nil
    MirrorStallToSkillUp()
        return
    end
    -- Waiting on refine (harvested plants -> seeds) or tier upgrade, not a stall.
    if CSP.HasRefinablePlants() == true or CSP.HasUpgradePlant() == true then
        CSP._stallLatch = nil
    MirrorStallToSkillUp()
        return
    end
    local pick = CSP.PickBestBagSeed()
    local seedUid = 0
    if type(pick) == "table" then
        seedUid = tonumber(pick.seedUid) or 0
    else
        local target = CSP.ResolveBuySeedTarget and CSP.ResolveBuySeedTarget() or nil
        if type(target) == "table" then
            seedUid = tonumber(target.seedUid) or 0
        end
    end
    -- Plots + buffer settled for the chosen line - not a stall.
    if seedUid > 0 and (tonumber(CSP.SeedDeficit(seedUid)) or 0) < 1 then
        CSP._stallLatch = nil
    MirrorStallToSkillUp()
        return
    end
    local canBuy = CSP.ShouldCultBuy() == true
    local VA = StockPiler4.VendorAdapter
    local storeOpen = VA and VA.IsStoreOpen and VA.IsStoreOpen() == true
    -- AutoBuy is actively purchasing - not a stall.
    if canBuy and storeOpen then
        CSP._stallLatch = nil
    MirrorStallToSkillUp()
        return
    end
    local reason = "no_seeds"
    if canBuy and not storeOpen then
        reason = "need_vendor"
    elseif not canBuy then
        local Watch = StockPiler4.Watch
        if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
            reason = "autobuy_off"
        else
            reason = "no_vendor_seed"
        end
    end
    if CSP._stallLatch == reason then
        return
    end
    CSP._stallLatch = reason
    MirrorStallToSkillUp()
    local msg
    if StockPiler4.T then
        msg = StockPiler4.T("skillup.stall." .. reason)
    else
        msg = L"<icon02486> Skill up Culti stalled - need seeds."
    end
    if StockPiler4.Debug and StockPiler4.Debug.Print then
        StockPiler4.Debug.Print(msg)
    end
    if type(PlaySound) == "function" and GameData and GameData.Sound
        and GameData.Sound.RESPAWN ~= nil
    then
        pcall(PlaySound, GameData.Sound.RESPAWN)
    elseif type(PlaySound) == "function" then
        pcall(PlaySound, 216)
    end
end

function CSP.DumpSkillPlan(emit)
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
    local Gates = StockPiler4.SkillUpGates
    local ASP = StockPiler4.ApoSkillPlan
    local Rates = StockPiler4.SkillRates
    local SWS = StockPiler4.SkillUpWatchStatus
    local cult = Gates and Gates.GetCultSkill and Gates.GetCultSkill() or 0
    local apo = Gates and Gates.GetApoSkill and Gates.GetApoSkill() or 0
    emit(string.format(
        "  skills cult=%d (floor=%d targetMax=%d) apo=%d (floor=%d next=%d)",
        cult,
        (Gates and Gates.FloorCultTier and Gates.FloorCultTier(cult) or 0),
        (Gates and Gates.TargetMaxSkill and Gates.TargetMaxSkill() or 0),
        apo,
        (Gates and Gates.FloorApoTier and Gates.FloorApoTier(apo) or 0),
        (ASP and ASP.NextApoTier and ASP.NextApoTier(apo) or 0)
    ))
    emit(string.format(
        "  toggles cultOn=%s apoOn=%s cultVis=%s apoVis=%s watchesDone=%s allowIdle=%s blocked=%s showStatus=%s",
        yn(Gates and Gates.IsCultEnabled and Gates.IsCultEnabled()),
        yn(Gates and Gates.IsApoEnabled and Gates.IsApoEnabled()),
        yn(Gates and Gates.IsCultVisible and Gates.IsCultVisible()),
        yn(Gates and Gates.IsApoVisible and Gates.IsApoVisible()),
        yn(Gates and Gates.WatchesDone and Gates.WatchesDone()),
        yn(Gates and Gates.WatchesAllowIdleSkillUp and Gates.WatchesAllowIdleSkillUp()),
        yn(Gates and Gates.AllShortWatchesProgressBlocked and Gates.AllShortWatchesProgressBlocked()),
        yn(SWS and SWS.ShouldShowWatchStatus and SWS.ShouldShowWatchStatus())
    ))
    emit(string.format(
        "  gates shouldCultGrow=%s shouldCultPlant=%s shouldApoBrew=%s canAutoGrow=%s autoGrowMaster=%s autoBuy=%s",
        yn(Gates and Gates.ShouldCultGrowForSkillUp and Gates.ShouldCultGrowForSkillUp()),
        yn(Gates and Gates.ShouldCultPlant and Gates.ShouldCultPlant()),
        yn(ASP and ASP.ShouldApoBrew and ASP.ShouldApoBrew()),
        yn(Caps and Caps.CanAutoGrow and Caps.CanAutoGrow()),
        yn(Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled()),
        yn(Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled())
    ))
    emit(string.format(
        "  latches cult=%s apo=%s pendingCult=%s pendingApo=%s",
        tostring(CSP._stallLatch or "-"),
        tostring(ASP and ASP._apoStallLatch or "-"),
        Rates and Rates._pendingCult and string.format("lvl=%s until=%.0f",
            tostring(Rates._pendingCult.level),
            tonumber(Rates._pendingCult.untilTime) or 0) or "-",
        Rates and Rates._pendingApo and string.format("lvl=%s until=%.0f",
            tostring(Rates._pendingApo.level),
            tonumber(Rates._pendingApo.untilTime) or 0) or "-"
    ))

    -- Garden plots
    emit("--- garden ---")
    local empty = CSP.CountEmptyPlots and CSP.CountEmptyPlots() or 0
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
    local pick = CSP.PickBestBagSeed and CSP.PickBestBagSeed() or nil
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
            tonumber(CSP.SeedDeficit and CSP.SeedDeficit(seedUid)) or 0,
            yn(CSP.HasUpgradePlant and CSP.HasUpgradePlant()),
            yn(CSP.HasRefinablePlants and CSP.HasRefinablePlants())
        ))
    else
        emit("  pick=(none)")
    end
    local job = CSP.PickPlantJob and CSP.PickPlantJob() or nil
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
    local refine = CSP.ScanBestRefinePlant and CSP.ScanBestRefinePlant() or nil
    if type(refine) == "table" then
        emit(string.format(
            "  refineBest plantUid=%d seedUid=%d req=%d count=%s upgrade=%s",
            tonumber(refine.plantUid) or 0,
            tonumber(refine.seedUid) or 0,
            tonumber(refine.skillReq) or 0,
            tostring(refine.count or refine.uses or "?"),
            yn(refine.upgrade == true or (CSP.HasUpgradePlant and CSP.HasUpgradePlant()))
        ))
    else
        emit("  refineBest=(none)")
    end
    local buySeed = CSP.ShouldCultBuy and CSP.ShouldCultBuy() == true
    emit(string.format("  shouldCultBuy=%s", yn(buySeed)))
    if CSP.CollectBuyJobs then
        local seedJobs = CSP.CollectBuyJobs() or {}
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
        ASP and ASP.ApoTargetTier and ASP.ApoTargetTier() or 0,
        ASP and ASP.CountApoContainers and ASP.CountApoContainers() or 0,
        Rates and Rates.ApoContainerBuyTarget and Rates.ApoContainerBuyTarget() or 0,
        yn(ASP and ASP.ShouldApoBuyContainer and ASP.ShouldApoBuyContainer())
    ))
    local vialTarget = ASP and ASP.ResolveBuyContainerTarget and ASP.ResolveBuyContainerTarget() or nil
    if type(vialTarget) == "table" then
        emit(string.format(
            "  vialTarget uid=%d skillReq=%d",
            tonumber(vialTarget.uid) or 0,
            tonumber(vialTarget.skillReq) or 0
        ))
    end
    if ASP and ASP.CollectContainerBuyJobs then
        local cJobs = ASP.CollectContainerBuyJobs() or {}
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
        local mats = ASP and ASP.ListApoBagMaterials and ASP.ListApoBagMaterials(role) or {}
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
    local brewRow = ASP and ASP.BuildApoBrewRow and ASP.BuildApoBrewRow({ quiet = true }) or nil
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
            tostring(ASP and ASP._apoStallLatch or "-")
        ))
    end

    -- Watch status rows
    emit("--- watch status rows ---")
    local rows = SWS and SWS.BuildWatchStatusRows and SWS.BuildWatchStatusRows() or {}
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
    if Rates and Rates.DumpRates then Rates.DumpRates(emit) end

    emit("=== end skillplan ===")
end


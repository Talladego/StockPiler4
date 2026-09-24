----------------------------------------------------------------
-- StockPiler4 Planner/CultSkillPlan - idle Cult plant/refine/buy
-- Extracted from SkillUp; SkillUp re-exports for callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.CultSkillPlan = StockPiler4.CultSkillPlan or {}
local CSP = StockPiler4.CultSkillPlan

local function SkillUpMod()
    return StockPiler4.SkillUp
end

local function ClimbEconomy()
    return StockPiler4.ClimbPlan or StockPiler4.UpgradeSeed
end

local function MirrorStallToSkillUp()
    local SU = StockPiler4.SkillUp
    if type(SU) == "table" then
        SU._stallLatch = CSP._stallLatch
    end
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
    if not (CE and CE.PickBestOwnedSeed and SM and SM.GetGenusLadder and Inv and Inv.ForEachItem) then
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
        local ladder = SM.GetGenusLadder(genus)
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
    local cult = SkillUpMod().GetCultSkill()
    if cult <= 0 then
        return nil
    end
    if cult >= (SkillUpMod().CULT_MAX or 200) and SkillUpMod().IsApoEnabled() ~= true then
        return nil
    end
    local targetMax = SkillUpMod().TargetMaxSkill()
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
    if SkillUpMod().ShouldCultPlant() ~= true then
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
    if SkillUpMod().ShouldCultPlant() ~= true then
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
    local watchSeedNeed = SkillUpMod().WatchDemandReserve(seedUid)
    if plantUid > 0 then
        local plantNeed = SkillUpMod().WatchDemandReserve(plantUid)
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
    SkillUpMod()._lastSeedUid = seedUid
    SkillUpMod()._lastPlantUid = plantUid
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
    local cult = SkillUpMod().GetCultSkill()
    local targetMax = SkillUpMod().FloorCultTier(cult)
    if targetMax < 1 then
        targetMax = SkillUpMod().TargetMaxSkill()
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
    if SkillUpMod().ShouldCultPlant() ~= true then
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

    local seedUid = tonumber(SkillUpMod()._lastSeedUid) or 0
    local plantUid = tonumber(SkillUpMod()._lastPlantUid) or 0
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
    local surplus = SkillUpMod().PlantRefineSurplus(plantUid, seedUid, bagCount)
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
    if SkillUpMod().ShouldCultPlant() ~= true then
        return
    end
    local target = CSP.PickRefineTarget()
    local uses, info = CSP.RefineUsesForTarget(target)
    if (tonumber(uses) or 0) < 1 or type(info) ~= "table" then
        return
    end
    SkillUpMod()._lastSeedUid = info.seedUid
    SkillUpMod()._lastPlantUid = info.plantUid
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
            targetMax = SkillUpMod().TargetMaxSkill(),
        }
    end

    local targetMax = SkillUpMod().TargetMaxSkill()
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
    if SkillUpMod().ShouldCultPlant() ~= true then
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
    local containerJobs = SkillUpMod().CollectContainerBuyJobs() or {}
    for i = 1, #containerJobs do
        jobs[#jobs + 1] = containerJobs[i]
    end
    return jobs
end

--- Notify once per Cult stall reason; clear latch when condition lifts.
function CSP.MaybeNotifyStall()
    if SkillUpMod().ShouldCultPlant() ~= true then
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

local function Reexport()
    local SU = StockPiler4.SkillUp
    if type(SU) ~= "table" then
        SU = {}
        StockPiler4.SkillUp = SU
    end
    local names = {
        "PickBestBagSeed", "PreferRefineOverPlant", "PickPlantJob", "CountEmptyPlots",
        "SeedDeficit", "ScanBestRefinePlant", "HasUpgradePlant", "PickRefineTarget",
        "RefineUsesForTarget", "AppendRefineIntents", "ResolveBuySeedTarget",
        "HasRefinablePlants", "ShouldCultBuy", "CollectBuyJobs", "MaybeNotifyStall",
    }
    for i = 1, #names do
        local n = names[i]
        if CSP[n] ~= nil then
            SU[n] = CSP[n]
        end
    end
    SU._stallLatch = CSP._stallLatch
end

function CSP.SyncSkillUpExports()
    Reexport()
end

Reexport()
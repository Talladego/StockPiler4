----------------------------------------------------------------
-- StockPiler4 Knowledge/WatchReserves - short-watch mat reserves
-- Extracted from SkillUp; SkillUp re-exports for callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.WatchReserves = StockPiler4.WatchReserves or {}
local WR = StockPiler4.WatchReserves

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

local function SeedDeficit(seedUid)
    local SU = StockPiler4.SkillUp
    if SU and SU.SeedDeficit then
        return tonumber(SU.SeedDeficit(seedUid)) or 0
    end
    local CE = StockPiler4.ClimbPlan or StockPiler4.UpgradeSeed
    if CE and CE.SeedDeficit then
        return tonumber(CE.SeedDeficit(seedUid, "skillup")) or 0
    end
    return 0
end

local function PotionWatchHave(key, watch)
    local RS = StockPiler4.RecipeSpec
    local Catalog = StockPiler4.Catalog
    local have = 0
    if RS and RS.ResolveWatchPotion then
        local resolved = RS.ResolveWatchPotion(key)
        local potion = resolved and resolved.potion
        if type(potion) == "table" and Catalog and Catalog.PotionHaveCombined then
            have = tonumber(Catalog.PotionHaveCombined(potion)) or 0
        elseif resolved and resolved.outputUid and StockPiler4.Inventory and StockPiler4.Inventory.CountByUid then
            have = tonumber(StockPiler4.Inventory.CountByUid(resolved.outputUid)) or 0
        end
    end
    return have
end

function WR.WatchDemandReserve(specOrUid)
    local wantUid = 0
    if type(specOrUid) == "table" then
        wantUid = tonumber(specOrUid.uid) or tonumber(specOrUid.uniqueID)
            or tonumber(specOrUid.boundUid) or 0
    else
        wantUid = tonumber(specOrUid) or 0
    end
    if wantUid <= 0 then
        return 0
    end

    local need = 0
    local Watch = StockPiler4.Watch
    local RS = StockPiler4.RecipeSpec
    local Inv = StockPiler4.Inventory
    local SM = StockPiler4.SeedMap

    local watches = Watch and Watch.GetWatches and Watch.GetWatches() or {}
    if type(watches) == "table" and RS then
        for key, watch in pairs(watches) do
            if type(watch) == "table" and watch.enabled == true then
                local target = tonumber(watch.targetStock) or 0
                local have = PotionWatchHave(key, watch)
                local deficit = math.max(0, target - have)
                if deficit > 0 and target > 0 then
                    local recipe = RS.RecipeSpecForPotion and RS.RecipeSpecForPotion(key) or nil
                    if type(recipe) == "table" then
                        if RS.HydrateRecipeSlots then
                            RS.HydrateRecipeSlots(recipe)
                        end
                        local yield = math.max(1, tonumber(recipe.recipeYield) or 1)
                        local craftsNeeded = math.ceil(deficit / yield)
                        if RS.CraftsNeededForDeficit then
                            craftsNeeded = tonumber(RS.CraftsNeededForDeficit(deficit, recipe)) or craftsNeeded
                        end
                        local slots = recipe.slots or {}
                        for i = 1, #slots do
                            local slot = slots[i]
                            local spec = nil
                            if RS.ResolveSlotSpec then
                                spec = RS.ResolveSlotSpec(slot)
                            end
                            if type(spec) ~= "table" and type(slot) == "table" then
                                spec = slot.spec
                            end
                            local uid = 0
                            if type(spec) == "table" then
                                uid = tonumber(spec.uid) or tonumber(spec.uniqueID) or tonumber(spec.boundUid) or 0
                            end
                            if uid <= 0 and type(slot) == "table" then
                                uid = tonumber(slot.uid) or tonumber(slot.uniqueID) or 0
                            end
                            if uid == wantUid then
                                local perCraft = 1
                                if RS.EffectiveSpecPerCraft then
                                    perCraft = math.max(1, tonumber(RS.EffectiveSpecPerCraft(slot, slots)) or 1)
                                else
                                    perCraft = math.max(1, tonumber(slot and slot.perCraft) or 1)
                                end
                                need = need + craftsNeeded * perCraft
                            end
                        end
                    end
                end
            end
        end
    end

    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) == "table" then
        for plantKey, watch in pairs(plantWatches) do
            if type(watch) == "table" and watch.enabled == true then
                local target = tonumber(watch.targetStock) or 0
                local plantUid = Watch.ParsePlantKey and tonumber(Watch.ParsePlantKey(plantKey)) or 0
                local have = 0
                if plantUid > 0 and Inv and Inv.CountByUid then
                    have = tonumber(Inv.CountByUid(plantUid)) or 0
                end
                local deficit = math.max(0, target - have)
                if deficit > 0 then
                    if plantUid == wantUid then
                        need = need + deficit
                    elseif SM and SM.ResolveSeedUidForPlant then
                        local seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, nil)) or 0
                        if seedUid == wantUid then
                            need = need + deficit
                        end
                    end
                end
            end
        end
    end

    return need
end

--- Plants to hold as Cult feedstock before Apo SkillUp may brew.
--- Seed-buffer headroom alone is not enough: when the buffer is full of seeds
--- (headroom=0), SkillUp still plants those seeds into empty plots - without a
--- standing plant reserve Apo drains the harvest and Cult falls back to lower
--- tiers. Always keep bufferMin plants (and SeedDeficit when higher).
function WR.PlantFeedstockReserve(seedUid, plantUid)
    seedUid = tonumber(seedUid) or 0
    plantUid = tonumber(plantUid) or 0
    local bufferMin = 0
    local headroom = 0
    if seedUid > 0 then
        local budget = SeedBudget(seedUid)
        bufferMin = tonumber(budget.bufferMin) or 0
        headroom = tonumber(budget.headroom) or 0
    end
    local reserve = headroom
    if bufferMin > 0 then
        if bufferMin > reserve then
            reserve = bufferMin
        end
        local deficit = SeedDeficit(seedUid)
        if deficit > reserve then
            reserve = deficit
        end
    end
    local watchNeed = 0
    if plantUid > 0 then
        watchNeed = WR.WatchDemandReserve(plantUid)
    end
    if seedUid > 0 then
        local seedNeed = WR.WatchDemandReserve(seedUid)
        if seedNeed > watchNeed then
            watchNeed = seedNeed
        end
    end
    if watchNeed > reserve then
        return watchNeed
    end
    return reserve
end

--- How many of this plant stack are safe for SkillUp Apo brew (and resin convert).
--- plantCount - PlantFeedstockReserve. Unresolved seedUid -> 0.
--- SkillUp refine-into-buffer uses PlantRefineSurplus instead (buffer headroom is
--- a refine target there, not a plant hold).
function WR.PlantBrewSurplus(plantUid, seedUid, plantCount)
    plantUid = tonumber(plantUid) or 0
    seedUid = tonumber(seedUid) or 0
    plantCount = tonumber(plantCount) or 0
    if plantCount <= 0 then
        return 0
    end
    if seedUid <= 0 and plantUid > 0 then
        local SM = StockPiler4.SeedMap
        if SM and SM.ResolveSeedUidForPlant then
            seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, nil)) or 0
        end
        if seedUid <= 0 and SM and SM.GetSeedUidsForPlant then
            local seeds = SM.GetSeedUidsForPlant(plantUid) or {}
            if type(seeds) == "table" and #seeds > 0 then
                seedUid = tonumber(seeds[1]) or 0
            end
        end
    end
    -- Unresolved seed: buffer math unavailable - do not treat stack as SkillUp surplus.
    if seedUid <= 0 then
        return 0
    end
    local reserve = WR.PlantFeedstockReserve(seedUid, plantUid)
    local surplus = plantCount - reserve
    if surplus < 0 then
        return 0
    end
    return surplus
end

--- Plants free for SkillUp refine into seeds. Buffer headroom is a refine *target*
--- (how many seeds we still need), not a plant reserve - only short-watch demand
--- holds plants back. Using PlantBrewSurplus here caused deadlocks: upgrade/buffer
--- refine needed the reserved plants to *create* the buffer.
function WR.PlantRefineSurplus(plantUid, seedUid, plantCount)
    plantUid = tonumber(plantUid) or 0
    seedUid = tonumber(seedUid) or 0
    plantCount = tonumber(plantCount) or 0
    if plantCount <= 0 then
        return 0
    end
    if seedUid <= 0 and plantUid > 0 then
        local SM = StockPiler4.SeedMap
        if SM and SM.ResolveSeedUidForPlant then
            seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, nil)) or 0
        end
        if seedUid <= 0 and SM and SM.GetSeedUidsForPlant then
            local seeds = SM.GetSeedUidsForPlant(plantUid) or {}
            if type(seeds) == "table" and #seeds > 0 then
                seedUid = tonumber(seeds[1]) or 0
            end
        end
    end
    if seedUid <= 0 then
        return 0
    end
    local watchNeed = 0
    if plantUid > 0 then
        watchNeed = WR.WatchDemandReserve(plantUid)
    end
    local seedNeed = WR.WatchDemandReserve(seedUid)
    if seedNeed > watchNeed then
        watchNeed = seedNeed
    end
    local surplus = plantCount - watchNeed
    if surplus < 0 then
        return 0
    end
    return surplus
end

local function Reexport()
    local SU = StockPiler4.SkillUp
    if type(SU) ~= "table" then
        SU = {}
        StockPiler4.SkillUp = SU
    end
    for _, n in ipairs({
        "WatchDemandReserve", "PlantFeedstockReserve", "PlantBrewSurplus", "PlantRefineSurplus",
    }) do
        SU[n] = WR[n]
    end
end

function WR.SyncSkillUpExports()
    Reexport()
end

Reexport()
----------------------------------------------------------------
-- StockPiler4 Planner/SkillUpGates - toggles, idle gates, skill facades
-- Extracted from SkillUp; SkillUp re-exports for callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.SkillUpGates = StockPiler4.SkillUpGates or {}
local Gates = StockPiler4.SkillUpGates

local function Caps()
    return StockPiler4.TradeSkillCaps
end

local function CharRow(create)
    local Watch = StockPiler4.Watch
    if Watch and Watch.CharacterRow then
        return Watch.CharacterRow(create ~= false)
    end
    return nil
end

Gates.CULT_MAX = 200
Gates.APO_MAX = 200
Gates._stallLatch = nil

Gates.CULT_TIERS = Caps().CULT_TIERS or { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
Gates.APO_TIERS = Caps().APO_TIERS or { 1, 25, 50, 75, 100, 125, 150, 175, 200 }

function Gates.FloorApoTier(apoSkill)
    local C = Caps()
    if C and C.FloorApoTier then
        return C.FloorApoTier(apoSkill)
    end
    apoSkill = tonumber(apoSkill) or 0
    local best = 1
    local tiers = Gates.APO_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if apoSkill >= t then
            best = t
        end
    end
    return best
end

--- Highest cult seed/plant tier the current Cult skill can use (1, 25, 50, ...).
function Gates.FloorCultTier(cultSkill)
    local C = Caps()
    if C and C.FloorCultTier then
        return C.FloorCultTier(cultSkill)
    end
    cultSkill = tonumber(cultSkill) or 0
    local best = 1
    local tiers = Gates.CULT_TIERS or Gates.APO_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if cultSkill >= t then
            best = t
        end
    end
    return best
end

function Gates.GetCultSkill()
    local C = Caps()
    return C and C.GetCultSkill and tonumber(C.GetCultSkill()) or 0
end

function Gates.GetApoSkill()
    local C = Caps()
    return C and C.GetApoSkill and tonumber(C.GetApoSkill()) or 0
end

function Gates.IsCultTrained()
    return Gates.GetCultSkill() > 0
end

function Gates.IsApoTrained()
    return Gates.GetApoSkill() > 0
end

function Gates.IsCultVisible()
    local cult = Gates.GetCultSkill()
    return cult > 0 and cult < (Gates.CULT_MAX or 200)
end

function Gates.IsApoVisible()
    local apo = Gates.GetApoSkill()
    return apo > 0 and apo < (Gates.APO_MAX or 200)
end

function Gates.IsCultEnabled()
    if not Gates.IsCultVisible() then
        return false
    end
    local row = CharRow(false)
    return type(row) == "table" and row.skillUpCultEnabled == true
end

function Gates.IsApoEnabled()
    if not Gates.IsApoVisible() then
        return false
    end
    local row = CharRow(false)
    return type(row) == "table" and row.skillUpApoEnabled == true
end

function Gates.SetCultEnabled(enabled)
    local row = CharRow(true)
    if type(row) ~= "table" then
        return false
    end
    row.skillUpCultEnabled = enabled == true
    local Watch = StockPiler4.Watch
    if Watch and Watch.BumpGen then
        Watch.BumpGen()
    end
    return true
end

function Gates.SetApoEnabled(enabled)
    local row = CharRow(true)
    if type(row) ~= "table" then
        return false
    end
    row.skillUpApoEnabled = enabled == true
    local Watch = StockPiler4.Watch
    if Watch and Watch.BumpGen then
        Watch.BumpGen()
    end
    return true
end

local function AllEnabledPlantWatchesStocked()
    local Watch = StockPiler4.Watch
    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) ~= "table" then
        return true
    end
    local Inv = StockPiler4.Inventory
    local Catalog = StockPiler4.Catalog
    local CE = ClimbEconomy()
    for plantKey, watch in pairs(plantWatches) do
        if type(watch) == "table" and watch.enabled == true then
            local plantUid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
            plantUid = tonumber(plantUid) or 0
            -- Ephemeral Upgrade Seed climb owns this watch: treat as stocked for idle gate.
            if plantUid > 0 and CE and CE.IsPlantWatchOwnedByUpgrade
                and CE.IsPlantWatchOwnedByUpgrade(plantUid) == true
            then
                -- ok
            else
                local target = tonumber(watch.targetStock) or 40
                local have = 0
                if plantUid > 0 and Catalog and Catalog.PlantHave then
                    have = tonumber(Catalog.PlantHave(plantUid)) or 0
                elseif plantUid > 0 and Inv and Inv.CountByUid then
                    have = tonumber(Inv.CountByUid(plantUid)) or 0
                end
                if have < target then
                    return false
                end
            end
        end
    end
    return true
end

local function SeedBufferOk()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true) then
        return true
    end
    local Grow = StockPiler4.Grow
    return Grow and Grow.IsSeedBufferSatisfied and Grow.IsSeedBufferSatisfied() == true
end

--- No short potion/plant watches (and seed buffer satisfied when enabled).
function Gates.WatchesDone()
    local Watch = StockPiler4.Watch
    if Watch and Watch.AllEnabledPotionWatchesStocked
        and Watch.AllEnabledPotionWatchesStocked() ~= true
    then
        return false
    end
    if AllEnabledPlantWatchesStocked() ~= true then
        return false
    end
    -- SkillUp must not run while the seed buffer is short (even with no AutoGrow watches).
    return SeedBufferOk()
end

-- Statuses where a short watch can still advance (SkillUp must wait).
local SHORT_WATCH_WORKING = {
    restocking = true,
    need_seeds = true,
    upgrading_seed = true,
    planting = true,
    buffer_plant = true,
    growing = true,
    refining = true,
    ready_to_craft = true,
    ready_to_craft_shared = true,
}

-- Statuses where AutoGrow/AutoBuy cannot progress the short watch.
local SHORT_WATCH_BLOCKED = {
    enable_autogrow = true,
    buy_ingredients = true,
    need_apothecary = true,
    need_vendor = true,
    no_vendor_seed = true,
    no_vendor_container = true,
    need_container_vendor = true,
    autobuy_off = true,
    no_seeds = true,
    no_recipe = true,
    no_target = true,
    need_skill = true,
}

local function AutoBuyCanProgress()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
        return false
    end
    local VA = StockPiler4.VendorAdapter
    return VA and VA.IsStoreOpen and VA.IsStoreOpen() == true
end

local function ShortStatusIsWorking(statusKey)
    statusKey = tostring(statusKey or "")
    if statusKey == "buy_ingredients" then
        return AutoBuyCanProgress()
    end
    return SHORT_WATCH_WORKING[statusKey] == true
end

local function ShortStatusIsBlocked(statusKey)
    statusKey = tostring(statusKey or "")
    if statusKey == "buy_ingredients" then
        return AutoBuyCanProgress() ~= true
    end
    return SHORT_WATCH_BLOCKED[statusKey] == true
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

local function PotionNeedsSkill(key)
    local RS = StockPiler4.RecipeSpec
    if not (RS and RS.RecipeSpecForPotion and RS.RecipeSkillRequirements) then
        return false
    end
    local recipe = RS.RecipeSpecForPotion(key)
    if type(recipe) ~= "table" then
        return false
    end
    local req = RS.RecipeSkillRequirements(recipe)
    if type(req) ~= "table" then
        return false
    end
    local Caps = StockPiler4.TradeSkillCaps
    local apo = Caps and Caps.GetApoSkill and tonumber(Caps.GetApoSkill()) or 0
    local need = tonumber(req.apothecary) or tonumber(req.apo) or 0
    return need > 0 and apo < need
end

local function PotionWatchWantsAutoGrow(key, watch)
    local RS = StockPiler4.RecipeSpec
    if RS and RS.ShouldAutoGrowPotion then
        return RS.ShouldAutoGrowPotion(key, watch) == true
    end
    local Watch = StockPiler4.Watch
    if type(watch) ~= "table" or watch.enabled ~= true then
        return false
    end
    if Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() ~= true then
        return false
    end
    return watch.autoGrow == true
end

--- True when every short enabled potion/plant watch is progress-blocked
--- (AG off, vendor stall, need_skill, no recipe, etc.). No short watches -> true.
function Gates.AllShortWatchesProgressBlocked()
    local shortCount = 0

    local PS = StockPiler4.PlanSnapshot
    local plan = nil
    if PS and PS.Get then
        plan = PS.Get()
    end
    if type(plan) == "table" and type(plan.rows) == "table" and #plan.rows > 0 then
        for i = 1, #plan.rows do
            local row = plan.rows[i]
            if type(row) == "table" and row.skillUp ~= true and row.addonOwned ~= true then
                local key = tostring(row.statusKey or "")
                if key ~= "potion_stocked" and key ~= "plant_stocked" and key ~= "" then
                    local target = tonumber(row.potionMin) or tonumber(row.target) or tonumber(row.targetStock) or 0
                    local have = tonumber(row.potionHave) or tonumber(row.have) or tonumber(row.plantHave) or 0
                    local deficit = tonumber(row.potionDeficit) or tonumber(row.deficit) or 0
                    local short = deficit > 0 or (target > 0 and have < target)
                    if not short and (SHORT_WATCH_WORKING[key] or SHORT_WATCH_BLOCKED[key]) then
                        -- Live status can mark progress work even when stock columns lag.
                        if key ~= "seed_buffer" then
                            short = true
                        end
                    end
                    if short then
                        shortCount = shortCount + 1
                        if ShortStatusIsWorking(key) then
                            return false
                        end
                        if not ShortStatusIsBlocked(key) then
                            -- Unknown status -> treat as still working (safe).
                            return false
                        end
                    end
                end
            end
        end
        return true
    end

    -- No plan snapshot: classify from Watch store + AG / skill gates.
    local Watch = StockPiler4.Watch
    local watches = Watch and Watch.GetWatches and Watch.GetWatches() or {}
    if type(watches) == "table" then
        for key, watch in pairs(watches) do
            if type(watch) == "table" and watch.enabled == true then
                local target = tonumber(watch.targetStock) or 40
                local have = PotionWatchHave(key, watch)
                if target > 0 and have < target then
                    shortCount = shortCount + 1
                    if PotionNeedsSkill(key) then
                        -- need_skill: watch brew blocked; SkillUp Apo is the unlock path.
                    elseif PotionWatchWantsAutoGrow(key, watch) then
                        return false
                    end
                    -- AG off / buy-only without progress -> blocked.
                end
            end
        end
    end
    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) == "table" then
        local Inv = StockPiler4.Inventory
        for plantKey, watch in pairs(plantWatches) do
            if type(watch) == "table" and watch.enabled == true then
                local target = tonumber(watch.targetStock) or 40
                local plantUid = Watch.ParsePlantKey and tonumber(Watch.ParsePlantKey(plantKey)) or 0
                local have = 0
                if plantUid > 0 and Inv and Inv.CountByUid then
                    have = tonumber(Inv.CountByUid(plantUid)) or 0
                end
                if target > 0 and have < target then
                    shortCount = shortCount + 1
                    if Watch.ShouldAutoGrowPlant and Watch.ShouldAutoGrowPlant(plantKey) == true then
                        return false
                    end
                end
            end
        end
    end
    return true
end

--- Soft gate: stocked+buffer, or all short watches blocked with seed buffer OK.
function Gates.WatchesAllowIdleSkillUp()
    local CE = ClimbEconomy()
    if CE and CE.IsActivelyClimbingPlantWatches
        and CE.IsActivelyClimbingPlantWatches() == true
    then
        return false
    end
    if Gates.WatchesDone() == true then
        return true
    end
    if SeedBufferOk() ~= true then
        return false
    end
    return Gates.AllShortWatchesProgressBlocked() == true
end

--- Max skillReq for SkillUp plant/seed picks.
--- Cult SkillUp only -> cult tier; Apo SkillUp only (Cult available) -> apo tier;
--- both on -> min(cult, apo) so Cult never outpaces Apo.
function Gates.TargetMaxSkill()
    local cult = Gates.GetCultSkill()
    local cultOn = Gates.IsCultEnabled() == true
    local apoOn = Gates.IsApoEnabled() == true
    local cultTier = 0
    if cult > 0 then
        cultTier = Gates.FloorCultTier(cult)
    end
    local apoTier = 0
    if apoOn then
        apoTier = Gates.FloorApoTier(Gates.GetApoSkill())
    end

    if cultOn and apoOn then
        if cultTier < 1 then
            return apoTier
        end
        if apoTier < 1 then
            return cultTier
        end
        if apoTier < cultTier then
            return apoTier
        end
        return cultTier
    end
    if apoOn then
        -- Apo SkillUp alone (or Cult already 200): grow/feed at Apo tier when Cult exists.
        return apoTier
    end
    if cultOn then
        return cultTier
    end
    return cultTier
end

--- Cultivation can plant/refine for SkillUp when skilling Cult or assisting Apo.
function Gates.ShouldCultGrowForSkillUp()
    local cult = Gates.GetCultSkill()
    if cult <= 0 then
        return false
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return false
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true) then
        return false
    end
    if Gates.WatchesAllowIdleSkillUp() ~= true then
        return false
    end
    if Gates.IsCultEnabled() == true then
        return true
    end
    -- Implicit assist: Apo SkillUp on -> Cult grows Apo-tier mains (even at Cult 200).
    if Gates.IsApoEnabled() == true then
        return true
    end
    return false
end

--- Back-compat alias used by plant/refine/buy paths.
function Gates.ShouldCultPlant()
    return Gates.ShouldCultGrowForSkillUp() == true

local function Reexport()
    local SU = StockPiler4.SkillUp
    if type(SU) ~= "table" then
        SU = {}
        StockPiler4.SkillUp = SU
    end
    local names = {
        "CULT_MAX", "APO_MAX", "CULT_TIERS", "APO_TIERS",
        "FloorApoTier", "FloorCultTier", "GetCultSkill", "GetApoSkill",
        "IsCultTrained", "IsApoTrained", "IsCultVisible", "IsApoVisible",
        "IsCultEnabled", "IsApoEnabled", "SetCultEnabled", "SetApoEnabled",
        "WatchesDone", "AllShortWatchesProgressBlocked", "WatchesAllowIdleSkillUp",
        "TargetMaxSkill", "ShouldCultGrowForSkillUp", "ShouldCultPlant",
    }
    for i = 1, #names do
        local n = names[i]
        if Gates[n] ~= nil then
            SU[n] = Gates[n]
        end
    end
end

function Gates.SyncSkillUpExports()
    Reexport()
end

Reexport()
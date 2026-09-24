----------------------------------------------------------------
-- StockPiler4 SkillUp - idle Cult + Apo skill-up
--
-- Cult climb + shared seed economy: ClimbPlan (UpgradeSeed alias). SkillUp owns
-- Apo brew boards, idle Cult/Apo gates, WatchesDone, and watch reserves.
-- Tier floors: TradeSkillCaps.FloorCultTier / FloorApoTier (canonical).
--
-- Cult tier policy (all rungs until Cult 200):
--   Prefer the highest seed/plant tier unlocked by current Cult skill
--   (1 -> 25 -> 50 -> 75 -> 100 -> 125 -> 150 -> 175). When that tier is not
--   in bags, keep planting/refining lower tiers for rare skillups and
--   crit upgrades into the next tier. Stop when Cult reaches 200.
--   When Apo SkillUp is also on, never *plant* above Apo tier (tandem);
--   still refine lucky higher Cult-floor plants into seeds for later.
--   Prefer exact Apo floor so Cult feeds Apo instead of racing ahead.
--   Fill every unlocked plot (1 / 50 / 100 / 150 -> 1-4 plots).
--   Prefer a bag seed line already at buffer (or plant-refinable to it);
--   AutoBuy tops up SeedDeficit (plots + buffer) even when bags hold some seeds.
--
-- Apo (when Skill up Apo is on and watches allow idle SkillUp):
--   Brew only at FloorApoTier (exact rung). No lower-tier waste after
--   tier-up - wait for Cult to supply that tier's main/resin.
--   Idle when watches stocked+buffer OK, or when every short watch is
--   progress-blocked (AG off / vendor stall / need_skill) and buffer OK.
--   Never consume plants/seeds still claimed by short watches
--   (WatchDemandReserve / PlantBrewSurplus for brew; PlantRefineSurplus
--   for SkillUp refine - buffer headroom is a refine target, not a hold).
--   Apo brew always keeps bufferMin plants as Cult feedstock (not merely
--   headroom) so a full seed buffer can be planted without Apo draining the
--   harvest and forcing lower-tier Cult seeds.
--   Stabilizer: Arboreal Resin byproduct only. Compose main + container
--   (+0/+1/+2) + lowest-skillReq resins that still reach engine HIGH (sum > 0).
--   Prefer burning lower-tier resin over fewer units of Hale/Resilient when both
--   stabilize. Resin short -> refine leftover lower-tier mains first, then
--   surplus of the exact-floor brew main (keep >=1 for brew).
--   Never hard-stall on "upgrade plant exists" when that plant cannot
--   actually refine (fall through to same-tier refine / plant / AutoBuy).
--   SkillUp crafts are not recorded as known potions (BrewLearn skips
--   session.skillUp learns). Legacy skillUpOrigin rows stay hidden in Potions.
--   Cult AutoGrow assists at Apo tier even at Cult 200 / Cult SkillUp off.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.SkillUp = StockPiler4.SkillUp or {}
local SkillUp = StockPiler4.SkillUp

--- Prefer ClimbPlan; fall back to deprecated UpgradeSeed alias.
local function ClimbEconomy()
    return StockPiler4.ClimbPlan or StockPiler4.UpgradeSeed
end

SkillUp.CULT_MAX = 200
SkillUp.APO_MAX = 200
SkillUp._stallLatch = nil

local function Caps()
    return StockPiler4.TradeSkillCaps
end

SkillUp.CULT_TIERS = Caps().CULT_TIERS or { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
SkillUp.APO_TIERS = Caps().APO_TIERS or { 1, 25, 50, 75, 100, 125, 150, 175, 200 }

local function CharRow(create)
    local Watch = StockPiler4.Watch
    if Watch and Watch.CharacterRow then
        return Watch.CharacterRow(create ~= false)
    end
    return nil
end

function SkillUp.FloorApoTier(apoSkill)
    local C = Caps()
    if C and C.FloorApoTier then
        return C.FloorApoTier(apoSkill)
    end
    apoSkill = tonumber(apoSkill) or 0
    local best = 1
    local tiers = SkillUp.APO_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if apoSkill >= t then
            best = t
        end
    end
    return best
end

--- Highest cult seed/plant tier the current Cult skill can use (1, 25, 50, ...).
function SkillUp.FloorCultTier(cultSkill)
    local C = Caps()
    if C and C.FloorCultTier then
        return C.FloorCultTier(cultSkill)
    end
    cultSkill = tonumber(cultSkill) or 0
    local best = 1
    local tiers = SkillUp.CULT_TIERS or SkillUp.APO_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if cultSkill >= t then
            best = t
        end
    end
    return best
end

function SkillUp.GetCultSkill()
    local C = Caps()
    return C and C.GetCultSkill and tonumber(C.GetCultSkill()) or 0
end

function SkillUp.GetApoSkill()
    local C = Caps()
    return C and C.GetApoSkill and tonumber(C.GetApoSkill()) or 0
end

function SkillUp.IsCultTrained()
    return SkillUp.GetCultSkill() > 0
end

function SkillUp.IsApoTrained()
    return SkillUp.GetApoSkill() > 0
end

function SkillUp.IsCultVisible()
    local cult = SkillUp.GetCultSkill()
    return cult > 0 and cult < (SkillUp.CULT_MAX or 200)
end

function SkillUp.IsApoVisible()
    local apo = SkillUp.GetApoSkill()
    return apo > 0 and apo < (SkillUp.APO_MAX or 200)
end

function SkillUp.IsCultEnabled()
    if not SkillUp.IsCultVisible() then
        return false
    end
    local row = CharRow(false)
    return type(row) == "table" and row.skillUpCultEnabled == true
end

function SkillUp.IsApoEnabled()
    if not SkillUp.IsApoVisible() then
        return false
    end
    local row = CharRow(false)
    return type(row) == "table" and row.skillUpApoEnabled == true
end

function SkillUp.SetCultEnabled(enabled)
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

function SkillUp.SetApoEnabled(enabled)
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
function SkillUp.WatchesDone()
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
function SkillUp.AllShortWatchesProgressBlocked()
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
function SkillUp.WatchesAllowIdleSkillUp()
    local CE = ClimbEconomy()
    if CE and CE.IsActivelyClimbingPlantWatches
        and CE.IsActivelyClimbingPlantWatches() == true
    then
        return false
    end
    if SkillUp.WatchesDone() == true then
        return true
    end
    if SeedBufferOk() ~= true then
        return false
    end
    return SkillUp.AllShortWatchesProgressBlocked() == true
end

--- Max skillReq for SkillUp plant/seed picks.
--- Cult SkillUp only -> cult tier; Apo SkillUp only (Cult available) -> apo tier;
--- both on -> min(cult, apo) so Cult never outpaces Apo.
function SkillUp.TargetMaxSkill()
    local cult = SkillUp.GetCultSkill()
    local cultOn = SkillUp.IsCultEnabled() == true
    local apoOn = SkillUp.IsApoEnabled() == true
    local cultTier = 0
    if cult > 0 then
        cultTier = SkillUp.FloorCultTier(cult)
    end
    local apoTier = 0
    if apoOn then
        apoTier = SkillUp.FloorApoTier(SkillUp.GetApoSkill())
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
function SkillUp.ShouldCultGrowForSkillUp()
    local cult = SkillUp.GetCultSkill()
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
    if SkillUp.WatchesAllowIdleSkillUp() ~= true then
        return false
    end
    if SkillUp.IsCultEnabled() == true then
        return true
    end
    -- Implicit assist: Apo SkillUp on -> Cult grows Apo-tier mains (even at Cult 200).
    if SkillUp.IsApoEnabled() == true then
        return true
    end
    return false
end

--- Back-compat alias used by plant/refine/buy paths.
function SkillUp.ShouldCultPlant()
    return SkillUp.ShouldCultGrowForSkillUp() == true
end

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
    local deficit = tonumber(SkillUp.SeedDeficit(uid)) or 0
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

function SkillUp.PickBestBagSeed()
    local cult = SkillUp.GetCultSkill()
    if cult <= 0 then
        return nil
    end
    if cult >= (SkillUp.CULT_MAX or 200) and SkillUp.IsApoEnabled() ~= true then
        return nil
    end
    local targetMax = SkillUp.TargetMaxSkill()
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
function SkillUp.PreferRefineOverPlant()
    if SkillUp.ShouldCultPlant() ~= true then
        return false
    end
    if SkillUp.HasUpgradePlant() == true then
        return true
    end
    local target = SkillUp.PickRefineTarget()
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
    local uses = SkillUp.RefineUsesForTarget(target)
    return (tonumber(uses) or 0) >= 1
end

function SkillUp.PickPlantJob()
    if SkillUp.ShouldCultPlant() ~= true then
        return nil
    end
    -- Hold planting while refine can make progress (upgrade or buffer fill).
    if SkillUp.PreferRefineOverPlant() == true then
        if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
            if SkillUp.HasUpgradePlant() == true then
                StockPiler4.Refine.MarkRefineDue("skill-up")
            else
                StockPiler4.Refine.MarkRefineDue("skill-up-buffer")
            end
        end
        if StockPiler4.Debug and StockPiler4.Debug.LogOp then
            local pick = SkillUp.PickBestBagSeed()
            local seedUid = type(pick) == "table" and (tonumber(pick.seedUid) or 0) or 0
            local budget = SeedBudget(seedUid)
            StockPiler4.Debug.LogOp("skillup", string.format(
                "hold-plant seedUid=%d headroom=%d upgrade=%s (prefer refine)",
                seedUid,
                tonumber(budget.headroom) or 0,
                tostring(SkillUp.HasUpgradePlant() == true)
            ))
        end
        return nil
    end
    local pick = SkillUp.PickBestBagSeed()
    if type(pick) ~= "table" or (tonumber(pick.seedUid) or 0) <= 0 then
        return nil
    end
    local seedUid = tonumber(pick.seedUid) or 0
    local plantUid = tonumber(pick.plantUid) or 0
    local budget = SeedBudget(seedUid)
    local buffer = tonumber(budget.bufferMin) or 0
    local live = tonumber(budget.live) or 0
    local headroom = tonumber(budget.headroom) or 0
    local empty = SkillUp.CountEmptyPlots()
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
    local watchSeedNeed = SkillUp.WatchDemandReserve(seedUid)
    if plantUid > 0 then
        local plantNeed = SkillUp.WatchDemandReserve(plantUid)
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
    SkillUp._lastSeedUid = seedUid
    SkillUp._lastPlantUid = plantUid
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

function SkillUp.CountEmptyPlots()
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
function SkillUp.SeedDeficit(seedUid)
    local CE = ClimbEconomy()
    if CE and CE.SeedDeficit then
        return CE.SeedDeficit(seedUid, "skillup")
    end
    seedUid = tonumber(seedUid) or 0
    local empty = SkillUp.CountEmptyPlots()
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
function SkillUp.ScanBestRefinePlant()
    local cult = SkillUp.GetCultSkill()
    local targetMax = SkillUp.FloorCultTier(cult)
    if targetMax < 1 then
        targetMax = SkillUp.TargetMaxSkill()
    end
    if targetMax < 1 then
        targetMax = 1
    end
    local CE = ClimbEconomy()
    if CE and CE.ScanUpgradePlant then
        local seed = SkillUp.PickBestBagSeed and SkillUp.PickBestBagSeed() or nil
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
function SkillUp.HasUpgradePlant()
    if SkillUp.ShouldCultPlant() ~= true then
        return false
    end
    local plant = SkillUp.ScanBestRefinePlant()
    if type(plant) ~= "table" then
        return false
    end
    local plantReq = tonumber(plant.skillReq) or 0
    if plantReq < 1 then
        return false
    end
    local seed = SkillUp.PickBestBagSeed()
    local seedReq = type(seed) == "table" and (tonumber(seed.skillReq) or 0) or 0
    if plantReq <= seedReq then
        return false
    end
    local uses = SkillUp.RefineUsesForTarget({
        seedUid = tonumber(plant.seedUid) or 0,
        plantUid = tonumber(plant.plantUid) or 0,
        skillReq = plantReq,
        upgrade = true,
    })
    return (tonumber(uses) or 0) >= 1
end

--- Resolve seed/plant for SkillUp refine (replant + tier graduation).
--- Prefers upgrade only when RefineUsesForTarget >= 1; else same-tier.
function SkillUp.PickRefineTarget()
    local SM = StockPiler4.SeedMap

    -- Prefer graduating when the upgrade plant can refine now.
    local upgrade = SkillUp.ScanBestRefinePlant()
    if type(upgrade) == "table" then
        local plantReq = tonumber(upgrade.skillReq) or 0
        local seed = SkillUp.PickBestBagSeed()
        local seedReq = type(seed) == "table" and (tonumber(seed.skillReq) or 0) or 0
        if plantReq > seedReq then
            local target = {
                seedUid = tonumber(upgrade.seedUid) or 0,
                plantUid = tonumber(upgrade.plantUid) or 0,
                skillReq = plantReq,
                upgrade = true,
            }
            local uses = SkillUp.RefineUsesForTarget(target)
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

    local pick = SkillUp.PickBestBagSeed()
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

    local seedUid = tonumber(SkillUp._lastSeedUid) or 0
    local plantUid = tonumber(SkillUp._lastPlantUid) or 0
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
function SkillUp.RefineUsesForTarget(target)
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
    local deficit = SkillUp.SeedDeficit(seedUid)
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
    local surplus = SkillUp.PlantRefineSurplus(plantUid, seedUid, bagCount)
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
function SkillUp.AppendRefineIntents(intents, appendFn)
    if type(intents) ~= "table" or type(appendFn) ~= "function" then
        return
    end
    if SkillUp.ShouldCultPlant() ~= true then
        return
    end
    local target = SkillUp.PickRefineTarget()
    local uses, info = SkillUp.RefineUsesForTarget(target)
    if (tonumber(uses) or 0) < 1 or type(info) ~= "table" then
        return
    end
    SkillUp._lastSeedUid = info.seedUid
    SkillUp._lastPlantUid = info.plantUid
    appendFn({
        spec = info.spec,
        seedUid = info.seedUid,
        plantUid = info.plantUid,
        specKey = "skill_up:" .. tostring(info.seedUid),
    }, "skill-up", uses, info.budget)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "refine-intent seedUid=%d plantUid=%d uses=%d empty=%d refinable=%d upgrade=%s req=%d headroom=%d deficit=%d",
            info.seedUid, info.plantUid, uses, SkillUp.CountEmptyPlots(), info.refinable,
            tostring(info.isUpgrade), info.skillReq,
            info.headroom, info.deficit
        ))
    end
end

--- Preferred vendor seed for AutoBuy: same line as bag pick / refine plants when possible.
function SkillUp.ResolveBuySeedTarget()
    -- Top up the SkillUp line already chosen from bags.
    local pick = SkillUp.PickBestBagSeed and SkillUp.PickBestBagSeed() or nil
    if type(pick) == "table" and (tonumber(pick.seedUid) or 0) > 0 then
        return {
            seedUid = tonumber(pick.seedUid) or 0,
            skillReq = tonumber(pick.skillReq) or 0,
            targetMax = SkillUp.TargetMaxSkill(),
        }
    end

    local targetMax = SkillUp.TargetMaxSkill()
    if targetMax < 1 then
        targetMax = 1
    end
    -- Prefer the seed linked to refinable plants already in bags.
    local preferUid = 0
    local plant = SkillUp.ScanBestRefinePlant and SkillUp.ScanBestRefinePlant() or nil
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
function SkillUp.HasRefinablePlants()
    local target = SkillUp.PickRefineTarget()
    local uses = SkillUp.RefineUsesForTarget(target)
    return (tonumber(uses) or 0) >= 1
end

--- Buy when SeedDeficit >= 1 for the chosen line (plots + buffer), even if bags
--- already hold some seeds. Refine-before-buy when plants can cover that line.
function SkillUp.ShouldCultBuy()
    if SkillUp.ShouldCultPlant() ~= true then
        return false
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
        return false
    end

    local pick = SkillUp.PickBestBagSeed()
    local seedUid = 0
    local plantUid = 0
    if type(pick) == "table" then
        seedUid = tonumber(pick.seedUid) or 0
        plantUid = tonumber(pick.plantUid) or 0
    else
        -- Empty bags: refine leftover plants before opening the vendor.
        if SkillUp.HasRefinablePlants() == true or SkillUp.HasUpgradePlant() == true then
            return false
        end
        local target = SkillUp.ResolveBuySeedTarget()
        if type(target) ~= "table" then
            return false
        end
        seedUid = tonumber(target.seedUid) or 0
    end
    if seedUid <= 0 then
        return false
    end

    local deficit = SkillUp.SeedDeficit(seedUid)
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
        local uses = SkillUp.RefineUsesForTarget({
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

function SkillUp.CollectBuyJobs()
    local jobs = {}
    -- Cult SkillUp seed top-up (SeedDeficit via ClimbPlan); climb L1 buys stay on UpgradeSeed path in Buy.lua.
    if SkillUp.ShouldCultBuy() == true then
        local target = SkillUp.ResolveBuySeedTarget()
        if type(target) == "table" and (tonumber(target.seedUid) or 0) > 0 then
            local seedUid = tonumber(target.seedUid) or 0
            local deficit = SkillUp.SeedDeficit(seedUid)
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
    local containerJobs = SkillUp.CollectContainerBuyJobs() or {}
    for i = 1, #containerJobs do
        jobs[#jobs + 1] = containerJobs[i]
    end
    return jobs
end

--- Notify once per Cult stall reason; clear latch when condition lifts.
function SkillUp.MaybeNotifyStall()
    if SkillUp.ShouldCultPlant() ~= true then
        SkillUp._stallLatch = nil
        return
    end
    -- Waiting on refine (harvested plants -> seeds) or tier upgrade, not a stall.
    if SkillUp.HasRefinablePlants() == true or SkillUp.HasUpgradePlant() == true then
        SkillUp._stallLatch = nil
        return
    end
    local pick = SkillUp.PickBestBagSeed()
    local seedUid = 0
    if type(pick) == "table" then
        seedUid = tonumber(pick.seedUid) or 0
    else
        local target = SkillUp.ResolveBuySeedTarget and SkillUp.ResolveBuySeedTarget() or nil
        if type(target) == "table" then
            seedUid = tonumber(target.seedUid) or 0
        end
    end
    -- Plots + buffer settled for the chosen line - not a stall.
    if seedUid > 0 and (tonumber(SkillUp.SeedDeficit(seedUid)) or 0) < 1 then
        SkillUp._stallLatch = nil
        return
    end
    local canBuy = SkillUp.ShouldCultBuy() == true
    local VA = StockPiler4.VendorAdapter
    local storeOpen = VA and VA.IsStoreOpen and VA.IsStoreOpen() == true
    -- AutoBuy is actively purchasing - not a stall.
    if canBuy and storeOpen then
        SkillUp._stallLatch = nil
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
    if SkillUp._stallLatch == reason then
        return
    end
    SkillUp._stallLatch = reason
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

----------------------------------------------------------------
-- Apo SkillUp - brew from surplus main + resin + container
----------------------------------------------------------------
-- Apo brew/buy/resin: Planner/ApoSkillPlan.lua (re-exported at file end).


SkillUp._apoStallLatch = nil
SkillUp._apoBrewRow = nil


----------------------------------------------------------------
-- Empirical skill-up rates: Knowledge/SkillRates.lua (re-exported at file end).
----------------------------------------------------------------

--- Full SkillUp diagnostic dump (/sp4 skillplan).
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


--- Count usable Apo-tier (or below) containers currently in bags.

--- Accepts a numeric uid, or a spec/item table with uid/uniqueID.
function SkillUp.WatchDemandReserve(specOrUid)
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
function SkillUp.PlantFeedstockReserve(seedUid, plantUid)
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
        local deficit = tonumber(SkillUp.SeedDeficit(seedUid)) or 0
        if deficit > reserve then
            reserve = deficit
        end
    end
    local watchNeed = 0
    if plantUid > 0 then
        watchNeed = SkillUp.WatchDemandReserve(plantUid)
    end
    if seedUid > 0 then
        local seedNeed = SkillUp.WatchDemandReserve(seedUid)
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
function SkillUp.PlantBrewSurplus(plantUid, seedUid, plantCount)
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
    local reserve = SkillUp.PlantFeedstockReserve(seedUid, plantUid)
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
function SkillUp.PlantRefineSurplus(plantUid, seedUid, plantCount)
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
        watchNeed = SkillUp.WatchDemandReserve(plantUid)
    end
    local seedNeed = SkillUp.WatchDemandReserve(seedUid)
    if seedNeed > watchNeed then
        watchNeed = seedNeed
    end
    local surplus = plantCount - watchNeed
    if surplus < 0 then
        return 0
    end
    return surplus
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
    if SkillUp.WatchesDone() == true then
        return nil, nil, nil
    end
    local Watch = StockPiler4.Watch
    local potionShort = Watch and Watch.AllEnabledPotionWatchesStocked
        and Watch.AllEnabledPotionWatchesStocked() ~= true
    local plantShort = AllEnabledPlantWatchesStocked() ~= true
    local bufferShort = SeedBufferOk() ~= true

    if bufferShort ~= true and SkillUp.AllShortWatchesProgressBlocked() == true then
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
    if SkillUp.HasUpgradePlant() == true or SkillUp.HasRefinablePlants() == true then
        local pick = SkillUp.PickBestBagSeed()
        local budget = pick and SeedBudget(tonumber(pick.seedUid) or 0) or nil
        local headroom = type(budget) == "table" and (tonumber(budget.headroom) or 0) or 0
        if headroom > 0 or SkillUp.HasUpgradePlant() == true then
            return "refining", TOr("skillup.watch.cult_refining", L"Refining for seeds")
        end
    end
    local job = SkillUp.PickPlantJob and SkillUp.PickPlantJob() or nil
    if type(job) == "table" and (tonumber(job.plantable) or 0) >= 1 then
        local budget = SeedBudget(tonumber(job.seedUid) or 0)
        local headroom = tonumber(budget.headroom) or 0
        if headroom > 0 then
            return "buffer_plant", TOr("skillup.watch.cult_buffer", L"Planting for seed buffer")
        end
        return "planting", TOr("skillup.watch.cult_planting", L"Planting Skill up seeds")
    end
    local latch = tostring(SkillUp._stallLatch or "")
    if latch ~= "" then
        local short = TOr("skillup.watch.cult_" .. latch, nil)
        if short ~= nil then
            return latch, short
        end
        return latch, TOr("skillup.stall." .. latch, L"Skill up Culti stalled")
    end
    if SkillUp.CountEmptyPlots() <= 0 then
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
    local cult = SkillUp.GetCultSkill()
    if cult <= 0 then
        return nil
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return nil
    end
    -- Show while Cult SkillUp is on, or while Apo SkillUp needs Cult assist.
    if SkillUp.IsCultEnabled() ~= true and SkillUp.IsApoEnabled() ~= true then
        return nil
    end

    local Watch = StockPiler4.Watch
    local agOn = Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true

    -- Internals still track the active seed line (highest in plots, else bag pick).
    local growing = HighestInGroundSkillUpSeed()
    local pick = SkillUp.PickBestBagSeed()
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
    local tier = SkillUp.TargetMaxSkill()
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
        -- Stock/Craftable/Target are potion-watch columns; blank on SkillUp.
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
    if SkillUp.IsApoEnabled() ~= true then
        return nil
    end
    local tier = SkillUp.ApoTargetTier()
    local waitingKey, waitingText, waitingLines = WaitingWatchesStatus("apo")
    local brewRow = nil
    local statusKey, statusText, craftable, target, recipe
    if waitingKey == "fallback_blocked" then
        if SkillUp.ShouldApoBrew() == true and SkillUp.BuildApoBrewRow then
            brewRow = SkillUp.BuildApoBrewRow({ quiet = true })
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
        if SkillUp.ShouldApoBrew() == true and SkillUp.BuildApoBrewRow then
            brewRow = SkillUp.BuildApoBrewRow({ quiet = true })
        end
        if type(brewRow) == "table" then
            statusKey = "ready_to_craft"
            statusText = TOr("plan.status.ready_to_craft", L"Ready to brew")
            craftable = tonumber(brewRow.craftable) or 0
            target = tonumber(brewRow.target) or (craftable * 5)
            recipe = brewRow.recipe
        else
            local latch = tostring(SkillUp._apoStallLatch or "need_mats")
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
        -- Stock/Craftable/Target are potion-watch columns; blank on SkillUp.
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
function SkillUp.ShouldShowWatchStatus()
    local Caps = StockPiler4.TradeSkillCaps
    if SkillUp.IsCultEnabled() == true
        and Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() == true
    then
        return true
    end
    -- Apo-only: Cult assist row still useful when Apo is on and Cult can grow.
    if SkillUp.IsApoEnabled() == true
        and Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() == true
        and SkillUp.GetCultSkill() > 0
    then
        return true
    end
    if SkillUp.IsApoEnabled() == true then
        return true
    end
    return false
end

--- 0-2 ephemeral Watch-tab rows (Cult / Apo). Never written to WatchStore.
--- Always built when the matching toggle is on; Status shows waiting vs active.
function SkillUp.BuildWatchStatusRows()
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

--- SkillRates owns rate APIs; re-bind after SkillUp table is fully defined.
if StockPiler4.SkillRates and StockPiler4.SkillRates.SyncSkillUpExports then
    StockPiler4.SkillRates.SyncSkillUpExports()
end

if StockPiler4.ApoSkillPlan and StockPiler4.ApoSkillPlan.SyncSkillUpExports then
    StockPiler4.ApoSkillPlan.SyncSkillUpExports()
end
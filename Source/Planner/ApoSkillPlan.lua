----------------------------------------------------------------
-- StockPiler4 Planner/ApoSkillPlan - idle Apo brew / resin / vial buy
-- Extracted from SkillUp; SkillUp re-exports for call-site compatibility.
-- Shared watch reserves (WatchDemandReserve / Plant*Surplus) live in WatchReserves.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.ApoSkillPlan = StockPiler4.ApoSkillPlan or {}
local ASP = StockPiler4.ApoSkillPlan

local function MirrorApoStateToSkillUp()
    -- Latch/row live on ASP; callers read ApoSkillPlan directly.
end

ASP._apoStallLatch = nil
ASP._apoBrewRow = nil

local function Gates()
    return StockPiler4.SkillUpGates
end

local function WR()
    return StockPiler4.WatchReserves
end

local function Rates()
    return StockPiler4.SkillRates
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

function ASP.ApoTargetTier()
    return Gates().FloorApoTier(Gates().GetApoSkill())
end

function ASP.ShouldApoBrew()
    if Gates().IsApoEnabled() ~= true then
        return false
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanBrewPotions and Caps.CanBrewPotions() ~= true then
        return false
    end
    if Gates().WatchesAllowIdleSkillUp() ~= true then
        return false
    end
    return true
end

--- Next Apo ladder step above current skill (25, 50, ..., 200).
function ASP.NextApoTier(apoSkill)
    apoSkill = tonumber(apoSkill) or Gates().GetApoSkill()
    local tiers = Gates().APO_TIERS or { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
    for i = 1, #tiers do
        local t = tiers[i]
        if apoSkill < t then
            return t
        end
    end
    return Gates().APO_MAX or 200
end

function ASP.CountApoContainers()
    local targetTier = ASP.ApoTargetTier()
    if targetTier < 1 then
        targetTier = 1
    end
    local Inv = StockPiler4.Inventory
    local MS = StockPiler4.MaterialSpec
    local SM = StockPiler4.SeedMap
    if not (Inv and Inv.ForEachItem and MS and MS.FromItemData) then
        return 0
    end
    local total = 0
    local seen = {}
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        local uid = tonumber(item.uniqueID) or 0
        if uid <= 0 or seen[uid] == true then
            return
        end
        seen[uid] = true
        local spec = MS.FromItemData(item, nil)
        if type(spec) ~= "table" or tostring(spec.role or "") ~= "container" then
            return
        end
        if SM and SM.ItemLooksLikeRefinablePlant and SM.ItemLooksLikeRefinablePlant(item) == true then
            return
        end
        local req = tonumber(spec.skillLevel) or SeedSkillReq(item)
        if req > targetTier then
            return
        end
        local count = Inv.CountByUid and tonumber(Inv.CountByUid(uid)) or 0
        if count <= 0 then
            count = tonumber(item.stackCount) or tonumber(item.StackCount) or 1
        end
        total = total + count
    end)
    return total
end

function ASP.ShouldApoBuyContainer()
    if ASP.ShouldApoBrew() ~= true then
        return false
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
        return false
    end
    -- Buy vials when an exact-tier main exists (even if held for seed buffer).
    if ASP.PickApoBagMaterial("main", { ignoreReserve = true }) == nil then
        return false
    end
    local want = Rates().ApoContainerBuyTarget()
    if want < 1 then
        return false
    end
    local have = ASP.CountApoContainers()
    return have < want
end

local function SpecStability(spec)
    if type(spec) ~= "table" then
        return 0
    end
    local stab = tonumber(spec.stability)
    if stab ~= nil then
        return stab
    end
    local B = GameData and GameData.CraftingItemBonus
    if type(spec.bonuses) == "table" and B and B.STABILITY ~= nil then
        return tonumber(spec.bonuses[B.STABILITY]) or 0
    end
    return 0
end

--- Absolute plant/seed/mat need from all short enabled potion/plant watches
--- (AG on or off). Used so SkillUp never drains mats still claimed by watches.

local function ResolveSeedUidForPlantItem(item, plantUid)
    plantUid = tonumber(plantUid) or 0
    local SM = StockPiler4.SeedMap
    if SM and SM.ResolveSeedUidForPlant and plantUid > 0 then
        local plantSpec = nil
        if type(item) == "table" then
            local MS = StockPiler4.MaterialSpec
            if MS and MS.FromItemData then
                plantSpec = MS.FromItemData(item, nil)
            end
        end
        local uid = tonumber(SM.ResolveSeedUidForPlant(plantUid, plantSpec)) or 0
        if uid > 0 then
            return uid
        end
    end
    if SM and SM.GetSeedUidsForPlant and plantUid > 0 then
        local seeds = SM.GetSeedUidsForPlant(plantUid) or {}
        if type(seeds) == "table" and #seeds > 0 then
            return tonumber(SM.PickBestSeedUid and SM.PickBestSeedUid(plantUid, seeds) or seeds[1]) or 0
        end
    end
    local entry = StockPiler4.Account and StockPiler4.Account.refines
        and StockPiler4.Account.refines[tostring(plantUid)]
    if type(entry) == "table" then
        return tonumber(entry.seedUid) or 0
    end
    return 0
end

--- True when spec is Arboreal Resin / harvest byproduct stabilizer.
local function IsApoResinSpec(spec, item)
    local SM = StockPiler4.SeedMap
    if SM and SM.IsHarvestByproduct and type(spec) == "table" and SM.IsHarvestByproduct(spec) == true then
        return true
    end
    local n = ""
    local src = item or spec
    if type(src) == "table" and src.name ~= nil then
        if type(src.name) == "wstring" and type(WStringToString) == "function" then
            n = string.lower(WStringToString(src.name) or "")
        else
            n = string.lower(tostring(src.name or ""))
        end
    end
    if n == "" and type(spec) == "table" and spec.name ~= nil then
        if type(spec.name) == "wstring" and type(WStringToString) == "function" then
            n = string.lower(WStringToString(spec.name) or "")
        else
            n = string.lower(tostring(spec.name or ""))
        end
    end
    return string.find(n, "resin", 1, true) ~= nil or string.find(n, "arboreal", 1, true) ~= nil
end

local function IsValidApoContainer(item, spec)
    if type(spec) ~= "table" or tostring(spec.role or "") ~= "container" then
        return false
    end
    local SM = StockPiler4.SeedMap
    local MS = StockPiler4.MaterialSpec
    if SM and SM.ItemLooksLikeRefinablePlant and SM.ItemLooksLikeRefinablePlant(item) == true then
        return false
    end
    if (tonumber(spec.cultivationType) or 0) ~= 0 then
        return false
    end
    if MS and MS.IsCultivationAdditive and MS.IsCultivationAdditive(item) == true then
        return false
    end
    return true
end

--- Units of resin stab needed so main+container+resin > 0 (engine HIGH).
local function ResinStabNeeded(mainStab, containerStab)
    local base = (tonumber(mainStab) or 0) + (tonumber(containerStab) or 0)
    if base > 0 then
        return 0
    end
    -- Need total > 0 => add at least (1 - base).
    return 1 - base
end

--- List bag candidates for Apo SkillUp role.
--- Main: exact FloorApoTier only. Container: skillReq <= floor. Stabilizer: resin byproduct.
function ASP.ListApoBagMaterials(role, opts)
    role = tostring(role or "")
    opts = type(opts) == "table" and opts or {}
    local ignoreReserve = opts.ignoreReserve == true
    local exactTier = opts.exactTier ~= false
    local targetTier = ASP.ApoTargetTier()
    if targetTier < 1 then
        targetTier = 1
    end
    local Inv = StockPiler4.Inventory
    local MS = StockPiler4.MaterialSpec
    local SM = StockPiler4.SeedMap
    local list = {}
    if not (Inv and Inv.ForEachItem and MS and MS.FromItemData) then
        return list
    end
    local seen = {}
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        local uid = tonumber(item.uniqueID) or 0
        if uid <= 0 or seen[uid] == true then
            return
        end
        seen[uid] = true
        if SM and SM.IsBagSeedOrSpore and SM.IsBagSeedOrSpore(item) then
            return
        end
        if not CanUseCraftingSample(item) then
            return
        end
        local spec = MS.FromItemData(item, nil)
        if type(spec) ~= "table" then
            return
        end
        local specRole = tostring(spec.role or "")
        if role == "stabilizer" then
            if specRole ~= "stabilizer" and specRole ~= "goldweed" and not IsApoResinSpec(spec, item) then
                return
            end
            if not IsApoResinSpec(spec, item) then
                return
            end
        elseif specRole ~= role then
            return
        end
        if role == "container" and not IsValidApoContainer(item, spec) then
            return
        end
        if role == "main" and LooksNonMainSeed(item, spec) then
            return
        end
        local count = Inv.CountByUid and tonumber(Inv.CountByUid(uid)) or 0
        if count <= 0 then
            count = tonumber(item.stackCount) or tonumber(item.StackCount) or 1
        end
        if count <= 0 then
            return
        end
        local brewable = count
        local seedUid = 0
        if role == "main" then
            seedUid = ResolveSeedUidForPlantItem(item, uid)
            if not ignoreReserve then
                brewable = WR().PlantBrewSurplus(uid, seedUid, count)
                if brewable < 1 then
                    return
                end
            end
        end
        local req = tonumber(spec.skillLevel) or SeedSkillReq(item)
        local stab = SpecStability(spec)
        if stab == 0 and type(spec.bonuses) == "table" then
            local B = GameData and GameData.CraftingItemBonus
            if B and B.STABILITY ~= nil then
                stab = tonumber(spec.bonuses[B.STABILITY]) or 0
            end
        end
        if role == "main" then
            -- Exact Apo floor only - no lower-tier brew after tier-up.
            if exactTier then
                if req ~= targetTier then
                    return
                end
            elseif req > targetTier then
                return
            end
        elseif role == "container" then
            if req > targetTier then
                return
            end
        elseif role == "stabilizer" then
            if stab <= 0 then
                return
            end
            if req > targetTier then
                return
            end
        end
        list[#list + 1] = {
            uid = uid,
            uniqueID = uid,
            skillReq = req,
            count = brewable,
            bagCount = count,
            seedUid = seedUid,
            stability = stab,
            item = item,
            spec = spec,
            role = role == "stabilizer" and "stabilizer" or role,
        }
    end)
    return list
end

--- Best bag item for role (see ListApoBagMaterials filters).
--- Never force role via MaterialSpec roleHint (that mislabeled plants as containers).
function ASP.PickApoBagMaterial(role, opts)
    role = tostring(role or "")
    opts = type(opts) == "table" and opts or {}
    local list = ASP.ListApoBagMaterials(role, opts)
    if #list == 0 then
        return nil
    end
    local targetTier = ASP.ApoTargetTier()
    if targetTier < 1 then
        targetTier = 1
    end
    local best = nil
    local bestScore = -1
    for i = 1, #list do
        local cand = list[i]
        local score = 0
        if role == "stabilizer" then
            local tierDist = math.abs((tonumber(cand.skillReq) or 0) - targetTier)
            score = (1000 - tierDist) * 100000
                - (tonumber(cand.stability) or 0) * 1000
                + (tonumber(cand.count) or 0)
        elseif role == "container" then
            score = (100 - (tonumber(cand.stability) or 0)) * 1000000
                + (1000 - math.abs((tonumber(cand.skillReq) or 0) - targetTier)) * 100
                + (tonumber(cand.count) or 0)
        else
            score = (tonumber(cand.count) or 0)
        end
        if score > bestScore then
            bestScore = score
            best = cand
        end
    end
    return best
end

--- Build a stable inventable recipe from bag surplus (container + main + resin).
--- Main must be exact Apo floor; resins prefer lowest that stabilize with container stab.
function ASP.BuildApoBrewRecipe()
    if ASP.ShouldApoBrew() ~= true then
        return nil
    end
    local main = ASP.PickApoBagMaterial("main")
    if type(main) ~= "table" then
        if ASP.PickApoBagMaterial("main", { ignoreReserve = true }) ~= nil then
            return nil, "seed_buffer"
        end
        local lower = ASP.ListApoBagMaterials("main", { exactTier = false, ignoreReserve = true })
        local targetTier = ASP.ApoTargetTier()
        for i = 1, #lower do
            if (tonumber(lower[i].skillReq) or 0) < targetTier then
                return nil, "wait_cult"
            end
        end
        return nil, "need_mats"
    end

    local containers = ASP.ListApoBagMaterials("container")
    local resins = ASP.ListApoBagMaterials("stabilizer")
    if #containers == 0 then
        return nil, "need_mats"
    end
    if #resins == 0 then
        local anyStableWithoutResin = false
        for i = 1, #containers do
            local c = containers[i]
            if (tonumber(c.uid) or 0) ~= (tonumber(main.uid) or 0) then
                if ResinStabNeeded(main.stability, c.stability) <= 0 then
                    anyStableWithoutResin = true
                    break
                end
            end
        end
        if not anyStableWithoutResin then
            return nil, "need_resin"
        end
    end

    table.sort(containers, function(a, b)
        local sa, sb = tonumber(a.stability) or 0, tonumber(b.stability) or 0
        if sa ~= sb then
            return sa < sb
        end
        local ta, tb = tonumber(a.skillReq) or 0, tonumber(b.skillReq) or 0
        if ta ~= tb then
            return ta > tb
        end
        return (tonumber(a.count) or 0) > (tonumber(b.count) or 0)
    end)
    -- Prefer lowest-tier resin that can still stabilize (burn Gooey/Slimy before Hale).
    -- Tip text: "Prefers lower resins ... that still go green."
    table.sort(resins, function(a, b)
        local ta, tb = tonumber(a.skillReq) or 0, tonumber(b.skillReq) or 0
        if ta ~= tb then
            return ta < tb
        end
        local sa, sb = tonumber(a.stability) or 0, tonumber(b.stability) or 0
        if sa ~= sb then
            return sa < sb
        end
        return (tonumber(a.count) or 0) > (tonumber(b.count) or 0)
    end)

    local RS = StockPiler4.RecipeSpec
    local bestRecipe, bestParts = nil, nil
    local bestCost = 1e9

    local function tryCombo(container, resin, resinUnits)
        if (tonumber(container.uid) or 0) == (tonumber(main.uid) or 0) then
            return
        end
        resinUnits = tonumber(resinUnits) or 0
        if resinUnits < 0 then
            resinUnits = 0
        end
        if resinUnits > 3 then
            return
        end
        if resinUnits > 0 then
            if type(resin) ~= "table" or (tonumber(resin.count) or 0) < resinUnits then
                return
            end
        end
        local slots = {
            {
                role = "container",
                uid = container.uid,
                uniqueID = container.uid,
                perCraft = 1,
                spec = container.spec,
            },
            {
                role = "main",
                uid = main.uid,
                uniqueID = main.uid,
                perCraft = 1,
                spec = main.spec,
            },
        }
        if resinUnits > 0 and type(resin) == "table" then
            slots[#slots + 1] = {
                role = "stabilizer",
                uid = resin.uid,
                uniqueID = resin.uid,
                perCraft = resinUnits,
                spec = resin.spec,
            }
        end
        if RS and RS.EffectiveSpecPerCraft and resinUnits > 0 then
            local want = tonumber(RS.EffectiveSpecPerCraft(slots[3], slots)) or resinUnits
            if want > resinUnits then
                if (tonumber(resin.count) or 0) < want or want > 3 then
                    return
                end
                slots[3].perCraft = want
                resinUnits = want
            end
        end
        if RS and RS.RecipeIsStable and RS.RecipeIsStable({ slots = slots }) ~= true then
            return
        end
        -- Prefer lower resin skillReq first (burn leftover tiers), then fewer
        -- units, then lower resin/container stab. Do not prefer high-tier resin
        -- just because it needs fewer slots.
        local rReq = 0
        local rStab = 0
        if type(resin) == "table" then
            rReq = tonumber(resin.skillReq) or 0
            rStab = tonumber(resin.stability) or 0
        end
        local cost = rReq * 10000
            + resinUnits * 100
            + rStab
            + (tonumber(container.stability) or 0)
        if cost < bestCost then
            bestCost = cost
            bestRecipe = {
                slots = slots,
                skillUpOrigin = true,
                recipeYield = 5,
            }
            if RS and RS.BuildRecipeSpecKey then
                bestRecipe.recipeSpecKey = RS.BuildRecipeSpecKey(slots)
                bestRecipe.key = bestRecipe.recipeSpecKey
            end
            bestParts = {
                main = main,
                container = container,
                stabilizer = resin,
                resinPerCraft = resinUnits,
            }
        end
    end

    for ci = 1, #containers do
        local container = containers[ci]
        local needStab = ResinStabNeeded(main.stability, container.stability)
        if needStab <= 0 then
            tryCombo(container, nil, 0)
        else
            for ri = 1, #resins do
                local resin = resins[ri]
                local rStab = tonumber(resin.stability) or 0
                if rStab > 0 then
                    local units = math.ceil(needStab / rStab)
                    if units < 1 then
                        units = 1
                    end
                    if units <= 3 then
                        for u = units, 3 do
                            tryCombo(container, resin, u)
                        end
                    end
                end
            end
        end
    end

    if type(bestRecipe) ~= "table" then
        if #resins == 0 then
            return nil, "need_resin"
        end
        return nil, "unstable"
    end
    return bestRecipe, nil, bestParts
end

--- Synthetic plan row so Brew can auto-load and CanBrewNow lights for SkillUp.
--- opts.quiet: skip stall notify / MarkRefineDue (Watch paint, skillplan dump).
function ASP.BuildApoBrewRow(opts)
    opts = type(opts) == "table" and opts or {}
    local quiet = opts.quiet == true
    if ASP.ShouldApoBrew() ~= true then
        ASP._apoBrewRow = nil
    MirrorApoStateToSkillUp()
        return nil
    end
    local recipe, why, parts = ASP.BuildApoBrewRecipe()
    if type(recipe) ~= "table" then
        ASP._apoBrewRow = nil
    MirrorApoStateToSkillUp()
        if not quiet then
            if why == "need_resin" or why == "unstable" then
                if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                    StockPiler4.Refine.MarkRefineDue("skill-up-resin")
                end
            end
            ASP.MaybeNotifyApoStall(why or "need_mats")
        end
        return nil
    end
    local RS = StockPiler4.RecipeSpec
    local craftable = 0
    if RS and RS.CountCraftsPossible then
        craftable = tonumber(RS.CountCraftsPossible(recipe, { respectGrowReserve = true })) or 0
    end
    if craftable < 1 then
        ASP._apoBrewRow = nil
    MirrorApoStateToSkillUp()
        if not quiet then
            if ASP.PickApoBagMaterial("main", { ignoreReserve = true }) ~= nil then
                ASP.MaybeNotifyApoStall("seed_buffer")
            else
                ASP.MaybeNotifyApoStall("need_mats")
            end
        end
        return nil
    end
    ASP._apoStallLatch = nil
    MirrorApoStateToSkillUp()
    local tier = ASP.ApoTargetTier()
    local mainUid = parts and parts.main and parts.main.uid or 0
    local name = L"Skill up Apo"
    if parts and parts.main and type(parts.main.item) == "table" and parts.main.item.name ~= nil then
        name = parts.main.item.name
    end
    local row = {
        id = "skill_up_apo",
        potionKey = "skill_up_apo",
        potionRecipeKey = "skill_up_apo",
        name = name,
        recipe = recipe,
        recipeYield = 5,
        skillUp = true,
        statusKey = "ready_to_craft",
        autoGrow = true,
        craftable = craftable,
        craftableSafe = true,
        potionHave = 0,
        potionMin = craftable * 5 + 5,
        potionDeficit = craftable * 5 + 5,
        target = craftable * 5 + 5,
        uniqueID = 0,
        outputUid = 0,
        skillReq = tier,
        mainUid = mainUid,
    }
    ASP._apoBrewRow = row
    MirrorApoStateToSkillUp()
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        local bagMain = 0
        local surplusMain = 0
        local reserveMain = 0
        if mainUid > 0 then
            local Inv = StockPiler4.Inventory
            if Inv and Inv.CountByUid then
                bagMain = tonumber(Inv.CountByUid(mainUid)) or 0
            end
            local seedUid = 0
            if parts and parts.main then
                seedUid = tonumber(parts.main.seedUid) or 0
            end
            if seedUid <= 0 then
                local SM = StockPiler4.SeedMap
                if SM and SM.ResolveSeedUidForPlant then
                    seedUid = tonumber(SM.ResolveSeedUidForPlant(mainUid, nil)) or 0
                end
            end
            surplusMain = tonumber(WR().PlantBrewSurplus(mainUid, seedUid, bagMain)) or 0
            reserveMain = tonumber(WR().PlantFeedstockReserve(seedUid, mainUid)) or 0
        end
        StockPiler4.Debug.LogOp("skillup", string.format(
            "apo-brew main=%d container=%d resin=%d x%d craftable=%d tier=%d bag=%d surplus=%d reserve=%d",
            mainUid,
            parts and parts.container and parts.container.uid or 0,
            parts and parts.stabilizer and parts.stabilizer.uid or 0,
            parts and parts.resinPerCraft or 0,
            craftable,
            tier,
            bagMain,
            surplusMain,
            reserveMain
        ))
    end
    return row
end

function ASP.GetApoBrewRow()
    return ASP._apoBrewRow
end

--- Buffer-safe refinable uses for Apo resin convert (0 if none).
--- keepOne: leave one plant for a later brew at this plantUid.
local function ApoResinRefineUses(plantUid, seedUid, spec, bagCount, keepOne)
    plantUid = tonumber(plantUid) or 0
    seedUid = tonumber(seedUid) or 0
    bagCount = tonumber(bagCount) or 0
    if plantUid <= 0 or bagCount < 1 then
        return 0, 0
    end
    local surplus = WR().PlantBrewSurplus(plantUid, seedUid, bagCount)
    if keepOne == true and surplus > 1 then
        surplus = surplus - 1
    elseif keepOne == true and surplus < 1 then
        return 0, 0
    elseif surplus < 1 then
        return 0, 0
    end
    local Refine = StockPiler4.Refine
    local refinable = 0
    if Refine and Refine.CountRefinablePlants then
        refinable = tonumber(Refine.CountRefinablePlants(plantUid, spec)) or 0
    end
    return math.min(surplus, refinable, 5), surplus
end

--- Leftover main plants below Apo floor (no longer brewable after tier-up).
--- Prefer lowest skillReq, then richest refinable stack.
local function PickApoLeftoverResinPlant(apoTier)
    apoTier = tonumber(apoTier) or 0
    if apoTier <= 1 then
        return nil
    end
    local Inv = StockPiler4.Inventory
    local MS = StockPiler4.MaterialSpec
    local SM = StockPiler4.SeedMap
    if not (Inv and Inv.ForEachItem and MS and MS.FromItemData) then
        return nil
    end
    local best = nil
    local seen = {}
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        local uid = tonumber(item.uniqueID) or 0
        if uid <= 0 or seen[uid] == true then
            return
        end
        seen[uid] = true
        if SM and SM.IsBagSeedOrSpore and SM.IsBagSeedOrSpore(item) then
            return
        end
        if not CanUseCraftingSample(item) then
            return
        end
        local spec = MS.FromItemData(item, nil)
        if type(spec) ~= "table" then
            return
        end
        if tostring(spec.role or "") ~= "main" then
            return
        end
        if LooksNonMainSeed(item, spec) then
            return
        end
        local req = tonumber(spec.skillLevel) or SeedSkillReq(item)
        if req < 1 or req >= apoTier then
            return
        end
        local seedUid = ResolveSeedUidForPlantItem(item, uid)
        local bagCount = Inv.CountByUid and tonumber(Inv.CountByUid(uid)) or 0
        if bagCount <= 0 then
            bagCount = tonumber(item.stackCount) or tonumber(item.StackCount) or 1
        end
        local uses, surplus = ApoResinRefineUses(uid, seedUid, spec, bagCount, false)
        if uses < 1 then
            return
        end
        if best == nil
            or req < best.req
            or (req == best.req and uses > best.uses)
            or (req == best.req and uses == best.uses and uid < best.plantUid)
        then
            best = {
                plantUid = uid,
                seedUid = seedUid,
                spec = spec,
                uses = uses,
                surplus = surplus,
                req = req,
            }
        end
    end)
    return best
end

--- When Apo SkillUp needs resin: prefer leftover lower-tier mains, then
--- surplus of the exact-floor brew main (keep >=1 for brew).
function ASP.AppendApoResinRefineIntents(intents, appendFn)
    if type(intents) ~= "table" or type(appendFn) ~= "function" then
        return
    end
    if ASP.ShouldApoBrew() ~= true then
        return
    end
    local recipe, why = ASP.BuildApoBrewRecipe()
    if type(recipe) == "table" then
        return
    end
    if why ~= "need_resin" and why ~= "unstable" then
        return
    end

    local apoTier = ASP.ApoTargetTier()
    local Refine = StockPiler4.Refine
    local pick = PickApoLeftoverResinPlant(apoTier)
    local source = "leftover"

    if type(pick) ~= "table" then
        source = "brew-main"
        local main = ASP.PickApoBagMaterial("main")
        if type(main) ~= "table" then
            -- Never ignoreReserve - that burned buffer plants for resin.
            return
        end
        local plantUid = tonumber(main.uid) or 0
        local seedUid = tonumber(main.seedUid) or 0
        if plantUid <= 0 then
            return
        end
        local Inv = StockPiler4.Inventory
        local bagCount = Inv and Inv.CountByUid and tonumber(Inv.CountByUid(plantUid))
            or tonumber(main.bagCount) or 0
        local uses, surplus = ApoResinRefineUses(plantUid, seedUid, main.spec, bagCount, true)
        if uses < 1 then
            return
        end
        pick = {
            plantUid = plantUid,
            seedUid = seedUid,
            spec = main.spec,
            uses = uses,
            surplus = surplus,
            req = apoTier,
        }
    end

    local plantUid = tonumber(pick.plantUid) or 0
    local seedUid = tonumber(pick.seedUid) or 0
    local uses = tonumber(pick.uses) or 0
    if plantUid <= 0 or uses < 1 then
        return
    end
    local budget = Refine and Refine.GetSeedBudget and Refine.GetSeedBudget(seedUid) or nil
    appendFn({
        spec = pick.spec,
        seedUid = seedUid,
        plantUid = plantUid,
        specKey = "skill_up_resin:" .. tostring(plantUid),
    }, "resin-need", uses, budget)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "apo-resin-refine source=%s plantUid=%d seedUid=%d uses=%d surplus=%d req=%d apoTier=%d",
            source, plantUid, seedUid, uses, tonumber(pick.surplus) or 0,
            tonumber(pick.req) or 0, apoTier
        ))
    end
end

function ASP.ResolveBuyContainerTarget()
    local targetTier = ASP.ApoTargetTier()
    if targetTier < 1 then
        targetTier = 1
    end
    local VA = StockPiler4.VendorAdapter
    local MS = StockPiler4.MaterialSpec
    if not MS then
        return nil
    end
    local main = ASP.PickApoBagMaterial("main")
        or ASP.PickApoBagMaterial("main", { ignoreReserve = true })
    local mainStab = main and (tonumber(main.stability) or SpecStability(main.spec)) or -2
    local resins = ASP.ListApoBagMaterials("stabilizer")
    local bestResinStab = 0
    local resinCount = 0
    for i = 1, #resins do
        local r = resins[i]
        local s = tonumber(r.stability) or 0
        if s > bestResinStab then
            bestResinStab = s
        end
        resinCount = resinCount + (tonumber(r.count) or 0)
    end
    if bestResinStab < 1 then
        bestResinStab = 1
    end
    local maxResinStab = math.min(3, math.max(1, resinCount)) * bestResinStab
    local needFromContainer = ResinStabNeeded(mainStab, 0) - maxResinStab
    if needFromContainer < 0 then
        needFromContainer = 0
    end

    local bestUid, bestSpec, bestReq = 0, nil, -1
    local bestScore = -1e18
    local function consider(uid, item)
        uid = tonumber(uid) or 0
        if uid <= 0 or type(item) ~= "table" then
            return
        end
        local spec = MS.FromItemData and MS.FromItemData(item, nil)
        if not IsValidApoContainer(item, spec) then
            return
        end
        local req = tonumber(spec.skillLevel) or SeedSkillReq(item)
        if req > targetTier then
            return
        end
        local stab = SpecStability(spec)
        local ok = (stab >= needFromContainer) and 1 or 0
        local score = ok * 1e12
            - stab * 1e6
            - math.abs(req - targetTier) * 1e3
            + req
        if score > bestScore then
            bestScore = score
            bestUid = uid
            bestReq = req
            bestSpec = spec
        end
    end
    local items = StockPiler4.Account and StockPiler4.Account.items
    if type(items) == "table" then
        for key, row in pairs(items) do
            if type(row) == "table" then
                local uid = tonumber(row.uniqueID) or tonumber(key) or 0
                consider(uid, row)
            end
        end
    end
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
    if VA and VA.GetStoreItems then
        local list = VA.GetStoreItems()
        if type(list) == "table" then
            for i = 1, #list do
                local item = list[i]
                if type(item) == "table" then
                    consider(item.uniqueID, item)
                end
            end
        end
    end
    if bestUid > 0 then
        return {
            seedUid = bestUid,
            uid = bestUid,
            skillReq = bestReq,
            targetMax = targetTier,
            spec = bestSpec,
        }
    end
    local cit = GameData and GameData.CraftingItemType or {}
    local Caps = StockPiler4.TradeSkillCaps
    local apoId = Caps and Caps.ApothecaryId and Caps.ApothecaryId() or 4
    local slotType = tonumber(cit.CONTAINER) or 5
    return {
        uid = 0,
        seedUid = 0,
        skillReq = targetTier,
        targetMax = targetTier,
        spec = {
            role = "container",
            tradeSkill = apoId,
            slotType = slotType,
            skillLevel = targetTier,
            bonuses = {},
            incomplete = false,
        },
    }
end

function ASP.CollectContainerBuyJobs()
    local jobs = {}
    if ASP.ShouldApoBuyContainer() ~= true then
        return jobs
    end
    local target = ASP.ResolveBuyContainerTarget()
    if type(target) ~= "table" then
        return jobs
    end
    local uid = tonumber(target.uid) or 0
    local spec = target.spec
    if type(spec) ~= "table" then
        local MS = StockPiler4.MaterialSpec
        local Inv = StockPiler4.Inventory
        local sample = uid > 0 and Inv and Inv.GetSample and Inv.GetSample(uid)
        if MS and MS.FromItemData and type(sample) == "table" then
            spec = MS.FromItemData(sample, nil)
        end
    end
    if type(spec) ~= "table" or tostring(spec.role or "") ~= "container" then
        return jobs
    end
    local want = Rates().ApoContainerBuyTarget()
    local have = ASP.CountApoContainers()
    local deficit = want - have
    if deficit < 1 then
        return jobs
    end
    jobs[#jobs + 1] = {
        uid = uid,
        uniqueID = uid,
        deficit = deficit,
        skillUp = true,
        growable = false,
        isGrowable = false,
        role = "container",
        spec = spec,
        specKey = "skill_up_container:" .. tostring(uid > 0 and uid or (tonumber(spec.skillLevel) or 1)),
        acquireKey = "skill_up_container:" .. tostring(uid > 0 and uid or (tonumber(spec.skillLevel) or 1)),
        skillReq = tonumber(target.skillReq) or tonumber(spec.skillLevel) or 0,
    }
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "buy-container uid=%d skillReq=%d want=%d have=%d deficit=%d nextTier=%d",
            uid, tonumber(target.skillReq) or 0, want, have, deficit,
            ASP.NextApoTier(Gates().GetApoSkill())
        ))
    end
    return jobs
end

--- Notify once per Apo stall reason; clear latch when condition lifts.
function ASP.MaybeNotifyApoStall(why)
    if ASP.ShouldApoBrew() ~= true then
        ASP._apoStallLatch = nil
    MirrorApoStateToSkillUp()
        return
    end
    why = tostring(why or "need_mats")
    if why == "" then
        why = "need_mats"
    end
    -- Do not mask mat/resin/Cult waits with vial AutoBuy prompts.
    if why ~= "wait_cult" and why ~= "need_resin" and why ~= "seed_buffer"
        and why ~= "unstable" and ASP.ShouldApoBuyContainer() == true
    then
        local VA = StockPiler4.VendorAdapter
        if not (VA and VA.IsStoreOpen and VA.IsStoreOpen() == true) then
            why = "need_container_vendor"
        else
            why = "no_vendor_container"
        end
    end
    if ASP._apoStallLatch == why then
        return
    end
    ASP._apoStallLatch = why
    MirrorApoStateToSkillUp()
    local msg
    if StockPiler4.T then
        local key = "skillup.apo.stall." .. why
        msg = StockPiler4.T(key)
    else
        msg = L"<icon02486> Skill up Apo stalled - need container, main, or resin."
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



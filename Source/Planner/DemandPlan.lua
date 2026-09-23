----------------------------------------------------------------

-- StockPiler4 Planner/DemandPlan - balanced watch/spec demand

----------------------------------------------------------------



StockPiler4 = StockPiler4 or {}

StockPiler4.DemandPlan = StockPiler4.DemandPlan or {}

local DemandPlan = StockPiler4.DemandPlan



local function PlannerRef()

    return StockPiler4.Planner

end



local function RecipeSpec()

    return StockPiler4.RecipeSpec

end



local function MaterialSpec()

    return StockPiler4.MaterialSpec

end



local function PerfBegin(name)

    local P = StockPiler4.Perf

    if P and P.Begin then

        P.Begin(name)

    end

end



local function PerfEnd(name)

    local P = StockPiler4.Perf

    if P and P.End then

        P.End(name)

    end

end



local function SpecKey(spec)

    local MS = MaterialSpec()

    if type(spec) ~= "table" then

        return nil

    end

    if MS and MS.Key then

        local bound = nil

        if spec.incomplete == true then

            bound = tonumber(spec.boundUid) or tonumber(spec.uid) or nil

        end

        local k = MS.Key(spec, bound)

        if type(k) == "string" and k ~= "" then

            return k

        end

    end

    if MS and MS.ProductKey then

        local k = MS.ProductKey(spec)

        if type(k) == "string" and k ~= "" then

            return k

        end

    end

    local uid = tonumber(spec.uid or spec.uniqueID) or 0

    if uid > 0 then

        return "uid:" .. tostring(uid)

    end

    return nil

end



local function CurrentSnapGen()

    local Inv = StockPiler4.Inventory

    if Inv and Inv.GetSnapGen then

        return tonumber(Inv.GetSnapGen()) or 0

    end

    return 0

end



local function HoldHaveCacheQuiet()

    local Sch = StockPiler4.Scheduler

    if not Sch then

        return false

    end

    if Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true then

        return true

    end

    if Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true then

        return true

    end

    return false

end



local function WarmSpecHaveCache(specs)

    local P = PlannerRef()

    if P and P.WarmSpecHaveCache then

        return P.WarmSpecHaveCache(specs)

    end

    return 0

end



local function CountItemsMatchingSpec(spec, opts)

    local P = PlannerRef()

    if P and P.CountItemsMatchingSpec then

        return P.CountItemsMatchingSpec(spec, opts)

    end

    return 0

end



local function RecipeYield(recipe)

    local RS = RecipeSpec()

    if RS and RS.RecipeOutputYield then

        local y = tonumber(RS.RecipeOutputYield(recipe)) or 1

        if y < 1 then

            y = 1

        end

        return y

    end

    return math.max(1, tonumber(recipe and recipe.recipeYield) or 1)

end



local function CraftsNeededForDeficit(deficit, recipe)

    local RS = RecipeSpec()

    if RS and RS.CraftsNeededForDeficit then

        return tonumber(RS.CraftsNeededForDeficit(deficit, recipe)) or 0

    end

    local yield = RecipeYield(recipe)

    deficit = tonumber(deficit) or 0

    if deficit <= 0 then

        return 0

    end

    return math.ceil(deficit / yield)

end



local function SpecIsGrowable(spec, role)

    if role == "container" then

        return false

    end

    local SM = StockPiler4.SeedMap

    if SM and SM.IsGrowableSpec and SM.IsGrowableSpec(spec) == true then

        return true

    end

    local MS = MaterialSpec()

    if MS and MS.IsGrowable and MS.IsGrowable(spec) == true then

        return true

    end

    if SM and SM.IsHarvestByproduct and SM.IsHarvestByproduct(spec) == true then

        return false

    end

    return false

end



local function SpecIsHarvestByproduct(spec)

    local SM = StockPiler4.SeedMap

    if SM and SM.IsHarvestByproduct then

        return SM.IsHarvestByproduct(spec) == true

    end

    return false

end



local function ByproductConvertRoleRank(role)

    role = tostring(role or "")

    if role == "main" then

        return 1

    end

    if role == "stabilizer" or role == "goldweed" then

        return 2

    end

    if role == "extender" then

        return 3

    end

    if role == "multiplier" or role == "stimulant" then

        return 4

    end

    return 99

end



local function InflateConvertGrowRow(row, byproductItemsShort)

    if type(row) ~= "table" or (tonumber(byproductItemsShort) or 0) <= 0 then

        return

    end

    if row.brewAbsolute == nil then

        row.brewAbsolute = tonumber(row.absolute) or 0

    end

    row.byproductConvertExtra = (tonumber(row.byproductConvertExtra) or 0)

        + byproductItemsShort

    row.absolute = (tonumber(row.absolute) or 0) + byproductItemsShort

    row.deficit = math.max(0, (tonumber(row.absolute) or 0) - (tonumber(row.have) or 0))

    local pc = math.max(1, tonumber(row.perCraft) or 1)

    row.craftsHave = math.floor((tonumber(row.have) or 0) / pc)

    row.craftsNeeded = math.ceil((tonumber(row.absolute) or 0) / pc)

    row.craftsShort = math.max(0, row.craftsNeeded - row.craftsHave)

end



local function EffectivePerCraft(slot, slots)

    local RS = RecipeSpec()

    if RS and RS.EffectiveSpecPerCraft then

        return math.max(1, tonumber(RS.EffectiveSpecPerCraft(slot, slots)) or 1)

    end

    return math.max(1, tonumber(slot and slot.perCraft) or 1)

end



local function ResolveSlotSpec(slot)

    if type(slot) ~= "table" then

        return nil

    end

    if type(slot.spec) == "table" then

        return slot.spec

    end

    local RS = RecipeSpec()

    if RS and RS.ResolveSlotSpec then

        return RS.ResolveSlotSpec(slot)

    end

    return nil

end



local function ResolveWatchRow(watchKey, watch)

    if type(watch) == "table" then

        return watch

    end

    local Watch = StockPiler4.Watch

    local watches = Watch and Watch.GetWatches and Watch.GetWatches() or nil

    if type(watches) ~= "table" then

        return nil

    end

    local key = tostring(watchKey or "")

    if key == "" then

        return nil

    end

    return watches[key]

end



local function WatchWantsAutoGrow(watchKey, watch)

    local RS = RecipeSpec()

    watch = ResolveWatchRow(watchKey, watch)

    if RS and RS.ShouldAutoGrowPotion then

        return RS.ShouldAutoGrowPotion(watchKey, watch) == true

    end

    if type(watch) ~= "table" or watch.enabled ~= true then

        return false

    end

    local Watch = StockPiler4.Watch

    if Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() ~= true then

        return false

    end

    return watch.autoGrow == true

end



local function ResolveWatchPotion(watchKey)

    local RS = RecipeSpec()

    if RS and RS.ResolveWatchPotion then

        return RS.ResolveWatchPotion(watchKey)

    end

    return nil

end



local function PotionHave(resolved, potion, outputUid)

    local RS = RecipeSpec()

    if RS and RS.PotionHaveCombined and type(potion) == "table" then

        return tonumber(RS.PotionHaveCombined(potion)) or 0

    end

    local uid = tonumber(outputUid)

        or (resolved and tonumber(resolved.outputUid))

        or (type(potion) == "table" and tonumber(potion.outputUid))

        or 0

    local Inv = StockPiler4.Inventory

    if uid > 0 and Inv and Inv.CountByUid then

        return tonumber(Inv.CountByUid(uid)) or 0

    end

    return 0

end



local function BuildBalancedSpecDemand(opts)

    opts = type(opts) == "table" and opts or {}

    local Planner = PlannerRef()

    local snapGen = CurrentSnapGen()

    local Watch = StockPiler4.Watch

    local watchGen = Watch and Watch.GetGen and Watch.GetGen() or 0

    local PS = StockPiler4.PlanSnapshot

    local plan = PS and PS.Get and PS.Get() or nil

    local planGen = type(plan) == "table" and tonumber(plan.planGen) or 0

    local cacheKey = tostring(snapGen) .. ":" .. tostring(watchGen) .. ":" .. tostring(planGen)

    if Planner and type(Planner._demandCache) == "table" and Planner._demandCacheKey == cacheKey then

        return Planner._demandCache

    end

    if Planner and HoldHaveCacheQuiet() and type(Planner._demandCache) == "table" then

        local prev = tostring(Planner._demandCacheKey or "")

        local suffix = ":" .. tostring(watchGen) .. ":" .. tostring(planGen)

        if string.len(prev) >= string.len(suffix)

            and string.sub(prev, -string.len(suffix)) == suffix

        then

            return Planner._demandCache

        end

    end

    PerfBegin("BuildBalancedSpecDemand")

    local demand = {}

    local RS = RecipeSpec()

    local watches = Watch and Watch.GetWatches and Watch.GetWatches() or {}

    if type(watches) ~= "table" or not RS then

        if Planner then

            Planner._demandCache = demand

            Planner._demandCacheKey = cacheKey

        end

        PerfEnd("BuildBalancedSpecDemand")

        return demand

    end

    local byUid = {}

    local uidOrder = {}

    for watchKey, watch in pairs(watches) do

        if WatchWantsAutoGrow(watchKey, watch) then

            local resolved = ResolveWatchPotion(watchKey)

            local potion = resolved and resolved.potion

            local recipe = RS.RecipeSpecForPotion and RS.RecipeSpecForPotion(watchKey)

            if type(potion) == "table" and type(recipe) == "table" then

                local uid = tonumber(resolved and resolved.outputUid) or tonumber(potion.outputUid) or 0

                local target = tonumber(watch.targetStock) or 0

                local have = PotionHave(resolved, potion, uid)

                local deficit = math.max(0, target - have)

                local stillNeeds = true

                if RS.WatchStillNeedsGrow then

                    stillNeeds = RS.WatchStillNeedsGrow(potion, recipe, target, watchKey) == true

                end

                if uid > 0 and deficit > 0 and target > 0 and stillNeeds then

                    local group = byUid[uid]

                    if group == nil then

                        group = {

                            uid = uid,

                            have = have,

                            maxTarget = target,

                            primaryKey = watchKey,

                            primaryRecipe = recipe,

                            potion = potion,

                            extras = 0,

                        }

                        byUid[uid] = group

                        uidOrder[#uidOrder + 1] = uid

                    else

                        if target > group.maxTarget then

                            group.maxTarget = target

                        end

                        group.extras = group.extras + 1

                    end

                end

            end

        end

    end

    for i = 1, #uidOrder do

        local group = byUid[uidOrder[i]]

        local recipe = group.primaryRecipe

        local target = group.maxTarget

        local have = group.have

        local deficit = math.max(0, target - have)

        local craftsNeeded = CraftsNeededForDeficit(deficit, recipe)

        local slots = recipe.slots or {}

        for j = 1, #slots do

            local slot = slots[j]

            local spec = ResolveSlotSpec(slot)

            if type(spec) == "table" then

                local specKey = SpecKey(spec)

                if specKey ~= nil then

                    local perCraft = EffectivePerCraft(slot, slots)

                    local absNeed = craftsNeeded * perCraft

                    local row = demand[specKey]

                    if row == nil then

                        row = {

                            spec = spec,

                            specKey = specKey,

                            role = slot.role,

                            perCraft = perCraft,

                            absolute = 0,

                            watchNames = {},

                            watchDetails = {},

                        }

                        demand[specKey] = row

                    end

                    row.absolute = row.absolute + absNeed

                    if perCraft > (row.perCraft or 0) then

                        row.perCraft = perCraft

                    end

                    local watchName = group.potion.name or towstring(tostring(group.primaryKey))

                    row.watchNames[#row.watchNames + 1] = watchName

                    row.watchDetails[#row.watchDetails + 1] = {

                        potionKey = group.primaryKey,

                        name = watchName,

                        have = have,

                        target = target,

                        deficit = deficit,

                    }

                end

            end

        end

    end

    WarmSpecHaveCache(demand)

    local SM = StockPiler4.SeedMap

    for _, row in pairs(demand) do

        row.have = CountItemsMatchingSpec(row.spec)

        row.deficit = math.max(0, (tonumber(row.absolute) or 0) - (tonumber(row.have) or 0))

        local pc = math.max(1, tonumber(row.perCraft) or 1)

        row.craftsHave = math.floor((tonumber(row.have) or 0) / pc)

        row.craftsNeeded = math.ceil((tonumber(row.absolute) or 0) / pc)

        row.craftsShort = math.max(0, row.craftsNeeded - row.craftsHave)

        row.brewAbsolute = row.absolute

        row.byproductConvertExtra = 0

        if type(row.spec) == "table" and SM then

            if SpecIsHarvestByproduct(row.spec) then

                row.isByproduct = true

                row.plantUid = 0

                row.seedUid = 0

            else

                row.isByproduct = false

                local plantUid = 0

                local seedUid = 0

                local role = tostring(row.role or row.spec.role or "")

                if role ~= "container" and SpecIsGrowable(row.spec, role) then

                    if SM.FindPlantUidForSpec then

                        plantUid = tonumber(SM.FindPlantUidForSpec(row.spec)) or 0

                    end

                    if SM.ResolveSeedForSpec then

                        local seed = SM.ResolveSeedForSpec(row.spec)

                        if type(seed) == "table" then

                            seedUid = tonumber(seed.uniqueID or seed.uid) or 0

                            if plantUid <= 0 then

                                plantUid = tonumber(seed.plantUid) or 0

                            end

                        end

                    end

                end

                row.plantUid = plantUid

                row.seedUid = seedUid

            end

        end

    end



    for watchKey, watch in pairs(watches) do

        if WatchWantsAutoGrow(watchKey, watch) then

            local recipe = RS.RecipeSpecForPotion and RS.RecipeSpecForPotion(watchKey)

            if type(recipe) == "table" then

                if RS.HydrateRecipeSlots then

                    RS.HydrateRecipeSlots(recipe)

                end

                local slots = recipe.slots or {}

                local resolved = ResolveWatchPotion(watchKey)

                local potion = resolved and resolved.potion

                local target = tonumber(watch.targetStock) or 0

                local havePot = PotionHave(resolved, potion, potion and potion.outputUid)

                local deficitPot = math.max(0, target - havePot)

                if deficitPot > 0 and target > 0 then

                    local craftsNeeded = CraftsNeededForDeficit(deficitPot, recipe)

                    local byproductItemsShort = 0

                    local preferredKey = nil

                    local preferredRank = 99

                    for j = 1, #slots do

                        local slot = slots[j]

                        local spec = ResolveSlotSpec(slot)

                        if type(spec) == "table" then

                            local perCraft = EffectivePerCraft(slot, slots)

                            local sk = SpecKey(spec)

                            local row = sk and demand[sk] or nil

                            local have = type(row) == "table" and (tonumber(row.have) or 0)

                                or CountItemsMatchingSpec(spec)

                            local need = craftsNeeded * perCraft

                            local slotDef = math.max(0, need - have)

                            if SpecIsHarvestByproduct(spec) then

                                if slotDef > byproductItemsShort then

                                    byproductItemsShort = slotDef

                                end

                            elseif SpecIsGrowable(spec, slot.role or spec.role) then

                                local rank = ByproductConvertRoleRank(slot.role or spec.role)

                                if rank < preferredRank and sk ~= nil then

                                    preferredRank = rank

                                    preferredKey = sk

                                end

                            end

                        end

                    end

                    if byproductItemsShort > 0 and preferredKey ~= nil then

                        InflateConvertGrowRow(demand[preferredKey], byproductItemsShort)

                    end

                end

            end

        end

    end



    local shortResinLevels = {}

    for _, row in pairs(demand) do

        if type(row) == "table" and row.isByproduct == true and (tonumber(row.deficit) or 0) > 0 then

            local lv = tonumber(row.spec and row.spec.skillLevel) or 0

            if lv > 0 then

                shortResinLevels[lv] = true

            end

        end

    end

    local hasResinFeedstock = false

    local Refine = StockPiler4.Refine

    for _, row in pairs(demand) do

        if type(row) == "table" and row.isByproduct ~= true and type(row.spec) == "table" then

            local lv = tonumber(row.spec.skillLevel) or 0

            if shortResinLevels[lv] == true and SpecIsGrowable(row.spec, row.role) then

                local brewAbs = tonumber(row.brewAbsolute) or 0

                local surplus = (tonumber(row.have) or 0) - brewAbs

                if surplus > 0 then

                    local refinable = 0

                    if Refine and Refine.CountRefinablePlants then

                        refinable = tonumber(Refine.CountRefinablePlants(row.plantUid, row.spec)) or 0

                    elseif (tonumber(row.plantUid) or 0) > 0 then

                        refinable = surplus

                    end

                    if refinable > 0 then

                        hasResinFeedstock = true

                        break

                    end

                end

            end

        end

    end

    demand._resinFeedstock = hasResinFeedstock



    if Planner then

        Planner._demandCache = demand

        Planner._demandCacheKey = cacheKey

    end

    PerfEnd("BuildBalancedSpecDemand")

    return demand

end



--- Demand lines from the latest plan snapshot (Planner owns assembly).

function DemandPlan.FromSnapshot(plan)

    plan = plan or (StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get and StockPiler4.PlanSnapshot.Get())

    if type(plan) ~= "table" then

        return nil

    end

    return plan.demand or plan.demandLines or plan.rows

end



function DemandPlan.BuildBalancedSpecDemand(opts)

    return BuildBalancedSpecDemand(opts)

end



DemandPlan.Build = DemandPlan.BuildBalancedSpecDemand



function DemandPlan.Rebuild(opts)

    local Planner = StockPiler4.Planner

    if Planner and Planner.Build then

        return Planner.Build(opts)

    end

    if Planner and Planner.GetOrBuild then

        return Planner.GetOrBuild(opts)

    end

    return nil

end



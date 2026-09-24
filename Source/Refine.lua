----------------------------------------------------------------
-- StockPiler4 Refine -- buffer flags + intents + IssueOne
-- Policy and executor live here. Callees above callers.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Refine = StockPiler4.Refine or {}
local Refine = StockPiler4.Refine

Refine.MAX_OUTSTANDING_PER_SEED = 6
Refine.MAX_PENDING_PER_PLANT = 6
Refine.SEED_BUFFER_FAIL_COOLDOWN_SEC = 45
Refine.OUTSTANDING_TTL_SEC = 30
Refine.EMPTY_INTENT_RETRY_SEC = 5

Refine._refineDirty = false
Refine._refineDirtyReason = nil
Refine._refineWaitTicks = 0
Refine._intentCacheKey = nil
Refine._intentCache = nil
Refine._emptyIntentBustAt = 0
Refine._bufferFlags = nil
Refine._bufferFlagsKey = nil
Refine._bufferFlagsStructKey = nil
Refine._bufferFlagsSticky = nil
Refine._bufferFlagsStickyStruct = nil
Refine._pendingByPlant = Refine._pendingByPlant or {}
Refine._pendingSeedByPlant = Refine._pendingSeedByPlant or {}
Refine._issuedSeedThisTick = nil
Refine._seedBufferCooldownUntil = Refine._seedBufferCooldownUntil or {}
Refine._bagIndex = nil
Refine._bagIndexGen = -1
Refine._reconcileSnapGen = -1
Refine._onUpdateFrame = -1
Refine._liveSeedBaseline = Refine._liveSeedBaseline or {}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function NowSec()
    return StockPiler4.Util.NowSec()
end

local function LogRefine(msg)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("refine", msg)
    end
end

local function CraftingBackpackType()
    if EA_Window_Backpack and EA_Window_Backpack.TYPE_CRAFTING then
        return EA_Window_Backpack.TYPE_CRAFTING
    end
    return 4
end

local function SeedBufferCooldownCacheToken()
    local parts = {}
    local now = NowSec()
    for seedUid, untilT in pairs(Refine._seedBufferCooldownUntil) do
        untilT = tonumber(untilT) or 0
        if untilT > now then
            parts[#parts + 1] = tostring(seedUid) .. "=" .. tostring(math.floor(untilT))
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function IsSeedBufferOnCooldown(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return false
    end
    local untilT = tonumber(Refine._seedBufferCooldownUntil[seedUid]) or 0
    if untilT <= 0 then
        return false
    end
    if NowSec() >= untilT then
        Refine._seedBufferCooldownUntil[seedUid] = nil
        return false
    end
    return true
end

local function ArmSeedBufferFailCooldown(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return
    end
    local untilT = NowSec() + (tonumber(Refine.SEED_BUFFER_FAIL_COOLDOWN_SEC) or 45)
    local cur = tonumber(Refine._seedBufferCooldownUntil[seedUid]) or 0
    if untilT > cur then
        Refine._seedBufferCooldownUntil[seedUid] = untilT
    end
    Refine.InvalidateIntentCache()
end

local function BufferFlagsStructuralKey()
    local gardenGen = 0
    local Garden = StockPiler4.Garden
    if Garden then
        gardenGen = tonumber(Garden.GetPlanGen and Garden.GetPlanGen() or Garden.GetGen and Garden.GetGen()) or 0
    end
    local watchGen = StockPiler4.Watch and StockPiler4.Watch.GetGen and StockPiler4.Watch.GetGen() or 0
    local buffer = StockPiler4.Watch and StockPiler4.Watch.GetSeedBufferMin and StockPiler4.Watch.GetSeedBufferMin() or 5
    local outstanding = 0
    local RP = StockPiler4.RefinePipeline
    if RP and RP.GetOutstandingSum then
        outstanding = tonumber(RP.GetOutstandingSum()) or 0
    end
    return tostring(gardenGen) .. ":" .. tostring(watchGen)
        .. ":" .. tostring(buffer) .. ":" .. tostring(outstanding)
end

local function BufferFlagsCacheKey()
    local snapGen = 0
    if StockPiler4.Inventory and StockPiler4.Inventory.GetSnapGen then
        snapGen = tonumber(StockPiler4.Inventory.GetSnapGen()) or 0
    end
    return tostring(snapGen) .. ":" .. BufferFlagsStructuralKey()
end

local function IntentCacheKey()
    local Watch = StockPiler4.Watch
    local RP = StockPiler4.RefinePipeline
    local Garden = StockPiler4.Garden
    local gardenGen = 0
    if Garden then
        gardenGen = tonumber(Garden.GetPlanGen and Garden.GetPlanGen() or Garden.GetGen and Garden.GetGen()) or 0
    end
    -- NO snapGen. Include active cooldowns + buffer enabled.
    local bufferOn = Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true
    return table.concat({
        tostring(Watch and Watch.GetGen and Watch.GetGen() or 0),
        tostring(RP and RP.GetGen and RP.GetGen() or 0),
        tostring(gardenGen),
        SeedBufferCooldownCacheToken(),
        bufferOn and "1" or "0",
    }, ":")
end

local function LiveSeedCount(seedUid)
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

--- Pending plant + established garden rows (seeds in ground are refundable until harvest).
local function CountInGround(seedUid)
    local Grow = StockPiler4.Grow
    if Grow and Grow.CountSeedPlotCredit then
        return tonumber(Grow.CountSeedPlotCredit(seedUid)) or 0
    end
    if Grow and Grow.CountInGroundSeeds then
        return tonumber(Grow.CountInGroundSeeds(seedUid)) or 0
    end
    return 0
end

--- Buffer-settle refine: hold only when this seed is still in plots AND there is
--- nowhere left to plant. Empty plots need seeds now; GetSeedBudget headroom
--- already counts in-ground credit, so refine-to-fill must not wait on harvest.
--- (0.3.187 deferred whenever ground>0, which starved empty plots until the
--- first replant harvested — second cycle then refined and filled.)
local function SeedBufferSettleDeferred(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return true
    end
    if CountInGround(seedUid) <= 0 then
        return false
    end
    local Grow = StockPiler4.Grow
    if Grow and Grow.HasEmptyPlot and Grow.HasEmptyPlot() == true then
        return false
    end
    if Grow and Grow.CountEmptyPlots and (tonumber(Grow.CountEmptyPlots()) or 0) > 0 then
        return false
    end
    return true
end

local function OpaqueCredit(seedUid, bag)
    local SM = StockPiler4.SeedMap
    if SM and SM.EffectiveSeedCredit then
        return tonumber(SM.EffectiveSeedCredit(seedUid, bag)) or bag
    end
    return bag
end

local function ItemLooksRefinable(item)
    if type(item) ~= "table" then
        return false
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.ItemLooksLikeRefinablePlant then
        return SM.ItemLooksLikeRefinablePlant(item) == true
    end
    return item.isRefinable == true
end

local function EnsureBagIndex()
    local Inv = StockPiler4.Inventory
    local gen = Inv and Inv.GetSnapGen and Inv.GetSnapGen() or 0
    if Refine._bagIndexGen == gen and type(Refine._bagIndex) == "table" then
        return Refine._bagIndex
    end
    local index = { entries = {}, byPlantUid = {} }
    if Inv and Inv.ForEachItem then
        -- Inventory.ForEachItem passes (item [, bagKey, slot]) - not (bagKey, slot, item).
        Inv.ForEachItem(function(item, bagKey, slot)
            if ItemLooksRefinable(item) then
                local plantUid = tonumber(item.uniqueID) or 0
                local stack = tonumber(item.stackCount) or tonumber(item.StackCount) or 1
                slot = tonumber(slot) or tonumber(item.slotNumber) or tonumber(item.slot) or 0
                bagKey = tostring(bagKey or item.bagKey or "craft")
                if stack < 1 then
                    stack = 1
                end
                index.entries[#index.entries + 1] = {
                    bagKey = bagKey,
                    slot = slot,
                    item = item,
                    plantUid = plantUid,
                    stack = stack,
                }
                if plantUid > 0 then
                    local row = index.byPlantUid[plantUid]
                    if type(row) ~= "table" then
                        row = { count = 0, bestSlot = slot, bestItem = item, bestBagKey = bagKey, bestStack = stack }
                        index.byPlantUid[plantUid] = row
                    end
                    row.count = (tonumber(row.count) or 0) + stack
                    if stack <= (tonumber(row.bestStack) or 9999) then
                        row.bestSlot = slot
                        row.bestItem = item
                        row.bestBagKey = bagKey
                        row.bestStack = stack
                    end
                end
            end
        end)
    end
    Refine._bagIndex = index
    Refine._bagIndexGen = gen
    return index
end

local function CountRefinableForSpec(plantUid, spec)
    plantUid = tonumber(plantUid) or 0
    local index = EnsureBagIndex()
    if plantUid > 0 then
        local row = index.byPlantUid[plantUid]
        return type(row) == "table" and (tonumber(row.count) or 0) or 0
    end
    if type(spec) ~= "table" then
        return 0
    end
    local MS = StockPiler4.MaterialSpec
    local SM = StockPiler4.SeedMap
    local n = 0
    for i = 1, #index.entries do
        local e = index.entries[i]
        local item = e.item
        local match = false
        if MS and MS.FromItemDataCached and MS.Matches then
            local itemSpec = MS.FromItemDataCached(item)
            match = MS.Matches(itemSpec, spec) == true
        elseif SM and SM.PlantMatchesSpec then
            match = SM.PlantMatchesSpec(item, spec) == true
        end
        if match then
            n = n + (tonumber(e.stack) or 0)
        end
    end
    return n
end

local function BagTypeForKey(bagKey)
    local bagType = CraftingBackpackType()
    if bagKey == "main" and EA_Window_Backpack and EA_Window_Backpack.TYPE_INVENTORY then
        bagType = EA_Window_Backpack.TYPE_INVENTORY
    end
    return bagType
end

local function FindPlantSlot(plantUid, spec)
    plantUid = tonumber(plantUid) or 0
    local index = EnsureBagIndex()
    if plantUid > 0 then
        local row = index.byPlantUid[plantUid]
        if type(row) == "table" and (tonumber(row.bestSlot) or 0) > 0 then
            return tonumber(row.bestSlot), row.bestItem, BagTypeForKey(row.bestBagKey)
        end
    end
    local MS = StockPiler4.MaterialSpec
    for i = 1, #index.entries do
        local e = index.entries[i]
        local match = false
        if MS and MS.FromItemDataCached and MS.Matches and type(spec) == "table" then
            match = MS.Matches(MS.FromItemDataCached(e.item), spec) == true
        elseif plantUid > 0 and (tonumber(e.plantUid) or 0) == plantUid then
            match = true
        end
        if match then
            return tonumber(e.slot), e.item, BagTypeForKey(e.bagKey)
        end
    end
    return 0, nil, CraftingBackpackType()
end

--- Highest-stack refinable slot matching plantUid/spec (resin convert prefers richest stack).
local function FindPlantSlotHighest(plantUid, spec)
    plantUid = tonumber(plantUid) or 0
    local index = EnsureBagIndex()
    local bestSlot, bestItem, bestBagKey, bestStack = 0, nil, nil, -1
    local MS = StockPiler4.MaterialSpec
    for i = 1, #index.entries do
        local e = index.entries[i]
        local match = false
        if plantUid > 0 and (tonumber(e.plantUid) or 0) == plantUid then
            match = true
        elseif MS and MS.FromItemDataCached and MS.Matches and type(spec) == "table" then
            match = MS.Matches(MS.FromItemDataCached(e.item), spec) == true
        end
        if match and (tonumber(e.stack) or 0) > bestStack then
            bestStack = tonumber(e.stack) or 0
            bestSlot = tonumber(e.slot) or 0
            bestItem = e.item
            bestBagKey = e.bagKey
        end
    end
    if bestSlot > 0 then
        return bestSlot, bestItem, BagTypeForKey(bestBagKey)
    end
    return 0, nil, CraftingBackpackType()
end

local function DemandRowSurplus(row)
    if type(row) ~= "table" then
        return 0
    end
    local have = tonumber(row.have) or 0
    local brew = tonumber(row.brewAbsolute)
    if brew == nil then
        brew = tonumber(row.absolute) or 0
    end
    -- Do not refine plant stock below an enabled plant-watch floor.
    local floor = 0
    local Watch = StockPiler4.Watch
    local plantUid = tonumber(row.plantUid) or 0
    if plantUid > 0 and Watch and Watch.PlantKeyFromUid and Watch.GetPlantWatch then
        local plantKey = Watch.PlantKeyFromUid(plantUid)
        local pw = Watch.GetPlantWatch(plantKey)
        if type(pw) == "table" and pw.enabled == true then
            floor = tonumber(pw.targetStock) or 0
        end
    end
    local reserved = math.max(brew, floor)
    local surplus = have - reserved
    if surplus < 0 then
        return 0
    end
    return surplus
end

local function RowSharesPotionKeys(row, potionKeys)
    if type(row) ~= "table" or type(potionKeys) ~= "table" then
        return false
    end
    if type(row.watchDetails) == "table" then
        for i = 1, #row.watchDetails do
            local detail = row.watchDetails[i]
            if type(detail) == "table" and detail.potionKey ~= nil and potionKeys[detail.potionKey] == true then
                return true
            end
        end
    end
    if type(row.potionKeys) == "table" then
        for k, v in pairs(row.potionKeys) do
            if v == true and potionKeys[k] == true then
                return true
            end
        end
    end
    return false
end

local function CandidateFromDemandRow(row, SM, tier, resinSkillLevel)
    if type(row) ~= "table" or type(row.spec) ~= "table" then
        return nil
    end
    if row.isByproduct == true then
        return nil
    end
    if not (SM and SM.IsGrowableSpec and SM.IsGrowableSpec(row.spec) == true) then
        return nil
    end
    resinSkillLevel = tonumber(resinSkillLevel)
    if resinSkillLevel ~= nil then
        local plantLv = tonumber(row.spec.skillLevel) or 0
        if plantLv ~= resinSkillLevel then
            return nil
        end
    end
    local surplus = DemandRowSurplus(row)
    if surplus <= 0 then
        return nil
    end
    local seedUid = tonumber(row.seedUid) or 0
    local plantUid = tonumber(row.plantUid) or 0
    if seedUid <= 0 and SM.ResolveSeedForSpec then
        local seed = SM.ResolveSeedForSpec(row.spec)
        if type(seed) == "table" then
            seedUid = tonumber(seed.uniqueID or seed.uid) or 0
            if plantUid <= 0 then
                plantUid = tonumber(seed.plantUid) or 0
            end
        end
    end
    if plantUid <= 0 and SM.FindPlantUidForSpec then
        plantUid = tonumber(SM.FindPlantUidForSpec(row.spec)) or 0
    end
    local refinable = CountRefinableForSpec(plantUid, row.spec)
    if refinable <= 0 then
        return nil
    end
    local slot, item, bagType = FindPlantSlotHighest(plantUid, row.spec)
    if slot <= 0 or type(item) ~= "table" then
        return nil
    end
    if plantUid <= 0 then
        plantUid = tonumber(item.uniqueID) or 0
    end
    if resinSkillLevel ~= nil then
        local itemLv = tonumber(item.craftingSkillRequirement)
            or tonumber(item.skillLevel)
            or tonumber(row.spec.skillLevel)
            or 0
        if itemLv ~= resinSkillLevel then
            return nil
        end
    end
    return {
        tier = tier,
        spec = row.spec,
        specKey = row.specKey,
        seedUid = seedUid,
        plantUid = plantUid,
        surplus = surplus,
        refinable = refinable,
        slot = slot,
        item = item,
        bagType = bagType,
        score = refinable,
    }
end

local function LineBufferShort(line)
    if type(line) ~= "table" then
        return false
    end
    local seedUid = tonumber(line.seedUid) or 0
    -- Plant-only lines (seed not resolved yet) cannot measure seed credit - do not
    -- treat as buffer-short or brew stays blocked forever.
    if seedUid <= 0 then
        return false
    end
    local budget = Refine.GetSeedBudget(seedUid)
    local buffer = StockPiler4.Watch and StockPiler4.Watch.GetSeedBufferMin and StockPiler4.Watch.GetSeedBufferMin() or 5
    return (tonumber(budget.credit) or 0) < buffer
end

local function LineConvertiblePending(line)
    if type(line) ~= "table" then
        return false
    end
    local seedUid = tonumber(line.seedUid) or 0
    if IsSeedBufferOnCooldown(seedUid) then
        return false
    end
    -- Do not treat as pending settle while this seed is still in plots and the
    -- garden is full (SeedBufferSettleDeferred). Empty plots still want refine.
    if SeedBufferSettleDeferred(seedUid) then
        return false
    end
    -- Pending buffer refine = plants waiting to fill a short buffer.
    -- Leftover plants after the buffer is met must not hold auto-brew.
    if not LineBufferShort(line) then
        return false
    end
    local refinable = CountRefinableForSpec(line.plantUid, line.spec)
    return refinable > 0
end

local function EnsureBufferFlagsCached()
    local RP = StockPiler4.RefinePipeline
    local hasOut = RP and RP.HasOutstanding and RP.HasOutstanding() == true
    local fullGarden = not (StockPiler4.Grow and StockPiler4.Grow.HasEmptyPlot and StockPiler4.Grow.HasEmptyPlot())
    if hasOut and fullGarden and type(Refine._bufferFlags) == "table" then
        local structKey = BufferFlagsStructuralKey()
        if Refine._bufferFlagsStructKey == structKey then
            return Refine._bufferFlags
        end
    end
    -- Plant quiet / harvest storm: reuse structural or sticky flags (avoid snapGen
    -- rebuild every Inv.ApplySlots / orch tick — libperf BufferFlags trails).
    local Sch = StockPiler4.Scheduler
    local quiet = Sch and (
        (Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true)
        or (Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true)
    )
    if quiet then
        if type(Refine._bufferFlags) == "table" then
            local structKey = BufferFlagsStructuralKey()
            if Refine._bufferFlagsStructKey == structKey
                or Refine._bufferFlagsStructKey ~= nil
            then
                return Refine._bufferFlags
            end
        end
        if type(Refine._bufferFlagsSticky) == "table" then
            return Refine._bufferFlagsSticky
        end
    end
    local key = BufferFlagsCacheKey()
    if Refine._bufferFlagsKey == key and type(Refine._bufferFlags) == "table" then
        return Refine._bufferFlags
    end
    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("Refine.BufferFlags")
    end
    local Planner = StockPiler4.Planner
    local lines = (Planner and Planner.CollectAutoGrowSeedLines and Planner.CollectAutoGrowSeedLines()) or {}
    local pending, short = false, false
    for i = 1, #lines do
        if LineConvertiblePending(lines[i]) then
            pending = true
        end
        if LineBufferShort(lines[i]) then
            short = true
        end
        if pending and short then
            break
        end
    end
    Refine._bufferFlags = { pending = pending, short = short }
    Refine._bufferFlagsKey = key
    Refine._bufferFlagsStructKey = BufferFlagsStructuralKey()
    Refine._bufferFlagsSticky = Refine._bufferFlags
    Refine._bufferFlagsStickyStruct = Refine._bufferFlagsStructKey
    if Perf and Perf.End then
        Perf.End("Refine.BufferFlags")
    end
    return Refine._bufferFlags
end

local function ReasonPriority(reason)
    if reason == "plant-need" then
        return 0
    end
    if reason == "resin-need" then
        return 1
    end
    return 2
end

local function AppendIntent(intents, line, reason, uses, budget, extra)
    uses = tonumber(uses) or 0
    if uses < 1 then
        return
    end
    local seedUid = tonumber(line.seedUid) or 0
    local plantUid = tonumber(line.plantUid) or 0
    local slot, item, bagType = FindPlantSlot(plantUid, line.spec)
    if slot <= 0 or type(item) ~= "table" then
        return
    end
    local intent = {
        reason = reason,
        spec = line.spec,
        seedUid = seedUid,
        plantUid = plantUid,
        uses = uses,
        headroom = type(budget) == "table" and (tonumber(budget.headroom) or 0) or 0,
        slot = slot,
        item = item,
        bagType = bagType,
        emergencyPlant = false,
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            intent[k] = v
        end
    end
    intents[#intents + 1] = intent
end

local function ClearOrphanPending()
    local RP = StockPiler4.RefinePipeline
    for plantUid, pending in pairs(Refine._pendingByPlant) do
        pending = tonumber(pending) or 0
        if pending > 0 then
            local seedUid = tonumber(Refine._pendingSeedByPlant[plantUid]) or 0
            local outstanding = RP and RP.GetOutstanding and RP.GetOutstanding(seedUid) or 0
            if outstanding <= 0 then
                Refine._pendingByPlant[plantUid] = nil
                Refine._pendingSeedByPlant[plantUid] = nil
            end
        end
    end
end

----------------------------------------------------------------
-- Public: buffer / cache / gates
----------------------------------------------------------------

function Refine.IsEnabled()
    return StockPiler4.Grow and StockPiler4.Grow.IsEnabled and StockPiler4.Grow.IsEnabled() == true
end

function Refine.InvalidateIntentCache()
    Refine._intentCacheKey = nil
    Refine._intentCache = nil
end

function Refine.InvalidateBufferFlags()
    if type(Refine._bufferFlags) == "table" then
        Refine._bufferFlagsSticky = Refine._bufferFlags
        Refine._bufferFlagsStickyStruct = Refine._bufferFlagsStructKey
    end
    Refine._bufferFlagsKey = nil
    Refine._bufferFlags = nil
    Refine._bufferFlagsStructKey = nil
end

--- Last cached pending flag without rebuilding (snap wake path).
function Refine.PeekCachedBufferPending()
    local flags = Refine._bufferFlags
    if type(flags) ~= "table" then
        return false
    end
    return flags.pending == true
end

--- True when BufferFlags cache is warm (orch can peek without rebuild).
function Refine.HasBufferFlagsCache()
    return type(Refine._bufferFlags) == "table"
end

--- O(1) urgent snap invalidate - do not rebuild BufferFlags / HasAnyBufferShort here.
function Refine.OnUrgentInventorySnap()
    Refine.InvalidateIntentCache()
    Refine._refineWaitTicks = 0
    Refine._bagIndexGen = -1
end

function Refine.PeekCachedIntents()
    local key = IntentCacheKey()
    if Refine._intentCacheKey == key and type(Refine._intentCache) == "table" then
        return Refine._intentCache
    end
    return nil
end

function Refine.MarkRefineDue(reason)
    Refine._refineDirty = true
    reason = tostring(reason or "")
    if reason == "harvest" then
        Refine._refineDirtyReason = "harvest"
    elseif Refine._refineDirtyReason ~= "harvest" then
        Refine._refineDirtyReason = (reason ~= "" and reason) or "generic"
    end
end

function Refine.IsDirty()
    return Refine._refineDirty == true
end

function Refine.ClearDirty()
    Refine._refineDirty = false
    Refine._refineDirtyReason = nil
end

function Refine.DirtyReason()
    return Refine._refineDirtyReason
end

function Refine.ClearPostHarvestState()
    Refine.ClearDirty()
end

function Refine.RefineCheckDue()
    local wait = tonumber(Refine._refineWaitTicks) or 0
    if Refine._refineDirty == true then
        if Refine._refineDirtyReason == "harvest" then
            return true
        end
        return wait <= 0
    end
    return wait <= 0
end

function Refine.DecayRefineWaitTicks()
    local wait = tonumber(Refine._refineWaitTicks) or 0
    if wait > 0 then
        Refine._refineWaitTicks = wait - 1
    end
end

function Refine.HasPendingBufferRefine()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true) then
        return false
    end
    local Planner = StockPiler4.Planner
    if not (Planner and Planner.CollectAutoGrowSeedLines) then
        return false
    end
    return EnsureBufferFlagsCached().pending == true
end

function Refine.HasAnyBufferShort()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true) then
        return false
    end
    local Planner = StockPiler4.Planner
    if not (Planner and Planner.CollectAutoGrowSeedLines) then
        return false
    end
    return EnsureBufferFlagsCached().short == true
end

function Refine.IsSeedBufferSatisfied()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true) then
        return true
    end
    if Refine.HasAnyBufferShort() == true then
        return false
    end
    if Refine.HasPendingBufferRefine() == true then
        return false
    end
    return true
end

function Refine.GetSeedBudget(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return {
            live = 0,
            ground = 0,
            outstanding = 0,
            credit = 0,
            headroom = 0,
            bufferMin = 0,
            unsettled = true,
        }
    end
    local live = OpaqueCredit(seedUid, LiveSeedCount(seedUid))
    local ground = CountInGround(seedUid)
    local outstanding = 0
    local RP = StockPiler4.RefinePipeline
    if RP and RP.GetOutstanding then
        outstanding = tonumber(RP.GetOutstanding(seedUid)) or 0
    end
    local credit = live + ground + outstanding
    local buffer = 0
    local Watch = StockPiler4.Watch
    if Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true then
        buffer = Watch.GetSeedBufferMin and tonumber(Watch.GetSeedBufferMin()) or 5
    end
    local headroom = math.max(0, buffer - credit)
    return {
        live = live,
        ground = ground,
        outstanding = outstanding,
        credit = credit,
        headroom = headroom,
        bufferMin = buffer,
        -- True while plots still hold this seed (refundable / outcome unknown).
        unsettled = ground > 0,
    }
end

function Refine.SeedBufferSettleDeferred(seedUid)
    return SeedBufferSettleDeferred(seedUid)
end

function Refine.GetSeedBudgetForSpec(spec, seedUid)
    return Refine.GetSeedBudget(seedUid)
end

function Refine.CountRefinablePlants(plantUid, spec)
    return CountRefinableForSpec(plantUid, spec)
end

function Refine.TrackLiveSeed(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return
    end
    Refine._liveSeedBaseline[seedUid] = LiveSeedCount(seedUid)
end

local function ResolveDemand(opts)
    opts = type(opts) == "table" and opts or {}
    if type(opts.demand) == "table" then
        return opts.demand
    end
    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get()
    if type(plan) == "table" and type(plan.demand) == "table" then
        return plan.demand
    end
    local DP = StockPiler4.DemandPlan
    if DP and DP.Build then
        return DP.Build()
    end
    return nil
end

--- Pick same-tier surplus plant to convert into resin (1:1 plant->seed+resin).
--- Prefers convert-inflated / same-recipe rows, then any same-skill surplus.
function Refine.PickPlantForResinConvert(resinSpec, resinDeficit, preferredPotionKeys, demand)
    if type(resinSpec) ~= "table" then
        return nil
    end
    resinDeficit = tonumber(resinDeficit) or 0
    if resinDeficit <= 0 then
        return nil
    end
    local resinSkillLevel = tonumber(resinSpec.skillLevel) or 0
    if resinSkillLevel <= 0 then
        return nil
    end
    local SM = StockPiler4.SeedMap
    if not SM then
        return nil
    end
    if type(demand) ~= "table" then
        demand = ResolveDemand(nil)
    end
    if type(demand) ~= "table" then
        return nil
    end
    preferredPotionKeys = type(preferredPotionKeys) == "table" and preferredPotionKeys or {}

    local best = nil
    local function consider(cand)
        if type(cand) ~= "table" then
            return
        end
        if best == nil
            or cand.tier < best.tier
            or (cand.tier == best.tier and cand.score > best.score)
            or (cand.tier == best.tier and cand.score == best.score
                and (tonumber(cand.plantUid) or 0) < (tonumber(best.plantUid) or 0))
        then
            best = cand
        end
    end

    for _, row in pairs(demand) do
        if type(row) == "table" and type(row.spec) == "table" then
            local preferred = RowSharesPotionKeys(row, preferredPotionKeys)
                or (tonumber(row.byproductConvertExtra) or 0) > 0
            local tier = preferred and 1 or 2
            consider(CandidateFromDemandRow(row, SM, tier, resinSkillLevel))
        end
    end

    if best ~= nil and best.seedUid <= 0 then
        if best.plantUid > 0 and SM.ResolveSeedForPlantUid then
            local resolved = SM.ResolveSeedForPlantUid(best.plantUid, best.spec)
            if type(resolved) == "table" then
                best.seedUid = tonumber(resolved.uniqueID or resolved.uid) or 0
            end
        end
        if best.seedUid <= 0 and SM.ResolveSeedForSpec then
            local resolved = SM.ResolveSeedForSpec(best.spec)
            if type(resolved) == "table" then
                best.seedUid = tonumber(resolved.uniqueID or resolved.uid) or 0
            end
        end
    end
    return best
end

function Refine.HasActiveResinNeed()
    local SM = StockPiler4.SeedMap
    if not (SM and SM.IsHarvestByproduct) then
        return false
    end
    local demand = ResolveDemand(nil)
    if type(demand) ~= "table" then
        return false
    end
    for _, row in pairs(demand) do
        if type(row) == "table" and type(row.spec) == "table"
            and (row.isByproduct == true or SM.IsHarvestByproduct(row.spec) == true)
            and (tonumber(row.deficit) or 0) > 0
        then
            if demand._resinFeedstock == true then
                return true
            end
            local pick = Refine.PickPlantForResinConvert(row.spec, tonumber(row.deficit) or 0, nil, demand)
            if type(pick) == "table" then
                return true
            end
        end
    end
    return false
end

--- Plant-first: block refine if empty plot + plantable unless buffer-pending or fillBlocked.
--- No refine during brew session.
function Refine.ShouldAllowRefineNow()
    if Refine.IsEnabled() ~= true then
        return false, "disabled"
    end
    local Orch = StockPiler4.Orchestrator
    if Orch and Orch.IsBrewSessionActive and Orch.IsBrewSessionActive() then
        return false, "brew-session"
    end
    local Grow = StockPiler4.Grow
    local bufferPending = Grow and Grow.HasPendingBufferRefine and Grow.HasPendingBufferRefine() == true
    local empty = Grow and Grow.HasEmptyPlot and Grow.HasEmptyPlot() == true
    if empty and Grow then
        local plantable = false
        local plantReason, peekReason = nil, nil
        if Grow.PeekSeedsForNextPlant then
            local ok, jobOrReason = Grow.PeekSeedsForNextPlant()
            if ok == true then
                plantable = true
                if type(jobOrReason) == "table" then
                    plantReason = tostring(jobOrReason.plantReason or "")
                end
            else
                peekReason = tostring(jobOrReason or "")
            end
        end
        if not plantable and (peekReason == "dirty" or peekReason == "unprobed") then
            -- Post-harvest / upgrade refine-first often leaves the plant queue dirty
            -- on purpose (skip demand probe). Do not block refine waiting for a plant
            -- probe that orch will not run this tick.
            local allowDirty = Refine._refineDirty == true
                or tostring(Refine._refineDirtyReason or "") == "harvest"
            if not allowDirty then
                local US = StockPiler4.UpgradeSeed
                if US and US.IsEnabled and US.IsEnabled() == true
                    and US.NeedsRefineFirst and US.NeedsRefineFirst() == true
                then
                    allowDirty = true
                end
            end
            if not allowDirty
                and not (Grow.IsFillBlocked and Grow.IsFillBlocked() == true)
            then
                return false, "plant-probe-pending"
            end
        end
        if plantable then
            local CSP = StockPiler4.CultSkillPlan
            -- Cult SkillUp: refine higher plant or buffer-fill plants before replanting.
            if CSP and CSP.PreferRefineOverPlant
                and CSP.PreferRefineOverPlant() == true
            then
                if CSP.HasUpgradePlant and CSP.HasUpgradePlant() == true then
                    return true, "skill-up-upgrade"
                end
                return true, "skill-up-refine"
            end

            if bufferPending then
                if plantReason == "potion_stock" or plantReason == "seed_buffer" then
                    return false, "plant-first"
                end
            else
                return false, "plant-first"
            end
        end
    end
    if bufferPending then
        return true, "seed-buffer"
    end
    if Refine._refineDirtyReason == "harvest" or Refine._refineDirty == true then
        return true, "post-harvest"
    end
    if empty then
        return true, "pre-plant"
    end
    if Refine.HasActiveResinNeed() == true then
        return true, "resin-need"
    end
    return false, "idle-grow"
end

----------------------------------------------------------------
-- CollectIntents / IssueOne
----------------------------------------------------------------

function Refine.CollectIntents(opts)
    opts = type(opts) == "table" and opts or {}
    if Refine.IsEnabled() ~= true then
        return {}
    end
    if Refine.ShouldAllowRefineNow() ~= true then
        return {}
    end
    local cacheKey = IntentCacheKey()
    if Refine._intentCacheKey == cacheKey and type(Refine._intentCache) == "table" then
        -- Empty-cache bust when buffer/SkillUp may have gained plants since last miss.
        -- Rate-limit: unbounded rebuilds here caused ~300-450ms spikes every AutoGrow
        -- tick while plots grew with a short seed buffer + leftover refinable plants.
        if #Refine._intentCache == 0 then
            local Gates = StockPiler4.SkillUpGates
            local CSP = StockPiler4.CultSkillPlan
            local skillUpPending = Gates and Gates.ShouldCultPlant
                and Gates.ShouldCultPlant() == true
                and CSP and CSP.HasRefinablePlants and CSP.HasRefinablePlants() == true

            local wantBust = Refine.HasPendingBufferRefine() == true
                or skillUpPending == true
                or Refine._refineDirtyReason == "harvest"
            if wantBust == true then
                local now = NowSec()
                local last = tonumber(Refine._emptyIntentBustAt) or 0
                local gap = tonumber(Refine.EMPTY_INTENT_RETRY_SEC) or 5
                if (now - last) >= gap then
                    Refine._emptyIntentBustAt = now
                    Refine.InvalidateIntentCache()
                else
                    return Refine._intentCache
                end
            else
                return Refine._intentCache
            end
        else
            return Refine._intentCache
        end
    end

    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("CollectIntents")
    end
    local intents = {}
    local RS = StockPiler4.RecipeSpec
    local SM = StockPiler4.SeedMap
    local Watch = StockPiler4.Watch
    local bufferOn = Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true
    local seenBuffer = {}

    -- 1) Seed-buffer (bootstrap when brew deficit 0 but buffer short)
    local Planner = StockPiler4.Planner
    if bufferOn and Planner and Planner.CollectAutoGrowSeedLines then
        local lines = Planner.CollectAutoGrowSeedLines() or {}
        for i = 1, #lines do
            local line = lines[i]
            local seedUid = tonumber(line.seedUid) or 0
            local key = tostring(line.specKey or seedUid)
            if seenBuffer[key] ~= true and seedUid > 0 and not IsSeedBufferOnCooldown(seedUid)
                and not SeedBufferSettleDeferred(seedUid)
            then
                seenBuffer[key] = true
                local budget = Refine.GetSeedBudget(seedUid)
                local refinable = CountRefinableForSpec(line.plantUid, line.spec)
                local brewNeed = tonumber(line.brewDeficit or line.deficit) or 0
                local convertible = 0
                if refinable > 0 and (tonumber(budget.headroom) or 0) > 0 then
                    if brewNeed <= 0 then
                        -- Bootstrap: buffer short with no brew plant need.
                        convertible = math.min(refinable, tonumber(budget.headroom) or 0, 5)
                    else
                        -- Prefer surplus above brew need.
                        local surplus = math.max(0, refinable - brewNeed)
                        convertible = math.min(surplus > 0 and surplus or 0, tonumber(budget.headroom) or 0, 5)
                        if convertible <= 0 and LineBufferShort(line) and brewNeed <= 0 then
                            convertible = math.min(refinable, tonumber(budget.headroom) or 0, 5)
                        end
                    end
                end
                if convertible > 0 then
                    AppendIntent(intents, line, "seed-buffer", convertible, budget)
                end
            end
        end
    end

    -- 1b) Upgrade Seed: refine family upgrade plants / buffer for climb line.
    local UpgradeSeed = StockPiler4.UpgradeSeed
    if UpgradeSeed and UpgradeSeed.AppendRefineIntents then
        UpgradeSeed.AppendRefineIntents(intents, function(line, reason, uses, budget)
            AppendIntent(intents, line, reason, uses, budget)
        end)
    end

    -- 1c) Cult SkillUp: refine plants back to seeds to fill empty plots.
    local CSP = StockPiler4.CultSkillPlan
    if CSP and CSP.AppendRefineIntents then
        CSP.AppendRefineIntents(intents, function(line, reason, uses, budget)
            AppendIntent(intents, line, reason, uses, budget)
        end)
    end
    -- 1d) Apo SkillUp: refine brew-main surplus into Arboreal Resin when resin-short.
    local ASP = StockPiler4.ApoSkillPlan
    if ASP and ASP.AppendApoResinRefineIntents then
        ASP.AppendApoResinRefineIntents(intents, function(line, reason, uses, budget)
            AppendIntent(intents, line, reason, uses, budget)
        end)
    end


    -- 2) Plant-need (prefer PlanSnapshot / opts demand — avoid WarmHave rebuild on orch tick)
    do
        local demand = ResolveDemand(opts)
        if type(demand) == "table" then
            for _, row in pairs(demand) do
                if type(row) == "table" and type(row.spec) == "table"
                    and not (SM and SM.IsHarvestByproduct and SM.IsHarvestByproduct(row.spec))
                    and row.isByproduct ~= true
                    -- Containers / vendor mats never plant-need refine (vials were matching via uid).
                    and (not SM.IsGrowableSpec or SM.IsGrowableSpec(row.spec) == true)
                then
                    local seedUid = tonumber(row.seedUid) or 0
                    if seedUid <= 0 and SM and SM.ResolveSeedForSpec then
                        local seed = SM.ResolveSeedForSpec(row.spec)
                        seedUid = type(seed) == "table" and (tonumber(seed.uniqueID) or 0) or 0
                    end
                    local plantUid = tonumber(row.plantUid) or 0
                    if plantUid <= 0 and SM and SM.FindPlantUidForSpec then
                        plantUid = tonumber(SM.FindPlantUidForSpec(row.spec)) or 0
                    end
                    if plantUid > 0 then
                        local key = tostring(row.specKey or seedUid)
                        if seenBuffer[key] ~= true then
                            local budget = Refine.GetSeedBudget(seedUid)
                            local refinable = CountRefinableForSpec(plantUid, row.spec)
                            local liveOk = (tonumber(budget.live) or 0) <= 0
                                and (tonumber(budget.outstanding) or 0) <= 0
                            local deficitOk = (tonumber(row.deficit) or 0) > 0 and refinable > 0
                            if liveOk and deficitOk then
                                -- Unknown seedUid: still refine plants (learn seed on convert).
                                local allow = seedUid <= 0
                                    or not bufferOn
                                    or (tonumber(budget.headroom) or 0) > 0
                                if allow then
                                    AppendIntent(intents, {
                                        spec = row.spec,
                                        specKey = row.specKey,
                                        seedUid = seedUid,
                                        plantUid = plantUid,
                                    }, "plant-need", 1, budget)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3) Resin-need: convert same-tier surplus plants (never plant-need the resin uid).
    if SM and SM.IsHarvestByproduct then
        local demand = ResolveDemand(opts)
        if type(demand) == "table" then
            local seen = {}
            for _, row in pairs(demand) do
                if type(row) == "table" and type(row.spec) == "table"
                    and (row.isByproduct == true or SM.IsHarvestByproduct(row.spec) == true)
                then
                    local deficit = tonumber(row.deficit) or 0
                    local resinKey = tostring(row.specKey or "")
                    if deficit > 0 and resinKey ~= "" and seen[resinKey] ~= true then
                        seen[resinKey] = true
                        local pick = Refine.PickPlantForResinConvert(row.spec, deficit, nil, demand)
                        if type(pick) == "table" and (tonumber(pick.slot) or 0) > 0 then
                            local uses = math.min(
                                deficit,
                                tonumber(pick.surplus) or 0,
                                tonumber(pick.refinable) or 0,
                                5
                            )
                            if uses > 0 then
                                intents[#intents + 1] = {
                                    reason = "resin-need",
                                    spec = pick.spec or row.spec,
                                    seedUid = tonumber(pick.seedUid) or 0,
                                    plantUid = tonumber(pick.plantUid) or 0,
                                    uses = uses,
                                    headroom = 0,
                                    slot = pick.slot,
                                    item = pick.item,
                                    bagType = pick.bagType or CraftingBackpackType(),
                                    emergencyPlant = false,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(intents, function(a, b)
        local pa, pb = ReasonPriority(a.reason), ReasonPriority(b.reason)
        if pa ~= pb then
            return pa < pb
        end
        return (tonumber(a.seedUid) or 0) < (tonumber(b.seedUid) or 0)
    end)

    Refine._intentCacheKey = cacheKey
    Refine._intentCache = intents
    if #intents == 0 then
        Refine._emptyIntentBustAt = NowSec()
    end
    if Perf and Perf.End then
        Perf.End("CollectIntents")
    end
    return intents
end

function Refine.CanIssue(intent)
    if type(intent) ~= "table" then
        return false, "nil-intent"
    end
    local seedUid = tonumber(intent.seedUid) or 0
    local plantUid = tonumber(intent.plantUid) or 0
    local reason = tostring(intent.reason or "")
    if reason == "seed-buffer" and IsSeedBufferOnCooldown(seedUid) then
        return false, "seed-buffer-cooldown"
    end
    if (reason == "seed-buffer" or reason == "upgrade-seed-buffer")
        and SeedBufferSettleDeferred(seedUid)
    then
        return false, "seed-buffer-unsettled"
    end
    if Refine._issuedSeedThisTick ~= nil and seedUid > 0 and Refine._issuedSeedThisTick == seedUid then
        return false, "duplicate-tick"
    end
    local RP = StockPiler4.RefinePipeline
    if RP and RP.GetOutstanding and RP.GetOutstanding(seedUid) >= (Refine.MAX_OUTSTANDING_PER_SEED or 6) then
        return false, "outstanding-throttle"
    end
    local pending = tonumber(Refine._pendingByPlant[plantUid]) or 0
    if pending >= (Refine.MAX_PENDING_PER_PLANT or 6) then
        return false, "pending-throttle"
    end
    if (tonumber(intent.slot) or 0) <= 0 or type(intent.item) ~= "table" then
        return false, "no-slot"
    end
    if (tonumber(intent.uses) or 0) <= 0 then
        return false, "no-uses"
    end
    return true
end

function Refine.IssueOne(intent, opId)
    if Refine.CanIssue(intent) ~= true then
        return false
    end
    if type(SendUseItem) ~= "function"
        or type(EA_Window_Backpack) ~= "table"
        or type(EA_Window_Backpack.GetCursorForBackpack) ~= "function"
    then
        return false
    end

    local Perf = StockPiler4.Perf
    if Perf and Perf.Begin then
        Perf.Begin("Refine.IssueOne")
    end
    local function done(ok)
        if Perf and Perf.End then
            Perf.End("Refine.IssueOne")
        end
        return ok == true
    end

    local slot = tonumber(intent.slot) or 0
    local item = intent.item
    local bagType = tonumber(intent.bagType) or CraftingBackpackType()
    local plantUid = tonumber(intent.plantUid) or tonumber(item.uniqueID) or 0
    local seedUid = tonumber(intent.seedUid) or 0
    local uses = tonumber(intent.uses) or 1
    local reason = tostring(intent.reason or "refine")
    local pending = tonumber(Refine._pendingByPlant[plantUid]) or 0
    local stack = tonumber(item.stackCount) or tonumber(item.StackCount) or 1
        local maxUses = (reason == "seed-buffer" or reason == "resin-need" or reason == "skill-up") and 5 or 1
    uses = math.min(uses, stack, (Refine.MAX_PENDING_PER_PLANT or 6) - pending, maxUses)

    -- Clamp to live headroom (not resin-need).
    local bufferOn = StockPiler4.Watch and StockPiler4.Watch.IsSeedBufferEnabled
        and StockPiler4.Watch.IsSeedBufferEnabled() == true
    if (reason == "seed-buffer" or reason == "upgrade-seed-buffer")
        and SeedBufferSettleDeferred(seedUid)
    then
        return done(false)
    end
    if seedUid > 0 and reason ~= "resin-need"
        and (reason == "seed-buffer" or reason == "upgrade-seed-buffer"
            or (reason == "plant-need" and bufferOn))
    then
        local budget = Refine.GetSeedBudget(seedUid)
        local headroom = tonumber(budget.headroom) or 0
        if headroom < 1 then
            return done(false)
        end
        uses = math.min(uses, headroom)
    end
    if uses < 1 then
        return done(false)
    end

    local SM = StockPiler4.SeedMap
    if SM and SM.BeginPendingRefine then
        SM.BeginPendingRefine(item)
    end
    Refine.TrackLiveSeed(seedUid)

    if StockPiler4.Scheduler and StockPiler4.Scheduler.SuppressInventorySideEffects then
        StockPiler4.Scheduler.SuppressInventorySideEffects(2)
    end

    local location = EA_Window_Backpack.GetCursorForBackpack(bagType)
    local sent = 0
    for _ = 1, uses do
        local ok = true
        if StockPiler4.Debug and StockPiler4.Debug.TryCall then
            ok = StockPiler4.Debug.TryCall("SendUseItem", SendUseItem, location, slot, 0, 0, 0)
        else
            ok = pcall(SendUseItem, location, slot, 0, 0, 0)
        end
        if ok ~= true then
            break
        end
        sent = sent + 1
        local RP = StockPiler4.RefinePipeline
        if RP and RP.Register then
            RP.Register(seedUid, plantUid)
        end
    end
    if sent <= 0 then
        return done(false)
    end

    Refine._pendingByPlant[plantUid] = pending + sent
    if plantUid > 0 and seedUid > 0 then
        Refine._pendingSeedByPlant[plantUid] = seedUid
    end
    Refine._issuedSeedThisTick = seedUid
    Refine._reconcileSnapGen = -1
    LogRefine(string.format(
        "%s plantUid=%d seedUid=%d uses=%d opId=%s",
        reason, plantUid, seedUid, sent, tostring(opId or "?")
    ))
    if StockPiler4.Grow and StockPiler4.Grow.InvalidatePlantQueue then
        StockPiler4.Grow.InvalidatePlantQueue({ jobOnly = true })
    end
    -- Hold plan/UI through refine inventory storms (same Flatten as plant).
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.ArmPlantQuiet then
        Sch.ArmPlantQuiet()
    end
    if Sch and Sch.SkipPlanThisFrame then
        Sch.SkipPlanThisFrame()
    end
    if Sch and Sch.SkipUiThisFrame then
        Sch.SkipUiThisFrame()
    end
    if Sch and Sch.EnqueueBagFlush then
        Sch.EnqueueBagFlush(false)
    end
    Refine.InvalidateIntentCache()
    Refine._refineWaitTicks = (reason == "seed-buffer") and 2 or 5
    Refine._refineDirty = false
    Refine._refineDirtyReason = nil
    if Sch and Sch.WakeAutoGrow then
        Sch.WakeAutoGrow()
    end
    return done(true)
end

function Refine.TryTick(opId)
    Refine._issuedSeedThisTick = nil
    if Refine.IsEnabled() ~= true then
        return false
    end
    if Refine.ShouldAllowRefineNow() ~= true then
        return false
    end
    if Refine.RefineCheckDue() ~= true then
        return false
    end
    ClearOrphanPending()
    -- Prefer immutable plan refineIntent (Planner.BuildFull) before CollectIntents rebuild.
    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get()
    local snapIntent = type(plan) == "table" and plan.refineIntent or nil
    if type(snapIntent) == "table"
        and (tonumber(snapIntent.plantUid) or 0) > 0
        and (tonumber(snapIntent.uses) or 0) >= 1
    then
        if Refine.IssueOne(snapIntent, opId) == true then
            return true
        end
    end
    local intents = Refine.CollectIntents()
    if type(intents) ~= "table" or #intents == 0 then
        -- No actionable refine: back off so grow-wait ticks do not rebuild intents
        -- every AutoGrow second (LibPerf ~300-450ms CollectIntents spikes).
        Refine._refineWaitTicks = math.max(tonumber(Refine._refineWaitTicks) or 0, 5)
        if Refine.IsDirty() == true and Refine.DirtyReason() ~= "harvest" then
            Refine.ClearDirty()
        end
        return false
    end
    for i = 1, #intents do
        if Refine.IssueOne(intents[i], opId) == true then
            return true
        end
    end
    -- No issue: throttle only (do not fill-block).
    if Refine.IsDirty() == true then
        Refine._refineWaitTicks = math.max(tonumber(Refine._refineWaitTicks) or 0, 3)
        if Refine.DirtyReason() ~= "harvest" then
            Refine.ClearDirty()
        else
            Refine._refineDirty = false
        end
    end
    return false
end

function Refine.OnTick(opId)
    return Refine.TryTick(opId)
end

----------------------------------------------------------------
-- Reconcile / OnUpdate
----------------------------------------------------------------

function Refine.ReconcileAll()
    local RP = StockPiler4.RefinePipeline
    if not RP or not RP.Snapshot then
        return
    end
    local snap = RP.Snapshot()
    for seedUid, outstanding in pairs(snap) do
        seedUid = tonumber(seedUid) or 0
        outstanding = tonumber(outstanding) or 0
        if seedUid > 0 and outstanding > 0 then
            local live = LiveSeedCount(seedUid)
            local base = tonumber(Refine._liveSeedBaseline[seedUid])
            if base ~= nil and live > base then
                local delivered = live - base
                RP.Reconcile(seedUid, delivered)
                Refine._liveSeedBaseline[seedUid] = live
                Refine.InvalidateIntentCache()
            end
        end
    end
end

function Refine.ExpireStuckOutstanding()
    local RP = StockPiler4.RefinePipeline
    if not RP or not RP.ExpireStuck then
        return false
    end
    local changed = RP.ExpireStuck() == true
    if changed then
        -- After soft+force expire: arm 45s seed-buffer fail cooldown for cleared seeds.
        for seedUid, untilT in pairs(Refine._seedBufferCooldownUntil) do
            -- keep existing
        end
        local snap = RP.Snapshot and RP.Snapshot() or {}
        -- Cooldown on seeds that still look stuck after expire pass is handled in pipeline;
        -- arm cooldown when pending cleared with no delivery.
        for plantUid, seedUid in pairs(Refine._pendingSeedByPlant) do
            seedUid = tonumber(seedUid) or 0
            local outstanding = RP.GetOutstanding and RP.GetOutstanding(seedUid) or 0
            if outstanding <= 0 then
                ArmSeedBufferFailCooldown(seedUid)
                Refine._pendingByPlant[plantUid] = nil
                Refine._pendingSeedByPlant[plantUid] = nil
            end
        end
        Refine.InvalidateIntentCache()
    end
    return changed
end

--- Frame-gated Reconcile / ExpireStuck.
function Refine.OnUpdateProcessed(timeElapsed)
    local frame = tonumber(StockPiler4.FrameCounter) or 0
    if Refine._onUpdateFrame == frame then
        return
    end
    Refine._onUpdateFrame = frame

    local Inv = StockPiler4.Inventory
    local snapGen = Inv and Inv.GetSnapGen and Inv.GetSnapGen() or 0
    if snapGen ~= Refine._reconcileSnapGen then
        Refine._reconcileSnapGen = snapGen
        Refine.ReconcileAll()
    end
    Refine.ExpireStuckOutstanding()
    Refine.DecayRefineWaitTicks()
end

function Refine.OnUpdate(timeElapsed)
    Refine.OnUpdateProcessed(timeElapsed)
end

function Refine.OnInventoryUpdated()
    Refine._bagIndexGen = -1
end

function Refine.DumpDiagnostics(emit)
    emit = type(emit) == "function" and emit or function(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    emit("=== refine ===")
    emit("enabled=" .. tostring(Refine.IsEnabled())
        .. " dirty=" .. tostring(Refine._refineDirty)
        .. " reason=" .. tostring(Refine._refineDirtyReason)
        .. " wait=" .. tostring(Refine._refineWaitTicks))
    local allow, why = Refine.ShouldAllowRefineNow()
    emit("allow=" .. tostring(allow) .. " why=" .. tostring(why))
    emit("bufferSatisfied=" .. tostring(Refine.IsSeedBufferSatisfied())
        .. " pending=" .. tostring(Refine.HasPendingBufferRefine())
        .. " short=" .. tostring(Refine.HasAnyBufferShort()))
    local intents = Refine.PeekCachedIntents() or {}
    emit("cachedIntents=" .. tostring(#intents) .. " key=" .. tostring(Refine._intentCacheKey))
    for i = 1, math.min(#intents, 12) do
        local it = intents[i]
        emit(string.format(
            "  %s seed=%s plant=%s uses=%s",
            tostring(it.reason), tostring(it.seedUid), tostring(it.plantUid), tostring(it.uses)
        ))
    end
    emit("=== end refine ===")
end

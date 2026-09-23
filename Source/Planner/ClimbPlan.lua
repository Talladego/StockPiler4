----------------------------------------------------------------
-- StockPiler4 ClimbPlan - watch-driven family climb + cult deficit
-- buy L1 -> plant -> crit harvest -> refine -> repeat toward watch skillReq.
-- Shared seed economy (SeedDeficit / PlantableSurplus / GetSeedBudget) and
-- ladder scan helpers also used by SkillUp (mains-only, TargetMaxSkill cap).
-- Phase 1: canonical climb engine (UpgradeSeed is a deprecated alias).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.ClimbPlan = StockPiler4.ClimbPlan or {}
local CP = StockPiler4.ClimbPlan

CP._stallLatch = nil
CP._active = nil -- last pick { familyKey, haveReq, needReq, why }
CP._upgradeTargetsCache = nil
CP._upgradeTargetsKey = nil

local function CharRow(create)
    return StockPiler4.Util.CharacterRow(create == true)
end

function CP.IsEnabled()
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() ~= true then
        return false
    end
    local row = CharRow(false)
    return type(row) == "table" and row.upgradeSeedsEnabled == true
end

function CP.SetEnabled(enabled)
    local row = CharRow(true)
    if type(row) ~= "table" then
        return false
    end
    row.upgradeSeedsEnabled = enabled == true
    CP.InvalidateUpgradeTargetsCache()
    local Watch = StockPiler4.Watch
    if Watch and Watch.BumpGen then
        Watch.BumpGen()
    end
    return true
end

function CP.GetCultSkill()
    -- SkillUp owns the Caps facade; fall back if SkillUp is unavailable.
    local SkillUp = StockPiler4.SkillUp
    if SkillUp and SkillUp.GetCultSkill then
        return tonumber(SkillUp.GetCultSkill()) or 0
    end
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.GetCultSkill then
        return tonumber(Caps.GetCultSkill()) or 0
    end
    if Caps and Caps.GetCultivationSkill then
        return tonumber(Caps.GetCultivationSkill()) or 0
    end
    return 0
end

--- Cult seed/plant floor (1, 25, ...). Canonical implementation is TradeSkillCaps.FloorCultTier.
function CP.FloorCultTier(cultSkill)
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.FloorCultTier then
        return Caps.FloorCultTier(cultSkill)
    end
    cultSkill = tonumber(cultSkill) or 0
    local tiers = { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
    local best = 1
    for i = 1, #tiers do
        if cultSkill >= tiers[i] then
            best = tiers[i]
        end
    end
    return best
end

--- Climb cap for a watch need: min(needed skillReq, Cult floor).
function CP.ClimbCap(neededReq)
    neededReq = tonumber(neededReq) or 0
    local floor = CP.FloorCultTier(CP.GetCultSkill())
    if floor < 1 then
        floor = 1
    end
    if neededReq < 1 then
        return floor
    end
    if neededReq < floor then
        return neededReq
    end
    return floor
end

--- Highest genus-ladder skillReq at or below current Cult floor (0 if unknown).
function CP.CultMaxNeedReq(ladder)
    local GL = StockPiler4.GenusLadder
    if GL and GL.CultMaxNeedReq then
        return GL.CultMaxNeedReq(ladder)
    end
    local floor = CP.FloorCultTier(CP.GetCultSkill())
    if floor < 1 then
        floor = 1
    end
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" then
        return 0
    end
    local best = 0
    for i = 1, #ladder.rungs do
        local req = tonumber(ladder.rungs[i].skillReq) or 0
        if req >= 1 and req <= floor and req > best then
            best = req
        end
    end
    return best
end

--- Prefer / merge genus ladders from plant name and linked seed name for climb.
function CP.LadderForPlantWatch(spec, plantUid)
    local GL = StockPiler4.GenusLadder
    if GL and GL.LadderForPlantWatch then
        return GL.LadderForPlantWatch(spec, plantUid)
    end
    return nil
end

--- Watched plant stock resolve (never retargets to Cult-max).
--- climbNeedReq = Cult-max rung when Upgrade Seeds is on (climb destination only).
function CP.ResolvePlantWatchTarget(watchPlantUid, watchSpec)
    watchPlantUid = tonumber(watchPlantUid) or 0
    local Items = StockPiler4.Items
    local SM = StockPiler4.SeedMap
    local MS = StockPiler4.MaterialSpec
    local Inv = StockPiler4.Inventory
    local spec = watchSpec
    if type(spec) ~= "table" and watchPlantUid > 0 then
        if Items and Items.ToSpec then
            spec = Items.ToSpec(watchPlantUid)
        end
        if type(spec) ~= "table" and MS and MS.FromUid then
            spec = MS.FromUid(watchPlantUid)
        end
    end
    local plantUid = watchPlantUid
    local needReq = tonumber(spec and spec.skillLevel) or 0
    if needReq < 1 and plantUid > 0 and Inv and Inv.GetSample then
        local sample = Inv.GetSample(plantUid)
        needReq = tonumber(sample and sample.craftingSkillRequirement) or 0
    end
    if needReq < 1 then
        needReq = 1
    end
    local ladder = CP.LadderForPlantWatch(spec, plantUid)
    local climbNeedReq = needReq
    if CP.IsEnabled() == true then
        local cultMax = CP.CultMaxNeedReq(ladder)
        if cultMax >= 1 then
            climbNeedReq = cultMax
        end
    end
    local seedUid = 0
    if plantUid > 0 and SM and SM.ResolveSeedUidForPlant then
        seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, spec)) or 0
    end
    if seedUid <= 0 and type(ladder) == "table" and type(ladder.rungs) == "table" then
        for i = 1, #ladder.rungs do
            local rung = ladder.rungs[i]
            if (tonumber(rung.skillReq) or 0) == needReq then
                seedUid = tonumber(rung.seedUid) or 0
                if seedUid > 0 then
                    break
                end
            end
        end
    end
    if seedUid <= 0 and type(spec) == "table" and SM and SM.ResolveSeedForSpec then
        local seed = SM.ResolveSeedForSpec(spec)
        if type(seed) == "table" then
            seedUid = tonumber(seed.uniqueID or seed.uid) or 0
        end
    end
    if seedUid <= 0 and plantUid > 0 and SM and SM.GetSeedUidsForPlant then
        local seeds = SM.GetSeedUidsForPlant(plantUid)
        if type(seeds) == "table" and #seeds > 0 then
            seedUid = tonumber(seeds[1]) or 0
        end
    end
    return {
        plantUid = plantUid,
        seedUid = seedUid,
        needReq = needReq,
        climbNeedReq = climbNeedReq,
        ladder = ladder,
        spec = spec,
        watchPlantUid = watchPlantUid,
        retargeted = false,
    }
end

--- Shared seed budget facade (Refine.GetSeedBudget).
function CP.GetSeedBudget(seedUid)
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

function CP.CountEmptyPlots()
    local Grow = StockPiler4.Grow
    if Grow and Grow.CountEmptyPlots then
        return tonumber(Grow.CountEmptyPlots()) or 0
    end
    return 0
end

--- Seeds still needed for planting / AutoBuy.
--- mode "climb" (default): with buffer on, buy to (buffer + empty) so climb surplus exists.
--- mode "skillup": max(headroom, empty-plot need) - SkillUp fills all plots.
function CP.SeedDeficit(seedUid, mode)
    seedUid = tonumber(seedUid) or 0
    mode = tostring(mode or "climb")
    local empty = CP.CountEmptyPlots()
    local budget = CP.GetSeedBudget(seedUid)
    local buffer = tonumber(budget.bufferMin) or 0
    local live = tonumber(budget.live) or 0
    local headroom = tonumber(budget.headroom) or 0
    local needPlots = empty
    if live >= empty then
        needPlots = 0
    else
        needPlots = empty - live
    end
    if mode == "skillup" then
        return math.max(headroom, needPlots)
    end
    -- Climb planting only uses surplus above the seed buffer, so AutoBuy must
    -- top up to (buffer + empty plots) or every harvest can wipe the rung.
    if buffer > 0 then
        return math.max(0, buffer + empty - live)
    end
    return math.max(headroom, needPlots)
end

--- How many bag seeds may be planted without dipping the keep cushion.
--- opts.mode "climb" (default): L1 prefers buffer but never stalls empty plots;
--- intermediate rungs keep 0 (not vendor-restocked).
--- opts.mode "skillup": plant up to headroom when buffer-short, else fill empties.
--- opts.intermediate: climb-only - treat as non-vendor intermediate rung.
function CP.PlantableSurplus(seedUid, bagSeeds, empty, opts)
    seedUid = tonumber(seedUid) or 0
    bagSeeds = tonumber(bagSeeds) or 0
    empty = tonumber(empty) or 0
    opts = type(opts) == "table" and opts or {}
    if bagSeeds < 1 or empty < 1 then
        return 0
    end
    local budget = CP.GetSeedBudget(seedUid)
    local buffer = tonumber(budget.bufferMin) or 0
    local mode = tostring(opts.mode or "climb")
    if mode == "skillup" then
        local headroom = tonumber(budget.headroom) or 0
        if buffer > 0 and headroom > 0 then
            return math.min(bagSeeds, empty, headroom)
        end
        return math.min(bagSeeds, empty)
    end
    -- Climb: intermediate rungs keep 0 - those seeds are not at the vendor; holding
    -- even 1 seed with empty plots stalls the climb (seen: have=50, plantable=0).
    if buffer <= 0 or opts.intermediate == true then
        return math.min(bagSeeds, empty)
    end
    -- L1 / vendor floor: prefer surplus above the seed buffer so AutoBuy can
    -- restock. If AutoBuy only filled the cushion (e.g. plots were full then),
    -- still plant into empties — otherwise Majestic Goldweed stays need_buy
    -- forever with 5 L1 seeds and open plots.
    local live = tonumber(budget.live) or bagSeeds
    local surplus = live - buffer
    if surplus >= 1 then
        return math.min(bagSeeds, empty, surplus)
    end
    return math.min(bagSeeds, empty)
end

local function SeedBudget(seedUid)
    return CP.GetSeedBudget(seedUid)
end

local function CountEmptyPlots()
    return CP.CountEmptyPlots()
end

local function PlantableSurplus(seedUid, bagSeeds, empty, opts)
    return CP.PlantableSurplus(seedUid, bagSeeds, empty, opts)
end

local function LadderLowestReq(ladder)
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" or #ladder.rungs < 1 then
        return 1
    end
    local lowest = tonumber(ladder.rungs[1].skillReq) or 1
    for i = 2, #ladder.rungs do
        local req = tonumber(ladder.rungs[i].skillReq) or 0
        if req >= 1 and req < lowest then
            lowest = req
        end
    end
    return lowest
end

--- True when bag seeds are not the vendor L1 cushion seed.
--- Multiplier/main ladders often start at 100+; treating that floor as "L1 buffer"
--- trapped Fusk 3010034 (live=1, buffer=5, plantable=0) while Spumepetal refined.
local function IsIntermediateClimb(ladder, ownedReq)
    ownedReq = tonumber(ownedReq) or 0
    local lowest = LadderLowestReq(ladder)
    if ownedReq > lowest then
        return true
    end
    if ownedReq > 1 then
        return true
    end
    return false
end

--- Plantable climb count for one upgrade target (0 if none / cannot plant).
local function TargetPlantableCount(t)
    if type(t) ~= "table" or type(t.ladder) ~= "table" then
        return 0, nil, 0
    end
    local needReq = tonumber(t.needReq) or 0
    local climbCap = CP.ClimbCap(needReq)
    local owned = CP.PickBestOwnedSeed({
        ladder = t.ladder,
        climbCap = climbCap,
    })
    if type(owned) ~= "table" or (tonumber(owned.seedUid) or 0) <= 0 then
        return 0, owned, climbCap
    end
    local seedUid = tonumber(owned.seedUid) or 0
    local ownedReq = tonumber(owned.skillReq) or 0
    local bagSeeds = tonumber(owned.count) or 0
    local empty = CountEmptyPlots()
    local intermediate = IsIntermediateClimb(t.ladder, ownedReq)
    local plantable = PlantableSurplus(seedUid, bagSeeds, empty, {
        intermediate = intermediate,
    })
    return plantable, owned, climbCap
end

--- Refine scan for one target (plants above owned seed rung).
--- Plant-watch buffer fill: also refine Cult-max plants while that seed buffer is short.
local function TargetUpgradePlant(t)
    if type(t) ~= "table" or type(t.ladder) ~= "table" then
        return nil, 0
    end
    local needReq = tonumber(t.needReq) or 0
    local climbCap = CP.ClimbCap(needReq)
    local owned = CP.PickBestOwnedSeed({
        ladder = t.ladder,
        climbCap = climbCap,
    })
    local ownedReq = type(owned) == "table" and (tonumber(owned.skillReq) or 0) or 0
    local refineCap = CP.FloorCultTier(CP.GetCultSkill())
    if refineCap < climbCap then
        refineCap = climbCap
    end
    local scanOwnedReq = ownedReq
    local watchPlantUid = tonumber(t.watchPlantUid) or 0
    if watchPlantUid > 0 and needReq >= 1
        and CultMaxTierBufferFull(t.ladder, needReq, t.plantUid, t.seedUid) ~= true
        and ownedReq >= needReq
    then
        -- Already own Cult-max seeds but buffer short: refine same-tier plants.
        scanOwnedReq = math.max(0, needReq - 1)
    end
    local up = CP.ScanUpgradePlant({
        ladder = t.ladder,
        climbCap = refineCap,
        ownedSeedReq = scanOwnedReq,
    })
    return up, ownedReq
end

--- Seed/plant uids on the needReq rung (Cult-max destination).
local function RungUidsAtNeed(ladder, needReq, fallbackPlantUid, fallbackSeedUid)
    needReq = tonumber(needReq) or 0
    local seedUid = tonumber(fallbackSeedUid) or 0
    local plantUid = tonumber(fallbackPlantUid) or 0
    if type(ladder) == "table" and type(ladder.rungs) == "table" and needReq >= 1 then
        for i = 1, #ladder.rungs do
            local rung = ladder.rungs[i]
            if (tonumber(rung.skillReq) or 0) == needReq then
                local rSeed = tonumber(rung.seedUid) or 0
                local rPlant = tonumber(rung.plantUid) or 0
                if rSeed > 0 then
                    seedUid = rSeed
                end
                if rPlant > 0 then
                    plantUid = rPlant
                end
                break
            end
        end
    end
    return seedUid, plantUid
end

--- Plant-watch climb done: Cult-max tier seed buffer is full (credit >= buffer).
--- Buffer off: at least one Cult-max seed.
--- Rung with plant but no known seed (Cross s0) is NOT done - keep climbing via
--- lower plantable rungs / refine until a plantable seed exists and its buffer fills.
local function CultMaxTierBufferFull(ladder, needReq, fallbackPlantUid, fallbackSeedUid)
    needReq = tonumber(needReq) or 0
    if needReq < 1 then
        return false
    end
    local seedUid = RungUidsAtNeed(ladder, needReq, fallbackPlantUid, fallbackSeedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        -- Orphan high plant must not end the climb (Fretting→Cross with s0).
        return false
    end
    local budget = CP.GetSeedBudget(seedUid)
    local credit = tonumber(budget.credit) or 0
    local buffer = tonumber(budget.bufferMin) or 0
    if buffer < 1 then
        return credit >= 1
    end
    return credit >= buffer
end

--- Have the target-tier seed/plant for this climb need?
--- Only the needReq rung counts - owned lower-tier seeds must not end the climb
--- (ResolveSeedForSpec prefers bag seeds and would falsely "arrive" at L25).
--- In-ground target seeds count: bag-only checks left "Upgrading fusk 0->200 /
--- need_buy" after AutoGrow planted L200 for the seed buffer.
--- Orphan high plant with no known plantable seed on the rung does NOT count
--- (Fretting in bag, seedUid=0 on ladder falsely ended marshroot climb).
--- opts.requireBufferFull: plant-watch Cult-max climb - keep going until the
--- Cult-max seed buffer is full (not after the first Fretting plant).
local function HaveTargetRung(ladder, needReq, plantUid, seedUid, opts)
    needReq = tonumber(needReq) or 0
    opts = type(opts) == "table" and opts or {}
    if opts.requireBufferFull == true then
        return CultMaxTierBufferFull(ladder, needReq, plantUid, seedUid)
    end
    local requirePlant = opts.requirePlant == true
    local Inv = StockPiler4.Inventory
    if not Inv or not Inv.CountByUid then
        return false
    end
    plantUid = tonumber(plantUid) or 0
    seedUid = tonumber(seedUid) or 0
    local Grow = StockPiler4.Grow

    local function haveUid(uid)
        uid = tonumber(uid) or 0
        if uid <= 0 then
            return false
        end
        if (tonumber(Inv.CountByUid(uid)) or 0) >= 1 then
            return true
        end
        if Grow and Grow.CountSeedPlotCredit then
            return (tonumber(Grow.CountSeedPlotCredit(uid)) or 0) >= 1
        end
        if Grow and Grow.CountInGroundSeeds then
            return (tonumber(Grow.CountInGroundSeeds(uid)) or 0) >= 1
        end
        return false
    end

    local function rungArrived(rSeed, rPlant)
        rSeed = tonumber(rSeed) or 0
        rPlant = tonumber(rPlant) or 0
        if requirePlant then
            -- Legacy: Cult-max plant in bags only.
            return haveUid(rPlant)
        end
        if haveUid(rSeed) then
            return true
        end
        -- Plant alone only counts when the rung has a known plantable seed.
        if rSeed > 0 and haveUid(rPlant) then
            return true
        end
        return false
    end

    if type(ladder) == "table" and type(ladder.rungs) == "table" and needReq >= 1 then
        for i = 1, #ladder.rungs do
            local rung = ladder.rungs[i]
            if (tonumber(rung.skillReq) or 0) == needReq then
                return rungArrived(rung.seedUid, rung.plantUid)
            end
        end
        return false
    end
    -- Ladder missing: only trust explicit target plant/seed uids (seed required
    -- for plant-only arrive, same orphan rule).
    return rungArrived(seedUid, plantUid)
end

function CP.HaveTargetRung(ladder, needReq, plantUid, seedUid, opts)
    return HaveTargetRung(ladder, needReq, plantUid, seedUid, opts)
end

function CP.CultMaxTierBufferFull(ladder, needReq, fallbackPlantUid, fallbackSeedUid)
    return CultMaxTierBufferFull(ladder, needReq, fallbackPlantUid, fallbackSeedUid)
end

--- Plant-watch climb descriptor (stock N vs Cult-max existence).
--- pending = climb not finished; eligible = stocked or mid-climb latch.
function CP.DescribePlantWatchClimb(watchPlantUid)
    watchPlantUid = tonumber(watchPlantUid) or 0
    local out = {
        watchPlantUid = watchPlantUid,
        have = 0,
        target = 40,
        stocked = false,
        midClimb = false,
        eligible = false,
        pending = false,
        climbNeedReq = 0,
        watchedReq = 1,
        ladder = nil,
        spec = nil,
        seedUid = 0,
        plantUid = watchPlantUid,
    }
    if watchPlantUid <= 0 or CP.IsEnabled() ~= true then
        return out
    end
    local Watch = StockPiler4.Watch
    local Catalog = StockPiler4.Catalog
    local Inv = StockPiler4.Inventory
    local plantKey = Watch and Watch.PlantKeyFromUid and Watch.PlantKeyFromUid(watchPlantUid)
        or ("plant:" .. tostring(watchPlantUid))
    local watch = Watch and Watch.GetPlantWatch and Watch.GetPlantWatch(plantKey) or nil
    if type(watch) ~= "table" then
        watch = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or nil
        watch = type(watch) == "table" and watch[plantKey] or nil
    end
    out.target = tonumber(watch and watch.targetStock) or 40
    if Catalog and Catalog.PlantHave then
        out.have = tonumber(Catalog.PlantHave(watchPlantUid)) or 0
    elseif Inv and Inv.CountByUid then
        out.have = tonumber(Inv.CountByUid(watchPlantUid)) or 0
    end
    out.stocked = out.have >= out.target
    local resolved = CP.ResolvePlantWatchTarget(watchPlantUid)
    out.spec = resolved and resolved.spec
    out.seedUid = tonumber(resolved and resolved.seedUid) or 0
    out.plantUid = tonumber(resolved and resolved.plantUid) or watchPlantUid
    out.watchedReq = tonumber(resolved and resolved.needReq) or 1
    out.climbNeedReq = tonumber(resolved and resolved.climbNeedReq) or out.watchedReq
    out.ladder = resolved and resolved.ladder
    local ladder = out.ladder
    local watchedReq = out.watchedReq
    local climbNeed = out.climbNeedReq
    if not out.stocked and type(ladder) == "table" and type(ladder.rungs) == "table"
        and Inv and Inv.CountByUid
    then
        local Grow = StockPiler4.Grow
        local climbCap = CP.ClimbCap(climbNeed)
        for i = 1, #ladder.rungs do
            local rung = ladder.rungs[i]
            local req = tonumber(rung.skillReq) or 0
            if req > watchedReq and req <= climbCap then
                local sUid = tonumber(rung.seedUid) or 0
                local pUid = tonumber(rung.plantUid) or 0
                if sUid > 0 then
                    local seedHave = tonumber(Inv.CountByUid(sUid)) or 0
                    if seedHave < 1 and Grow and Grow.CountSeedPlotCredit then
                        seedHave = tonumber(Grow.CountSeedPlotCredit(sUid)) or 0
                    end
                    if seedHave < 1 and Grow and Grow.CountInGroundSeeds then
                        seedHave = tonumber(Grow.CountInGroundSeeds(sUid)) or 0
                    end
                    if seedHave >= 1 then
                        out.midClimb = true
                        break
                    end
                end
                -- Higher-tier plant (e.g. Cross with no known seed) also latches mid-climb.
                if pUid > 0 and (tonumber(Inv.CountByUid(pUid)) or 0) >= 1 then
                    out.midClimb = true
                    break
                end
            end
        end
    end
    out.eligible = out.stocked or out.midClimb
    if out.eligible and climbNeed > watchedReq then
        -- Plant-watch climb arrives when Cult-max seed buffer is full.
        out.pending = HaveTargetRung(ladder, climbNeed, out.plantUid, out.seedUid, {
            requireBufferFull = true,
        }) ~= true
    elseif out.eligible and climbNeed <= watchedReq then
        -- Nowhere above watched tier on the known ladder.
        out.pending = false
    end
    return out
end

--- True while Upgrade Seeds owns this plant watch for Cult-max climb (ephemeral row).
function CP.IsPlantWatchOwnedByUpgrade(watchPlantUid)
    if CP.IsEnabled() ~= true then
        return false
    end
    local d = CP.DescribePlantWatchClimb(watchPlantUid)
    return d.eligible == true and d.pending == true
end

local function SeedBufferOkForIdle()
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsSeedBufferEnabled and Watch.IsSeedBufferEnabled() == true) then
        return true
    end
    local Grow = StockPiler4.Grow
    return Grow and Grow.IsSeedBufferSatisfied and Grow.IsSeedBufferSatisfied() == true
end

local function PlantsStockedForUpgradeIdle()
    local Watch = StockPiler4.Watch
    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) ~= "table" then
        return true
    end
    local Catalog = StockPiler4.Catalog
    local Inv = StockPiler4.Inventory
    for plantKey, watch in pairs(plantWatches) do
        if type(watch) == "table" and watch.enabled == true then
            local plantUid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
            plantUid = tonumber(plantUid) or 0
            if plantUid > 0 then
                if CP.IsPlantWatchOwnedByUpgrade(plantUid) then
                    -- Mid-climb / stocked pending climb: treat as satisfied for idle gate.
                else
                    local target = tonumber(watch.targetStock) or 40
                    local have = 0
                    if Catalog and Catalog.PlantHave then
                        have = tonumber(Catalog.PlantHave(plantUid)) or 0
                    elseif Inv and Inv.CountByUid then
                        have = tonumber(Inv.CountByUid(plantUid)) or 0
                    end
                    if have < target then
                        return false
                    end
                end
            end
        end
    end
    return true
end

--- Idle gate for ephemeral plant-watch Cult-max climb (and SkillUp plant check).
--- Shares SkillUp.WatchesDone (potions + plants + seed buffer); owned mid-climb
--- plants count as stocked via IsPlantWatchOwnedByUpgrade.
function CP.WatchesAllowUpgradeClimb()
    if CP.IsEnabled() ~= true then
        return false
    end
    local SkillUp = StockPiler4.SkillUp
    if SkillUp and SkillUp.WatchesDone then
        return SkillUp.WatchesDone() == true
    end
    local Watch = StockPiler4.Watch
    if Watch and Watch.AllEnabledPotionWatchesStocked
        and Watch.AllEnabledPotionWatchesStocked() ~= true
    then
        return false
    end
    if PlantsStockedForUpgradeIdle() ~= true then
        return false
    end
    return SeedBufferOkForIdle()
end

--- Shared: scan bags for a refinable upgrade plant (any main family when no ladder).
--- opts: climbCap, mainsOnly, familyKey / ladder, ownedSeedReq
function CP.ScanUpgradePlant(opts)
    opts = type(opts) == "table" and opts or {}
    local SM = StockPiler4.SeedMap
    local climbCap = tonumber(opts.climbCap) or 0
    if climbCap < 1 then
        return nil
    end
    local ladder = opts.ladder
    if type(ladder) ~= "table" and opts.familyKey and SM and SM.GetFamilyLadder then
        ladder = SM.GetFamilyLadder(opts.familyKey)
    end
    if type(ladder) == "table" and SM and SM.BestUpgradePlantOnLadder then
        return SM.BestUpgradePlantOnLadder(ladder, climbCap, opts.ownedSeedReq or 0, {
            mainsOnly = opts.mainsOnly == true,
        })
    end
    -- Opportunistic (SkillUp): any main plant under climbCap above ownedSeedReq.
    local Inv = StockPiler4.Inventory
    local Items = StockPiler4.Items
    local Refine = StockPiler4.Refine
    if not (Inv and Inv.ForEachItem) then
        return nil
    end
    local ownedSeedReq = tonumber(opts.ownedSeedReq) or 0
    local best = nil
    local bestReq = -1
    Inv.ForEachItem(function(item)
        if type(item) ~= "table" then
            return
        end
        if SM and SM.IsBagSeedOrSpore and SM.IsBagSeedOrSpore(item) then
            return
        end
        if SM and SM.ItemLooksLikeRefinablePlant
            and SM.ItemLooksLikeRefinablePlant(item) ~= true
            and item.isRefinable ~= true
        then
            return
        end
        local pUid = tonumber(item.uniqueID) or 0
        if pUid <= 0 then
            return
        end
        local spec = Items and Items.ToSpec and Items.ToSpec(pUid) or nil
        local role = tostring(spec and spec.role or "")
        if opts.mainsOnly == true and role ~= "" and role ~= "main" then
            return
        end
        local req = tonumber(spec and spec.skillLevel) or 0
        if req < 1 then
            req = tonumber(item.craftingSkillRequirement) or 0
        end
        if req <= ownedSeedReq or req > climbCap then
            return
        end
        local sUid = 0
        if SM and SM.ResolveSeedUidForPlant then
            sUid = tonumber(SM.ResolveSeedUidForPlant(pUid, spec)) or 0
        end
        if sUid <= 0 and SM and SM.GetSeedUidsForPlant then
            local seeds = SM.GetSeedUidsForPlant(pUid) or {}
            if type(seeds) == "table" and #seeds > 0 then
                sUid = tonumber(seeds[1]) or 0
            end
        end
        if sUid <= 0 then
            return
        end
        local refinable = 0
        if Refine and Refine.CountRefinablePlants then
            refinable = tonumber(Refine.CountRefinablePlants(pUid, spec)) or 0
        end
        if refinable <= 0 then
            return
        end
        if req > bestReq then
            bestReq = req
            best = {
                seedUid = sUid,
                plantUid = pUid,
                skillReq = req,
                refinable = refinable,
                upgrade = true,
            }
        end
    end)
    return best
end

function CP.PickBestOwnedSeed(opts)
    opts = type(opts) == "table" and opts or {}
    local SM = StockPiler4.SeedMap
    local climbCap = tonumber(opts.climbCap) or 0
    if climbCap < 1 then
        return nil
    end
    local ladder = opts.ladder
    if type(ladder) ~= "table" and opts.familyKey and SM and SM.GetFamilyLadder then
        ladder = SM.GetFamilyLadder(opts.familyKey)
    end
    if type(ladder) == "table" and SM and SM.BestOwnedSeedOnLadder then
        return SM.BestOwnedSeedOnLadder(ladder, climbCap, { mainsOnly = opts.mainsOnly == true })
    end
    return nil
end

--- Collect short growable demand + plant watches that need a genus climb.
local function CollectUpgradeTargets()
    local RS = StockPiler4.RecipeSpec
    local SM = StockPiler4.SeedMap
    local Watch = StockPiler4.Watch
    local Items = StockPiler4.Items
    local MS = StockPiler4.MaterialSpec
    local Catalog = StockPiler4.Catalog
    local Inv = StockPiler4.Inventory
    if not (SM and Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true) then
        return {}
    end
    local out = {}
    local seenPlant = {}

    local function LadderFor(spec)
        if SM.GetGenusLadderForSpec then
            return SM.GetGenusLadderForSpec(spec)
        end
        return SM.GetFamilyLadderForSpec and SM.GetFamilyLadderForSpec(spec) or nil
    end

    local function NeedReqFor(spec, plantUid)
        local needReq = tonumber(spec and spec.skillLevel) or 0
        if needReq < 1 and plantUid > 0 and Inv and Inv.GetSample then
            local sample = Inv.GetSample(plantUid)
            needReq = tonumber(sample and sample.craftingSkillRequirement) or 0
        end
        if needReq < 1 then
            needReq = 1
        end
        return needReq
    end

    --- opts.needReq / opts.seedUid / opts.watchPlantUid / opts.ladder (plant-watch climb).
    local function Consider(spec, short, plantUidHint, opts)
        opts = type(opts) == "table" and opts or nil
        if type(spec) ~= "table" or (tonumber(short) or 0) < 1 then
            return
        end
        if not (SM.IsGrowableSpec and SM.IsGrowableSpec(spec) == true) then
            return
        end
        if SM.IsHarvestByproduct and SM.IsHarvestByproduct(spec) == true then
            return
        end
        local plantUid = tonumber(plantUidHint) or 0
        if plantUid <= 0 and SM.FindPlantUidForSpec then
            plantUid = tonumber(SM.FindPlantUidForSpec(spec)) or 0
        end
        if plantUid > 0 and seenPlant[plantUid] == true then
            return
        end
        local needReq = (opts and tonumber(opts.needReq)) or 0
        if needReq < 1 then
            needReq = NeedReqFor(spec, plantUid)
        end
        local ladder = (opts and opts.ladder) or nil
        if type(ladder) ~= "table" then
            ladder = LadderFor(spec)
        end
        local seedUid = (opts and tonumber(opts.seedUid)) or 0
        -- Prefer skill-matched plant->seed link; ResolveSeedForSpec prefers any
        -- owned genus seed in bags and would pin climb to L25 Gobswort spores.
        if seedUid <= 0 and plantUid > 0 and SM.ResolveSeedUidForPlant then
            seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, spec)) or 0
        end
        if seedUid <= 0 and type(ladder) == "table" and type(ladder.rungs) == "table" then
            for i = 1, #ladder.rungs do
                local rung = ladder.rungs[i]
                if (tonumber(rung.skillReq) or 0) == needReq then
                    seedUid = tonumber(rung.seedUid) or 0
                    if seedUid > 0 then
                        break
                    end
                end
            end
        end
        if seedUid <= 0 and SM.ResolveSeedForSpec then
            local seed = SM.ResolveSeedForSpec(spec)
            if type(seed) == "table" then
                seedUid = tonumber(seed.uniqueID or seed.uid) or 0
            end
        end
        if seedUid <= 0 and plantUid > 0 and SM.GetSeedUidsForPlant then
            local seeds = SM.GetSeedUidsForPlant(plantUid)
            if type(seeds) == "table" and #seeds > 0 then
                seedUid = tonumber(seeds[1]) or 0
            end
        end
        if HaveTargetRung(ladder, needReq, plantUid, seedUid, {
            -- Plant-watch: Cult-max seed buffer full. Potion demand: seed OK.
            requireBufferFull = (opts and (tonumber(opts.watchPlantUid) or 0) > 0) == true,
        }) then
            return
        end
        if plantUid > 0 then
            seenPlant[plantUid] = true
        end
        out[#out + 1] = {
            spec = spec,
            needReq = needReq,
            short = tonumber(short) or 0,
            ladder = ladder,
            plantUid = plantUid,
            seedUid = seedUid,
            familyKey = ladder and ladder.key or nil,
            watchPlantUid = (opts and tonumber(opts.watchPlantUid)) or 0,
        }
    end

    -- Potion / balanced demand (growable mats short).
    local demand = RS and RS.BuildBalancedSpecDemand and RS.BuildBalancedSpecDemand() or nil
    if type(demand) == "table" then
        for _, row in pairs(demand) do
            if type(row) == "table" and type(row.spec) == "table" then
                local absNeed = tonumber(row.absolute) or tonumber(row.brewAbsolute) or 0
                local have = 0
                if RS.CountItemsMatchingSpec then
                    have = tonumber(RS.CountItemsMatchingSpec(row.spec)) or 0
                end
                local short = math.max(0, absNeed - have)
                if short < 1 then
                    short = tonumber(row.craftsShort) or 0
                end
                Consider(row.spec, short, nil)
            end
        end
    end

    -- Explicit plant watches: Phase A restocks watched plant to N (Grow plant_stock).
    -- Ephemeral Phase B: Cult-max climb only when watches-done idle gate passes.
    local allowPlantClimb = CP.WatchesAllowUpgradeClimb() == true
    local plantWatches = Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) == "table" and allowPlantClimb then
        for plantKey, watch in pairs(plantWatches) do
            if type(watch) == "table" and watch.enabled == true
                and (Watch.ShouldAutoGrowPlant == nil or Watch.ShouldAutoGrowPlant(plantKey) == true)
            then
                local watchPlantUid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
                watchPlantUid = tonumber(watchPlantUid) or 0
                if watchPlantUid > 0 then
                    local d = CP.DescribePlantWatchClimb(watchPlantUid)
                    if d.eligible == true and d.pending == true then
                        Consider(d.spec, 1, watchPlantUid, {
                            needReq = d.climbNeedReq,
                            seedUid = d.seedUid,
                            ladder = d.ladder,
                            watchPlantUid = watchPlantUid,
                        })
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return (tonumber(a.short) or 0) > (tonumber(b.short) or 0)
    end)
    return out
end

local function UpgradeTargetsCacheKey()
    local Inv = StockPiler4.Inventory
    local Watch = StockPiler4.Watch
    local snapGen = 0
    local watchGen = 0
    if Inv and Inv.GetSnapGen then
        snapGen = tonumber(Inv.GetSnapGen()) or 0
    end
    if Watch and Watch.GetGen then
        watchGen = tonumber(Watch.GetGen()) or 0
    end
    -- Cult floor gates ClimbCap; include so skill-ups invalidate without bag churn.
    local cult = 0
    if CP.GetCultSkill then
        cult = math.floor((tonumber(CP.GetCultSkill()) or 0) / 25)
    end
    return tostring(snapGen) .. ":" .. tostring(watchGen) .. ":" .. tostring(cult)
        .. ":" .. tostring(CP.IsEnabled() == true)
        .. ":" .. tostring(CP.WatchesAllowUpgradeClimb() == true)
end

function CP.InvalidateUpgradeTargetsCache()
    CP._upgradeTargetsCache = nil
    CP._upgradeTargetsKey = nil
end

--- Snap/watch-keyed cache over CollectUpgradeTargets (NeedsRefineFirst / PickPlantJob / status).
local function GetUpgradeTargets()
    local key = UpgradeTargetsCacheKey()
    if CP._upgradeTargetsKey == key and type(CP._upgradeTargetsCache) == "table" then
        return CP._upgradeTargetsCache
    end
    local out = CollectUpgradeTargets()
    CP._upgradeTargetsCache = out
    CP._upgradeTargetsKey = key
    return out
end

function CP.NeedsRefineFirst()
    if CP.IsEnabled() ~= true then
        return false
    end
    local targets = GetUpgradeTargets()
    local anyRefine = false
    local anyPlantable = false
    for i = 1, #targets do
        local t = targets[i]
        local climbCap = CP.ClimbCap(t.needReq)
        if climbCap < t.needReq and climbCap < 1 then
            -- gated
        else
            local up = TargetUpgradePlant(t)
            if type(up) == "table" and (tonumber(up.plantUid) or 0) > 0 then
                anyRefine = true
            end
            local plantable = TargetPlantableCount(t)
            if (tonumber(plantable) or 0) >= 1 then
                anyPlantable = true
            end
        end
    end
    -- Only skip demand/plant when refine is the only climb work.
    -- Spumepetal refine must not starve Fusk (or other) plantable climb seeds.
    return anyRefine == true and anyPlantable ~= true
end

--- Hold empty plots for climb status only when no target has plantable seeds
--- or refinable plants (need_buy / climbing must not starve another genus).
function CP.ShouldHoldEmptyPlots(climb)
    if CP.IsEnabled() ~= true then
        return false
    end
    local why = tostring(type(climb) == "table" and climb.why or "")
    if why == "refining" then
        -- Refine armed and PickPlantJob found no plantable elsewhere.
        return true
    end
    if why ~= "climbing" and why ~= "need_buy" and why ~= "no_family" then
        return false
    end
    local targets = GetUpgradeTargets()
    for i = 1, #targets do
        local t = targets[i]
        local plantable = TargetPlantableCount(t)
        if (tonumber(plantable) or 0) >= 1 then
            return false
        end
        local up = TargetUpgradePlant(t)
        if type(up) == "table" and (tonumber(up.plantUid) or 0) > 0 then
            return false
        end
    end
    return true
end

function CP.PickPlantJob()
    if CP.IsEnabled() ~= true then
        CP._active = nil
        return nil
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true) then
        return nil
    end
    if CountEmptyPlots() <= 0 then
        return nil
    end
    local SM = StockPiler4.SeedMap
    local targets = GetUpgradeTargets()
    local refineActive = nil
    local stallActive = nil
    local plantCandidates = {}
    for i = 1, #targets do
        local t = targets[i]
        local needReq = tonumber(t.needReq) or 0
        local climbCap = CP.ClimbCap(needReq)
        local cultFloor = CP.FloorCultTier(CP.GetCultSkill())
        if cultFloor < 1 then
            CP._active = {
                familyKey = t.familyKey,
                haveReq = 0,
                needReq = needReq,
                why = "need_cult",
                genus = t.ladder and t.ladder.genus,
                needCult = needReq,
            }
            return nil
        end
        if type(t.ladder) ~= "table" or type(t.ladder.rungs) ~= "table" or #t.ladder.rungs == 0 then
            stallActive = stallActive or {
                familyKey = t.familyKey,
                haveReq = 0,
                needReq = needReq,
                why = "no_family",
                genus = SM and SM.GenusKeyFromName and SM.GenusKeyFromName(t.spec and t.spec.name),
            }
        else
            local up, ownedReq = TargetUpgradePlant(t)
            local upgradePlantReq = 0
            if type(up) == "table" and (tonumber(up.plantUid) or 0) > 0 then
                upgradePlantReq = tonumber(up.skillReq) or 0
                if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                    StockPiler4.Refine.MarkRefineDue("upgrade-seed")
                end
                refineActive = refineActive or {
                    familyKey = t.ladder.key,
                    haveReq = ownedReq,
                    needReq = needReq,
                    why = "refining",
                    genus = t.ladder.genus,
                }
                -- Continue: another family (e.g. Fusk) may still have plantable seeds.
            end
            local plantable, owned = TargetPlantableCount(t)
            if type(owned) == "table" and (tonumber(owned.seedUid) or 0) > 0 then
                local seedUid = tonumber(owned.seedUid) or 0
                ownedReq = tonumber(owned.skillReq) or 0
                local budget = SeedBudget(seedUid)
                local headroom = tonumber(budget.headroom) or 0
                local buffer = tonumber(budget.bufferMin) or 0
                local bagSeeds = tonumber(owned.count) or 0
                local empty = CountEmptyPlots()
                local plantUid = tonumber(owned.plantUid) or 0
                local refinable = 0
                if plantUid > 0 and StockPiler4.Refine and StockPiler4.Refine.CountRefinablePlants then
                    local Items = StockPiler4.Items
                    local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
                    refinable = tonumber(StockPiler4.Refine.CountRefinablePlants(plantUid, spec)) or 0
                end
                local intermediate = IsIntermediateClimb(t.ladder, ownedReq)
                -- Do not plant a lower rung while higher-tier plants sit in bag
                -- (L1 Fusk 3010030 filled all plots while Cloudy Fusk waited to refine).
                local plantGoesBackward = upgradePlantReq > ownedReq
                local plotCredit = 0
                local Grow = StockPiler4.Grow
                if Grow and Grow.CountSeedPlotCredit then
                    plotCredit = tonumber(Grow.CountSeedPlotCredit(seedUid)) or 0
                elseif Grow and Grow.CountInGroundSeeds then
                    plotCredit = tonumber(Grow.CountInGroundSeeds(seedUid)) or 0
                end
                local settleDeferred = false
                if StockPiler4.Refine and StockPiler4.Refine.SeedBufferSettleDeferred then
                    settleDeferred = StockPiler4.Refine.SeedBufferSettleDeferred(seedUid) == true
                else
                    settleDeferred = plotCredit > 0 and empty < 1
                end
                -- Buffer refine wake: allow while empty plots remain (shared settle rule).
                if buffer > 0 and headroom > 0 and refinable > 0
                    and settleDeferred ~= true
                    and (not intermediate or bagSeeds < 1)
                then
                    if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                        StockPiler4.Refine.MarkRefineDue("upgrade-seed-buffer")
                    end
                    refineActive = refineActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "refining",
                        genus = t.ladder.genus,
                    }
                elseif plantable < 1 and empty > 0 and refinable > 0 then
                    if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                        StockPiler4.Refine.MarkRefineDue("upgrade-seed-reseed")
                    end
                    refineActive = refineActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "refining",
                        genus = t.ladder.genus,
                    }
                elseif plantable >= 1 and plantGoesBackward ~= true then
                    plantCandidates[#plantCandidates + 1] = {
                        seedUid = seedUid,
                        plantUid = plantUid,
                        bagSeeds = bagSeeds,
                        plantable = plantable,
                        ownedReq = ownedReq,
                        needReq = needReq,
                        short = tonumber(t.short) or 0,
                        intermediate = intermediate == true,
                        familyKey = t.ladder.key,
                        genus = t.ladder.genus,
                        targetIndex = i,
                    }
                elseif plantable >= 1 and plantGoesBackward == true then
                    if StockPiler4.Refine and StockPiler4.Refine.MarkRefineDue then
                        StockPiler4.Refine.MarkRefineDue("upgrade-seed-no-backslide")
                    end
                    refineActive = refineActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "refining",
                        genus = t.ladder.genus,
                    }
                elseif empty < 1 then
                    stallActive = stallActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "climbing",
                        genus = t.ladder.genus,
                    }
                elseif climbCap < needReq and ownedReq >= climbCap then
                    stallActive = stallActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "need_cult",
                        genus = t.ladder.genus,
                        needCult = needReq,
                    }
                elseif not intermediate and CP.SeedDeficit(seedUid) >= 1 then
                    stallActive = stallActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "need_buy",
                        genus = t.ladder.genus,
                    }
                else
                    stallActive = stallActive or {
                        familyKey = t.ladder.key,
                        haveReq = ownedReq,
                        needReq = needReq,
                        why = "climbing",
                        genus = t.ladder.genus,
                    }
                end
            elseif climbCap < needReq and ownedReq >= climbCap and ownedReq > 0 then
                stallActive = stallActive or {
                    familyKey = t.ladder.key,
                    haveReq = ownedReq,
                    needReq = needReq,
                    why = "need_cult",
                    genus = t.ladder.genus,
                    needCult = needReq,
                }
            else
                stallActive = stallActive or {
                    familyKey = t.ladder.key,
                    haveReq = ownedReq,
                    needReq = needReq,
                    why = "need_buy",
                    genus = t.ladder.genus,
                }
            end
        end
    end
    if #plantCandidates > 0 then
        -- Prefer the behind family (lowest owned seed rung), not the largest potion short.
        -- Spumepetal@150 with short=24 used to starve Fusk@125 before any Fusk seeds landed.
        table.sort(plantCandidates, function(a, b)
            local oa = tonumber(a.ownedReq) or 0
            local ob = tonumber(b.ownedReq) or 0
            if oa ~= ob then
                return oa < ob
            end
            return (tonumber(a.short) or 0) > (tonumber(b.short) or 0)
        end)
        local function SiblingBehind(cand)
            for i = 1, #targets do
                if i ~= (tonumber(cand.targetIndex) or 0) then
                    local t2 = targets[i]
                    local owned2 = CP.PickBestOwnedSeed({
                        ladder = t2.ladder,
                        climbCap = CP.ClimbCap(t2.needReq),
                    })
                    local req2 = type(owned2) == "table" and (tonumber(owned2.skillReq) or 0) or 0
                    if req2 < (tonumber(cand.ownedReq) or 0) then
                        return true
                    end
                end
            end
            return false
        end
        local function PlotsHoldingSeed(seedUid)
            seedUid = tonumber(seedUid) or 0
            if seedUid <= 0 then
                return 0
            end
            local Grow = StockPiler4.Grow
            if Grow and Grow.CountSeedPlotCredit then
                return tonumber(Grow.CountSeedPlotCredit(seedUid)) or 0
            end
            if Grow and Grow.CountInGroundSeeds then
                return tonumber(Grow.CountInGroundSeeds(seedUid)) or 0
            end
            return 0
        end
        local best = nil
        for ci = 1, #plantCandidates do
            local cand = plantCandidates[ci]
            local behind = SiblingBehind(cand)
            -- Cap is per-wave, not per-job: plantable=1 still re-picked every tick and
            -- filled all 4 plots. Skip an ahead family that already holds a plot.
            if behind == true and cand.intermediate == true
                and PlotsHoldingSeed(cand.seedUid) >= 1
            then
                cand = nil
            end
            if cand ~= nil then
                best = cand
                if behind == true and best.intermediate == true then
                    best.plantable = 1
                end
                break
            end
        end
        if best == nil then
            -- Ahead family already occupies a plot; leave empties for the behind family.
            if refineActive then
                CP._active = refineActive
            elseif stallActive then
                CP._active = stallActive
            end
            return nil
        end
        CP._active = {
            familyKey = best.familyKey,
            haveReq = best.ownedReq,
            needReq = best.needReq,
            why = "planting",
            genus = best.genus,
            seedUid = best.seedUid,
            plantUid = best.plantUid,
        }
        CP._stallLatch = nil
        local Inv = StockPiler4.Inventory
        local sample = Inv and Inv.GetSample and Inv.GetSample(best.seedUid)
        return {
            seedUid = best.seedUid,
            plantUid = best.plantUid,
            seed = sample or { uniqueID = best.seedUid },
            seedHave = best.bagSeeds,
            plantable = tonumber(best.plantable) or 1,
            deficit = tonumber(best.plantable) or 1,
            plantReason = "upgrade_seed",
            pickMode = "upgrade_seed",
            familyKey = best.familyKey,
            skillReq = best.ownedReq,
            needReq = best.needReq,
        }
    end
    if refineActive then
        CP._active = refineActive
        return nil
    end
    if stallActive then
        CP._active = stallActive
    end
    return nil
end

function CP.AppendRefineIntents(intents, appendFn)
    if type(appendFn) ~= "function" then
        return
    end
    if CP.IsEnabled() ~= true then
        return
    end
    local targets = GetUpgradeTargets()
    local SM = StockPiler4.SeedMap
    for i = 1, #targets do
        local t = targets[i]
        if type(t.ladder) == "table" then
            local climbCap = CP.ClimbCap(t.needReq)
            local owned = CP.PickBestOwnedSeed({
                ladder = t.ladder,
                climbCap = climbCap,
            })
            local ownedReq = type(owned) == "table" and (tonumber(owned.skillReq) or 0) or 0
            local refineCap = CP.FloorCultTier(CP.GetCultSkill())
            if refineCap < climbCap then
                refineCap = climbCap
            end
            local up = CP.ScanUpgradePlant({
                ladder = t.ladder,
                climbCap = refineCap,
                ownedSeedReq = ownedReq,
            })
            if type(up) == "table" and (tonumber(up.plantUid) or 0) > 0 then
                local seedUid = tonumber(up.seedUid) or 0
                local plantUid = tonumber(up.plantUid) or 0
                if seedUid <= 0 and SM and SM.ResolveSeedUidForPlant then
                    seedUid = tonumber(SM.ResolveSeedUidForPlant(plantUid, nil)) or 0
                end
                local budget = SeedBudget(seedUid)
                local Items = StockPiler4.Items
                local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
                local Refine = StockPiler4.Refine
                local refinable = tonumber(up.refinable) or 0
                if refinable < 1 and Refine and Refine.CountRefinablePlants then
                    refinable = tonumber(Refine.CountRefinablePlants(plantUid, spec)) or 0
                end
                local uses = math.min(refinable, 5)
                if uses >= 1 then
                    appendFn({
                        spec = spec,
                        seedUid = seedUid,
                        plantUid = plantUid,
                        specKey = "upgrade_seed:" .. tostring(seedUid),
                    }, "upgrade-seed", uses, budget)
                    return
                end
            end
            -- Buffer refine for owned climb seed (settle only when garden full;
            -- empty plots still refine up to headroom — see SeedBufferSettleDeferred).
            if type(owned) == "table" and (tonumber(owned.seedUid) or 0) > 0 then
                local seedUid = tonumber(owned.seedUid) or 0
                local plantUid = tonumber(owned.plantUid) or 0
                local Refine = StockPiler4.Refine
                local settleDeferred = false
                if Refine and Refine.SeedBufferSettleDeferred then
                    settleDeferred = Refine.SeedBufferSettleDeferred(seedUid) == true
                else
                    local Grow = StockPiler4.Grow
                    if Grow and Grow.CountSeedPlotCredit then
                        settleDeferred = (tonumber(Grow.CountSeedPlotCredit(seedUid)) or 0) > 0
                    end
                end
                local budget = SeedBudget(seedUid)
                local headroom = tonumber(budget.headroom) or 0
                if headroom > 0 and plantUid > 0 and settleDeferred ~= true then
                    local Items = StockPiler4.Items
                    local spec = Items and Items.ToSpec and Items.ToSpec(plantUid) or nil
                    local refinable = 0
                    if Refine and Refine.CountRefinablePlants then
                        refinable = tonumber(Refine.CountRefinablePlants(plantUid, spec)) or 0
                    end
                    local uses = math.min(refinable, headroom, 5)
                    if uses >= 1 then
                        appendFn({
                            spec = spec,
                            seedUid = seedUid,
                            plantUid = plantUid,
                            specKey = "upgrade_seed:" .. tostring(seedUid),
                        }, "upgrade-seed-buffer", uses, budget)
                        return
                    end
                end
            end
        end
    end
end

function CP.CollectBuyJobs()
    local jobs = {}
    if CP.IsEnabled() ~= true then
        return jobs
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
        return jobs
    end
    local SM = StockPiler4.SeedMap
    local targets = GetUpgradeTargets()
    local seenBuy = {}
    for i = 1, #targets do
        local t = targets[i]
        if type(t.ladder) == "table" then
            -- L1 vendor seed only for cold-start / wiped vendor rung.
            -- Owning mid/high seeds (Spumepetal@150+) must not trigger L1 top-up:
            -- SeedDeficit(L1) only counts that uid's live stack, so buffer=5 with
            -- live(L1)=0 bought 5x 84235 while L150/L175 seeds were already owned.
            local buy = SM.LowestBuySeedOnLadder and SM.LowestBuySeedOnLadder(t.ladder) or nil
            if type(buy) == "table" and (tonumber(buy.seedUid) or 0) > 0 then
                local seedUid = tonumber(buy.seedUid) or 0
                local buyReq = tonumber(buy.skillReq) or 1
                if buyReq < 1 then
                    buyReq = 1
                end
                local owned = CP.PickBestOwnedSeed({
                    ladder = t.ladder,
                    climbCap = CP.ClimbCap(t.needReq),
                })
                local ownedReq = type(owned) == "table" and (tonumber(owned.skillReq) or 0) or 0
                if ownedReq > buyReq then
                    -- Family already past vendor rung; climb via plant/refine only.
                elseif seenBuy[seedUid] ~= true then
                    local deficit = CP.SeedDeficit(seedUid)
                    if deficit >= 1 then
                        seenBuy[seedUid] = true
                        local MS = StockPiler4.MaterialSpec
                        local Inv = StockPiler4.Inventory
                        local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
                        local spec = nil
                        if MS and MS.FromItemData and type(sample) == "table" then
                            spec = MS.FromItemData(sample, tostring(t.ladder.role or "main"))
                        elseif MS and MS.FromUid then
                            spec = MS.FromUid(seedUid)
                        end
                        jobs[#jobs + 1] = {
                            uid = seedUid,
                            uniqueID = seedUid,
                            deficit = deficit,
                            upgradeSeed = true,
                            skillUp = true, -- allow growable purchase path
                            growable = true,
                            isGrowable = true,
                            role = tostring(t.ladder.role or "main"),
                            spec = spec or t.spec,
                            specKey = "upgrade_seed:" .. tostring(seedUid),
                            acquireKey = "upgrade_seed:" .. tostring(seedUid),
                            skillReq = buyReq,
                            familyKey = t.ladder.key,
                        }
                    end
                end
            end
            -- Never AutoBuy intermediate climb seeds (L25/L50/...) - vendor only sells L1.
            -- Progress those rungs via plant / crit / refine.
        end
    end
    return jobs
end

function CP.MaybeNotifyStall()
    if CP.IsEnabled() ~= true then
        CP._stallLatch = nil
        return
    end
    local active = CP._active
    if type(active) ~= "table" then
        CP._stallLatch = nil
        return
    end
    local why = tostring(active.why or "")
    -- Progress: clear latch so a later real stall can warn once.
    if why == "planting" then
        CP._stallLatch = nil
        return
    end
    -- Refining / waiting on plots: not a user-action stall. Keep any latch so
    -- need_buy <-> climbing <-> refining flicker cannot spam chat.
    if why == "refining" or why == "climbing" then
        return
    end
    local reason = why
    if reason == "" then
        reason = "need_buy"
    end
    if reason == "need_buy" then
        local Watch = StockPiler4.Watch
        if not (Watch and Watch.IsAutoBuyEnabled and Watch.IsAutoBuyEnabled() == true) then
            reason = "autobuy_off"
        else
            local VA = StockPiler4.VendorAdapter
            if VA and VA.IsStoreOpen and VA.IsStoreOpen() == true then
                -- Vendor open / AutoBuy can run - not a stall warn.
                return
            end
            reason = "need_vendor"
        end
    end
    -- One chat warn per stall episode (any reason). Reason flips must not re-fire.
    if CP._stallLatch ~= nil then
        return
    end
    CP._stallLatch = reason
    local genus = tostring(active.genus or "seed")
    local haveReq = tonumber(active.haveReq) or 0
    local needReq = tonumber(active.needReq) or 0
    local msg
    if StockPiler4.T then
        msg = StockPiler4.T("upgrade.stall." .. reason, {
            genus = genus,
            have = haveReq,
            need = needReq,
            cult = tonumber(active.needCult) or needReq,
        })
    else
        msg = L"<icon02486> Upgrade seed stalled."
    end
    if StockPiler4.Debug and StockPiler4.Debug.Notify then
        StockPiler4.Debug.Notify(msg)
    elseif StockPiler4.Debug and StockPiler4.Debug.Print then
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

function CP.GetActiveStatus()
    return CP._active
end

--- Best owned seed/plant skillReq on a ladder at or below climbCap.
--- Counts bag and in-ground seeds (plot credit) so status matches seed-buffer plant.
local function BestOwnedReqOnLadder(ladder, climbCap)
    climbCap = tonumber(climbCap) or 0
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" or climbCap < 1 then
        return 0
    end
    local Inv = StockPiler4.Inventory
    if not (Inv and Inv.CountByUid) then
        return 0
    end
    local Grow = StockPiler4.Grow
    local best = 0
    for i = 1, #ladder.rungs do
        local rung = ladder.rungs[i]
        local req = tonumber(rung.skillReq) or 0
        if req >= 1 and req <= climbCap then
            local seedUid = tonumber(rung.seedUid) or 0
            local plantUid = tonumber(rung.plantUid) or 0
            local have = false
            if seedUid > 0 and (tonumber(Inv.CountByUid(seedUid)) or 0) >= 1 then
                have = true
            elseif plantUid > 0 and (tonumber(Inv.CountByUid(plantUid)) or 0) >= 1 then
                have = true
            elseif seedUid > 0 and Grow then
                local ground = 0
                if Grow.CountSeedPlotCredit then
                    ground = tonumber(Grow.CountSeedPlotCredit(seedUid)) or 0
                elseif Grow.CountInGroundSeeds then
                    ground = tonumber(Grow.CountInGroundSeeds(seedUid)) or 0
                end
                if ground >= 1 then
                    have = true
                end
            end
            if have and req > best then
                best = req
            end
        end
    end
    return best
end

local function RebuildWatchStatusCache()
    local frame = tonumber(StockPiler4.FrameCounter) or 0
    if CP._statusCacheFrame == frame and type(CP._statusByPlant) == "table" then
        return
    end
    CP._statusCacheFrame = frame
    CP._statusByPlant = {}
    CP._statusByGenus = {}
    if CP.IsEnabled() ~= true then
        CP._active = nil
        return
    end
    local targets = GetUpgradeTargets()
    if #targets < 1 then
        -- Climb done / no targets: always clear latch. Keeping planting/refining
        -- here made ApplySeedBufferStatus re-paint upgrading_seed via GetActiveStatus.
        CP._active = nil
        return
    end
    for i = 1, #targets do
        local t = targets[i]
        local needReq = tonumber(t.needReq) or 0
        local climbCap = CP.ClimbCap(needReq)
        local haveReq = BestOwnedReqOnLadder(t.ladder, climbCap)
        local watchPlantUid = tonumber(t.watchPlantUid) or 0
        local bufferDone = true
        if watchPlantUid > 0 then
            bufferDone = CultMaxTierBufferFull(t.ladder, needReq, t.plantUid, t.seedUid) == true
        end
        -- Target rung owned and (non-plant-watch or Cult-max buffer full): idle.
        if haveReq >= needReq and needReq >= 1 and bufferDone then
            -- Seed-buffer / restock paths own the row status.
        else
            local why = "climbing"
            if haveReq < 1 then
                why = "need_buy"
            elseif climbCap < needReq and haveReq >= climbCap then
                why = "need_cult"
            elseif haveReq >= needReq and bufferDone ~= true then
                -- Own Cult-max seeds/plants but seed buffer still short.
                why = "climbing"
            end
            local genus = t.ladder and t.ladder.genus or nil
            local st = {
                familyKey = t.familyKey or (t.ladder and t.ladder.key),
                genus = genus,
                haveReq = haveReq,
                needReq = needReq,
                climbCap = climbCap,
                why = why,
                plantUid = tonumber(t.plantUid) or 0,
                seedUid = tonumber(t.seedUid) or 0,
            }
            local plantUid = tonumber(t.plantUid) or 0
            if plantUid > 0 then
                CP._statusByPlant[plantUid] = st
            end
            -- Plant watches keep the low-tier uid in the UI; map status there too.
            if watchPlantUid > 0 and watchPlantUid ~= plantUid then
                CP._statusByPlant[watchPlantUid] = st
            end
            if genus and genus ~= "" then
                CP._statusByGenus[genus] = st
            end
            -- Keep _active filled so stalls / dumps reflect the climb even when
            -- Grow planted via plant_stock rather than upgrade_seed.
            if i == 1 then
                local curWhy = type(CP._active) == "table" and tostring(CP._active.why or "") or ""
                if curWhy ~= "planting" and curWhy ~= "refining" then
                    CP._active = st
                end
            end
        end
    end
end

--- Merge live PickPlantJob/_active action onto a status snapshot for tips.
local function WithLiveActive(st)
    if type(st) ~= "table" then
        return st
    end
    local active = CP._active
    if type(active) ~= "table" then
        return st
    end
    local sameGenus = tostring(active.genus or "") ~= ""
        and tostring(active.genus) == tostring(st.genus or "")
    local sameFamily = tostring(active.familyKey or "") ~= ""
        and tostring(active.familyKey) == tostring(st.familyKey or "")
    if not sameGenus and not sameFamily then
        return st
    end
    local why = tostring(active.why or "")
    if why ~= "planting" and why ~= "refining" and why ~= "need_buy"
        and why ~= "need_cult" and why ~= "climbing" and why ~= "no_family"
    then
        return st
    end
    return {
        familyKey = st.familyKey or active.familyKey,
        genus = st.genus or active.genus,
        haveReq = tonumber(active.haveReq) or tonumber(st.haveReq) or 0,
        needReq = tonumber(st.needReq) or tonumber(active.needReq) or 0,
        climbCap = tonumber(st.climbCap) or tonumber(active.climbCap) or 0,
        why = why,
        plantUid = tonumber(active.plantUid) or tonumber(st.plantUid) or 0,
        seedUid = tonumber(active.seedUid) or 0,
        live = true,
    }
end

--- UI: climb status for a plant watch (or genus), or nil if not climbing.
function CP.StatusForPlant(plantUid, spec)
    if CP.IsEnabled() ~= true then
        return nil
    end
    RebuildWatchStatusCache()
    plantUid = tonumber(plantUid) or 0
    if plantUid > 0 and type(CP._statusByPlant[plantUid]) == "table" then
        return WithLiveActive(CP._statusByPlant[plantUid])
    end
    local SM = StockPiler4.SeedMap
    local genus = nil
    if type(spec) == "table" and SM and SM.GenusKeyFromName then
        genus = SM.GenusKeyFromName(spec.name)
        if (not genus or genus == "") and SM.GetGenusLadderForSpec then
            local ladder = SM.GetGenusLadderForSpec(spec)
            genus = ladder and ladder.genus
        end
    end
    if genus and genus ~= "" and type(CP._statusByGenus[genus]) == "table" then
        return WithLiveActive(CP._statusByGenus[genus])
    end
    return nil
end

--- UI: climb status for potion seed-buffer rows.
--- Prefer the live active genus so the tip matches what AutoGrow is doing.
function CP.StatusForWatch()
    if CP.IsEnabled() ~= true then
        return nil
    end
    RebuildWatchStatusCache()
    local active = CP._active
    if type(active) == "table" then
        local genus = tostring(active.genus or "")
        if genus ~= "" and type(CP._statusByGenus) == "table"
            and type(CP._statusByGenus[genus]) == "table"
        then
            return WithLiveActive(CP._statusByGenus[genus])
        end
        local why = tostring(active.why or "")
        if why == "planting" or why == "refining" or why == "need_buy"
            or why == "need_cult" or why == "climbing"
        then
            return WithLiveActive({
                familyKey = active.familyKey,
                genus = active.genus,
                haveReq = tonumber(active.haveReq) or 0,
                needReq = tonumber(active.needReq) or 0,
                climbCap = tonumber(active.climbCap) or 0,
                why = why,
                plantUid = tonumber(active.plantUid) or 0,
                seedUid = tonumber(active.seedUid) or 0,
            })
        end
    end
    if type(CP._statusByGenus) == "table" then
        for _, st in pairs(CP._statusByGenus) do
            if type(st) == "table" then
                return WithLiveActive(st)
            end
        end
    end
    return nil
end

--- All live climb statuses (one per genus), for multi-family tips.
function CP.ListClimbStatuses()
    if CP.IsEnabled() ~= true then
        return {}
    end
    RebuildWatchStatusCache()
    local out = {}
    local seen = {}
    if type(CP._statusByGenus) == "table" then
        for genus, st in pairs(CP._statusByGenus) do
            if type(st) == "table" and seen[tostring(genus)] ~= true then
                seen[tostring(genus)] = true
                out[#out + 1] = WithLiveActive(st)
            end
        end
    end
    table.sort(out, function(a, b)
        local ga = tostring(a and a.genus or "")
        local gb = tostring(b and b.genus or "")
        if ga ~= gb then
            return ga < gb
        end
        return (tonumber(a and a.needReq) or 0) < (tonumber(b and b.needReq) or 0)
    end)
    return out
end

local function ClimbCapShow(climb)
    local needReq = tonumber(climb and climb.needReq) or 0
    local climbCap = tonumber(climb and climb.climbCap) or 0
    if climbCap < 1 and CP.ClimbCap then
        climbCap = CP.ClimbCap(needReq) or needReq
    end
    local capShow = climbCap
    if needReq > 0 and needReq < capShow then
        capShow = needReq
    end
    return capShow, needReq, tonumber(climb and climb.haveReq) or 0
end

--- Short parenthetical for tip Have/Need notes (per recipe slot).
function CP.FormatClimbSlotNote(climb)
    if type(climb) ~= "table" then
        return nil
    end
    local why = tostring(climb.why or "")
    if why ~= "planting" and why ~= "refining" and why ~= "need_buy"
        and why ~= "need_cult" and why ~= "climbing" and why ~= "no_family"
    then
        return nil
    end
    local genus = tostring(climb.genus or "seed")
    local capShow, needReq, haveReq = ClimbCapShow(climb)
    local T = function(key, tokens)
        return StockPiler4.Util.T(key, tokens)
    end
    if why == "planting" then
        return T("watch.note.climb_planting", {
            genus = genus,
            have = tostring(haveReq),
        })
    end
    if why == "refining" then
        return T("watch.note.climb_refining", {
            genus = genus,
            have = tostring(haveReq),
        })
    end
    if why == "need_buy" then
        return T("watch.note.climb_buy", { genus = genus })
    end
    if why == "need_cult" or (needReq > 0 and capShow > 0 and capShow < needReq) then
        return T("watch.note.climb_cult", {
            genus = genus,
            need = tostring(needReq),
            floor = tostring(capShow),
        })
    end
    return T("watch.note.climb_progress", {
        genus = genus,
        have = tostring(haveReq),
        cap = tostring(capShow),
    })
end

local function TUpgrade(key, tokens)
    if StockPiler4.Util and StockPiler4.Util.T then
        return StockPiler4.Util.T(key, tokens)
    end
    return towstring(tostring(key))
end

--- True when any plant-watch Cult-max climb job may run (idle gate + pending).
function CP.IsActivelyClimbingPlantWatches()
    if CP.WatchesAllowUpgradeClimb() ~= true then
        return false
    end
    local Watch = StockPiler4.Watch
    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) ~= "table" then
        return false
    end
    for plantKey, watch in pairs(plantWatches) do
        if type(watch) == "table" and watch.enabled == true then
            local uid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
            uid = tonumber(uid) or 0
            if uid > 0 then
                local d = CP.DescribePlantWatchClimb(uid)
                if d.eligible == true and d.pending == true then
                    return true
                end
            end
        end
    end
    return false
end

function CP.ShouldShowWatchStatus()
    return CP.IsEnabled() == true
end

--- Ephemeral Watch-tab rows for plant-watch Cult-max climbs. Never saved.
function CP.BuildWatchStatusRows()
    local rows = {}
    if CP.IsEnabled() ~= true then
        return rows
    end
    local Watch = StockPiler4.Watch
    local Items = StockPiler4.Items
    local Inv = StockPiler4.Inventory
    local plantWatches = Watch and Watch.GetPlantWatches and Watch.GetPlantWatches() or {}
    if type(plantWatches) ~= "table" then
        return rows
    end
    local agOn = Watch and Watch.IsAutoGrowEnabled and Watch.IsAutoGrowEnabled() == true
    local allow = CP.WatchesAllowUpgradeClimb() == true
    local list = {}
    for plantKey, watch in pairs(plantWatches) do
        if type(watch) == "table" and watch.enabled == true then
            list[#list + 1] = { plantKey = tostring(plantKey), watch = watch }
        end
    end
    table.sort(list, function(a, b)
        return tostring(a.plantKey) < tostring(b.plantKey)
    end)
    local dash = TUpgrade("ui.dash")
    for i = 1, #list do
        local plantKey = list[i].plantKey
        local watchPlantUid = Watch.ParsePlantKey and Watch.ParsePlantKey(plantKey) or 0
        watchPlantUid = tonumber(watchPlantUid) or 0
        if watchPlantUid > 0 then
            local d = CP.DescribePlantWatchClimb(watchPlantUid)
            if d.eligible == true and d.pending == true then
                local name = nil
                local iconNum = 0
                local itemData = nil
                if Items and Items.GetByUid then
                    local item = Items.GetByUid(watchPlantUid)
                    if type(item) == "table" then
                        name = item.name
                        iconNum = tonumber(item.iconNum) or 0
                        itemData = item.itemData or item
                    end
                end
                if Inv and Inv.GetSample then
                    local sample = Inv.GetSample(watchPlantUid)
                    if type(sample) == "table" then
                        itemData = sample
                        iconNum = tonumber(sample.iconNum) or iconNum
                        if sample.name ~= nil then
                            name = sample.name
                        end
                    end
                end
                if name == nil then
                    name = towstring("Upgrade " .. tostring(watchPlantUid))
                end
                local genus = d.ladder and d.ladder.genus or "seed"
                local climbCap = CP.ClimbCap(d.climbNeedReq)
                local statusKey = "waiting_watches"
                local statusText = TUpgrade("upgrade.watch.waiting_watches")
                local statusLines = {
                    TUpgrade("upgrade.watch.tip"),
                    TUpgrade("upgrade.watch.ag_tip"),
                }
                if allow ~= true then
                    local potionShort = Watch.AllEnabledPotionWatchesStocked
                        and Watch.AllEnabledPotionWatchesStocked() ~= true
                    local bufferShort = SeedBufferOkForIdle() ~= true
                    if potionShort and not bufferShort then
                        statusKey = "waiting_potions"
                        statusText = TUpgrade("upgrade.watch.waiting_potions")
                    elseif bufferShort and not potionShort then
                        statusKey = "waiting_seed_buffer"
                        statusText = TUpgrade("upgrade.watch.waiting_seed_buffer")
                    end
                    statusLines[#statusLines + 1] = TUpgrade("upgrade.watch.waiting_tip")
                elseif agOn ~= true then
                    statusKey = "enable_autogrow"
                    statusText = TUpgrade("plan.status.enable_autogrow")
                else
                    local climb = CP.StatusForPlant(watchPlantUid, d.spec)
                    local why = type(climb) == "table" and tostring(climb.why or "") or "climbing"
                    local haveReq = type(climb) == "table" and (tonumber(climb.haveReq) or 0) or 0
                    if why == "need_buy" then
                        statusKey = "need_buy"
                        statusText = TUpgrade("upgrade.watch.need_buy", { genus = genus })
                    elseif why == "need_cult" then
                        statusKey = "need_cult"
                        statusText = TUpgrade("upgrade.watch.need_cult", {
                            genus = genus,
                            need = tostring(d.climbNeedReq),
                            floor = tostring(climbCap),
                        })
                    elseif why == "refining" then
                        statusKey = "refining"
                        statusText = TUpgrade("upgrade.watch.refining", { genus = genus })
                    elseif why == "planting" then
                        statusKey = "planting"
                        statusText = TUpgrade("upgrade.watch.planting", { genus = genus })
                    else
                        statusKey = "upgrading_seed"
                        statusText = TUpgrade("plan.status.upgrading_seed_progress", {
                            genus = genus,
                            have = tostring(haveReq),
                            cap = tostring(climbCap),
                        })
                    end
                    statusLines[#statusLines + 1] = TUpgrade("upgrade.watch.tier_line", {
                        have = tostring(haveReq),
                        need = tostring(d.climbNeedReq),
                        floor = tostring(climbCap),
                    })
                end
                local id = "upgrade_seed:" .. tostring(watchPlantUid)
                rows[#rows + 1] = {
                    id = id,
                    potionKey = id,
                    potionRecipeKey = id,
                    kind = "upgrade",
                    upgradeWatch = true,
                    addonOwned = true,
                    skillUp = false,
                    isPlantWatch = false,
                    watchPlantUid = watchPlantUid,
                    plantUid = watchPlantUid,
                    seedUid = d.seedUid,
                    name = TUpgrade("upgrade.watch.name", { name = name }),
                    iconNum = iconNum,
                    itemData = itemData,
                    uniqueID = watchPlantUid,
                    potionHave = d.have,
                    stockText = dash,
                    target = d.climbNeedReq,
                    potionMin = d.climbNeedReq,
                    potionDeficit = 0,
                    targetText = dash,
                    priorityTier = 0,
                    priorityTierText = L"-",
                    plantPrioSentinel = true,
                    autoGrow = agOn == true,
                    hideAutoGrow = false,
                    hideBrew = true,
                    hideCraftable = true,
                    craftable = 0,
                    craftableText = L"",
                    statusKey = statusKey,
                    statusText = statusText,
                    statusLines = statusLines,
                    skillReq = d.climbNeedReq,
                    nameR = 255,
                    nameG = 255,
                    nameB = 255,
                }
            end
        end
    end
    return rows
end

function CP.Dump(emit)
    emit = emit or print
    emit("--- upgrade seed ---")
    emit("  enabled=" .. tostring(CP.IsEnabled() == true))
    local cult = CP.GetCultSkill()
    emit("  cultSkill=" .. tostring(cult)
        .. " cultFloor=" .. tostring(CP.FloorCultTier(cult)))
    local targets = GetUpgradeTargets()
    emit("  targets=" .. tostring(#targets))
    for i = 1, math.min(5, #targets) do
        local t = targets[i]
        local rungN = (type(t.ladder) == "table" and type(t.ladder.rungs) == "table")
            and #t.ladder.rungs or 0
        emit(string.format(
            "  target[%d] genus=%s needReq=%s short=%s plant=%s seed=%s rungs=%s key=%s",
            i,
            tostring(t.ladder and t.ladder.genus),
            tostring(t.needReq),
            tostring(t.short),
            tostring(t.plantUid),
            tostring(t.seedUid),
            tostring(rungN),
            tostring(t.familyKey)
        ))
    end
    local active = CP._active
    if type(active) == "table" then
        emit(string.format(
            "  active family=%s genus=%s have=%s need=%s why=%s",
            tostring(active.familyKey),
            tostring(active.genus),
            tostring(active.haveReq),
            tostring(active.needReq),
            tostring(active.why)
        ))
    else
        emit("  active=(none)")
    end
    local jobs = CP.CollectBuyJobs() or {}
    emit("  buyJobs=" .. tostring(#jobs))
    for i = 1, #jobs do
        local j = jobs[i]
        emit(string.format(
            "  buy[%d] uid=%s deficit=%s skillReq=%s family=%s",
            i,
            tostring(j.uid),
            tostring(j.deficit),
            tostring(j.skillReq),
            tostring(j.familyKey)
        ))
    end
    emit("  emptyPlots=" .. tostring(CountEmptyPlots()))
    -- Merged genus ladders for climb targets (from CollectUpgradeTargets cache;
    -- BuildAllFamilyLadders is gen-cached so this stays cheap).
    for i = 1, math.min(5, #targets) do
        local t = targets[i]
        local ladder = t.ladder
        if type(ladder) == "table" and type(ladder.rungs) == "table" then
            local parts = {}
            for r = 1, #ladder.rungs do
                local rung = ladder.rungs[r]
                parts[#parts + 1] = string.format(
                    "%d:s%d/p%d",
                    tonumber(rung.skillReq) or 0,
                    tonumber(rung.seedUid) or 0,
                    tonumber(rung.plantUid) or 0
                )
            end
            emit(string.format(
                "  merged[%s] role=%s %s",
                tostring(ladder.genus or ladder.key),
                tostring(ladder.role),
                table.concat(parts, " ")
            ))
        end
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.DumpFamilies then
        SM.DumpFamilies(emit)
    end
end

-- Deprecated alias; existing callers use StockPiler4.UpgradeSeed until migrated.
StockPiler4.UpgradeSeed = StockPiler4.ClimbPlan

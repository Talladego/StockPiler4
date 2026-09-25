----------------------------------------------------------------
-- StockPiler4 Knowledge/GenusLadder - pure genus ladder queries
-- No UI. SeedMap owns persistence; this module merges/views ladders.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.GenusLadder = StockPiler4.GenusLadder or {}
local GL = StockPiler4.GenusLadder

local function SM()
    return StockPiler4.SeedMap
end

local function Caps()
    return StockPiler4.TradeSkillCaps
end

local function RungCount(ladder)
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" then
        return 0
    end
    return #ladder.rungs
end

--- Merge two genus ladders by skillReq (fill missing seedUid/plantUid from either).
--- Needed when plant vs seed names split genus ("Marsh Root" / "Marshroot").
function GL.MergeGenusLadders(a, b)
    if type(a) ~= "table" or type(a.rungs) ~= "table" then
        return b
    end
    if type(b) ~= "table" or type(b.rungs) ~= "table" then
        return a
    end
    local merged = {
        key = tostring(a.genus or a.key or "x") .. "+merge|*|0",
        genus = a.genus or b.genus,
        role = a.role,
        effectId = tonumber(a.effectId) or tonumber(b.effectId) or 0,
        rungs = {},
        merged = true,
    }
    local roleA = tostring(a.role or "")
    local roleB = tostring(b.role or "")
    if roleA == "" or roleA == "unknown" or roleA == "ingredient" then
        if roleB ~= "" and roleB ~= "unknown" then
            merged.role = b.role
        end
    end
    local byReq = {}
    local function absorb(src)
        for i = 1, #src.rungs do
            local srcRung = src.rungs[i]
            local req = tonumber(srcRung.skillReq) or 0
            if req >= 1 then
                local rung = byReq[req]
                if rung == nil then
                    rung = {
                        skillReq = req,
                        seedUid = 0,
                        plantUid = 0,
                        name = srcRung.name or "",
                    }
                    byReq[req] = rung
                    merged.rungs[#merged.rungs + 1] = rung
                end
                local sUid = tonumber(srcRung.seedUid) or 0
                local pUid = tonumber(srcRung.plantUid) or 0
                if sUid > 0 and (tonumber(rung.seedUid) or 0) <= 0 then
                    rung.seedUid = sUid
                end
                if pUid > 0 and (tonumber(rung.plantUid) or 0) <= 0 then
                    rung.plantUid = pUid
                end
                if (rung.name == nil or rung.name == "") and srcRung.name and srcRung.name ~= "" then
                    rung.name = srcRung.name
                end
            end
        end
    end
    absorb(a)
    absorb(b)
    table.sort(merged.rungs, function(x, y)
        return (tonumber(x.skillReq) or 0) < (tonumber(y.skillReq) or 0)
    end)
    return merged
end

function GL.GetLadder(genus)
    local sm = SM()
    if sm and sm.GetGenusLadder then
        return sm.GetGenusLadder(genus)
    end
    return nil
end

function GL.GetLadderForSpec(spec)
    local sm = SM()
    if sm and sm.GetGenusLadderForSpec then
        return sm.GetGenusLadderForSpec(spec)
    end
    return nil
end

function GL.GetRung(genus, skillReq)
    skillReq = tonumber(skillReq) or 0
    if skillReq < 1 then
        return nil
    end
    local ladder = type(genus) == "table" and genus.rungs and genus or GL.GetLadder(genus)
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" then
        return nil
    end
    for i = 1, #ladder.rungs do
        local rung = ladder.rungs[i]
        if (tonumber(rung.skillReq) or 0) == skillReq then
            return rung
        end
    end
    return nil
end

function GL.BestOwnedRung(genus, climbCap, opts)
    local sm = SM()
    if not sm or not sm.BestOwnedSeedOnLadder then
        return nil
    end
    local ladder = type(genus) == "table" and genus.rungs and genus or GL.GetLadder(genus)
    return sm.BestOwnedSeedOnLadder(ladder, climbCap, opts)
end

function GL.VendorRung(genus)
    local sm = SM()
    if not sm or not sm.LowestBuySeedOnLadder then
        return nil
    end
    local ladder = type(genus) == "table" and genus.rungs and genus or GL.GetLadder(genus)
    return sm.LowestBuySeedOnLadder(ladder)
end

--- Highest ladder skillReq at or below cultFloor (0 if unknown).
function GL.CultMaxNeedReq(ladder, cultFloor)
    cultFloor = tonumber(cultFloor)
    if cultFloor == nil then
        local caps = Caps()
        local cultSkill = caps and caps.GetCultSkill and tonumber(caps.GetCultSkill()) or 0
        cultFloor = caps and caps.FloorCultTier and tonumber(caps.FloorCultTier(cultSkill)) or 0
    end
    if cultFloor < 1 then
        cultFloor = 1
    end
    if type(ladder) ~= "table" or type(ladder.rungs) ~= "table" then
        return 0
    end
    local best = 0
    for i = 1, #ladder.rungs do
        local req = tonumber(ladder.rungs[i].skillReq) or 0
        if req >= 1 and req <= cultFloor and req > best then
            best = req
        end
    end
    return best
end

--- Prefer / merge genus ladders from plant name and linked seed name for climb.
function GL.LadderForPlantWatch(spec, plantUid)
    plantUid = tonumber(plantUid) or 0
    local sm = SM()
    if not sm then
        return nil
    end
    local plantLadder = nil
    if type(spec) == "table" and sm.GetGenusLadderForSpec then
        plantLadder = sm.GetGenusLadderForSpec(spec)
    end
    if type(plantLadder) ~= "table" and type(spec) == "table" and sm.GetFamilyLadderForSpec then
        plantLadder = sm.GetFamilyLadderForSpec(spec)
    end
    local seedLadder = nil
    local seedUid = 0
    if plantUid > 0 and sm.ResolveSeedUidForPlant then
        seedUid = tonumber(sm.ResolveSeedUidForPlant(plantUid, spec)) or 0
    end
    if seedUid > 0 and sm.GenusKeyFromName then
        local Inv = StockPiler4.Inventory
        local Items = StockPiler4.Items
        local seedName = nil
        if Inv and Inv.GetSample then
            local sample = Inv.GetSample(seedUid)
            seedName = sample and sample.name
        end
        if seedName == nil and Items and Items.GetByUid then
            local row = Items.GetByUid(seedUid)
            seedName = row and row.name
        end
        local genus = sm.GenusKeyFromName(seedName)
        if genus and genus ~= "" and sm.GetGenusLadder then
            seedLadder = sm.GetGenusLadder(genus)
        end
    end
    if type(plantLadder) == "table" and type(seedLadder) == "table" then
        return GL.MergeGenusLadders(plantLadder, seedLadder)
    end
    local plantMax = GL.CultMaxNeedReq(plantLadder)
    local seedMax = GL.CultMaxNeedReq(seedLadder)
    if seedMax > plantMax then
        return seedLadder
    end
    if plantMax > seedMax then
        return plantLadder
    end
    if RungCount(seedLadder) > RungCount(plantLadder) then
        return seedLadder
    end
    return plantLadder or seedLadder
end

function GL.GetFamilyLadder(familyKey)
    local sm = SM()
    if sm and sm.GetFamilyLadder then
        return sm.GetFamilyLadder(familyKey)
    end
    return nil
end

function GL.GetFamilyLadderForSpec(spec)
    local sm = SM()
    if sm and sm.GetFamilyLadderForSpec then
        return sm.GetFamilyLadderForSpec(spec)
    end
    return nil
end

function GL.InvalidateCache()
    local sm = SM()
    if sm and sm.InvalidateFamilyLadderCache then
        sm.InvalidateFamilyLadderCache()
    end
end

----------------------------------------------------------------
-- StockPiler4 Knowledge/SkillRates - empirical cult/apo skill-up rates
-- Extracted from SkillUp; SkillUp re-exports for call-site compatibility.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.SkillRates = StockPiler4.SkillRates or {}
local Rates = StockPiler4.SkillRates

local function Caps()
    return StockPiler4.TradeSkillCaps
end

local function GetCultSkill()
    local C = Caps()
    return C and C.GetCultSkill and tonumber(C.GetCultSkill()) or 0
end

local function GetApoSkill()
    local C = Caps()
    return C and C.GetApoSkill and tonumber(C.GetApoSkill()) or 0
end

local function FloorApoTier(apoSkill)
    local C = Caps()
    if C and C.FloorApoTier then
        return C.FloorApoTier(apoSkill)
    end
    apoSkill = tonumber(apoSkill) or 0
    local tiers = { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
    local best = 1
    for i = 1, #tiers do
        if apoSkill >= tiers[i] then
            best = tiers[i]
        end
    end
    return best
end

local function NextApoTier(apoSkill)
    apoSkill = tonumber(apoSkill) or GetApoSkill()
    local tiers = { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
    for i = 1, #tiers do
        if apoSkill < tiers[i] then
            return tiers[i]
        end
    end
    return 200
end

local CULT_MAX = 200
local APO_MAX = 200

local function MirrorPendingToSkillUp()
end


local function NowSec()
    return StockPiler4.Util.NowSec()
end
----------------------------------------------------------------
-- Empirical skill-up rates (per skill level) for buy estimates
----------------------------------------------------------------

Rates.SKILL_RATE_MIN_ATTEMPTS = 5
Rates.SKILL_PENDING_TTL_SEC = 90
Rates.SKILL_RATE_NEARBY_SPAN = 3
Rates.SKILL_RATES_SCHEMA = 2
Rates.APO_VIAL_BUY_CAP = 300


local function RatesTable()
    local Acc = StockPiler4.Account
    if type(Acc) ~= "table" then
        return nil
    end
    local wantV = Rates.SKILL_RATES_SCHEMA or 2
    if type(Acc.skillUpRates) ~= "table" or tonumber(Acc.skillUpRates.v) ~= wantV then
        -- v1 keyed by tier band; wipe so per-level samples are not mixed with averages.
        Acc.skillUpRates = { v = wantV, cult = {}, apo = {} }
    end
    if type(Acc.skillUpRates.cult) ~= "table" then
        Acc.skillUpRates.cult = {}
    end
    if type(Acc.skillUpRates.apo) ~= "table" then
        Acc.skillUpRates.apo = {}
    end
    return Acc.skillUpRates
end

local function LevelBucket(kind, level, create)
    local rates = RatesTable()
    if type(rates) ~= "table" then
        return nil
    end
    local root = rates[kind]
    if type(root) ~= "table" then
        return nil
    end
    level = math.floor(tonumber(level) or 0)
    if level < 1 then
        return nil
    end
    local key = tostring(level)
    local row = root[key]
    if type(row) ~= "table" then
        if create ~= true then
            return nil
        end
        row = { attempts = 0, hits = 0 }
        root[key] = row
    end
    return row
end

--- Record one Cult attempt at the current skill level.
--- Re-arming while pending only extends the window (no double attempt count).
--- opts.extendOnly: harvest path - extend live pending only; never start a new attempt.
function Rates.NoteCultAttempt(opts)
    opts = type(opts) == "table" and opts or {}
    local cult = GetCultSkill()
    if cult <= 0 or cult >= (CULT_MAX or 200) then
        return false
    end
    local level = math.floor(cult)
    local ttl = Rates.SKILL_PENDING_TTL_SEC or 90
    local seedUid = tonumber(opts.seedUid) or 0
    local pending = Rates._pendingCult
    if type(pending) == "table" and (tonumber(pending.untilTime) or 0) > NowSec() then
        pending.untilTime = NowSec() + ttl
        if seedUid > 0 then
            pending.seedUid = seedUid
        end
        return true
    end
    if opts.extendOnly == true then
        return false
    end
    local row = LevelBucket("cult", level, true)
    if type(row) ~= "table" then
        return false
    end
    row.attempts = (tonumber(row.attempts) or 0) + 1
    Rates._pendingCult = {
        level = level,
        seedUid = seedUid,
        untilTime = NowSec() + ttl,
    }
    MirrorPendingToSkillUp()
    return true
end

--- Record one Apo SkillUp attempt at the current skill level (SkillUp sessions only).
function Rates.NoteApoAttempt(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.skillUp ~= true then
        return false
    end
    local apo = GetApoSkill()
    if apo <= 0 or apo >= (APO_MAX or 200) then
        return false
    end
    local level = math.floor(apo)
    local ttl = Rates.SKILL_PENDING_TTL_SEC or 90
    local pending = Rates._pendingApo
    if type(pending) == "table" and (tonumber(pending.untilTime) or 0) > NowSec() then
        pending.untilTime = NowSec() + ttl
        return true
    end
    local row = LevelBucket("apo", level, true)
    if type(row) ~= "table" then
        return false
    end
    row.attempts = (tonumber(row.attempts) or 0) + 1
    Rates._pendingApo = {
        level = level,
        untilTime = NowSec() + ttl,
    }
    MirrorPendingToSkillUp()
    return true
end

function Rates.OnCultSkillDelta(delta)
    delta = tonumber(delta) or 0
    if delta <= 0 or delta > 3 then
        return false
    end
    local pending = Rates._pendingCult
    if type(pending) ~= "table" then
        return false
    end
    if (tonumber(pending.untilTime) or 0) < NowSec() then
        Rates._pendingCult = nil
        MirrorPendingToSkillUp()
        return false
    end
    local level = tonumber(pending.level) or math.floor(GetCultSkill())
    local seedUid = tonumber(pending.seedUid) or 0
    Rates._pendingCult = nil
    MirrorPendingToSkillUp()
    local row = LevelBucket("cult", level, true)
    if type(row) == "table" then
        -- One craft -> one skill-up event (credit the level the attempt was armed at).
        row.hits = (tonumber(row.hits) or 0) + 1
    end
    local SM = StockPiler4.SeedMap
    if seedUid > 0 and SM and SM.NoteCultSkillHit then
        SM.NoteCultSkillHit(seedUid, delta)
    end
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "cult-hit level=%d delta=%d hits=%d attempts=%d",
            level, delta, tonumber(row and row.hits) or 0, tonumber(row and row.attempts) or 0
        ))
    end
    return true
end

function Rates.OnApoSkillDelta(delta)
    delta = tonumber(delta) or 0
    if delta <= 0 or delta > 3 then
        return false
    end
    local pending = Rates._pendingApo
    if type(pending) ~= "table" then
        return false
    end
    if (tonumber(pending.untilTime) or 0) < NowSec() then
        Rates._pendingApo = nil
        MirrorPendingToSkillUp()
        return false
    end
    local level = tonumber(pending.level) or math.floor(GetApoSkill())
    Rates._pendingApo = nil
    MirrorPendingToSkillUp()
    local row = LevelBucket("apo", level, true)
    if type(row) == "table" then
        row.hits = (tonumber(row.hits) or 0) + 1
    end
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", string.format(
            "apo-hit level=%d delta=%d hits=%d attempts=%d",
            level, delta, tonumber(row and row.hits) or 0, tonumber(row and row.attempts) or 0
        ))
    end
    return true
end

--- Empirical skill-up rate at an exact skill level (nil if too few samples).
function Rates.LevelRate(kind, level)
    local row = LevelBucket(kind, level, false)
    if type(row) ~= "table" then
        return nil, 0, 0
    end
    local attempts = tonumber(row.attempts) or 0
    local hits = tonumber(row.hits) or 0
    local minN = Rates.SKILL_RATE_MIN_ATTEMPTS or 5
    if attempts < minN or attempts <= 0 then
        return nil, hits, attempts
    end
    return hits / attempts, hits, attempts
end

--- Default expected crafts for one skill-up at `level` (SkillUp Apo floor mats).
--- Rises sharply toward the next tier - brewing T50 at skill 74 is much harder than at 50.
function Rates.DefaultCraftsPerLevel(kind, level)
    level = math.floor(tonumber(level) or 0)
    if kind == "apo" then
        local floorTier = FloorApoTier(level)
        local nextTier = NextApoTier(level)
        if nextTier <= floorTier then
            nextTier = floorTier + 25
        end
        local band = math.max(1, nextTier - floorTier)
        local pos = (level - floorTier) / math.max(1, band - 1)
        if pos < 0 then
            pos = 0
        elseif pos > 1 then
            pos = 1
        end
        -- ~1.3 at floor start -> ~28 near next tier (pos^2 curve).
        return 1.3 + (pos * pos) * 26.7
    end
    return 1.5
end

--- Soft rate for buy estimates: exact samples, else nearby, else tier-progress default.
--- Blends thin samples (n < min) with the default so early luck cannot under-buy.
--- opts.noNearby: skip +/-span lookup (Apo vial buy - lower levels look too easy).
function Rates.ResolveLevelRate(kind, level, opts)
    level = math.floor(tonumber(level) or 0)
    opts = type(opts) == "table" and opts or {}
    local minN = Rates.SKILL_RATE_MIN_ATTEMPTS or 5
    local defaultCrafts = Rates.DefaultCraftsPerLevel(kind, level)
    local defaultRate = 1 / math.max(defaultCrafts, 1)

    local function softFromRow(row, srcLevel)
        if type(row) ~= "table" then
            return nil
        end
        local attempts = tonumber(row.attempts) or 0
        local hits = tonumber(row.hits) or 0
        if attempts <= 0 then
            return nil
        end
        local emp = hits / attempts
        if attempts >= minN then
            -- Floor so a 0% sample still plans some crafts.
            local rate = emp
            if rate < 0.02 then
                rate = 0.02
            end
            return rate, hits, attempts, srcLevel, "exact"
        end
        local w = attempts / minN
        local rate = emp * w + defaultRate * (1 - w)
        if rate < 0.02 then
            rate = 0.02
        end
        return rate, hits, attempts, srcLevel, "blend"
    end

    local own = LevelBucket(kind, level, false)
    local rate, hits, attempts, src, how = softFromRow(own, level)
    if rate ~= nil then
        return rate, hits, attempts, src, how
    end

    if opts.noNearby ~= true then
        local span = tonumber(Rates.SKILL_RATE_NEARBY_SPAN) or 3
        for d = 1, span do
            local rLo, hLo, aLo, sLo, howLo = softFromRow(LevelBucket(kind, level - d, false), level - d)
            if rLo ~= nil then
                return rLo, hLo, aLo, sLo, howLo or "nearby"
            end
            local rHi, hHi, aHi, sHi, howHi = softFromRow(LevelBucket(kind, level + d, false), level + d)
            if rHi ~= nil then
                return rHi, hHi, aHi, sHi, howHi or "nearby"
            end
        end
    end
    return defaultRate, 0, 0, level, "default"
end

-- Back-compat aliases (argument is skill level, not tier band).
function Rates.BandRate(kind, level)
    return Rates.LevelRate(kind, level)
end

function Rates.CultSkillUpRate(level)
    level = tonumber(level) or math.floor(GetCultSkill())
    return Rates.LevelRate("cult", level)
end

function Rates.ApoSkillUpRate(level)
    level = tonumber(level) or math.floor(GetApoSkill())
    return Rates.LevelRate("apo", level)
end

--- Expected crafts to climb from `fromLevel` (inclusive) to `toLevel` (exclusive).
local function ExpectedCraftsForRange(kind, fromLevel, toLevel)
    fromLevel = math.floor(tonumber(fromLevel) or 0)
    toLevel = math.floor(tonumber(toLevel) or 0)
    if toLevel <= fromLevel then
        return 0, false
    end
    local total = 0
    local anyEmpirical = false
    -- Apo vial buys: do not borrow easier nearby levels (e.g. 71 rate at skill 74).
    local rateOpts = kind == "apo" and { noNearby = true } or nil
    for level = fromLevel, toLevel - 1 do
        local rate, _, att, _, how = Rates.ResolveLevelRate(kind, level, rateOpts)
        if how == "exact" or how == "blend" or how == "nearby" then
            anyEmpirical = true
        end
        if (tonumber(att) or 0) > 0 then
            anyEmpirical = true
        end
        rate = tonumber(rate) or 0
        if rate > 0.02 then
            total = total + (1 / rate)
        else
            total = total + Rates.DefaultCraftsPerLevel(kind, level)
        end
    end
    return total, anyEmpirical
end

--- How many vials to keep for SkillUp Apo (one Apo tier band at a time).
--- Target = expected crafts from current skill to the next tier rung
--- (e.g. 50->75, or remaining 74->75) using per-level rates + tier-progress prior.
--- Not the full path to 200 - fewer vendor trips within a band, without stocking
--- hundreds of vials for every future tier.
function Rates.ApoContainerBuyTarget()
    local apo = GetApoSkill()
    local apoMax = APO_MAX or 200
    if apo <= 0 or apo >= apoMax then
        return 0
    end
    local nextTier = NextApoTier(apo)
    if nextTier <= apo then
        nextTier = apoMax
    end
    local gap = nextTier - apo
    if gap < 1 then
        return 0
    end
    local need = ExpectedCraftsForRange("apo", apo, nextTier)
    need = math.ceil(need)
    -- Small safety margin so one vendor visit covers E[crafts] for this band.
    need = need + 2
    -- Cap for bag/budget sanity (full band prior can be ~250 at a tier start).
    local hardCap = tonumber(Rates.APO_VIAL_BUY_CAP) or 300
    if need > hardCap then
        need = hardCap
    end
    if need < gap then
        need = gap
    end
    return need
end

function Rates.DumpRates(emit)
    emit = type(emit) == "function" and emit or function(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    emit("--- skill-up rates (by skill level) ---")
    local rates = RatesTable()
    if type(rates) ~= "table" then
        emit("  (none)")
        return
    end
    local function dumpKind(kind, label)
        local root = rates[kind]
        if type(root) ~= "table" then
            emit("  " .. label .. ": (none)")
            return
        end
        local keys = {}
        for k in pairs(root) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)
        if #keys == 0 then
            emit("  " .. label .. ": (none)")
            return
        end
        for i = 1, #keys do
            local row = root[keys[i]]
            local att = tonumber(row and row.attempts) or 0
            local hits = tonumber(row and row.hits) or 0
            if att > 0 or hits > 0 then
                local pct = att > 0 and (hits / att * 100) or 0
                emit(string.format(
                    "  %s level=%s hits=%d attempts=%d rate=%.0f%%",
                    label, tostring(keys[i]), hits, att, pct
                ))
            end
        end
    end
    dumpKind("cult", "Cult")
    dumpKind("apo", "Apo")
    local apo = GetApoSkill()
    local rate, hits, att, srcLevel, how = Rates.ResolveLevelRate("apo", apo, { noNearby = true })
    local want = Rates.ApoContainerBuyTarget()
    local nextTier = NextApoTier(apo)
    local defCrafts = Rates.DefaultCraftsPerLevel("apo", apo)
    local tierNeed = ExpectedCraftsForRange("apo", apo, nextTier)
    emit(string.format(
        "  vial estimate (one tier): apo=%d->%d E[crafts]=%.0f rate@%s=%.0f%% (%s n=%d) default@lvl=%.1f want=%d",
        apo,
        nextTier,
        tierNeed,
        tostring(srcLevel or apo),
        (rate or 0) * 100,
        tostring(how or "?"),
        att or 0,
        defCrafts,
        want
    ))
end

--- Wipe Cult/Apo per-level skill-up samples (and pending attribution).
function Rates.ClearRates()
    local Acc = StockPiler4.Account
    if type(Acc) ~= "table" then
        return false
    end
    local wantV = Rates.SKILL_RATES_SCHEMA or 2
    Acc.skillUpRates = { v = wantV, cult = {}, apo = {} }
    Rates._pendingCult = nil
    Rates._pendingApo = nil
    MirrorPendingToSkillUp()
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("skillup", "rates cleared")
    end
    return true
end


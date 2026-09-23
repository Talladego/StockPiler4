----------------------------------------------------------------
-- StockPiler4 Adapters/TradeSkillCaps - live cult/apo skill levels
-- Read GameData on each call (SP2 style). Engine often leaves tradeSkills
-- empty until TRADE_SKILL_UPDATED; never cache across that event.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.TradeSkillCaps = StockPiler4.TradeSkillCaps or {}
local Caps = StockPiler4.TradeSkillCaps

Caps._skillsReady = Caps._skillsReady == true

local function SkillId(name, fallback)
    if GameData and GameData.TradeSkills and GameData.TradeSkills[name] then
        return GameData.TradeSkills[name]
    end
    return fallback
end

local function ReadLevel(skillId)
    skillId = tonumber(skillId) or 0
    if skillId <= 0 then
        return 0
    end
    if GameData and GameData.Player and type(GameData.Player.tradeSkills) == "table" then
        local row = GameData.Player.tradeSkills[skillId]
        if type(row) == "table" then
            return tonumber(row.level) or 0
        end
        if row ~= nil then
            return tonumber(row) or 0
        end
    end
    if GameData and type(GameData.TradeSkillLevels) == "table" then
        return tonumber(GameData.TradeSkillLevels[skillId]) or 0
    end
    if GameData and type(GameData.TradeSkillData) == "table" then
        local row = GameData.TradeSkillData[skillId]
        if type(row) == "table" then
            return tonumber(row.level) or tonumber(row.SkillLevel) or 0
        end
        if row ~= nil then
            return tonumber(row) or 0
        end
    end
    return 0
end

function Caps.Refresh()
    if Caps.GetCultSkill() > 0 or Caps.GetApoSkill() > 0 then
        Caps._skillsReady = true
    end
end

function Caps.CultivationId()
    return SkillId("CULTIVATION", 3)
end

function Caps.ApothecaryId()
    return SkillId("APOTHECARY", 4)
end

--- Abilities-window trade skill icon id (GetTradeskillIcon). 0 if unavailable.
function Caps.GetTradeSkillIcon(skillId)
    skillId = tonumber(skillId) or 0
    if skillId <= 0 then
        return 0
    end
    if type(GetTradeskillIcon) == "function" then
        local ok, icon = pcall(GetTradeskillIcon, skillId)
        if ok == true then
            return tonumber(icon) or 0
        end
    end
    return 0
end

function Caps.GetCultivationIcon()
    return Caps.GetTradeSkillIcon(Caps.CultivationId())
end

function Caps.GetApothecaryIcon()
    return Caps.GetTradeSkillIcon(Caps.ApothecaryId())
end

function Caps.Level(skillId)
    return ReadLevel(skillId)
end

function Caps.GetCultSkill()
    return ReadLevel(Caps.CultivationId())
end

function Caps.GetApoSkill()
    return ReadLevel(Caps.ApothecaryId())
end

function Caps.AreTradeSkillsReady()
    if Caps._skillsReady == true then
        return true
    end
    if Caps.GetCultSkill() > 0 or Caps.GetApoSkill() > 0 then
        Caps._skillsReady = true
        return true
    end
    return false
end

function Caps.MarkTradeSkillsReady()
    Caps.Refresh()
    -- Do not latch ready on an empty reading (login often fires with one skill
    -- still at 0). AreTradeSkillsReady still auto-latches once either is >0.
    if Caps.GetCultSkill() > 0 or Caps.GetApoSkill() > 0 then
        Caps._skillsReady = true
    end
end

function Caps.ResetTradeSkillsReady()
    Caps._skillsReady = false
end

function Caps.CanAutoGrow()
    return Caps.GetCultSkill() > 0
end

function Caps.CanApothecary()
    return Caps.GetApoSkill() > 0
end

function Caps.CanBrewPotions()
    return Caps.CanApothecary()
end

function Caps.CanAutoBuy()
    return Caps.CanAutoGrow() or Caps.CanApothecary()
end

function Caps.LevelsHash()
    return tostring(Caps.GetCultSkill()) .. ":" .. tostring(Caps.GetApoSkill())
end

Caps.CULT_TIERS = { 1, 25, 50, 75, 100, 125, 150, 175, 200 }
Caps.APO_TIERS = { 1, 25, 50, 75, 100, 125, 150, 175, 200 }

--- Highest cult seed/plant tier unlocked by cultSkill (1, 25, 50, ...).
function Caps.FloorCultTier(cultSkill)
    cultSkill = tonumber(cultSkill) or 0
    local best = 1
    local tiers = Caps.CULT_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if cultSkill >= t then
            best = t
        end
    end
    return best
end

--- Highest apo recipe tier unlocked by apoSkill (1, 25, 50, ...).
function Caps.FloorApoTier(apoSkill)
    apoSkill = tonumber(apoSkill) or 0
    local best = 1
    local tiers = Caps.APO_TIERS
    for i = 1, #tiers do
        local t = tiers[i]
        if apoSkill >= t then
            best = t
        end
    end
    return best
end

----------------------------------------------------------------
-- StockPiler4 Core/Util - shared micro-helpers (NowSec, ToNarrow, T, TryCall)
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.Util = StockPiler4.Util or {}
local U = StockPiler4.Util

function U.NowSec()
    if type(GetGameTime) == "function" then
        local t = tonumber(GetGameTime())
        if t ~= nil then
            return t
        end
    end
    if type(FrameCounter) == "number" then
        return FrameCounter * 0.001
    end
    return 0
end

function U.ToNarrow(value)
    if StockPiler4.Persistence and StockPiler4.Persistence.ToNarrow then
        return StockPiler4.Persistence.ToNarrow(value)
    end
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    if type(value) == "wstring" and type(WStringToString) == "function" then
        local ok, text = pcall(WStringToString, value)
        if ok and type(text) == "string" then
            return text
        end
        return ""
    end
    return tostring(value)
end

function U.T(key, tokens)
    if StockPiler4.T then
        return StockPiler4.T(key, tokens)
    end
    return L"[" .. towstring(tostring(key or "")) .. L"]"
end

function U.TryCall(context, fn, ...)
    if StockPiler4.Debug and StockPiler4.Debug.TryCall then
        return StockPiler4.Debug.TryCall(context, fn, ...)
    end
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end

function U.TryCallQuiet(context, fn, ...)
    if StockPiler4.Debug and StockPiler4.Debug.TryCallQuiet then
        return StockPiler4.Debug.TryCallQuiet(context, fn, ...)
    end
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end

function U.CharacterRow(create)
    if StockPiler4.Persistence and StockPiler4.Persistence.GetCharacterBucket then
        return StockPiler4.Persistence.GetCharacterBucket(create ~= false)
    end
    return nil
end

function U.StageEmpty(t)
    if type(t) ~= "table" then
        return {}
    end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

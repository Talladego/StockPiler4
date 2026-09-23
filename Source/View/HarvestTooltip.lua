----------------------------------------------------------------
-- StockPiler4 HarvestTooltip -- live plot readiness tip
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.HarvestTooltip = StockPiler4.HarvestTooltip or {}
local HarvestTooltip = StockPiler4.HarvestTooltip

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

local function ReadyCount()
    local Grow = StockPiler4.Grow
    if Grow and Grow.GetReadyHarvestPlots then
        local plots = Grow.GetReadyHarvestPlots()
        if type(plots) == "table" then
            return #plots
        end
    end
    return 0
end

local function BuildTipText()
    local ready = ReadyCount()
    local can = StockPiler4.Grow and StockPiler4.Grow.CanHarvestNow
        and StockPiler4.Grow.CanHarvestNow() == true
    if can and ready > 0 then
        return T("grow.harvest_ready", { count = tostring(ready) })
    end
    if ready > 0 then
        return T("ui.harvest_tip_ready", { count = tostring(ready) })
    end
    return T("ui.harvest_tip_none")
end

local function Fingerprint()
    local ready = ReadyCount()
    local can = StockPiler4.Grow and StockPiler4.Grow.CanHarvestNow
        and StockPiler4.Grow.CanHarvestNow() == true
    return tostring(can) .. ":" .. tostring(ready)
end

function HarvestTooltip.Show(mouseoverWindow, anchor)
    StockPiler4.ViewList.LiveTipShow(
        HarvestTooltip,
        BuildTipText,
        Fingerprint,
        mouseoverWindow,
        anchor,
        Tooltips and Tooltips.ANCHOR_WINDOW_TOP
    )
end

function HarvestTooltip.ClearLive()
    StockPiler4.ViewList.LiveTipClear(HarvestTooltip)
end

function HarvestTooltip.MaybeRefresh()
    StockPiler4.ViewList.LiveTipMaybeRefresh(
        HarvestTooltip,
        BuildTipText,
        Fingerprint,
        HarvestTooltip.Show
    )
end

function HarvestTooltip.TickLive()
    HarvestTooltip.MaybeRefresh()
end

----------------------------------------------------------------
-- StockPiler4 Core/Perf - LibPerf.Scope bridge or in-addon hitch logger
-- Spike phase tags (instrumentation): phase=… emptyPlots=N additive=…
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}

local CAPTURE_FLOOR_MS = 250
local Noop = function() end

local VALID_PHASE = {
    login = true,
    harvestStorm = true,
    plantQuiet = true,
    quietEnd = true,
    executePlant = true,
    dumpall = true,
    unknown = true,
}

--- Shared spike-phase state (LibPerf Scope or in-addon).
local function AttachSpikePhaseApi(Perf)
    Perf._spikePhase = Perf._spikePhase or "unknown"
    Perf._spikePhaseGen = tonumber(Perf._spikePhaseGen) or 0

    function Perf.SetSpikePhase(phase)
        phase = tostring(phase or "unknown")
        if VALID_PHASE[phase] ~= true then
            phase = "unknown"
        end
        if Perf._spikePhase == phase then
            return phase
        end
        Perf._spikePhase = phase
        Perf._spikePhaseGen = (tonumber(Perf._spikePhaseGen) or 0) + 1
        -- Prefer native LibPerf annotation hooks when present.
        local ctx = Perf.FormatSpikeContext and Perf.FormatSpikeContext() or ("phase=" .. phase)
        if type(Perf.SetExtra) == "function" then
            pcall(Perf.SetExtra, ctx)
        elseif type(Perf.SetAnnotation) == "function" then
            pcall(Perf.SetAnnotation, ctx)
        elseif type(Perf.Annotate) == "function" then
            pcall(Perf.Annotate, ctx)
        else
            Perf.extra = ctx
            Perf._annotation = ctx
        end
        return phase
    end

    function Perf.ClearSpikePhase(expected)
        local cur = tostring(Perf._spikePhase or "unknown")
        if expected ~= nil and cur ~= tostring(expected) then
            return cur
        end
        return Perf.SetSpikePhase("unknown")
    end

    function Perf.GetSpikePhase()
        local phase = tostring(Perf._spikePhase or "unknown")
        if VALID_PHASE[phase] ~= true then
            return "unknown"
        end
        return phase
    end

    --- Cheap emptyPlots + additive flag for spike lines (no bag walks).
    function Perf.FormatSpikeContext()
        local phase = Perf.GetSpikePhase()
        local emptyPlots = 0
        local additive = 0
        local Grow = StockPiler4.Grow
        if Grow then
            if Grow.CountEmptyPlots then
                emptyPlots = tonumber(Grow.CountEmptyPlots()) or 0
            elseif Grow.HasEmptyPlot and Grow.HasEmptyPlot() == true then
                emptyPlots = 1
            end
            -- Cheap sticky flag / pending count — avoid NeedsCurrentStageAdditive.
            if Grow._additiveDirty == true then
                additive = 1
            end
            local pending = Grow._pendingAdditive
            if type(pending) == "table" then
                local n = 0
                for _ in pairs(pending) do
                    n = n + 1
                end
                if n > additive then
                    additive = n
                end
            end
        end
        return string.format(
            "phase=%s emptyPlots=%d additive=%d",
            phase,
            emptyPlots,
            additive
        )
    end

    --- No-op: per-frame Perf.Mark flooded trails (phase=quietEnd x1692).
    --- Phase context is appended only on real hitch lines via FormatSpikeContext.
    function Perf.StampSpikePhase()
    end

    local origPrintSummary = Perf.PrintSummary or Perf.DumpSummary
    function Perf.PrintSummary()
        if type(origPrintSummary) == "function" then
            origPrintSummary()
        end
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(towstring(
                "SP4 spikeCtx " .. tostring(Perf.FormatSpikeContext())
            ))
        elseif StockPiler4.Debug and StockPiler4.Debug.LogAlways then
            StockPiler4.Debug.LogAlways(
                "perf| summary " .. tostring(Perf.FormatSpikeContext())
            )
        end
    end
    Perf.DumpSummary = Perf.PrintSummary
end

local function MakeInAddonPerf()
    local Perf = {
        Enabled = false,
        FrameThresholdMs = 400,
        Available = false,
        _trail = {},
        _hold = false,
        _section = nil,
        _t0 = 0,
        _summary = { spikes = 0, emptyTrail = 0 },
        _emptyRate = 0,
    }

    function Perf.IsEnabled()
        return Perf.Enabled == true
    end

    function Perf.SetEnabled(on)
        Perf.Enabled = on == true
    end

    function Perf.Enable()
        Perf.SetEnabled(true)
    end

    function Perf.Disable()
        Perf.SetEnabled(false)
    end

    function Perf.SetFrameThreshold(ms)
        ms = tonumber(ms)
        if ms == nil or ms < 1 then
            return tonumber(Perf.FrameThresholdMs) or 400
        end
        if ms < CAPTURE_FLOOR_MS then
            ms = CAPTURE_FLOOR_MS
        end
        if ms > 10000 then
            ms = 10000
        end
        Perf.FrameThresholdMs = ms
        return ms
    end

    function Perf.GetFrameThreshold()
        return tonumber(Perf.FrameThresholdMs) or 400
    end

    Perf.SetThreshold = Perf.SetFrameThreshold
    Perf.GetThreshold = Perf.GetFrameThreshold

    function Perf.Begin(name)
        if Perf.Enabled ~= true then
            return
        end
        Perf._section = tostring(name or "?")
        Perf._t0 = (GetGameTime and GetGameTime()) or 0
        Perf._trail[#Perf._trail + 1] = ">" .. Perf._section
    end

    function Perf.End(name)
        if Perf.Enabled ~= true then
            return
        end
        name = tostring(name or Perf._section or "?")
        Perf._trail[#Perf._trail + 1] = "<" .. name
        Perf._section = nil
    end

    function Perf.Mark(name)
        if Perf.Enabled ~= true then
            return
        end
        Perf._trail[#Perf._trail + 1] = "*" .. tostring(name or "?")
    end

    function Perf.HoldTrail(on)
        Perf._hold = on == true
        if Perf._hold ~= true then
            Perf._trail = {}
        end
    end

    function Perf.ShouldHoldTrail()
        return Perf._hold == true
    end

    function Perf.ResetSummary()
        Perf._summary = { spikes = 0, emptyTrail = 0 }
    end

    function Perf.OnFrame(timeElapsed)
        if Perf.Enabled ~= true then
            return
        end
        -- Prefer frame delta (ms); GetGameTime is 1s resolution and false-triggers.
        local dt = (tonumber(timeElapsed) or 0) * 1000
        if dt <= 0 then
            local now = (GetGameTime and GetGameTime()) or 0
            dt = (now - (Perf._frameT0 or now)) * 1000
            Perf._frameT0 = now
        end
        if dt < (tonumber(Perf.FrameThresholdMs) or 400) then
            if Perf._hold ~= true then
                Perf._trail = {}
            end
            return
        end
        Perf._summary.spikes = (Perf._summary.spikes or 0) + 1
        local trail = Perf._trail
        local empty = type(trail) ~= "table" or #trail == 0
        local ctx = Perf.FormatSpikeContext and Perf.FormatSpikeContext()
            or ("phase=" .. tostring(Perf._spikePhase or "unknown"))
        if empty then
            Perf._summary.emptyTrail = (Perf._summary.emptyTrail or 0) + 1
            Perf._emptyRate = (Perf._emptyRate or 0) + 1
            if Perf._emptyRate <= 3 or (Perf._emptyRate % 20) == 0 then
                StockPiler4.Debug.LogAlways(string.format(
                    "perf| hitch %.0fms trail=(none) %s empty=%d spikes=%d",
                    dt, ctx, Perf._summary.emptyTrail, Perf._summary.spikes
                ))
            end
        else
            Perf._emptyRate = 0
            local parts = {}
            local n = #trail
            local start = math.max(1, n - 24)
            for i = start, n do
                parts[#parts + 1] = trail[i]
            end
            StockPiler4.Debug.LogAlways(string.format(
                "perf| hitch %.0fms trail=%s %s",
                dt, table.concat(parts, " "), ctx
            ))
        end
        if Perf._hold ~= true then
            Perf._trail = {}
        end
    end

    function Perf.PrintSummary()
        local ctx = Perf.FormatSpikeContext and Perf.FormatSpikeContext()
            or ("phase=" .. tostring(Perf._spikePhase or "unknown"))
        StockPiler4.Debug.Print(towstring(string.format(
            "SP3 perf spikes=%d emptyTrail=%d thr=%dms enabled=%s %s",
            Perf._summary.spikes or 0,
            Perf._summary.emptyTrail or 0,
            Perf.GetFrameThreshold(),
            tostring(Perf.Enabled),
            ctx
        )))
    end

    Perf.DumpSummary = Perf.PrintSummary
    Perf.PrintBaseline = Noop
    function Perf.IsBaselineCollecting()
        return false
    end
    function Perf.StartBaseline()
        return 50
    end
    function Perf.GetLogPath()
        return "in-addon"
    end

    AttachSpikePhaseApi(Perf)
    return Perf
end

if LibPerf and type(LibPerf.Scope) == "function" then
    local Perf = LibPerf.Scope("StockPiler4")
    Perf.Available = true
    local libOnFrame = Perf.OnFrame
    function Perf.OnFrame(timeElapsed)
        if type(libOnFrame) == "function" then
            libOnFrame(timeElapsed)
        end
    end
    local thr = 0
    if Perf.GetThreshold then
        thr = tonumber(Perf.GetThreshold()) or 0
    elseif Perf.GetFrameThreshold then
        thr = tonumber(Perf.GetFrameThreshold()) or 0
    end
    if thr > 0 and thr < CAPTURE_FLOOR_MS then
        if Perf.SetThreshold then
            Perf.SetThreshold(CAPTURE_FLOOR_MS)
        elseif Perf.SetFrameThreshold then
            Perf.SetFrameThreshold(CAPTURE_FLOOR_MS)
        end
    end
    -- Ensure IsEnabled exists for StampSpikePhase.
    if type(Perf.IsEnabled) ~= "function" then
        function Perf.IsEnabled()
            if Perf.Enabled == true then
                return true
            end
            if type(Perf.GetEnabled) == "function" then
                local ok, on = pcall(Perf.GetEnabled)
                return ok and on == true
            end
            return false
        end
    end
    AttachSpikePhaseApi(Perf)
    -- Companion hitch line when LibPerf is on (Bridge skips Perf.OnFrame for
    -- Available=true). Mirror threshold hits into uilog with phase context.
    -- Use timeElapsed (frame delta); GetGameTime is 1s resolution (~1000ms spam).
    local _spikeCount = 0
    function Perf.NoteSpikePhaseFrame(timeElapsed)
        local on = false
        if type(Perf.IsEnabled) == "function" then
            on = Perf.IsEnabled() == true
        elseif Perf.Enabled == true then
            on = true
        elseif type(Perf.GetEnabled) == "function" then
            local ok, v = pcall(Perf.GetEnabled)
            on = ok and v == true
        end
        if on ~= true then
            return
        end
        local dt = (tonumber(timeElapsed) or 0) * 1000
        if dt <= 0 then
            return
        end
        local thrMs = CAPTURE_FLOOR_MS
        if Perf.GetThreshold then
            thrMs = tonumber(Perf.GetThreshold()) or thrMs
        elseif Perf.GetFrameThreshold then
            thrMs = tonumber(Perf.GetFrameThreshold()) or thrMs
        end
        if thrMs < CAPTURE_FLOOR_MS then
            thrMs = CAPTURE_FLOOR_MS
        end
        if dt < thrMs then
            return
        end
        _spikeCount = _spikeCount + 1
        local ctx = Perf.FormatSpikeContext()
        if StockPiler4.Debug and StockPiler4.Debug.LogAlways then
            StockPiler4.Debug.LogAlways(string.format(
                "perf| hitch %.0fms %s spikes=%d",
                dt, ctx, _spikeCount
            ))
        end
    end
    StockPiler4.Perf = Perf
else
    StockPiler4.Perf = MakeInAddonPerf()
end

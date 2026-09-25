----------------------------------------------------------------
-- StockPiler4 GrowDump - grow plan diagnostics
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
local Grow = StockPiler4.Grow

function Grow.DumpDiagnostics(emit)
    emit = type(emit) == "function" and emit or function(msg)
        if StockPiler4.Debug and StockPiler4.Debug.Print then
            StockPiler4.Debug.Print(msg)
        end
    end
    emit("=== grow plan ===")
    emit("enabled=" .. tostring(Grow.IsEnabled()))
    emit("fillBlocked=" .. tostring(Grow.IsFillBlocked())
        .. " wait=" .. tostring(Grow._plantWaitTicks or 0))
    emit("emptyPlot=" .. tostring(Grow.HasEmptyPlot())
        .. " seeds=" .. tostring(Grow.HasSeedsForNextPlant()))
    emit("bufferSatisfied=" .. tostring(Grow.IsSeedBufferSatisfied())
        .. " pendingRefine=" .. tostring(Grow.HasPendingBufferRefine())
        .. " bufferShort=" .. tostring(Grow.HasAnyBufferShort()))
    emit("holdHarvestBatch=" .. tostring(Grow.ShouldHoldPlantForReadyHarvest())
        .. " canHarvest=" .. tostring(Grow.CanHarvestNow()))
    emit("lastPlantedSeedUid=" .. tostring(Grow._lastPlantedSeedUid or 0))
    local job = Grow._cachedPlantJob
    if type(job) == "table" then
        emit(string.format(
            "job seedUid=%s role=%s watch=%s deficit=%s reason=%s mode=%s",
            tostring(job.seedUid),
            tostring(job.role),
            tostring(job.watchKey),
            tostring(job.potionDeficit or job.deficit),
            tostring(job.plantReason),
            tostring(job.pickMode)
        ))
    else
        emit("job=(none)")
    end
    local ready = Grow.GetReadyHarvestPlots and Grow.GetReadyHarvestPlots() or {}
    if type(ready) == "table" then
        emit("readyPlots=" .. table.concat(ready, ","))
    else
        emit("readyPlots=")
    end
    emit("=== end grow plan ===")
end

function Grow.DumpGrowPlan(emit)
    Grow.DumpDiagnostics(emit)
end

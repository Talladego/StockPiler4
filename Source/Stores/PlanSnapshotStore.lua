----------------------------------------------------------------
-- StockPiler4 Stores/PlanSnapshotStore - cached planner output
--
-- Immutability contract:
--   Set / Replace store a whole plan object owned by the Planner publish path.
--   Get returns that snapshot for read-only use (executors must not mutate rows).
--   Invalidate drops cache key; Clear drops plan (session / character change).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.PlanSnapshot = StockPiler4.PlanSnapshot or {}
local PS = StockPiler4.PlanSnapshot

PS._plan = nil
PS._cacheKey = nil

local function FireInvalidated()
    local B = StockPiler4.EventBus
    local E = StockPiler4.Events
    if B and E and E.PLAN_INVALIDATED then
        B.Fire(E.PLAN_INVALIDATED, {})
    end
end

local function FireUpdated()
    local B = StockPiler4.EventBus
    local E = StockPiler4.Events
    if B and E and E.PLAN_UPDATED then
        B.Fire(E.PLAN_UPDATED, { hasPlan = type(PS._plan) == "table" })
    end
end

--- Last published plan; treat as read-only (mutate only via Set/Replace after rebuild).
function PS.Get()
    return PS._plan
end

function PS.Set(plan, cacheKey)
    PS._plan = plan
    PS._cacheKey = cacheKey
    FireUpdated()
end

--- Alias of Set: replace the entire cached plan atomically.
function PS.Replace(plan, cacheKey)
    return PS.Set(plan, cacheKey)
end

function PS.GetCacheKey()
    return PS._cacheKey
end

--- Soft invalidate: drop cache key, keep stale plan for UI / GetOrBuild(false).
function PS.Invalidate()
    PS._cacheKey = nil
    FireInvalidated()
end

--- Hard clear: drop plan (character / session change only).
function PS.Clear()
    PS._plan = nil
    PS._cacheKey = nil
    FireInvalidated()
end

--- Never sync-build while a coalesced rebuild is pending.
--- GetOrBuild(false) / {refresh=false}: return stale only (may nudge enqueue).
--- GetOrBuild() / true / {refresh=true}: build when Planner exists and not pending.
function PS.GetOrBuild(refresh)
    local opts = {}
    local wantRefresh = true
    if refresh == false then
        wantRefresh = false
    elseif type(refresh) == "table" then
        opts = refresh
        if opts.refresh == false then
            wantRefresh = false
        end
        if opts.force == true then
            wantRefresh = true
        end
    elseif refresh == true then
        wantRefresh = true
    end

    local Sch = StockPiler4.Scheduler
    local pending = Sch and Sch.IsPlanRebuildPending and Sch.IsPlanRebuildPending() == true

    -- Pending rebuild: never sync-build; serve last plan (or nil).
    if pending then
        return PS._plan
    end

    if not wantRefresh then
        if Sch and Sch.EnqueuePlanRebuild and type(PS._plan) == "table" then
            -- Stale with key mismatch: nudge only; do not Build here.
            if PS._cacheKey == nil and Sch.EnqueuePlanRebuild then
                Sch.EnqueuePlanRebuild({ nudge = true })
            end
        elseif Sch and Sch.EnqueuePlanRebuild then
            Sch.EnqueuePlanRebuild({ nudge = true })
        end
        return PS._plan
    end

    -- Cache hit: skip Build (Scheduler GetOrBuild(true) used to full-Build every
    -- PLAN_MIN_GAP even when gens were unchanged — Upgrade Seeds + empty plots).
    local Planner = StockPiler4.Planner
    if opts.force ~= true and type(PS._plan) == "table" and PS._cacheKey ~= nil
        and Planner and Planner.CacheKeyFromGens
    then
        local key = Planner.CacheKeyFromGens()
        if key ~= nil and key == PS._cacheKey then
            return PS._plan
        end
    end

    if Planner and type(Planner.Build) == "function" then
        local plan = Planner.Build(opts)
        if type(plan) == "table" then
            local key = nil
            if Planner.CacheKeyFromGens then
                key = Planner.CacheKeyFromGens()
            end
            PS.Set(plan, key)
            return plan
        end
    end

    return PS._plan
end

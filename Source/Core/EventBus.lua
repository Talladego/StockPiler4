----------------------------------------------------------------
-- StockPiler4 Core/EventBus - internal pub/sub
----------------------------------------------------------------

StockPiler4.EventBus = StockPiler4.EventBus or {}

local Bus = StockPiler4.EventBus
local subs = {}
local nextToken = 0

StockPiler4.Events = StockPiler4.Events or {
    INVENTORY_DIRTY = "sp4.inventory.dirty",
    INVENTORY_SNAPSHOT = "sp4.inventory.snapshot",
    GARDEN_DIRTY = "sp4.garden.dirty",
    GARDEN_SNAPSHOT = "sp4.garden.snapshot",
    PLAN_INVALIDATED = "sp4.plan.invalidated",
    PLAN_UPDATED = "sp4.plan.updated",
    PHASE_CHANGED = "sp4.phase.changed",
    OP_COMPLETED = "sp4.op.completed",
    CMD_HARVEST = "sp4.cmd.harvest",
    CMD_BREW_LOAD = "sp4.cmd.brew.load",
    CMD_BREW_PERFORM = "sp4.cmd.brew.perform",
    SESSION_LOADED = "sp4.session.loaded",
    KNOWLEDGE_UPDATED = "sp4.knowledge.updated",
    REFINE_OUTSTANDING = "sp4.refine.outstanding",
    VENDOR_UPDATED = "sp4.vendor.updated",
    CRAFT_READY_CHANGED = "sp4.craft.ready",
    FOOTER_DIRTY = "sp4.footer.dirty",
    WATCH_UI_DIRTY = "sp4.watch.ui.dirty",
}

function Bus.Subscribe(eventName, fn)
    eventName = tostring(eventName or "")
    if eventName == "" or type(fn) ~= "function" then
        return false
    end
    local list = subs[eventName]
    if list == nil then
        list = {}
        subs[eventName] = list
    end
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" and entry.fn == fn then
            return entry.token
        end
    end
    nextToken = nextToken + 1
    local token = nextToken
    list[#list + 1] = { token = token, fn = fn }
    return token
end

function Bus.Unsubscribe(token)
    token = tonumber(token)
    if token == nil then
        return false
    end
    for eventName, list in pairs(subs) do
        if type(list) == "table" then
            for i = #list, 1, -1 do
                local entry = list[i]
                if type(entry) == "table" and entry.token == token then
                    table.remove(list, i)
                    if #list == 0 then
                        subs[eventName] = nil
                    end
                    return true
                end
            end
        end
    end
    return false
end

function Bus.UnsubscribeAll(eventName)
    if eventName == nil then
        subs = {}
        return
    end
    subs[tostring(eventName)] = nil
end

--- Domain modules publish footer readiness via EventBus (not Scheduler→Ui).
function Bus.FireFooterDirty(payload)
    local E = StockPiler4.Events
    if E and E.FOOTER_DIRTY then
        Bus.Fire(E.FOOTER_DIRTY, type(payload) == "table" and payload or {})
    end
end

--- Domain modules mark Watch paint dirty via EventBus (View owns flush).
function Bus.FireWatchUiDirty(payload)
    local E = StockPiler4.Events
    if E and E.WATCH_UI_DIRTY then
        Bus.Fire(E.WATCH_UI_DIRTY, type(payload) == "table" and payload or {})
    end
end

function Bus.Fire(eventName, payload)
    eventName = tostring(eventName or "")
    local list = subs[eventName]
    local n = type(list) == "table" and #list or 0
    if StockPiler4.Debug and StockPiler4.Debug.EventTraceNote then
        local summary = ""
        if type(payload) == "table" then
            if payload.snapGen then
                summary = summary .. "snapGen=" .. tostring(payload.snapGen) .. " "
            end
            if payload.reason then
                summary = summary .. "reason=" .. tostring(payload.reason) .. " "
            end
            if payload.phase then
                summary = summary .. "phase=" .. tostring(payload.phase) .. " "
            end
        end
        StockPiler4.Debug.EventTraceNote(eventName, summary, n)
    end
    if n <= 0 then
        return
    end
    local handlers = {}
    for i = 1, n do
        local entry = list[i]
        local fn = type(entry) == "table" and entry.fn or entry
        if type(fn) == "function" then
            handlers[#handlers + 1] = fn
        end
    end
    for i = 1, #handlers do
        if StockPiler4.Debug and StockPiler4.Debug.TryCallQuiet then
            StockPiler4.Debug.TryCallQuiet("EventBus." .. eventName, handlers[i], payload)
        else
            handlers[i](payload)
        end
    end
end

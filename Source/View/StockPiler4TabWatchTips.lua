----------------------------------------------------------------
-- StockPiler4TabWatchTips -- status / chrome tooltip builders
-- Bind-only helpers for Watch tab mouseover tips.
----------------------------------------------------------------

StockPiler4TabWatchTips = StockPiler4TabWatchTips or {}
local Tips = StockPiler4TabWatchTips

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

local COLOR_OK = { 80, 200, 80 }
local COLOR_WARN = { 220, 180, 60 }
local COLOR_BLOCK = { 220, 70, 70 }

local function IsPlantWatchRow(data)
    return type(data) == "table" and (data.kind == "plant" or data.isPlantWatch == true)
end

local function IsUpgradeWatchRow(data)
    return type(data) == "table" and data.upgradeSeed == true
end

local function IsSkillUpWatchRow(data)
    return type(data) == "table" and data.skillUp == true
end

local function IsEphemeralWatchRow(data)
    return IsSkillUpWatchRow(data) or IsUpgradeWatchRow(data)
end

local function Tip(text)
    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, text)
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_RIGHT)
end

local function TipTradeSkill(skillId)
    skillId = tonumber(skillId) or 0
    if skillId > 0 and Tooltips and type(Tooltips.CreateTradeskillTooltip) == "function" then
        Tooltips.CreateTradeskillTooltip(skillId, Tooltips.ANCHOR_WINDOW_RIGHT)
        return
    end
    local Caps = StockPiler4.TradeSkillCaps
    local level = Caps and Caps.Level and Caps.Level(skillId) or 0
    local label = L"Trade skill"
    if skillId == (Caps and Caps.CultivationId and Caps.CultivationId() or 3) then
        label = T("watch.skillup_cult")
    elseif skillId == (Caps and Caps.ApothecaryId and Caps.ApothecaryId() or 4) then
        label = T("watch.skillup_apo")
    end
    if level > 0 then
        Tip(towstring(string.format("%s\nSkill Level: %d", tostring(label), level)))
    else
        Tip(label)
    end
end

local function ToNarrow(value)
    return StockPiler4.Util.ToNarrow(value)
end

local function RgbDef(rgb)
    if type(rgb) ~= "table" then
        return nil
    end
    return {
        r = tonumber(rgb[1]) or 255,
        g = tonumber(rgb[2]) or 255,
        b = tonumber(rgb[3]) or 255,
    }
end

local STATUS_TIP_COLORS = {
    no_recipe = COLOR_BLOCK,
    no_target = COLOR_BLOCK,
    potion_stocked = COLOR_OK,
    plant_stocked = COLOR_OK,
    ready_to_craft = COLOR_OK,
    ready_to_craft_shared = COLOR_WARN,
    restocking = COLOR_WARN,
    enable_autogrow = COLOR_BLOCK,
    need_apothecary = COLOR_BLOCK,
    need_skill = COLOR_BLOCK,
    buy_ingredients = COLOR_BLOCK,
    need_seeds = COLOR_WARN,
    upgrading_seed = COLOR_WARN,
    seed_buffer = COLOR_WARN,
    planting = COLOR_OK,
    buffer_plant = COLOR_OK,
    growing = COLOR_OK,
    refining = COLOR_WARN,
    wait_cult = COLOR_WARN,
    idle = COLOR_WARN,
    fallback_blocked = COLOR_OK,
    waiting_watches = COLOR_WARN,
    waiting_potions = COLOR_WARN,
    waiting_plants = COLOR_WARN,
    waiting_seed_buffer = COLOR_WARN,
    no_seeds = COLOR_BLOCK,
    need_vendor = COLOR_BLOCK,
    autobuy_off = COLOR_BLOCK,
    no_vendor_seed = COLOR_BLOCK,
    need_mats = COLOR_BLOCK,
    need_resin = COLOR_BLOCK,
    unstable = COLOR_BLOCK,
    need_container_vendor = COLOR_BLOCK,
    no_vendor_container = COLOR_BLOCK,
}

local function StatusTitleColor(statusKey)
    local def = RgbDef(STATUS_TIP_COLORS[statusKey or ""])
    if def ~= nil then
        return def
    end
    if Tooltips and Tooltips.COLOR_HEADING then
        return Tooltips.COLOR_HEADING
    end
    return nil
end

local function PlanTipCacheKey()
    local planGen = 0
    local cacheKey = ""
    if StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get then
        local plan = StockPiler4.PlanSnapshot.Get()
        if type(plan) == "table" then
            planGen = tonumber(plan.planGen) or 0
            cacheKey = tostring(plan.cacheKey or "")
        end
    end
    return tostring(planGen) .. ":" .. cacheKey
end

local function GrowingNoteKind(notes)
    local n = string.lower(ToNarrow(notes))
    if string.find(n, "needs planting", 1, true)
        or string.find(n, "converting", 1, true)
        or string.find(n, "need seed", 1, true)
        or string.find(n, "buy seeds", 1, true)
        or string.find(n, "buy plants", 1, true)
        or string.find(n, "climbing", 1, true)
        or string.find(n, "climb ", 1, true)
        or string.find(n, "refining", 1, true)
        or string.find(n, "buy lower", 1, true)
    then
        return "warning"
    end
    if string.find(n, "buy flasks", 1, true)
        or string.find(n, "buy materials", 1, true)
        or string.find(n, "autogrow off", 1, true)
        or string.find(n, "needs cultivation", 1, true)
        or string.find(n, "need cult", 1, true)
    then
        return "negative"
    end
    if string.find(n, "ready to harvest", 1, true)
        or string.find(n, "growing", 1, true)
        or string.find(n, "germination", 1, true)
        or string.find(n, "seedling", 1, true)
        or string.find(n, "flowering", 1, true)
        or string.find(n, "planting", 1, true)
    then
        return "positive"
    end
    return "body"
end

local function SpecIsAutoGrowProgressableTip(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.role == "container" then
        return false
    end
    local spec = entry.spec
    if type(spec) ~= "table" then
        return false
    end
    local SM = StockPiler4.SeedMap
    if SM and SM.IsGrowableSpec and SM.IsGrowableSpec(spec) == true then
        return true
    end
    return false
end

local function TipEntrySpecKey(entry)
    if type(entry) ~= "table" then
        return ""
    end
    if type(entry.specKey) == "string" and entry.specKey ~= "" then
        return entry.specKey
    end
    local MS = StockPiler4.MaterialSpec
    local spec = entry.spec
    if MS and MS.Key and type(spec) == "table" then
        local bound = nil
        if spec.incomplete == true then
            bound = tonumber(spec.boundUid) or tonumber(spec.uid) or nil
        end
        local k = MS.Key(spec, bound)
        if type(k) == "string" and k ~= "" then
            return k
        end
    end
    return ""
end

local function TitleCaseStatusNote(notes)
    local narrow = ToNarrow(notes)
    if narrow == "" then
        return notes
    end
    local lower = string.lower(narrow)
    if lower == "stocked" then
        return T("watch.note.stocked")
    end
    if lower == "shared" or lower == "(shared)" then
        return T("watch.note.shared")
    end
    if lower == "pooled" or lower == "(pooled)" then
        return T("watch.note.pooled")
    end
    if lower == "buy flasks" then
        return T("watch.note.buy_flasks")
    end
    if lower == "buy materials" then
        return T("watch.note.buy_materials")
    end
    if lower == "buy seeds" then
        return T("watch.note.buy_seeds")
    end
    if lower == "buy plants" then
        return T("watch.note.buy_plants")
    end
    if lower == "needs planting" then
        return T("watch.note.needs_planting")
    end
    if lower == "needs cultivation" then
        return T("watch.note.needs_cult")
    end
    if lower == "autogrow off for this watch" then
        return T("watch.note.autogrow_off")
    end
    local first = string.sub(narrow, 1, 1)
    local rest = string.sub(narrow, 2)
    if first >= "a" and first <= "z" then
        return towstring(string.upper(first) .. rest)
    end
    return notes
end

local function TrimStatusTooltipRows(rows, limit)
    limit = tonumber(limit) or 17
    if type(rows) ~= "table" or #rows <= limit then
        return rows
    end

    local function isIngredientDivider(i)
        local prev = rows[i - 1]
        local nextRow = rows[i + 1]
        if not (nextRow and nextRow.kind == "ingredient") or not prev then
            return false
        end
        if prev.kind == "stocked" or prev.kind == "bonus" or prev.kind == "effect"
            or prev.kind == "positive" or prev.kind == "negative"
        then
            return true
        end
        if prev.kind == "body" or prev.kind == "warning" then
            local t = ToNarrow(prev.text)
            if string.find(t, "Have ", 1, true) then
                return true
            end
        end
        return false
    end

    for i = #rows, 1, -1 do
        if #rows <= limit then
            return rows
        end
        local r = rows[i]
        if r.kind == "meta" then
            local t = ToNarrow(r.text)
            if string.find(t, "Recipe yield", 1, true) then
                table.remove(rows, i)
            end
        end
    end
    for i = #rows, 1, -1 do
        if #rows <= limit then
            return rows
        end
        if rows[i].kind == "warning" then
            local t = ToNarrow(rows[i].text)
            if string.find(t, "success", 1, true) then
                table.remove(rows, i)
            end
        end
    end

    while #rows > limit do
        local removed = false
        for i = #rows, 1, -1 do
            if rows[i].kind == "separator" and not isIngredientDivider(i) then
                table.remove(rows, i)
                removed = true
                break
            end
        end
        if not removed then
            break
        end
    end
    return rows
end

local function BuildStatusTooltipRows(data)
    local rows = {
        {
            text = data.statusText or T("watch.col.status"),
            kind = "title",
            color = StatusTitleColor(data.statusKey),
        },
    }

    local function appendMeta(text)
        if text and text ~= L"" then
            rows[#rows + 1] = { text = text, kind = "meta" }
        end
    end

    -- SkillUp / Upgrade ephemeral rows: status message + statusLines only.
    if IsEphemeralWatchRow(data) then
        if type(data.statusLines) == "table" then
            for i = 1, #data.statusLines do
                appendMeta(data.statusLines[i])
            end
        end
        return rows
    end

    local liveHave = tonumber(data.potionHave)
    local liveMin = tonumber(data.potionMin) or tonumber(data.target) or 0

    -- Plant watches: title + color-coded Have/Target (no recipe ingredient slots).
    if IsPlantWatchRow(data) then
        if type(data.statusLines) == "table" then
            for i = 1, #data.statusLines do
                local line = data.statusLines[i]
                if line and line ~= L"" then
                    local narrow = ToNarrow(line)
                    if string.find(narrow, "buffer=", 1, true) == nil then
                        rows[#rows + 1] = {
                            text = line,
                            kind = "warning",
                            color = StatusTitleColor(data.statusKey),
                        }
                    end
                end
            end
        end
        if liveHave ~= nil and liveMin > 0 then
            local stocked = liveHave >= liveMin
            local statusKey = tostring(data.statusKey or "")
            local haveColor = RgbDef(COLOR_BLOCK)
            local noteKind = "block"
            local statusNote = nil
            if stocked or statusKey == "plant_stocked" then
                haveColor = RgbDef(COLOR_OK)
                noteKind = "stocked"
                statusNote = T("watch.note.stocked")
            elseif statusKey == "need_seeds" or statusKey == "upgrading_seed" then
                haveColor = RgbDef(COLOR_WARN)
                noteKind = "warning"
                if statusKey == "upgrading_seed" then
                    statusNote = data.statusText or T("plan.status.upgrading_seed")
                else
                    statusNote = T("plan.status.need_seeds")
                end
            elseif statusKey == "waiting_potions" then
                haveColor = RgbDef(COLOR_WARN)
                noteKind = "warning"
                statusNote = T("watch.note.waiting_potions")
            elseif statusKey == "restocking" then
                -- Match potion tip plant-slot warn tint while AutoGrow can progress.
                haveColor = RgbDef(COLOR_WARN)
                noteKind = "warning"
                if data.autoGrow == true then
                    statusNote = T("watch.note.needs_planting")
                else
                    statusNote = T("watch.note.autogrow_off")
                    haveColor = RgbDef(COLOR_BLOCK)
                    noteKind = "block"
                end
            elseif statusKey == "enable_autogrow" then
                haveColor = RgbDef(COLOR_BLOCK)
                noteKind = "block"
                statusNote = T("watch.note.autogrow_off")
            else
                haveColor = RgbDef(COLOR_WARN)
                noteKind = "warning"
                statusNote = T("watch.note.needs_planting")
            end
            local haveText
            if statusNote and statusNote ~= L"" then
                haveText = T("tip.watch.have_need_note", {
                    have = tostring(liveHave),
                    need = tostring(liveMin),
                    note = statusNote,
                })
            else
                haveText = T("tip.watch.have_target", {
                    have = tostring(liveHave),
                    target = tostring(liveMin),
                })
            end
            rows[#rows + 1] = {
                text = haveText,
                kind = noteKind,
                color = haveColor,
            }
        end
        return rows
    end

    local slots = data.statusTipSlots
    local recipe = data.recipe or data.specRecipe
    local craftsNeeded = tonumber(data.craftsNeeded) or 0
    local deficit = tonumber(data.potionDeficit) or 0
    if liveHave ~= nil and liveMin > 0 then
        deficit = math.max(0, liveMin - liveHave)
        if deficit <= 0 then
            craftsNeeded = 0
        end
    end
    local yield = tonumber(data.recipeYield) or 0
    if type(recipe) == "table" and yield <= 0 then
        yield = tonumber(recipe.recipeYield) or 0
    end

    if type(slots) == "table" and #slots > 0 then
        if craftsNeeded > 0 and deficit > 0 then
            rows[#rows + 1] = {
                text = T("tip.watch.need_crafts", {
                    crafts = tostring(craftsNeeded),
                    deficit = tostring(deficit),
                }),
                kind = "body",
            }
            if yield > 0 then
                appendMeta(T("tip.watch.yield_best_case", { yield = tostring(yield) }))
            end
            if data.statusKey == "enable_autogrow" then
                rows[#rows + 1] = {
                    text = T("tip.watch.enable_autogrow_row"),
                    kind = "warning",
                    color = RgbDef(COLOR_BLOCK),
                }
            elseif data.statusKey == "need_skill" then
                local lines = data.statusLines
                if type(lines) == "table" and #lines > 0 then
                    for i = 1, #lines do
                        rows[#rows + 1] = {
                            text = lines[i],
                            kind = "warning",
                            color = RgbDef(COLOR_BLOCK),
                        }
                    end
                else
                    rows[#rows + 1] = {
                        text = data.statusText or T("tip.watch.need_higher_skill"),
                        kind = "warning",
                        color = RgbDef(COLOR_BLOCK),
                    }
                end
            elseif data.statusKey == "need_apothecary" then
                rows[#rows + 1] = {
                    text = T("tip.watch.apo_only_brew"),
                    kind = "warning",
                    color = RgbDef(COLOR_BLOCK),
                }
            elseif data.statusKey == "buy_ingredients" and not CanAutoGrowUi() then
                local st = string.lower(ToNarrow(data.statusText))
                if not string.find(st, "flask", 1, true) then
                    rows[#rows + 1] = {
                        text = T("tip.watch.cult_required"),
                        kind = "warning",
                        color = RgbDef(COLOR_BLOCK),
                    }
                end
            elseif data.statusKey == "need_seeds" or data.statusKey == "upgrading_seed" then
                local lines = data.statusLines
                if type(lines) == "table" then
                    for i = 1, #lines do
                        local line = lines[i]
                        if line and line ~= L"" then
                            local narrow = ToNarrow(line)
                            if string.find(narrow, "buffer=", 1, true) == nil then
                                rows[#rows + 1] = {
                                    text = line,
                                    kind = "warning",
                                    color = RgbDef(COLOR_WARN),
                                }
                            end
                        end
                    end
                end
            end
            local RS = StockPiler4.RecipeSpec
            local uid = tonumber(data.uniqueID) or 0
            if RS and RS.ExpectedCraftsForDeficit and type(recipe) == "table" then
                local expectedCrafts, rate = RS.ExpectedCraftsForDeficit(deficit, recipe, uid)
                if rate ~= nil and rate < 0.99 and expectedCrafts and expectedCrafts > craftsNeeded then
                    local pct = math.floor(rate * 100 + 0.5)
                    rows[#rows + 1] = {
                        text = T("tip.watch.success_expected", {
                            pct = tostring(pct),
                            crafts = tostring(expectedCrafts),
                        }),
                        kind = "warning",
                    }
                end
                if RS.FormatApoSkillUpLine then
                    local apoLine = RS.FormatApoSkillUpLine(recipe)
                    if apoLine and apoLine ~= L"" then
                        appendMeta(apoLine)
                    end
                end
            end
        elseif data.statusNeedLine and data.statusNeedLine ~= L"" then
            appendMeta(data.statusNeedLine)
        end

        local RT = StockPiler4.RecipeTooltip
        rows[#rows + 1] = {
            text = (RT and RT.SEP_LINE) or T("watch.sep"),
            kind = "separator",
        }

        local MS = StockPiler4.MaterialSpec
        local Grow = StockPiler4.Grow
        local colorOk = RgbDef(COLOR_OK)
        local colorWarn = RgbDef(COLOR_WARN)
        local colorBlock = RgbDef(COLOR_BLOCK)
        local slotShown = 0
        for i = 1, #slots do
            local entry = slots[i]
            if type(entry) == "table" and type(entry.spec) == "table" then
                if slotShown > 0 then
                    if RT and RT.AppendSeparator then
                        RT.AppendSeparator(rows)
                    else
                        rows[#rows + 1] = { text = T("watch.sep"), kind = "separator" }
                    end
                end
                slotShown = slotShown + 1

                local parts = MS and MS.NeedLabelParts and MS.NeedLabelParts(entry.spec) or nil
                local header = parts and parts.header
                    or (MS and MS.NeedLabel and MS.NeedLabel(entry.spec))
                    or T("watch.material_fallback")
                local detail = parts and parts.detail or L""
                rows[#rows + 1] = {
                    text = header,
                    kind = "ingredient",
                    role = entry.role,
                }
                if detail ~= nil and detail ~= L"" then
                    rows[#rows + 1] = {
                        text = detail,
                        kind = "bonus",
                        role = entry.role,
                    }
                end

                -- Live Have: copy tip-slot fields locally - never write back into statusTipSlots.
                local tipHave = tonumber(entry.have) or 0
                local tipNeed = tonumber(entry.need) or 0
                local tipDeficit = tonumber(entry.deficit) or math.max(0, tipNeed - tipHave)
                local tipStocked = entry.stocked == true or tipDeficit <= 0
                local Planner = StockPiler4.Planner
                if Planner and Planner.CountItemsMatchingSpec and type(entry.spec) == "table" then
                    local live = Planner.CountItemsMatchingSpec(entry.spec, { cacheOnly = true })
                    if live ~= nil then
                        tipHave = tonumber(live) or tipHave
                        tipDeficit = math.max(0, tipNeed - tipHave)
                        tipStocked = tipDeficit <= 0
                    end
                end
                local stocked = tipStocked
                local agProgressable = SpecIsAutoGrowProgressableTip(entry)
                local haveColor = colorOk
                if not stocked then
                    if entry.kind == "convert" then
                        local feedable = data.convertFeedable == true
                        if not feedable then
                            for j = 1, #slots do
                                local sibling = slots[j]
                                if type(sibling) == "table" and sibling.kind == "plant" then
                                    feedable = true
                                    break
                                end
                            end
                        end
                        haveColor = feedable and colorWarn or colorBlock
                    elseif agProgressable then
                        haveColor = colorWarn
                    else
                        haveColor = colorBlock
                    end
                end
                local statusNote = nil
                local noteKind = stocked and "stocked" or "body"
                if (entry.kind == "plant" or (agProgressable and entry.kind ~= "convert"))
                    and not stocked
                then
                    -- Prefer per-slot Upgrade Seed climb note (Spumepetal vs Fusk).
                    local climbNote = nil
                    local US = StockPiler4.UpgradeSeed
                    if US and US.IsEnabled and US.IsEnabled() == true
                        and US.StatusForPlant and US.FormatClimbSlotNote
                    then
                        local climb = US.StatusForPlant(entry.plantUid, entry.spec)
                        climbNote = US.FormatClimbSlotNote(climb)
                    end
                    if climbNote ~= nil and climbNote ~= L"" then
                        statusNote = climbNote
                        noteKind = "warning"
                        haveColor = colorWarn
                    else
                        local notes = nil
                        if Grow and Grow.GrowingNotesForSpec then
                            notes = Grow.GrowingNotesForSpec(entry.spec, { cacheOnly = true })
                        end
                        if notes == nil or notes == L"" then
                            notes = entry.growingNotes
                        end
                        if notes == nil or notes == L"" then
                            notes = L""
                        end
                        if notes == L"" then
                            if not CanAutoGrowUi() then
                                notes = T("watch.note.needs_cult")
                                haveColor = colorBlock
                            elseif data.autoGrow == true then
                                local seedUid = tonumber(entry.seedUid) or 0
                                local credit = tonumber(entry.seedCredit) or 0
                                if seedUid > 0 and credit <= 0 then
                                    notes = T("watch.note.buy_seeds")
                                    haveColor = colorWarn
                                elseif seedUid <= 0 then
                                    notes = T("watch.note.buy_plants")
                                    haveColor = colorWarn
                                else
                                    notes = T("watch.note.needs_planting")
                                    haveColor = colorWarn
                                end
                            else
                                notes = T("watch.note.autogrow_off")
                                haveColor = colorBlock
                            end
                        end
                        statusNote = TitleCaseStatusNote(notes)
                        noteKind = GrowingNoteKind(notes)
                    end
                elseif not stocked then
                    if entry.role == "container" then
                        statusNote = T("watch.note.buy_flasks")
                    elseif entry.buySeedOrMat == true
                        and (tonumber(entry.seedUid) or 0) > 0
                    then
                        statusNote = T("watch.note.buy_seeds")
                    else
                        statusNote = T("watch.note.buy_materials")
                    end
                    noteKind = "block"
                    haveColor = colorBlock
                elseif stocked then
                    local contestedKeys = data.contestedSpecKeys
                    local specKey = TipEntrySpecKey(entry)
                    local claimContested = (data.craftableShared == true
                            or data.statusKey == "ready_to_craft_shared"
                            or data.statusKey == "buy_ingredients")
                        and type(contestedKeys) == "table"
                        and specKey ~= ""
                        and contestedKeys[specKey] == true
                    local noteNarrow = string.lower(ToNarrow(entry.note))
                    if claimContested or noteNarrow == "(shared)" then
                        if data.statusKey == "buy_ingredients"
                            and not SpecIsAutoGrowProgressableTip(entry)
                        then
                            if entry.role == "container" then
                                statusNote = T("watch.note.buy_flasks")
                            elseif entry.buySeedOrMat == true
                                and (tonumber(entry.seedUid) or 0) > 0
                            then
                                statusNote = T("watch.note.buy_seeds")
                            else
                                statusNote = T("watch.note.buy_materials")
                            end
                            noteKind = "block"
                            haveColor = colorBlock
                        else
                            statusNote = T("watch.note.shared")
                            noteKind = "warning"
                            haveColor = colorWarn
                        end
                    elseif entry.sharedPool == true or noteNarrow == "(pooled)" then
                        statusNote = T("watch.note.pooled")
                        noteKind = "warning"
                        haveColor = colorWarn
                    else
                        statusNote = T("watch.note.stocked")
                        noteKind = "stocked"
                    end
                end
                local haveText
                if statusNote and statusNote ~= L"" then
                    haveText = T("tip.watch.have_need_note", {
                        have = tostring(tipHave),
                        need = tostring(tipNeed),
                        note = statusNote,
                    })
                else
                    haveText = T("tip.watch.have_need", {
                        have = tostring(tipHave),
                        need = tostring(tipNeed),
                    })
                end
                rows[#rows + 1] = {
                    text = haveText,
                    kind = noteKind,
                    color = haveColor,
                }
            end
        end
    elseif type(recipe) == "table" then
        appendMeta(T("tip.status.plan_pending"))
        if type(data.statusLines) == "table" and #data.statusLines > 0 then
            for i = 1, #data.statusLines do
                appendMeta(data.statusLines[i])
            end
        end
        if liveHave ~= nil and liveMin > 0 then
            appendMeta(T("tip.watch.have_target", {
                have = tostring(liveHave),
                target = tostring(liveMin),
            }))
        end
    elseif type(data.statusLines) == "table" and #data.statusLines > 0 then
        for i = 1, #data.statusLines do
            appendMeta(data.statusLines[i])
        end
        if liveHave ~= nil and liveMin > 0 then
            appendMeta(T("tip.watch.have_target", {
                have = tostring(liveHave),
                target = tostring(liveMin),
            }))
        end
    elseif data.statusDetail and data.statusDetail ~= L"" then
        appendMeta(data.statusDetail)
    elseif liveHave ~= nil and liveMin > 0 then
        appendMeta(T("tip.watch.have_target", {
            have = tostring(liveHave),
            target = tostring(liveMin),
        }))
    end

    return rows
end


function Tips.Tip(text)
    Tip(text)
end

function Tips.TipTradeSkill(skillId)
    TipTradeSkill(skillId)
end

function Tips.ToNarrow(value)
    return ToNarrow(value)
end

function Tips.PlanTipCacheKey()
    return PlanTipCacheKey()
end

function Tips.BuildStatusTooltipRows(data)
    return BuildStatusTooltipRows(data)
end

function Tips.TrimStatusTooltipRows(rows, limit)
    return TrimStatusTooltipRows(rows, limit)
end

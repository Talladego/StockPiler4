----------------------------------------------------------------
-- StockPiler4TabPotions -- known potions list (watch / filters / forget)
----------------------------------------------------------------

StockPiler4TabPotions = {}

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

StockPiler4TabPotions.listData = {}
StockPiler4TabPotions.displayOrder = {}

local ICON_SCALE = 0.34
local TAB_ROOT = "SP4TabPotions"

local SORT_IDS = {
    [1] = "name",
    [2] = "effect",
    [3] = "power",
    [4] = "stability",
    [5] = "superCrit",
    [6] = "yield",
    [7] = "have",
    [8] = "watch",
    [9] = "level",
    [10] = "multiplier",
}

local SORT_HEADERS = {
    watch = "SP4TabPotionsSortWatch",
    name = "SP4TabPotionsSortName",
    level = "SP4TabPotionsSortLevel",
    effect = "SP4TabPotionsSortEffect",
    power = "SP4TabPotionsSortPower",
    stability = "SP4TabPotionsSortStability",
    multiplier = "SP4TabPotionsSortMultiplier",
    superCrit = "SP4TabPotionsSortSuperCrit",
    yield = "SP4TabPotionsSortYield",
    have = "SP4TabPotionsSortHave",
}

local function ToNarrow(text)
    return StockPiler4.Util.ToNarrow(text)
end

local function GetSettings()
    if StockPiler4.Persistence and StockPiler4.Persistence.EnsureSettings then
        return StockPiler4.Persistence.EnsureSettings()
    end
    return StockPiler4.Settings
end

local function EffectTextForRow(effectKey)
    return StockPiler4.ViewList.EffectTextForRow(effectKey)
end

local function ItemRarityNameColor(itemData)
    return StockPiler4.ViewList.ItemRarityNameColor(itemData)
end

local function FormatSignedStat(value)
    return StockPiler4.ViewList.FormatSignedStat(value)
end

local function FormatPercentStat(value)
    return StockPiler4.ViewList.FormatPercentStat(value)
end

local function FormatYieldStat(value)
    value = tonumber(value) or 0
    if value <= 0 then
        return T("ui.dash")
    end
    local rounded = math.floor(value + 0.5)
    if math.abs(value - rounded) < 0.05 then
        return towstring(tostring(rounded))
    end
    return towstring(string.format("%.1f", value))
end

local function ApplyPotionStats(row, itemData)
    local dash = T("ui.dash")
    row.rankNum = 0
    row.levelNum = 0
    row.levelText = dash
    if StockPiler4.Classify and StockPiler4.Classify.GetPotionStats then
        local stats = StockPiler4.Classify.GetPotionStats(itemData)
        if type(stats) == "table" then
            row.rankNum = tonumber(stats.rank) or tonumber(stats.level) or 0
            row.levelNum = tonumber(stats.level) or row.rankNum
            if type(stats.levelText) == "wstring" and stats.levelText ~= L"" then
                row.levelText = stats.levelText
            elseif row.levelNum > 0 then
                row.levelText = towstring(tostring(row.levelNum))
            end
            if (not row.effectKey or row.effectKey == "") and stats.effectKey then
                row.effectKey = stats.effectKey
                row.effectText = stats.effectText or EffectTextForRow(stats.effectKey)
            end
            return
        end
    end
    if type(itemData) == "table" then
        local lvl = tonumber(itemData.iLevel) or tonumber(itemData.level) or 0
        row.rankNum = lvl
        row.levelNum = lvl
        if lvl > 0 then
            row.levelText = towstring(tostring(lvl))
        end
    end
end

local function BuildRecipeDataForPotion(potionName, recipe, potionLevel, potionUid, potionBase)
    if type(recipe) ~= "table" then
        return nil
    end
    local uid = tonumber(potionUid) or tonumber(recipe.outputUid) or 0
    local attempts = tonumber(recipe.brewAttempts) or 0
    local successes = tonumber(recipe.brewSuccesses) or 0
    local successRate = nil
    if attempts > 0 then
        successRate = successes / attempts
    end
    local recipeYield = tonumber(recipe.recipeYield) or 0
    local RS = StockPiler4.RecipeSpec
    if RS and RS.RecipeFingerprintStats then
        local stats = RS.RecipeFingerprintStats(recipe, uid)
        if type(stats) == "table" and tonumber(stats.yield) and tonumber(stats.yield) > 0 then
            recipeYield = tonumber(stats.yield)
        end
    end
    local effectKey = nil
    if type(potionBase) == "table" and type(potionBase.effectKey) == "string" and potionBase.effectKey ~= "" then
        effectKey = potionBase.effectKey
    end
    if (type(effectKey) ~= "string" or effectKey == "") and RS and RS.ResolveEffectKeyForPotion
        and type(potionBase) == "table"
    then
        effectKey = RS.ResolveEffectKeyForPotion(potionBase, {
            recipe = recipe,
            stamp = false,
            allowClassify = true,
        })
    end
    if type(effectKey) == "string" and effectKey ~= "" and RS and RS.NormalizeEffectKeyForUi then
        effectKey = RS.NormalizeEffectKeyForUi(effectKey) or effectKey
    end
    return {
        name = potionName,
        potionLevel = tonumber(potionLevel) or 0,
        potionUid = uid,
        recipeSpecKey = recipe.recipeSpecKey,
        recipe = recipe,
        recipeYield = recipeYield,
        brewAttempts = attempts,
        brewSuccesses = successes,
        successRate = successRate,
        effectKey = effectKey,
        materials = recipe.slots or {},
    }
end

local function MatchesNameFilter(name, filter)
    if filter == nil or filter == "" then
        return true
    end
    return string.find(string.lower(ToNarrow(name)), string.lower(filter), 1, true) ~= nil
end

local function MatchesEffectFilter(effectKey, filter)
    if filter == nil or filter == "" then
        return true
    end
    return effectKey == filter
end

local function PassesFilters(row, nameFilter, effectFilter)
    -- Legacy defense: SkillUp Apo no longer learns potions; hide any leftover
    -- skillUpOrigin rows unless the player watched them.
    if row.skillUpOrigin == true and row.watched ~= true then
        return false
    end
    if not MatchesNameFilter(row.name, nameFilter)
        and not MatchesNameFilter(row.baseName, nameFilter)
        and not MatchesNameFilter(row.recipeLabel, nameFilter)
    then
        return false
    end
    return MatchesEffectFilter(row.effectKey, effectFilter)
end

local function CompareName(a, b)
    local na = string.lower(ToNarrow(a.baseName or a.name))
    local nb = string.lower(ToNarrow(b.baseName or b.name))
    if na == nb then
        return ToNarrow(a.id) < ToNarrow(b.id)
    end
    return na < nb
end

local function CompareRows(a, b, column, ascending)
    local function finish(lt)
        if lt then
            return ascending
        end
        return not ascending
    end
    if column == "name" then
        local na = string.lower(ToNarrow(a.name))
        local nb = string.lower(ToNarrow(b.name))
        if na == nb then
            return CompareName(a, b)
        end
        return finish(na < nb)
    elseif column == "level" then
        local la = a.levelNum or a.rankNum or 0
        local lb = b.levelNum or b.rankNum or 0
        if la == lb then
            return CompareName(a, b)
        end
        return finish(la < lb)
    elseif column == "effect" then
        local ea = ToNarrow(a.effectText)
        local eb = ToNarrow(b.effectText)
        if ea == eb then
            return CompareName(a, b)
        end
        return finish(ea < eb)
    elseif column == "power" then
        if (a.powerNum or 0) == (b.powerNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.powerNum or 0) < (b.powerNum or 0))
    elseif column == "stability" then
        if (a.stabilityNum or 0) == (b.stabilityNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.stabilityNum or 0) < (b.stabilityNum or 0))
    elseif column == "multiplier" then
        if (a.multiplierNum or 0) == (b.multiplierNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.multiplierNum or 0) < (b.multiplierNum or 0))
    elseif column == "superCrit" then
        if (a.superCritNum or 0) == (b.superCritNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.superCritNum or 0) < (b.superCritNum or 0))
    elseif column == "yield" then
        if (a.yieldNum or 0) == (b.yieldNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.yieldNum or 0) < (b.yieldNum or 0))
    elseif column == "have" then
        if (a.have or 0) == (b.have or 0) then
            return CompareName(a, b)
        end
        return finish((a.have or 0) < (b.have or 0))
    elseif column == "watch" then
        local wa = a.watched == true
        local wb = b.watched == true
        if wa == wb then
            return CompareName(a, b)
        end
        return finish(wa and not wb)
    end
    return CompareName(a, b)
end

local function SortRows(rows)
    local s = GetSettings()
    local column = s.potionSortColumn or "name"
    local ascending = s.potionSortAscending ~= false
    table.sort(rows, function(a, b)
        return CompareRows(a, b, column, ascending)
    end)
end

local function EffectCycle()
    return StockPiler4.ViewList.EffectFilterCycle()
end

local function SyncEffectComboSelection()
    StockPiler4.ViewList.SyncEffectCombo("SP4TabPotionsEffectCombo", (GetSettings().potionEffectFilter) or "")
end

local function InitEffectCombo()
    StockPiler4.ViewList.InitEffectCombo(
        "SP4TabPotionsEffectCombo",
        (GetSettings().potionEffectFilter) or "",
        EffectTextForRow
    )
end

local function UpdateSortHeaderLabels()
    local labels = {
        name = T("potions.sort.name"),
        level = T("potions.sort.level"),
        effect = T("potions.sort.effect"),
        power = T("potions.sort.power"),
        stability = T("potions.sort.stability"),
        multiplier = T("potions.sort.multiplier"),
        superCrit = T("potions.sort.super_crit"),
        yield = T("potions.sort.yield"),
        have = T("potions.sort.have"),
    }
    for key, win in pairs(SORT_HEADERS) do
        if DoesWindowExist(win) and labels[key] then
            ButtonSetText(win, labels[key])
        end
    end
    if DoesWindowExist("SP4TabPotionsSortRecipe") then
        ButtonSetText("SP4TabPotionsSortRecipe", T("potions.sort.recipe"))
    end
    if DoesWindowExist("SP4TabPotionsSortForget") then
        ButtonSetText("SP4TabPotionsSortForget", T("potions.sort.forget"))
    end
end

local function UpdateSortHeaders()
    UpdateSortHeaderLabels()
    local s = GetSettings()
    StockPiler4.ViewList.UpdateSortArrows(
        SORT_HEADERS,
        s.potionSortColumn or "name",
        s.potionSortAscending ~= false
    )
end

local function ResolvePotionItemData(uid)
    uid = tonumber(uid) or 0
    if uid <= 0 then
        return nil
    end
    if StockPiler4.Inventory and StockPiler4.Inventory.ResolvePotionItemData then
        return StockPiler4.Inventory.ResolvePotionItemData(nil, uid, nil)
    end
    return nil
end

local function BuildVisibleList()
    local s = GetSettings()
    if type(s) ~= "table" then
        return
    end
    local nameFilter = s.potionNameFilter or ""
    local effectFilter = s.potionEffectFilter or ""
    local rows = {}

    if StockPiler4.Inventory and StockPiler4.Inventory.RefreshAllIfNeeded then
        StockPiler4.Inventory.RefreshAllIfNeeded()
    end
    if StockPiler4.Watch and StockPiler4.Watch.ScrubPristineDisabledStubs then
        StockPiler4.Watch.ScrubPristineDisabledStubs()
    end
    -- Heal uid:↔fx: watch/recipe drift before painting checkboxes.
    if StockPiler4.RecipeSpec and StockPiler4.RecipeSpec.HealWatchRecipeFingerprints then
        StockPiler4.RecipeSpec.HealWatchRecipeFingerprints()
    end

    local Catalog = StockPiler4.Catalog
    local RS = StockPiler4.RecipeSpec
    local potions = Catalog and Catalog.ListPotionRecipeEntries and Catalog.ListPotionRecipeEntries() or {}

    for i = 1, #potions do
        local potion = potions[i]
        local potionKey = potion.potionRecipeKey or potion.potionKey
        local potionBase = potion.potion or potion
        local watch = Catalog and Catalog.GetWatch and Catalog.GetWatch(potionKey)
            or { enabled = false, targetStock = 40 }
        local watched = watch.enabled == true
        local have = Catalog and Catalog.PotionHaveCombined and Catalog.PotionHaveCombined(potionBase) or 0
        local uid = tonumber(potion.outputUid or potionBase.outputUid) or 0
        local itemData = ResolvePotionItemData(uid)
        local effectKey = nil
        if RS and RS.ResolveEffectKeyForPotion then
            effectKey = RS.ResolveEffectKeyForPotion(potionBase, {
                recipeKey = potion.recipeSpecKey,
                recipe = potion.recipe,
                itemData = itemData,
                stamp = true,
            })
        else
            effectKey = potion.effectKey or potionBase.effectKey
            if (not effectKey or effectKey == "") and itemData and StockPiler4.Classify and StockPiler4.Classify.GetEffectKey then
                effectKey = StockPiler4.Classify.GetEffectKey(itemData)
            end
        end
        local baseName = potion.name or potionBase.name or towstring(tostring(uid))
        local skillUpOrigin = potion.skillUpOrigin == true
            or (type(potionBase) == "table" and potionBase.skillUpOrigin == true)
            or (type(potion.recipe) == "table" and potion.recipe.skillUpOrigin == true)
        local displayName = baseName
        if skillUpOrigin == true then
            displayName = baseName .. T("potions.tag.skillup")
        end
        local powerNum = tonumber(potion.power) or 0
        local stabilityNum = tonumber(potion.stability) or 0
        local multiplierNum = tonumber(potion.multiplier) or 0
        local superCritNum = tonumber(potion.superCrit) or 0
        local yieldNum = tonumber(potion.yield) or 0
        local row = {
            id = potionKey,
            potionKey = potionKey,
            potionBaseKey = potion.potionKey or potionBase.potionKey,
            recipeSpecKey = potion.recipeSpecKey,
            recipeLabel = potion.recipeLabel or L"",
            name = displayName,
            baseName = baseName,
            skillUpOrigin = skillUpOrigin,
            effectKey = effectKey,
            effectText = EffectTextForRow(effectKey),
            powerNum = powerNum,
            powerText = FormatSignedStat(powerNum),
            stabilityNum = stabilityNum,
            stabilityText = FormatSignedStat(stabilityNum),
            multiplierNum = multiplierNum,
            multiplierText = FormatSignedStat(multiplierNum),
            superCritNum = superCritNum,
            superCritText = FormatPercentStat(superCritNum),
            yieldNum = yieldNum,
            yieldText = FormatYieldStat(yieldNum),
            have = have,
            haveText = towstring(tostring(have)),
            watched = watched,
            watchBlocked = (StockPiler4.Watch and StockPiler4.Watch.CanEnablePotionWatch
                and StockPiler4.Watch.CanEnablePotionWatch(potionKey) ~= true) == true,
            iconNum = tonumber(potion.iconNum or potionBase.iconNum) or 0,
            itemData = itemData,
            uniqueID = uid,
        }
        ApplyPotionStats(row, itemData)
        -- Learned Account.items tier when bag/DB shell still lacks iLevel/skillReq.
        if (tonumber(row.levelNum) or 0) <= 0 and uid > 0 then
            local learned = StockPiler4.Items and StockPiler4.Items.GetByUid and StockPiler4.Items.GetByUid(uid)
            if type(learned) == "table" then
                local lvl = tonumber(learned.iLevel) or tonumber(learned.skillReq) or tonumber(learned.skillLevel) or 0
                if lvl <= 0 and type(learned.bonuses) == "table" then
                    lvl = tonumber(learned.bonuses[9]) or 0
                end
                if lvl > 0 then
                    row.rankNum = lvl
                    row.levelNum = lvl
                    row.levelText = towstring(tostring(lvl))
                end
            end
        end
        if (tonumber(row.levelNum) or 0) <= 0 and type(potionBase) == "table" then
            local lvl = tonumber(potionBase.iLevel) or tonumber(potionBase.level) or 0
            if lvl > 0 then
                row.rankNum = lvl
                row.levelNum = lvl
                row.levelText = towstring(tostring(lvl))
            end
        end
        row.nameR, row.nameG, row.nameB = ItemRarityNameColor(itemData)
        local recipe = potion.recipe
        if not recipe and RS and RS.GetRecipe and potion.recipeSpecKey then
            recipe = RS.GetRecipe(potion.recipeSpecKey)
        end
        if recipe and RS and RS.RecipeFingerprintStats then
            local stats = RS.RecipeFingerprintStats(recipe, uid)
            row.powerNum = stats.power
            row.powerText = FormatSignedStat(stats.power)
            row.stabilityNum = stats.stability
            row.stabilityText = FormatSignedStat(stats.stability)
            row.multiplierNum = stats.multiplier
            row.multiplierText = FormatSignedStat(stats.multiplier)
            row.superCritNum = stats.superCrit
            row.superCritText = FormatPercentStat(stats.superCrit)
            row.yieldNum = stats.yield
            row.yieldText = FormatYieldStat(stats.yield)
        end
        row.recipeData = BuildRecipeDataForPotion(
            baseName,
            recipe,
            row.levelNum or row.rankNum,
            uid,
            potionBase
        )
        row.hasRecipe = row.recipeData ~= nil
        if PassesFilters(row, nameFilter, effectFilter) then
            rows[#rows + 1] = row
        end
    end

    SortRows(rows)
    local order = {}
    for i = 1, #rows do
        order[i] = i
    end
    StockPiler4TabPotions.listData = rows
    StockPiler4TabPotions.displayOrder = order
end

local function SetIconTexture(iconWin, iconNum)
    StockPiler4.ViewList.SetIconTexture(iconWin, iconNum, ICON_SCALE)
end

local function RowDataFromActiveChild()
    local rowWindow = WindowGetParent(SystemData.ActiveWindow.name)
    local rowIndex = WindowGetId(rowWindow)
    local dataIndex = ListBoxGetDataIndex("SP4TabPotionsList", rowIndex)
    return StockPiler4TabPotions.listData[dataIndex]
end

local function AfterWatchToggle()
    if StockPiler4.Watch and StockPiler4.Watch.BumpGen then
        StockPiler4.Watch.BumpGen()
    end
    if StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Invalidate then
        StockPiler4.PlanSnapshot.Invalidate()
    end
    -- Sync-build so Watch tab has rows immediately (coalesce alone left empty plan).
    if StockPiler4.Planner and StockPiler4.Planner.Build then
        StockPiler4.Planner.Build({ force = true })
    else
        local Sch = StockPiler4.Scheduler
        if Sch and Sch.EnqueuePlanRebuild then
            Sch.EnqueuePlanRebuild()
        end
    end
    if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
        StockPiler4.Ui.MarkWatchUiDirty()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.Refresh
        and StockPiler4Window and StockPiler4Window.SelectedTab == StockPiler4Window.TABS_WATCH
    then
        StockPiler4TabWatch.Refresh({ forcePlan = true })
    end
end

function StockPiler4TabPotions.Initialize()
    LabelSetText("SP4TabPotionsBannerTitle", T("potions.banner_title"))
    LabelSetText("SP4TabPotionsBannerText", T("potions.banner_text"))
    LabelSetText("SP4TabPotionsSearchLabel", T("potions.search"))
    LabelSetText("SP4TabPotionsEffectLabel", T("potions.effect"))
    UpdateSortHeaderLabels()

    local s = GetSettings()
    if DoesWindowExist("SP4TabPotionsSearchBox") then
        TextEditBoxSetText("SP4TabPotionsSearchBox", towstring(s.potionNameFilter or ""))
    end
    InitEffectCombo()
    UpdateSortHeaders()
end

function StockPiler4TabPotions.Refresh()
    if not DoesWindowExist(TAB_ROOT) then
        return
    end
    SyncEffectComboSelection()
    UpdateSortHeaders()
    BuildVisibleList()
    if DoesWindowExist("SP4TabPotionsList") then
        ListBoxSetDisplayOrder("SP4TabPotionsList", {})
        ListBoxSetDisplayOrder("SP4TabPotionsList", StockPiler4TabPotions.displayOrder)
        StockPiler4TabPotions.UpdateRows()
    end
end

function StockPiler4TabPotions.UpdateRows()
    if not SP4TabPotionsList then
        return
    end
    local numVisible = tonumber(SP4TabPotionsList.numVisibleRows) or 12
    local indices = SP4TabPotionsList.PopulatorIndices
    local active = {}
    if type(indices) == "table" then
        for rowIndex, dataIndex in ipairs(indices) do
            active[rowIndex] = dataIndex
        end
    end
    local listData = StockPiler4TabPotions.listData
    for rowIndex = 1, numVisible do
        local rowName = "SP4TabPotionsListRow" .. rowIndex
        if DoesWindowExist(rowName) then
            local dataIndex = active[rowIndex]
            local data = dataIndex and type(listData) == "table" and listData[dataIndex] or nil
            if data then
                WindowSetShowing(rowName, true)
                DefaultColor.SetListRowTint(rowName .. "Background", rowIndex, false)
                local blocked = data.watchBlocked == true
                if StockPiler4.Watch and StockPiler4.Watch.CanEnablePotionWatch then
                    blocked = StockPiler4.Watch.CanEnablePotionWatch(data.potionKey or data.id) ~= true
                    data.watchBlocked = blocked
                end
                StockPiler4.ViewList.PaintWatchCheckbox(rowName .. "Watch", data.watched == true, blocked)
                SetIconTexture(rowName .. "Icon", data.iconNum)
                LabelSetText(rowName .. "Name", data.name or L"")
                LabelSetTextColor(
                    rowName .. "Name",
                    tonumber(data.nameR) or 255,
                    tonumber(data.nameG) or 255,
                    tonumber(data.nameB) or 255
                )
                LabelSetText(rowName .. "Level", data.levelText or T("ui.dash"))
                LabelSetText(rowName .. "Effect", data.effectText or L"")
                LabelSetText(rowName .. "Power", data.powerText or L"0")
                LabelSetText(rowName .. "Stability", data.stabilityText or L"0")
                LabelSetText(rowName .. "Multiplier", data.multiplierText or L"0")
                LabelSetText(rowName .. "SuperCrit", data.superCritText or T("ui.dash"))
                LabelSetText(rowName .. "Yield", data.yieldText or T("ui.dash"))
                LabelSetText(rowName .. "Have", data.haveText or towstring(tostring(data.have or 0)))
                LabelSetTextColor(rowName .. "Have", 255, 255, 255)
                if DoesWindowExist(rowName .. "Recipe") then
                    WindowSetShowing(rowName .. "Recipe", data.hasRecipe == true)
                end
                if DoesWindowExist(rowName .. "Forget") then
                    WindowSetShowing(rowName .. "Forget", data.hasRecipe == true)
                end
            else
                WindowSetShowing(rowName, false)
            end
        end
    end
end

function StockPiler4TabPotions.OnSearchChanged()
    local text = TextEditBoxGetText("SP4TabPotionsSearchBox")
    GetSettings().potionNameFilter = ToNarrow(text)
    StockPiler4TabPotions.Refresh()
end

function StockPiler4TabPotions.OnEffectComboChanged()
    local idx = tonumber(ComboBoxGetSelectedMenuItem("SP4TabPotionsEffectCombo")) or 1
    local cycle = EffectCycle()
    local newFilter = cycle[idx] or ""
    local s = GetSettings()
    if s.potionEffectFilter == newFilter then
        return
    end
    s.potionEffectFilter = newFilter
    StockPiler4TabPotions.Refresh()
end

function StockPiler4TabPotions.OnSortColumn()
    local id = WindowGetId(SystemData.ActiveWindow.name)
    local col = SORT_IDS[id]
    if not col then
        return
    end
    local s = GetSettings()
    if s.potionSortColumn == col then
        s.potionSortAscending = not (s.potionSortAscending ~= false)
    else
        s.potionSortColumn = col
        s.potionSortAscending = true
    end
    StockPiler4TabPotions.Refresh()
end

function StockPiler4TabPotions.OnToggleWatch()
    local data = RowDataFromActiveChild()
    if not data then
        return
    end
    local potionKey = data.potionKey or data.id
    local win = SystemData.ActiveWindow.name
    local enabled = ButtonGetPressedFlag(win) == true
    if enabled then
        local blocked = data.watchBlocked == true
        if StockPiler4.Watch and StockPiler4.Watch.CanEnablePotionWatch then
            blocked = StockPiler4.Watch.CanEnablePotionWatch(potionKey) ~= true
            data.watchBlocked = blocked
        end
        if blocked then
            if DoesWindowExist(win) then
                ButtonSetPressedFlag(win, false)
                if ButtonSetDisabledFlag then
                    ButtonSetDisabledFlag(win, true)
                end
            end
            -- Notify via the shared gate (does not enable).
            if StockPiler4.Watch and StockPiler4.Watch.SetEnabled then
                StockPiler4.Watch.SetEnabled(potionKey, true, { fromPotionsToggle = true })
            end
            return
        end
    end
    local ok = true
    if StockPiler4.Watch and StockPiler4.Watch.SetEnabled then
        local _, setOk = StockPiler4.Watch.SetEnabled(potionKey, enabled, { fromPotionsToggle = true })
        ok = setOk ~= false
        if enabled and ok ~= true then
            enabled = false
            if DoesWindowExist(win) then
                ButtonSetPressedFlag(win, false)
                if ButtonSetDisabledFlag then
                    ButtonSetDisabledFlag(win, true)
                end
            end
            data.watchBlocked = true
        end
    else
        local watch = StockPiler4.Catalog and StockPiler4.Catalog.EnsureWatch and StockPiler4.Catalog.EnsureWatch(potionKey)
        if type(watch) == "table" then
            watch.enabled = enabled
            if enabled then
                watch.autoGrow = true
            end
        end
        if StockPiler4.Watch and StockPiler4.Watch.BumpGen then
            StockPiler4.Watch.BumpGen()
        end
    end
    data.watched = enabled
    AfterWatchToggle()
    if StockPiler4TabPotions.UpdateRows then
        StockPiler4TabPotions.UpdateRows()
    end
end

function StockPiler4TabPotions.OnMouseOverIcon()
    local data = RowDataFromActiveChild()
    if not data then
        return
    end
    local itemData = data.itemData
    if StockPiler4.Inventory and StockPiler4.Inventory.ShowItemTooltip
        and StockPiler4.Inventory.ShowItemTooltip(itemData, SystemData.ActiveWindow.name)
    then
        return
    end
    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, data.name or T("ui.potion_fallback"))
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_RIGHT)
end

function StockPiler4TabPotions.OnMouseOverRecipe()
    local data = RowDataFromActiveChild()
    if not data or not data.recipeData then
        return
    end
    if StockPiler4.RecipeTooltip and StockPiler4.RecipeTooltip.Show then
        StockPiler4.RecipeTooltip.Show(SystemData.ActiveWindow.name, data.recipeData)
    end
end

function StockPiler4TabPotions.ConfirmForgetRecipe()
    local outputUid = StockPiler4TabPotions._pendingForgetOutputUid
    local recipeSpecKey = StockPiler4TabPotions._pendingForgetRecipeKey
    local label = StockPiler4TabPotions._pendingForgetLabel or recipeSpecKey
    StockPiler4TabPotions._pendingForgetOutputUid = nil
    StockPiler4TabPotions._pendingForgetRecipeKey = nil
    StockPiler4TabPotions._pendingForgetKey = nil
    StockPiler4TabPotions._pendingForgetLabel = nil
    local forgot = false
    if StockPiler4.Catalog and StockPiler4.Catalog.ForgetPotionRecipeLink then
        forgot = StockPiler4.Catalog.ForgetPotionRecipeLink(outputUid, recipeSpecKey) == true
    end
    if forgot then
        if StockPiler4.Ui and StockPiler4.Ui.Print then
            StockPiler4.Ui.Print(T("ui.forgot_recipe", { name = label }))
        end
        StockPiler4TabPotions.Refresh()
    end
end

function StockPiler4TabPotions.OnForgetRow()
    local data = RowDataFromActiveChild()
    if not data or not data.hasRecipe then
        return
    end
    local outputUid = tonumber(data.uniqueID) or 0
    local recipeSpecKey = data.recipeSpecKey
    local label = data.name or T("ui.potion_fallback")
    StockPiler4TabPotions._pendingForgetOutputUid = outputUid
    StockPiler4TabPotions._pendingForgetRecipeKey = recipeSpecKey
    StockPiler4TabPotions._pendingForgetKey = data.potionKey
    StockPiler4TabPotions._pendingForgetLabel = label
    StockPiler4.ViewList.ConfirmTwoButton(
        T("potions.forget_confirm", { name = label }),
        StockPiler4TabPotions.ConfirmForgetRecipe
    )
end

function StockPiler4TabPotions.OnMouseOverForget()
    StockPiler4.ViewList.ShowTextTip(SystemData.ActiveWindow.name, T("potions.forget_tip"))
end

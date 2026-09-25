----------------------------------------------------------------
-- StockPiler4TabPlants -- known harvested plants (watch / filters / forget)
----------------------------------------------------------------

StockPiler4TabPlants = {}

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

StockPiler4TabPlants.listData = {}
StockPiler4TabPlants.displayOrder = {}

local ICON_SCALE = 0.34

local SORT_IDS = {
    [1] = "name",
    [2] = "effect",
    [3] = "power",
    [4] = "stability",
    [5] = "superCrit",
    [6] = "stock",
    [7] = "stock",
    [8] = "watch",
    [9] = "level",
    [10] = "multiplier",
    [11] = "duration",
}

local SORT_HEADERS = {
    watch = "SP4TabPlantsSortWatch",
    name = "SP4TabPlantsSortName",
    level = "SP4TabPlantsSortLevel",
    effect = "SP4TabPlantsSortEffect",
    power = "SP4TabPlantsSortPower",
    stability = "SP4TabPlantsSortStability",
    multiplier = "SP4TabPlantsSortMultiplier",
    duration = "SP4TabPlantsSortDuration",
    superCrit = "SP4TabPlantsSortSuperCrit",
    stock = "SP4TabPlantsSortStock",
}

local function ToNarrow(value)
    return StockPiler4.Util.ToNarrow(value)
end

local function GetSettings()
    if StockPiler4.Persistence and StockPiler4.Persistence.GetSettings then
        return StockPiler4.Persistence.GetSettings()
    end
    StockPiler4.Settings = StockPiler4.Settings or {}
    return StockPiler4.Settings
end

local function ItemRarityNameColor(itemData)
    return StockPiler4.ViewList.ItemRarityNameColor(itemData)
end

--- Resolve bag/DB sample so Plants-tab names get tier tint (cached catalog
--- shells often omit rarity after ListPlantEntries cache hits).
local function EnsurePlantNameRarityColors(plant)
    if type(plant) ~= "table" then
        return 255, 255, 255
    end
    local itemData = plant.itemData
    local uid = tonumber(plant.plantUid) or 0
    local needResolve = type(itemData) ~= "table"
        or (tonumber(itemData.rarity) or 0) <= 0
    if (tonumber(plant.rarity) or 0) > 0 and type(itemData) == "table"
        and (tonumber(itemData.rarity) or 0) <= 0
    then
        itemData.rarity = plant.rarity
        needResolve = false
    end
    if needResolve and StockPiler4.Inventory and uid > 0 then
        if StockPiler4.Inventory.GetSample then
            local sample = StockPiler4.Inventory.GetSample(uid)
            if type(sample) == "table" then
                if type(itemData) ~= "table" then
                    itemData = sample
                else
                    if (tonumber(sample.rarity) or 0) > 0 then
                        itemData.rarity = sample.rarity
                    end
                    if sample.name ~= nil and (itemData.name == nil or itemData.name == L"") then
                        itemData.name = sample.name
                    end
                end
                plant.itemData = itemData
            end
        end
        if StockPiler4.Inventory.ResolvePotionItemData then
            itemData = StockPiler4.Inventory.ResolvePotionItemData(
                plant.plantKey,
                uid,
                itemData
            )
            if type(itemData) == "table" then
                plant.itemData = itemData
            end
        end
    end
    itemData = plant.itemData
    if type(itemData) == "table" and (tonumber(itemData.rarity) or 0) <= 0
        and (tonumber(plant.rarity) or 0) > 0
    then
        itemData.rarity = plant.rarity
    end
    local nameR, nameG, nameB = ItemRarityNameColor(itemData)
    plant.nameR, plant.nameG, plant.nameB = nameR, nameG, nameB
    return nameR, nameG, nameB
end

local function FormatSignedStat(n)
    return StockPiler4.ViewList.FormatSignedStat(n, { zeroAsDash = true })
end

-- Match Potions tab: SPECIAL_CHANCE is already a percent points value (1 -> "1%").
local function FormatPercentStat(n)
    return StockPiler4.ViewList.FormatPercentStat(n)
end

local function EffectTextForRow(effectKey)
    return StockPiler4.ViewList.EffectTextForRow(effectKey, { emptyDash = true })
end

local function IconMarkup(iconNum)
    iconNum = tonumber(iconNum) or 0
    if iconNum <= 0 then
        return L""
    end
    return towstring(string.format("<icon%05d> ", iconNum))
end

local function CompareName(a, b)
    return string.lower(ToNarrow(a.name)) < string.lower(ToNarrow(b.name))
end

local function CompareRows(a, b, column, ascending)
    local function finish(less)
        if ascending then
            return less
        end
        return not less
    end
    if column == "level" then
        if (a.levelNum or 0) == (b.levelNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.levelNum or 0) < (b.levelNum or 0))
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
    elseif column == "duration" then
        if (a.durationNum or 0) == (b.durationNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.durationNum or 0) < (b.durationNum or 0))
    elseif column == "superCrit" then
        if (a.superCritNum or 0) == (b.superCritNum or 0) then
            return CompareName(a, b)
        end
        return finish((a.superCritNum or 0) < (b.superCritNum or 0))
    elseif column == "stock" or column == "have" then
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
    local column = s.plantSortColumn or "name"
    local ascending = s.plantSortAscending ~= false
    table.sort(rows, function(a, b)
        return CompareRows(a, b, column, ascending)
    end)
end

local function EffectCycle()
    return StockPiler4.ViewList.EffectFilterCycle()
end

local function SyncEffectComboSelection()
    StockPiler4.ViewList.SyncEffectCombo("SP4TabPlantsEffectCombo", (GetSettings().plantEffectFilter) or "")
end

local function InitEffectCombo()
    StockPiler4.ViewList.InitEffectCombo(
        "SP4TabPlantsEffectCombo",
        (GetSettings().plantEffectFilter) or "",
        EffectTextForRow
    )
end

local function UpdateSortHeaderLabels()
    local labels = {
        name = T("plants.sort.name"),
        level = T("plants.sort.level"),
        effect = T("plants.sort.effect"),
        power = T("plants.sort.power"),
        stability = T("plants.sort.stability"),
        multiplier = T("plants.sort.multiplier"),
        duration = T("plants.sort.duration"),
        superCrit = T("plants.sort.super_crit"),
        stock = T("plants.sort.stock"),
    }
    for key, win in pairs(SORT_HEADERS) do
        if DoesWindowExist(win) and labels[key] then
            ButtonSetText(win, labels[key])
        end
    end
    if DoesWindowExist("SP4TabPlantsSortRecipes") then
        ButtonSetText("SP4TabPlantsSortRecipes", T("plants.sort.recipes"))
    end
    if DoesWindowExist("SP4TabPlantsSortForget") then
        ButtonSetText("SP4TabPlantsSortForget", T("plants.sort.forget"))
    end
end

local function UpdateSortHeaders()
    UpdateSortHeaderLabels()
    local s = GetSettings()
    StockPiler4.ViewList.UpdateSortArrows(
        SORT_HEADERS,
        s.plantSortColumn or "name",
        s.plantSortAscending ~= false
    )
end

local function VisibleListBuildKey(s)
    local knowGen = 0
    if StockPiler4.Knowledge and StockPiler4.Knowledge.GetGen then
        knowGen = tonumber(StockPiler4.Knowledge.GetGen()) or 0
    end
    local watchGen = 0
    if StockPiler4.Watch and StockPiler4.Watch.GetGen then
        watchGen = tonumber(StockPiler4.Watch.GetGen()) or 0
    end
    return table.concat({
        tostring(knowGen),
        tostring(watchGen),
        tostring(s.plantNameFilter or ""),
        tostring(s.plantEffectFilter or ""),
        tostring(s.plantSortColumn or "name"),
        tostring(s.plantSortAscending ~= false),
    }, "|")
end

local function PatchVisibleListStocks()
    local Catalog = StockPiler4.Catalog
    local rows = StockPiler4TabPlants.listData
    if type(rows) ~= "table" then
        return false
    end
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            local have = 0
            if Catalog and Catalog.PlantHave then
                have = Catalog.PlantHave(row.plantUid)
            end
            row.have = have
            local stockW = towstring(tostring(have))
            row.stockText = stockW
            row.yieldText = stockW
        end
    end
    return true
end

local function BuildVisibleList(opts)
    opts = type(opts) == "table" and opts or {}
    local s = GetSettings()
    if type(s) ~= "table" then
        return
    end
    local buildKey = VisibleListBuildKey(s)
    if opts.stocksOnly == true
        and StockPiler4TabPlants._listBuildKey == buildKey
        and type(StockPiler4TabPlants.listData) == "table"
        and #StockPiler4TabPlants.listData > 0
    then
        PatchVisibleListStocks()
        return
    end
    if opts.force ~= true
        and opts.stocksOnly ~= true
        and StockPiler4TabPlants._listBuildKey == buildKey
        and type(StockPiler4TabPlants.listData) == "table"
        and #StockPiler4TabPlants.listData > 0
    then
        -- Tab flip / UiFlush with unchanged filters: refresh stock counts only.
        PatchVisibleListStocks()
        return
    end

    local nameFilter = string.lower(tostring(s.plantNameFilter or ""))
    local effectFilter = s.plantEffectFilter or ""
    local rows = {}

    if StockPiler4.Inventory and StockPiler4.Inventory.RefreshAllIfNeeded then
        StockPiler4.Inventory.RefreshAllIfNeeded()
    end

    local Catalog = StockPiler4.Catalog
    local plants = Catalog and Catalog.ListPlantEntries and Catalog.ListPlantEntries() or {}

    for i = 1, #plants do
        local plant = plants[i]
        local plantKey = plant.plantKey
        local watch = Catalog and Catalog.GetPlantWatch and Catalog.GetPlantWatch(plantKey)
            or { enabled = false, targetStock = 40 }
        local watched = watch.enabled == true
        local have = tonumber(plant.have) or 0
        if Catalog and Catalog.PlantHave then
            have = Catalog.PlantHave(plant.plantUid)
        end
        local effectKey = plant.effectKey
        local include = true
        if nameFilter ~= "" then
            local nm = string.lower(ToNarrow(plant.name))
            if string.find(nm, nameFilter, 1, true) == nil then
                include = false
            end
        end
        if include and effectFilter ~= "" and tostring(effectKey or "") ~= effectFilter then
            include = false
        end
        if include then
            local powerNum = tonumber(plant.power) or 0
            local stabilityNum = tonumber(plant.stability) or 0
            local durationNum = tonumber(plant.duration) or 0
            local multiplierNum = tonumber(plant.multiplier) or 0
            local superCritNum = tonumber(plant.superCrit) or 0
            local levelNum = tonumber(plant.apoLevel) or 0
            local stockW = towstring(tostring(have))
            local nameR, nameG, nameB = EnsurePlantNameRarityColors(plant)
            rows[#rows + 1] = {
                id = plantKey,
                plantKey = plantKey,
                plantUid = plant.plantUid,
                seedUid = plant.seedUid,
                name = plant.name,
                effectKey = effectKey,
                effectText = EffectTextForRow(effectKey),
                powerNum = powerNum,
                powerText = FormatSignedStat(powerNum),
                stabilityNum = stabilityNum,
                stabilityText = FormatSignedStat(stabilityNum),
                durationNum = durationNum,
                durationText = FormatSignedStat(durationNum),
                multiplierNum = multiplierNum,
                multiplierText = FormatSignedStat(multiplierNum),
                superCritNum = superCritNum,
                superCritText = FormatPercentStat(superCritNum),
                stockText = stockW,
                haveText = L"",
                yieldText = stockW,
                levelNum = levelNum,
                levelText = towstring(levelNum > 0 and tostring(levelNum) or ""),
                have = have,
                watched = watched,
                watchBlocked = (StockPiler4.Watch and StockPiler4.Watch.CanEnablePlantWatch
                    and StockPiler4.Watch.CanEnablePlantWatch(plantKey) ~= true) == true,
                iconNum = tonumber(plant.iconNum) or 0,
                itemData = plant.itemData,
                recipes = plant.recipes,
                recipeCount = tonumber(plant.recipeCount) or 0,
                hasRecipes = (tonumber(plant.recipeCount) or 0) > 0,
                nameR = nameR,
                nameG = nameG,
                nameB = nameB,
                kind = "plant",
            }
        end
    end

    SortRows(rows)
    StockPiler4TabPlants.listData = rows
    StockPiler4TabPlants._listBuildKey = buildKey
    local order = {}
    for i = 1, #rows do
        order[i] = i
    end
    StockPiler4TabPlants.displayOrder = order
end

function StockPiler4TabPlants.Initialize()
    if DoesWindowExist("SP4TabPlantsBannerTitle") then
        LabelSetText("SP4TabPlantsBannerTitle", T("plants.banner_title"))
    end
    if DoesWindowExist("SP4TabPlantsBannerText") then
        LabelSetText("SP4TabPlantsBannerText", T("plants.banner_text"))
    end
    if DoesWindowExist("SP4TabPlantsSearchLabel") then
        LabelSetText("SP4TabPlantsSearchLabel", T("potions.search"))
    end
    if DoesWindowExist("SP4TabPlantsEffectLabel") then
        LabelSetText("SP4TabPlantsEffectLabel", T("potions.effect"))
    end
    if DoesWindowExist("SP4TabPlantsFilterUnused") then
        WindowSetShowing("SP4TabPlantsFilterUnused", false)
    end
    if DoesWindowExist("SP4TabPlantsFilterUnusedLabel") then
        WindowSetShowing("SP4TabPlantsFilterUnusedLabel", false)
    end
    local s = GetSettings()
    if DoesWindowExist("SP4TabPlantsSearchBox") then
        TextEditBoxSetText("SP4TabPlantsSearchBox", towstring(s.plantNameFilter or ""))
    end
    InitEffectCombo()
    UpdateSortHeaders()
    StockPiler4TabPlants.Refresh()
end

function StockPiler4TabPlants.Refresh(opts)
    opts = type(opts) == "table" and opts or {}
    UpdateSortHeaders()
    local stocksOnly = opts.stocksOnly == true
    local prevKey = StockPiler4TabPlants._listBuildKey
    BuildVisibleList(opts)
    local keyChanged = prevKey ~= StockPiler4TabPlants._listBuildKey
    if DoesWindowExist("SP4TabPlantsList") then
        -- Avoid empty→full ListBoxSetDisplayOrder on stock-only / warm-cache tab flips
        -- (that alone hitch-painted ~700ms+ with RefreshWatch).
        if stocksOnly == true or (keyChanged ~= true and prevKey ~= nil) then
            StockPiler4TabPlants.UpdateRows()
        else
            ListBoxSetDisplayOrder("SP4TabPlantsList", {})
            ListBoxSetDisplayOrder("SP4TabPlantsList", StockPiler4TabPlants.displayOrder)
            StockPiler4TabPlants.UpdateRows()
        end
    end
end

function StockPiler4TabPlants.UpdateRows()
    if not SP4TabPlantsList then
        return
    end
    local numVisible = tonumber(SP4TabPlantsList.numVisibleRows) or 12
    local indices = SP4TabPlantsList.PopulatorIndices
    local listData = StockPiler4TabPlants.listData
    for rowIndex = 1, numVisible do
        local rowName = "SP4TabPlantsListRow" .. tostring(rowIndex)
        if DoesWindowExist(rowName) then
            local dataIndex = type(indices) == "table" and indices[rowIndex] or nil
            local data = type(listData) == "table" and dataIndex and listData[dataIndex] or nil
            if type(data) == "table" then
                WindowSetShowing(rowName, true)
                if DefaultColor and DefaultColor.SetListRowTint then
                    DefaultColor.SetListRowTint(rowName .. "Background", rowIndex, false)
                end
                if DoesWindowExist(rowName .. "Watch") then
                    -- Use build-time watchBlocked; re-querying CanEnablePlantWatch per
                    -- visible row on every paint stacked with ListPlantEntries spikes.
                    StockPiler4.ViewList.PaintWatchCheckbox(
                        rowName .. "Watch",
                        data.watched == true,
                        data.watchBlocked == true
                    )
                end
                if DoesWindowExist(rowName .. "Icon") then
                    StockPiler4.ViewList.SetIconTexture(rowName .. "Icon", data.iconNum, ICON_SCALE)
                end
                if DoesWindowExist(rowName .. "Name") then
                    LabelSetText(rowName .. "Name", data.name or L"")
                    LabelSetTextColor(rowName .. "Name", data.nameR or 255, data.nameG or 255, data.nameB or 255)
                end
                if DoesWindowExist(rowName .. "Recipe") then
                    WindowSetShowing(rowName .. "Recipe", data.hasRecipes == true)
                end
                if DoesWindowExist(rowName .. "Yield") then
                    LabelSetText(rowName .. "Yield", data.stockText or L"")
                end
            else
                WindowSetShowing(rowName, false)
            end
        end
    end
end

local function RowDataFromSender()
    local rowIndex = WindowGetId(WindowGetParent(SystemData.ActiveWindow.name))
    local dataIndex = ListBoxGetDataIndex("SP4TabPlantsList", rowIndex)
    return StockPiler4TabPlants.listData[dataIndex]
end

function StockPiler4TabPlants.OnToggleWatch()
    local data = RowDataFromSender()
    if type(data) ~= "table" or data.plantKey == nil then
        return
    end
    local Watch = StockPiler4.Watch
    if not (Watch and Watch.SetPlantEnabled) then
        return
    end
    local cur = Watch.GetPlantWatch and Watch.GetPlantWatch(data.plantKey)
    local enable = not (cur and cur.enabled == true)
    local win = SystemData.ActiveWindow.name
    if enable then
        local blocked = data.watchBlocked == true
        if Watch.CanEnablePlantWatch then
            blocked = Watch.CanEnablePlantWatch(data.plantKey) ~= true
            data.watchBlocked = blocked
        end
        if blocked then
            if DoesWindowExist(win) then
                ButtonSetPressedFlag(win, false)
                if ButtonSetDisabledFlag then
                    ButtonSetDisabledFlag(win, true)
                end
            end
            Watch.SetPlantEnabled(data.plantKey, true, { fromPlantsToggle = true })
            return
        end
    end
    local _, ok = Watch.SetPlantEnabled(data.plantKey, enable, { fromPlantsToggle = true })
    if enable and ok == false then
        enable = false
        data.watchBlocked = true
    end
    data.watched = enable
    if DoesWindowExist(win) then
        ButtonSetPressedFlag(win, enable)
        if ButtonSetDisabledFlag then
            ButtonSetDisabledFlag(win, data.watchBlocked == true)
        end
    end
    if StockPiler4.Scheduler and StockPiler4.Scheduler.EnqueuePlanRebuild then
        StockPiler4.Scheduler.EnqueuePlanRebuild()
    end
    if StockPiler4TabWatch and StockPiler4TabWatch.Refresh then
        StockPiler4TabWatch.Refresh({ forcePlan = true })
    end
end

function StockPiler4TabPlants.OnSortColumn()
    local id = WindowGetId(SystemData.ActiveWindow.name)
    local col = SORT_IDS[id]
    if col == nil then
        return
    end
    local s = GetSettings()
    if s.plantSortColumn == col then
        s.plantSortAscending = not (s.plantSortAscending ~= false)
    else
        s.plantSortColumn = col
        s.plantSortAscending = true
    end
    UpdateSortHeaders()
    StockPiler4TabPlants.Refresh()
end

function StockPiler4TabPlants.OnSearchChanged()
    local s = GetSettings()
    if DoesWindowExist("SP4TabPlantsSearchBox") then
        s.plantNameFilter = ToNarrow(TextEditBoxGetText("SP4TabPlantsSearchBox"))
    end
    StockPiler4TabPlants.Refresh()
end

function StockPiler4TabPlants.OnEffectComboChanged()
    local s = GetSettings()
    local sel = ComboBoxGetSelectedMenuItem("SP4TabPlantsEffectCombo")
    local cycle = EffectCycle()
    s.plantEffectFilter = cycle[sel] or ""
    StockPiler4TabPlants.Refresh()
end

function StockPiler4TabPlants.OnMouseOverIcon()
    local data = RowDataFromSender()
    if type(data) ~= "table" then
        return
    end
    local itemData = data.itemData
    local uid = tonumber(data.plantUid) or 0
    if StockPiler4.Inventory and StockPiler4.Inventory.ResolvePotionItemData and uid > 0 then
        itemData = StockPiler4.Inventory.ResolvePotionItemData(nil, uid, itemData) or itemData
    end
    if StockPiler4.Inventory and StockPiler4.Inventory.ShowItemTooltip
        and StockPiler4.Inventory.ShowItemTooltip(itemData, SystemData.ActiveWindow.name, { allowWithoutUse = true })
    then
        return
    end
    -- Same placeholder as Potions when bag/DB tooltip cannot be built.
    if type(Tooltips) == "table" and type(Tooltips.CreateTextOnlyTooltip) == "function" then
        Tooltips.CreateTextOnlyTooltip(
            SystemData.ActiveWindow.name,
            data.name or T("ui.plant_fallback")
        )
        if Tooltips.AnchorTooltip and Tooltips.ANCHOR_WINDOW_RIGHT then
            Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_RIGHT)
        end
    end
end

function StockPiler4TabPlants.OnMouseOverRecipe()
    local data = RowDataFromSender()
    if type(data) ~= "table" or type(data.recipes) ~= "table" then
        return
    end
    local tipRows = {}
    local seen = {}
    for i = 1, #data.recipes do
        local r = data.recipes[i]
        local potions = type(r) == "table" and r.potions or nil
        if type(potions) == "table" then
            for j = 1, #potions do
                local p = potions[j]
                if type(p) == "table" then
                    local uid = tonumber(p.outputUid) or 0
                    local key = uid > 0 and tostring(uid) or ToNarrow(p.name)
                    if key ~= "" and seen[key] ~= true then
                        seen[key] = true
                        local itemData = p.itemData
                        if uid > 0 and StockPiler4.Inventory and StockPiler4.Inventory.ResolvePotionItemData then
                            itemData = StockPiler4.Inventory.ResolvePotionItemData(nil, uid, itemData) or itemData
                        end
                        local iconNum = tonumber(p.iconNum) or tonumber(itemData and itemData.iconNum) or 0
                        local rR, rG, rB = ItemRarityNameColor(itemData or p)
                        tipRows[#tipRows + 1] = {
                            sort = string.lower(ToNarrow(p.name)),
                            text = IconMarkup(iconNum) .. (p.name or L""),
                            kind = "body",
                            color = { r = rR, g = rG, b = rB },
                        }
                    end
                end
            end
        elseif type(r) == "table" and type(r.potionNames) == "table" then
            for j = 1, #r.potionNames do
                local nm = ToNarrow(r.potionNames[j])
                if nm ~= "" and seen[nm] ~= true then
                    seen[nm] = true
                    tipRows[#tipRows + 1] = {
                        sort = string.lower(nm),
                        text = r.potionNames[j],
                        kind = "body",
                    }
                end
            end
        end
    end
    table.sort(tipRows, function(a, b)
        return (a.sort or "") < (b.sort or "")
    end)
    if #tipRows == 0 then
        tipRows[1] = { text = T("plants.recipes_none"), kind = "meta" }
    end
    table.insert(tipRows, 1, {
        text = T("plants.recipes_tip_title"),
        kind = "title",
    })
    if StockPiler4.RecipeTooltip and StockPiler4.RecipeTooltip.ShowColoredRows then
        StockPiler4.RecipeTooltip.ShowColoredRows(
            SystemData.ActiveWindow.name,
            tipRows,
            Tooltips and Tooltips.ANCHOR_WINDOW_RIGHT
        )
        return
    end
    local lines = {}
    for i = 1, #tipRows do
        lines[#lines + 1] = ToNarrow(tipRows[i].text)
    end
    if Tooltips and Tooltips.CreateTextOnlyTooltip then
        Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, towstring(table.concat(lines, "\n")))
        Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_RIGHT)
    end
end

function StockPiler4TabPlants.OnMouseOverForget()
    StockPiler4.ViewList.ShowTextTip(SystemData.ActiveWindow.name, T("tip.plants.forget"))
end

function StockPiler4TabPlants.ConfirmForgetPlant()
    local uid = tonumber(StockPiler4TabPlants._pendingForgetUid) or 0
    StockPiler4TabPlants._pendingForgetUid = nil
    StockPiler4TabPlants._pendingForgetLabel = nil
    if uid <= 0 then
        return
    end
    if StockPiler4.Catalog and StockPiler4.Catalog.ForgetPlant then
        StockPiler4.Catalog.ForgetPlant(uid)
    end
    StockPiler4TabPlants.Refresh()
    if StockPiler4TabWatch and StockPiler4TabWatch.Refresh then
        StockPiler4TabWatch.Refresh({ forcePlan = true })
    end
end

function StockPiler4TabPlants.OnForgetRow()
    local data = RowDataFromSender()
    if type(data) ~= "table" then
        return
    end
    local uid = tonumber(data.plantUid) or 0
    if uid <= 0 then
        return
    end
    local name = ToNarrow(data.name)
    StockPiler4TabPlants._pendingForgetUid = uid
    StockPiler4TabPlants._pendingForgetLabel = name
    StockPiler4.ViewList.ConfirmTwoButton(
        T("plants.forget_confirm", { name = towstring(name) }),
        StockPiler4TabPlants.ConfirmForgetPlant
    )
end

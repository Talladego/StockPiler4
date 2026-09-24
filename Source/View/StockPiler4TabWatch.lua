----------------------------------------------------------------
-- StockPiler4TabWatch -- bind-only Watch tab (PlanSnapshot.rows)
-- Row data comes from PlanSnapshot.Get().rows; no domain row assembly here.
----------------------------------------------------------------

StockPiler4TabWatch = {}
StockPiler4TabWatch.listData = {}
StockPiler4TabWatch.displayOrder = {}

local function T(key, tokens)
    return StockPiler4.Util.T(key, tokens)
end

local TAB_ROOT = "SP4TabWatch"
local ENABLE_WIN = "SP4TabWatchEnable"
local ADDITIVES_WIN = "SP4TabWatchAdditives"
local AUTOBUY_WIN = "SP4TabWatchAutoBuy"
local SEED_BUFFER_ENABLE_WIN = "SP4TabWatchSeedBufferEnable"
local COMBAT_PAUSE_WIN = "SP4TabWatchCombatPause"
local SKILLUP_SKILLS_WIN = "SP4TabWatchSkillUpSkills"
local UPGRADE_SEEDS_WIN = "SP4TabWatchUpgradeSeeds"

local COLOR_OK = { 80, 200, 80 }
local COLOR_WARN = { 220, 180, 60 }
local COLOR_BLOCK = { 220, 70, 70 }
local COLOR_GRAY = { 140, 140, 140 }

local ICON_SCALE = 0.34
local TARGET_MAX = 200
local syncingUi = false

local function CharRow(create)
    return StockPiler4.Util.CharacterRow(create)
end

local function CanAutoGrowUi()
    local Caps = StockPiler4.TradeSkillCaps
    return Caps and Caps.CanAutoGrow and Caps.CanAutoGrow() == true
end

local function CanAutoBuyUi()
    local Caps = StockPiler4.TradeSkillCaps
    if Caps and Caps.CanApothecary and Caps.CanApothecary() == true then
        return true
    end
    return CanAutoGrowUi()
end

local function OnOff(flag)
    return flag and T("boot.on") or T("boot.off")
end

local function NotifySettings(msg)
    if StockPiler4.Ui and StockPiler4.Ui.Print then
        StockPiler4.Ui.Print(msg)
    elseif StockPiler4.Debug and StockPiler4.Debug.Print then
        StockPiler4.Debug.Print(msg)
    end
end

local function TintStepper(bgWin)
    if DoesWindowExist(bgWin) and WindowSetTintColor then
        WindowSetTintColor(bgWin, 40, 40, 40)
    end
end

--- TintableSolidBackground defaults to bright white until SetListRowTint runs.
--- Session settle defers Watch paint ~2.5s, so prime dark chrome and hide
--- unpainted rows so login/reload never flashes white bars.
function StockPiler4TabWatch.PrimeRowChrome()
    if not DoesWindowExist("SP4TabWatchList") then
        return
    end
    local numVisible = 11
    if SP4TabWatchList and SP4TabWatchList.numVisibleRows then
        numVisible = tonumber(SP4TabWatchList.numVisibleRows) or 11
    end
    local paintKeys = StockPiler4TabWatch._rowPaintKey
    for rowIndex = 1, numVisible do
        local rowName = "SP4TabWatchListRow" .. rowIndex
        if DoesWindowExist(rowName) then
            if DefaultColor and DefaultColor.SetListRowTint then
                DefaultColor.SetListRowTint(rowName .. "Background", rowIndex, false)
            elseif WindowSetTintColor then
                WindowSetTintColor(rowName .. "Background", 20, 20, 20)
            end
            TintStepper(rowName .. "PrioChipBg")
            TintStepper(rowName .. "TargetChipBg")
            if type(paintKeys) ~= "table" or paintKeys[rowIndex] == nil then
                WindowSetShowing(rowName, false)
            end
        end
    end
end

local function SetChipNumber(valueWin, chipWin, value)
    if DoesWindowExist(valueWin) then
        LabelSetText(valueWin, towstring(tostring(value)))
        LabelSetTextColor(valueWin, 255, 255, 255)
    end
    if DoesWindowExist(chipWin) then
        TintStepper(chipWin .. "Bg")
    end
end

local function ChipDelta(flags, dir)
    local step = 1
    if SystemData and SystemData.ButtonFlags and flags == SystemData.ButtonFlags.SHIFT then
        step = 10
    elseif type(flags) == "number" and flags ~= 0 then
        -- Some clients pass combined flags; treat nonzero as shift-ish when SHIFT bit present.
        if SystemData and SystemData.ButtonFlags and SystemData.ButtonFlags.SHIFT then
            if bit and bit.band and bit.band(flags, SystemData.ButtonFlags.SHIFT) ~= 0 then
                step = 10
            end
        end
    end
    return step * (dir or 1)
end

local function Clamp(n, lo, hi)
    n = tonumber(n) or lo
    if n < lo then
        return lo
    end
    if n > hi then
        return hi
    end
    return math.floor(n)
end

local function SetIconTexture(iconWin, iconNum)
    StockPiler4.ViewList.SetIconTexture(iconWin, iconNum, ICON_SCALE)
end

local function ApplyStatusColor(labelWin, statusKey)
    statusKey = tostring(statusKey or "")
    local c = COLOR_GRAY
    if statusKey == "potion_stocked" or statusKey == "plant_stocked" or statusKey == "ready_to_craft"
        or statusKey == "planting" or statusKey == "buffer_plant" or statusKey == "growing"
        or statusKey == "fallback_blocked" or statusKey == "skill_done"
    then
        c = COLOR_OK
    elseif statusKey == "ready_to_craft_shared"
        or statusKey == "restocking"
        or statusKey == "need_seeds"
        or statusKey == "upgrading_seed"
        or statusKey == "refining"
        or statusKey == "wait_cult"
        or statusKey == "seed_buffer"
        or statusKey == "idle"
        or statusKey == "waiting_watches"
        or statusKey == "waiting_potions"
        or statusKey == "waiting_plants"
        or statusKey == "waiting_seed_buffer"
    then
        c = COLOR_WARN
    elseif statusKey == "no_recipe"
        or statusKey == "no_target"
        or statusKey == "enable_autogrow"
        or statusKey == "need_apothecary"
        or statusKey == "need_skill"
        or statusKey == "buy_ingredients"
        or statusKey == "no_seeds"
        or statusKey == "need_vendor"
        or statusKey == "autobuy_off"
        or statusKey == "no_vendor_seed"
        or statusKey == "need_mats"
        or statusKey == "need_resin"
        or statusKey == "unstable"
        or statusKey == "need_container_vendor"
        or statusKey == "no_vendor_container"
    then
        c = COLOR_BLOCK
    end
    LabelSetTextColor(labelWin, c[1], c[2], c[3])
end

local function IsPlantWatchRow(data)
    return type(data) == "table" and (data.kind == "plant" or data.isPlantWatch == true)
end

local function IsUpgradeWatchRow(data)
    return type(data) == "table" and data.upgradeWatch == true
end

local function IsSkillUpWatchRow(data)
    return type(data) == "table" and data.skillUp == true
end

--- SkillUp + Upgrade Seed ephemeral rows (addon-owned, not saved watches).
local function IsEphemeralWatchRow(data)
    return IsSkillUpWatchRow(data) or IsUpgradeWatchRow(data)
        or (type(data) == "table" and data.addonOwned == true)
end

local function EnsureWatchNameRarityColors(data)
    if type(data) ~= "table" then
        return 255, 255, 255
    end
    local itemData = data.itemData
    local uid = tonumber(data.uniqueID) or tonumber(data.plantUid) or 0
    local isPlant = IsPlantWatchRow(data)
    local needResolve = type(itemData) ~= "table"
        or (tonumber(itemData.rarity) or 0) <= 0
    if not isPlant then
        needResolve = needResolve
            or not (StockPiler4.Inventory and StockPiler4.Inventory.ItemDataHasUseBonus
                and StockPiler4.Inventory.ItemDataHasUseBonus(itemData))
    elseif StockPiler4.Inventory then
        -- Plants: always prefer bag/DB sample so rarity tint matches the item tooltip.
        needResolve = true
    end
    if needResolve and StockPiler4.Inventory then
        if StockPiler4.Inventory.GetSample and uid > 0 then
            local sample = StockPiler4.Inventory.GetSample(uid)
            if type(sample) == "table" then
                itemData = sample
                data.itemData = sample
            end
        end
        if StockPiler4.Inventory.ResolvePotionItemData then
            itemData = StockPiler4.Inventory.ResolvePotionItemData(
                data.potionKey or data.potionBaseKey or data.plantKey,
                uid,
                itemData
            )
            if type(itemData) == "table" then
                data.itemData = itemData
            end
        end
    end
    itemData = data.itemData
    if itemData and DataUtils and DataUtils.GetItemRarityColor then
        local ok, color = pcall(DataUtils.GetItemRarityColor, itemData)
        if ok and type(color) == "table" then
            data.nameR = tonumber(color.r) or 255
            data.nameG = tonumber(color.g) or 255
            data.nameB = tonumber(color.b) or 255
            return data.nameR, data.nameG, data.nameB
        end
    end
    if data.nameR ~= nil and data.nameG ~= nil and data.nameB ~= nil then
        return tonumber(data.nameR) or 255, tonumber(data.nameG) or 255, tonumber(data.nameB) or 255
    end
    data.nameR, data.nameG, data.nameB = 255, 255, 255
    return 255, 255, 255
end

local function GetRowCraftUiState(data)
    local Brew = StockPiler4.Brew
    if not Brew or type(data) ~= "table" then
        return "idle"
    end
    local session = Brew.GetSession and Brew.GetSession()
    if type(session) ~= "table" then
        return "idle"
    end
    local phase = tostring(session.phase or "idle")
    if phase == "idle" then
        return "idle"
    end
    local rowKey = tostring(data.potionRecipeKey or data.id or data.potionKey or "")
    local sessKey = tostring(session.potionRecipeKey or session.potionKey or session.rowId or "")
    if rowKey ~= "" and sessKey ~= "" and rowKey == sessKey then
        if phase == "loading" then
            return "load"
        end
        if phase == "loaded" then
            return "brew"
        end
    end
    return "idle"
end

--- True when Craftable label is green: bags can craft and seed buffer is safe.
--- Shared mats do not block green (Status may still show Ready-shared).
local function RowCraftableGreen(data)
    if type(data) ~= "table" then
        return false
    end
    if data.craftableSafe == true then
        return true
    end
    if data.craftableSafe == false then
        return false
    end
    -- Fallback if plan row lacks stamp (tests / partial rows).
    if (tonumber(data.craftable) or 0) <= 0 then
        return false
    end
    return data.seedBufferShort ~= true
end

local function SetButtonTextColorAll(windowName, r, g, b)
    if not windowName or not DoesWindowExist(windowName) or type(ButtonSetTextColor) ~= "function" then
        return
    end
    local states = { 0, 1, 2, 3, 4 }
    if Button and Button.ButtonState then
        states = {
            Button.ButtonState.NORMAL or 0,
            Button.ButtonState.HIGHLIGHTED or 1,
            Button.ButtonState.PRESSED or 2,
            Button.ButtonState.PRESSED_HIGHLIGHTED or 3,
            Button.ButtonState.DISABLED or 4,
        }
    end
    for i = 1, #states do
        pcall(ButtonSetTextColor, windowName, states[i], r, g, b)
    end
end

local function ApplyRowBrewButton(btnWin, data)
    if not DoesWindowExist(btnWin) then
        return
    end
    if IsPlantWatchRow(data) or (type(data) == "table" and data.hideBrew == true) then
        WindowSetShowing(btnWin, false)
        return
    end
    WindowSetShowing(btnWin, true)
    local craftableGreen = RowCraftableGreen(data)
    local state = GetRowCraftUiState(data)
    -- This row's apo session is loaded: always show Brew (ready to perform).
    if state == "brew" then
        ButtonSetText(btnWin, T("watch.chip_brew"))
        ButtonSetDisabledFlag(btnWin, false)
        SetButtonTextColorAll(btnWin, COLOR_OK[1], COLOR_OK[2], COLOR_OK[3])
        return
    end
    if not craftableGreen then
        ButtonSetText(btnWin, T("watch.chip_load"))
        ButtonSetDisabledFlag(btnWin, true)
        SetButtonTextColorAll(btnWin, COLOR_GRAY[1], COLOR_GRAY[2], COLOR_GRAY[3])
        return
    end
    -- Idle or loading: yellow Load (green Craftable, apo not ready to perform).
    ButtonSetDisabledFlag(btnWin, false)
    ButtonSetText(btnWin, T("watch.chip_load"))
    SetButtonTextColorAll(btnWin, COLOR_WARN[1], COLOR_WARN[2], COLOR_WARN[3])
end

local function BumpWatch()
    if StockPiler4.Watch and StockPiler4.Watch.BumpGen then
        StockPiler4.Watch.BumpGen()
    end
    if StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Invalidate then
        StockPiler4.PlanSnapshot.Invalidate()
    end
end

--- Soft demand change: Bump + immediate AutoGrow status reconcile + coalesced PlanRebuild.
local function AfterWatchSettingsChanged()
    BumpWatch()
    -- Flip Enable AutoGrow <-> Restocking now (UI throttle / plan gap must not leave stale status).
    if StockPiler4.Planner and StockPiler4.Planner.ReconcileAutoGrowStatusesNow then
        StockPiler4.Planner.ReconcileAutoGrowStatusesNow(StockPiler4TabWatch.listData)
    end
    if StockPiler4.Ui and StockPiler4.Ui.ClearWatchTipCaches then
        StockPiler4.Ui.ClearWatchTipCaches()
    else
        StockPiler4TabWatch._statusTipCache = nil
    end
    local Sch = StockPiler4.Scheduler
    if Sch and Sch.EnqueuePlanRebuild then
        Sch.EnqueuePlanRebuild({ nudge = true })
    end
    if StockPiler4.Ui then
        -- Bypass 5s Watch flush throttle so status text updates on this click.
        StockPiler4.Ui._watchUiLastKey = nil
        StockPiler4.Ui._watchUiFlushedAt = 0
        if StockPiler4.Ui.MarkWatchUiDirty then
            StockPiler4.Ui.MarkWatchUiDirty()
        end
    end
    if StockPiler4.Buy and StockPiler4.Buy.IsEnabled and StockPiler4.Buy.IsEnabled() == true then
        local VA = StockPiler4.VendorAdapter
        if VA and VA.IsStoreOpen and VA.IsStoreOpen() == true then
            if StockPiler4.Buy.InvalidateJobsCache then
                StockPiler4.Buy.InvalidateJobsCache()
            end
            if Sch and Sch.WakeAutoBuy then
                Sch.WakeAutoBuy()
            end
        end
    end
end

--- Reserve/Budget: no PlanRebuild; clear money-gate + wake AutoBuy if store open.
local function AfterSoftMoneySetting()
    if StockPiler4.Buy and StockPiler4.Buy.OnMoneySettingsChanged then
        StockPiler4.Buy.OnMoneySettingsChanged()
    end
    if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
        StockPiler4.Ui.MarkWatchUiDirty()
    end
    StockPiler4TabWatch.RefreshSkillGates()
end

local function ApplyTargetOptimistic(data, target)
    if type(data) ~= "table" then
        return
    end
    target = tonumber(target) or 0
    data.target = target
    data.targetText = towstring(tostring(target))
    data.potionMin = target
    local have = tonumber(data.potionHave) or 0
    data.potionDeficit = math.max(0, target - have)
    StockPiler4TabWatch._rowPaintKey = nil
    if StockPiler4TabWatch.UpdateRows then
        StockPiler4TabWatch.UpdateRows()
    end
end

local function PatchPlanSnapshotTarget(potionKey, target, have)
    if potionKey == nil then
        return
    end
    target = tonumber(target) or 0
    have = tonumber(have)
    local PS = StockPiler4.PlanSnapshot
    local plan = PS and PS.Get and PS.Get()
    if type(plan) ~= "table" or type(plan.rows) ~= "table" then
        return
    end
    local keyStr = tostring(potionKey)
    for i = 1, #plan.rows do
        local row = plan.rows[i]
        if type(row) == "table" then
            local rowKey = row.potionRecipeKey or row.id or row.potionKey
            if rowKey ~= nil and tostring(rowKey) == keyStr then
                row.target = target
                row.potionMin = target
                local rowHave = have
                if rowHave == nil then
                    rowHave = tonumber(row.potionHave) or 0
                end
                row.potionDeficit = math.max(0, target - rowHave)
            end
        end
    end
end

local function TargetChangeIsDemandNoop(have, oldTarget, newTarget)
    have = tonumber(have) or 0
    oldTarget = tonumber(oldTarget) or 0
    newTarget = tonumber(newTarget) or 0
    local oldDeficit = math.max(0, oldTarget - have)
    local newDeficit = math.max(0, newTarget - have)
    if oldDeficit > 0 or newDeficit > 0 then
        return false
    end
    if (oldTarget > 0) ~= (newTarget > 0) then
        return false
    end
    return true
end

local function AfterTargetChipChanged(data, potionKey, oldTarget, newTarget)
    local have = tonumber(data and data.potionHave) or 0
    if TargetChangeIsDemandNoop(have, oldTarget, newTarget) then
        ApplyTargetOptimistic(data, newTarget)
        PatchPlanSnapshotTarget(potionKey, newTarget, have)
        return
    end
    ApplyTargetOptimistic(data, newTarget)
    AfterWatchSettingsChanged()
end

local function HasEnabledWatch()
    local watches = StockPiler4.Watch and StockPiler4.Watch.GetWatches and StockPiler4.Watch.GetWatches()
    if type(watches) == "table" then
        for _, w in pairs(watches) do
            if type(w) == "table" and w.enabled == true then
                return true
            end
        end
    end
    if StockPiler4.Watch and StockPiler4.Watch.CountEnabledPlantWatches then
        if (tonumber(StockPiler4.Watch.CountEnabledPlantWatches()) or 0) > 0 then
            return true
        end
    end
    return false
end

local function HasSkillUpWatchStatus()
    local SkillUp = StockPiler4.SkillUp
    if SkillUp and SkillUp.ShouldShowWatchStatus and SkillUp.ShouldShowWatchStatus() == true then
        return true
    end
    local US = StockPiler4.UpgradeSeed
    return US and US.ShouldShowWatchStatus and US.ShouldShowWatchStatus() == true
end

local function BuildVisibleList(opts)
    opts = type(opts) == "table" and opts or {}
    local prevList = StockPiler4TabWatch.listData
    local prevOrder = StockPiler4TabWatch.displayOrder
    local plan = nil
    local forcePlan = opts.forcePlan == true
    local hasContent = HasEnabledWatch() or HasSkillUpWatchStatus()
    -- Never sync-force Planner.Build from Watch paint (SP2 Flatten). Empty/stale
    -- plan: keep previous rows and enqueue a coalesced rebuild.
    local Sch = StockPiler4.Scheduler
    local holdBuild = (Sch and Sch.IsHarvestStorm and Sch.IsHarvestStorm() == true)
        or (Sch and Sch.IsPlantQuiet and Sch.IsPlantQuiet() == true)
        or (Sch and Sch.IsPlanRebuildPending and Sch.IsPlanRebuildPending() == true)
    local snap = StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get
        and StockPiler4.PlanSnapshot.Get()
    local snapRows = type(snap) == "table" and snap.rows or nil
    local snapEmpty = type(snapRows) ~= "table" or #snapRows == 0
    if hasContent and (forcePlan or snapEmpty) and Sch and Sch.EnqueuePlanRebuild then
        Sch.EnqueuePlanRebuild({ nudge = holdBuild or not forcePlan })
    end
    if StockPiler4.Planner and StockPiler4.Planner.GetOrBuild then
        plan = StockPiler4.Planner.GetOrBuild({ refresh = false })
    elseif StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get then
        plan = StockPiler4.PlanSnapshot.Get()
    end
    local rows = type(plan) == "table" and plan.rows or nil
    if type(rows) ~= "table" or #rows == 0 then
        local keepPrev = type(prevList) == "table" and #prevList > 0
        if keepPrev then
            local keep = type(plan) ~= "table"
            if not keep and hasContent then
                keep = true
            end
            if keep then
                if Sch and Sch.EnqueuePlanRebuild then
                    Sch.EnqueuePlanRebuild({ nudge = true })
                end
                -- Prefer current snapshot rows when they exist (avoid orphaned stale listData).
                local snap = StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get
                    and StockPiler4.PlanSnapshot.Get()
                local snapRows = type(snap) == "table" and snap.rows or nil
                if type(snapRows) == "table" and #snapRows > 0 then
                    StockPiler4TabWatch.listData = snapRows
                else
                    StockPiler4TabWatch.listData = prevList
                end
                StockPiler4TabWatch.displayOrder = {}
                for i = 1, #StockPiler4TabWatch.listData do
                    StockPiler4TabWatch.displayOrder[i] = i
                end
                return
            end
        end
        rows = {}
    end
    StockPiler4TabWatch.listData = rows
    StockPiler4TabWatch.displayOrder = {}
    for i = 1, #StockPiler4TabWatch.listData do
        StockPiler4TabWatch.displayOrder[i] = i
    end
end

local function UpdateEnableCheckbox()
    if not DoesWindowExist(ENABLE_WIN) then
        return
    end
    local canGrow = CanAutoGrowUi()
    local row = CharRow(false)
    local on = canGrow and type(row) == "table" and row.autoGrowEnabled == true
    syncingUi = true
    ButtonSetCheckButtonFlag(ENABLE_WIN, true)
    ButtonSetPressedFlag(ENABLE_WIN, on)
    ButtonSetDisabledFlag(ENABLE_WIN, not canGrow)
    syncingUi = false
end

local function UpdateAdditivesCheckbox()
    if not DoesWindowExist(ADDITIVES_WIN) then
        return
    end
    local canGrow = CanAutoGrowUi()
    local row = CharRow(false)
    local on = canGrow and type(row) == "table" and row.autoGrowAdditives == true
    syncingUi = true
    ButtonSetCheckButtonFlag(ADDITIVES_WIN, true)
    ButtonSetPressedFlag(ADDITIVES_WIN, on)
    ButtonSetDisabledFlag(ADDITIVES_WIN, not canGrow)
    syncingUi = false
end

local function UpdateAutoBuyCheckbox()
    if not DoesWindowExist(AUTOBUY_WIN) then
        return
    end
    local canBuy = CanAutoBuyUi()
    local row = CharRow(false)
    local on = canBuy and type(row) == "table" and row.autoBuyEnabled == true
    syncingUi = true
    ButtonSetCheckButtonFlag(AUTOBUY_WIN, true)
    ButtonSetPressedFlag(AUTOBUY_WIN, on)
    ButtonSetDisabledFlag(AUTOBUY_WIN, not canBuy)
    syncingUi = false
end

local function UpdateCombatPauseCheckbox()
    if not DoesWindowExist(COMBAT_PAUSE_WIN) then
        return
    end
    local row = CharRow(false)
    local on = type(row) ~= "table" or row.autoGrowPauseCombat ~= false
    syncingUi = true
    ButtonSetCheckButtonFlag(COMBAT_PAUSE_WIN, true)
    ButtonSetPressedFlag(COMBAT_PAUSE_WIN, on)
    syncingUi = false
end

local function UpdateSkillUpCheckboxes()
    local SkillUp = StockPiler4.SkillUp
    local cultVis = SkillUp and SkillUp.IsCultVisible and SkillUp.IsCultVisible() == true
    local apoVis = SkillUp and SkillUp.IsApoVisible and SkillUp.IsApoVisible() == true
    local show = cultVis == true or apoVis == true
    local cultOn = SkillUp and SkillUp.IsCultEnabled and SkillUp.IsCultEnabled() == true
    local apoOn = SkillUp and SkillUp.IsApoEnabled and SkillUp.IsApoEnabled() == true
    local on = (cultVis == true and cultOn == true) or (apoVis == true and apoOn == true)

    if DoesWindowExist(SKILLUP_SKILLS_WIN) then
        WindowSetShowing(SKILLUP_SKILLS_WIN, show)
        syncingUi = true
        ButtonSetCheckButtonFlag(SKILLUP_SKILLS_WIN, true)
        ButtonSetPressedFlag(SKILLUP_SKILLS_WIN, show and on)
        syncingUi = false
    end
    if DoesWindowExist("SP4TabWatchSkillUpSkillsLabel") then
        WindowSetShowing("SP4TabWatchSkillUpSkillsLabel", show)
    end
end

local function UpdateSeedBufferEnableCheckbox()
    if not DoesWindowExist(SEED_BUFFER_ENABLE_WIN) then
        return
    end
    local canGrow = CanAutoGrowUi()
    local row = CharRow(false)
    local on = canGrow and (type(row) ~= "table" or row.growSeedBufferEnabled ~= false)
    syncingUi = true
    ButtonSetCheckButtonFlag(SEED_BUFFER_ENABLE_WIN, true)
    ButtonSetPressedFlag(SEED_BUFFER_ENABLE_WIN, on)
    ButtonSetDisabledFlag(SEED_BUFFER_ENABLE_WIN, not canGrow)
    syncingUi = false
end

local function UpdateUpgradeSeedsCheckbox()
    if not DoesWindowExist(UPGRADE_SEEDS_WIN) then
        return
    end
    local canGrow = CanAutoGrowUi()
    local US = StockPiler4.UpgradeSeed
    local on = canGrow and US and US.IsEnabled and US.IsEnabled() == true
    syncingUi = true
    ButtonSetCheckButtonFlag(UPGRADE_SEEDS_WIN, true)
    ButtonSetPressedFlag(UPGRADE_SEEDS_WIN, on == true)
    ButtonSetDisabledFlag(UPGRADE_SEEDS_WIN, not canGrow)
    syncingUi = false
end

local function UpdateSeedBufferLabel()
    local buf = StockPiler4.Watch and StockPiler4.Watch.GetSeedBufferMin
        and StockPiler4.Watch.GetSeedBufferMin() or 5
    SetChipNumber("SP4TabWatchSeedBufferChipValue", "SP4TabWatchSeedBufferChip", buf)
end

local function UpdateAutoBuyChips()
    local row = CharRow(false)
    local reserve = type(row) == "table" and tonumber(row.autoBuyReserveGold) or 10
    local budget = type(row) == "table" and tonumber(row.autoBuyBudgetGold) or 50
    SetChipNumber("SP4TabWatchReserveChipValue", "SP4TabWatchReserveChip", reserve)
    SetChipNumber("SP4TabWatchBudgetChipValue", "SP4TabWatchBudgetChip", budget)

    local spent = 0
    local exhausted = false
    local Buy = StockPiler4.Buy
    if Buy and Buy.GetSpentBrass then
        spent = tonumber(Buy.GetSpentBrass()) or 0
    elseif type(row) == "table" then
        spent = tonumber(row.autoBuySpentBrass) or 0
    end
    local budgetBrass = budget * ((Buy and Buy.BRASS_PER_GOLD) or 10000)
    exhausted = spent >= budgetBrass
    local c = exhausted and COLOR_BLOCK or COLOR_OK
    if DoesWindowExist("SP4TabWatchBudgetChipValue") then
        LabelSetTextColor("SP4TabWatchBudgetChipValue", c[1], c[2], c[3])
    end
    if DoesWindowExist("SP4TabWatchBudgetChipBg") and WindowSetTintColor then
        if exhausted then
            WindowSetTintColor("SP4TabWatchBudgetChipBg", 90, 30, 30)
        else
            WindowSetTintColor("SP4TabWatchBudgetChipBg", 30, 70, 30)
        end
    end
    if DoesWindowExist("SP4TabWatchBudgetReset") then
        local canReset = spent > 0
        ButtonSetDisabledFlag("SP4TabWatchBudgetReset", not canReset)
        if canReset then
            -- Match per-row Load/Brew: gold when actionable.
            SetButtonTextColorAll("SP4TabWatchBudgetReset", COLOR_WARN[1], COLOR_WARN[2], COLOR_WARN[3])
        else
            SetButtonTextColorAll("SP4TabWatchBudgetReset", COLOR_GRAY[1], COLOR_GRAY[2], COLOR_GRAY[3])
        end
    end
end

function StockPiler4TabWatch.RefreshAutoBuyMoneyUi()
    UpdateAutoBuyChips()
end

local function RowDataFromActiveChild()
    local win = SystemData.ActiveWindow and SystemData.ActiveWindow.name
    for _ = 1, 6 do
        if win == nil or win == "" then
            break
        end
        local rowIndex = WindowGetId(win)
        if rowIndex and rowIndex > 0 and DoesWindowExist("SP4TabWatchList") then
            local dataIndex = ListBoxGetDataIndex("SP4TabWatchList", rowIndex)
            local data = StockPiler4TabWatch.listData[dataIndex]
            if data then
                return data, win
            end
        end
        if type(WindowGetParent) == "function" then
            win = WindowGetParent(win)
        else
            break
        end
    end
    return nil
end

local function AdjustTarget(data, delta)
    if type(data) ~= "table" then
        return
    end
    if IsEphemeralWatchRow(data) then
        return
    end
    if IsPlantWatchRow(data) then
        local plantKey = data.plantKey or data.id or data.potionKey
        local oldTarget = tonumber(data.target) or 0
        local newTarget = Clamp(oldTarget + delta, 0, TARGET_MAX)
        if newTarget == oldTarget then
            return
        end
        if StockPiler4.Watch and StockPiler4.Watch.SetPlantTarget then
            StockPiler4.Watch.SetPlantTarget(plantKey, newTarget)
        end
        data.target = newTarget
        data.potionMin = newTarget
        data.targetText = towstring(tostring(newTarget))
        local have = tonumber(data.potionHave) or 0
        data.potionDeficit = math.max(0, newTarget - have)
        AfterWatchSettingsChanged()
        StockPiler4TabWatch._rowPaintKey = nil
        StockPiler4TabWatch.UpdateRows()
        return
    end
    local potionKey = data.potionRecipeKey or data.id or data.potionKey
    local oldTarget = tonumber(data.target) or 0
    local newTarget = Clamp(oldTarget + delta, 0, TARGET_MAX)
    if newTarget == oldTarget then
        return
    end
    if StockPiler4.Watch and StockPiler4.Watch.SetTarget then
        StockPiler4.Watch.SetTarget(potionKey, newTarget)
    end
    if newTarget > 0 and StockPiler4.Watch and StockPiler4.Watch.SetEnabled then
        local watch = StockPiler4.Watch.EnsureWatch and StockPiler4.Watch.EnsureWatch(potionKey)
        if type(watch) == "table" and watch.enabled ~= true then
            StockPiler4.Watch.SetEnabled(potionKey, true)
        end
    end
    AfterTargetChipChanged(data, potionKey, oldTarget, newTarget)
end

local function AdjustPriority(data, delta)
    if type(data) ~= "table" or IsPlantWatchRow(data) or IsEphemeralWatchRow(data) then
        return
    end
    local potionKey = data.potionRecipeKey or data.id or data.potionKey
    if potionKey == nil or not StockPiler4.Watch or not StockPiler4.Watch.BumpPriorityTier then
        return
    end
    local oldTier = tonumber(data.priorityTier)
    if oldTier == nil and StockPiler4.Watch.GetPriorityTier then
        oldTier = StockPiler4.Watch.GetPriorityTier(potionKey)
    end
    oldTier = tonumber(oldTier) or 1
    local watch = StockPiler4.Watch.BumpPriorityTier(potionKey, delta)
    local newTier = tonumber(watch and watch.priorityTier) or oldTier
    if StockPiler4.Watch.GetPriorityTier then
        newTier = StockPiler4.Watch.GetPriorityTier(potionKey)
    end
    if newTier == oldTier then
        return
    end
    data.priorityTier = newTier
    data.priorityTierText = towstring(tostring(newTier))
    AfterWatchSettingsChanged()
    -- Force rebuild so list re-sorts by tier.
    StockPiler4TabWatch.Refresh({ forcePlan = true })
end

function StockPiler4TabWatch.Initialize()
    LabelSetText("SP4TabWatchBannerTitle", T("watch.banner_title"))
    LabelSetText("SP4TabWatchBannerText", T("watch.banner_text"))
    LabelSetText("SP4TabWatchEnableLabel", T("watch.enable_autogrow"))
    LabelSetText("SP4TabWatchAdditivesLabel", T("watch.use_additives"))
    LabelSetText("SP4TabWatchSeedBufferLabel", T("watch.seed_buffer_label"))
    LabelSetText("SP4TabWatchAutoBuyLabel", T("watch.autobuy_label"))
    LabelSetText("SP4TabWatchCombatPauseLabel", T("watch.combat_pause_label"))
    LabelSetText("SP4TabWatchReserveLabel", T("watch.reserve_label"))
    LabelSetText("SP4TabWatchBudgetLabel", T("watch.budget_label"))
    if DoesWindowExist("SP4TabWatchBudgetReset") then
        ButtonSetText("SP4TabWatchBudgetReset", T("watch.budget_reset"))
    end
    if DoesWindowExist("SP4TabWatchSkillUpSkillsLabel") then
        LabelSetText("SP4TabWatchSkillUpSkillsLabel", T("watch.skillup_skills"))
    end
    if DoesWindowExist("SP4TabWatchUpgradeSeedsLabel") then
        LabelSetText("SP4TabWatchUpgradeSeedsLabel", T("watch.upgrade_seeds"))
    end
    TintStepper("SP4TabWatchSeedBufferChipBg")
    TintStepper("SP4TabWatchReserveChipBg")
    TintStepper("SP4TabWatchBudgetChipBg")
    ButtonSetText("SP4TabWatchColPrio", T("watch.col.prio"))
    ButtonSetText("SP4TabWatchColPotion", T("watch.col.name"))
    ButtonSetText("SP4TabWatchColStock", T("watch.col.stock"))
    ButtonSetText("SP4TabWatchColStatus", T("watch.col.status"))
    ButtonSetText("SP4TabWatchColCraftable", T("watch.col.craftable"))
    ButtonSetText("SP4TabWatchColTarget", T("watch.col.target"))
    ButtonSetText("SP4TabWatchColPriority", T("watch.col.autogrow"))
    ButtonSetText("SP4TabWatchColBrew", T("watch.col.brew"))
    StockPiler4TabWatch.RefreshSkillGates()
    if StockPiler4TabWatch.PrimeRowChrome then
        StockPiler4TabWatch.PrimeRowChrome()
    end
end

function StockPiler4TabWatch.RefreshSkillGates()
    if not DoesWindowExist(TAB_ROOT) then
        return
    end
    local canGrow = CanAutoGrowUi()
    local canBuy = CanAutoBuyUi()
    local row = CharRow(false)
    local autoGrow = canGrow and type(row) == "table" and row.autoGrowEnabled == true
    local additives = canGrow and type(row) == "table" and row.autoGrowAdditives == true
    local autoBuy = canBuy and type(row) == "table" and row.autoBuyEnabled == true
    local combatPause = type(row) ~= "table" or row.autoGrowPauseCombat ~= false
    local seedBufOn = canGrow and (type(row) ~= "table" or row.growSeedBufferEnabled ~= false)
    local seedBuf = StockPiler4.Watch and StockPiler4.Watch.GetSeedBufferMin and StockPiler4.Watch.GetSeedBufferMin() or 5
    local reserve = type(row) == "table" and tonumber(row.autoBuyReserveGold) or 10
    local budget = type(row) == "table" and tonumber(row.autoBuyBudgetGold) or 50
    local spent = type(row) == "table" and tonumber(row.autoBuySpentBrass) or 0
    local SkillUp = StockPiler4.SkillUp
    local skillUpCult = SkillUp and SkillUp.IsCultEnabled and SkillUp.IsCultEnabled() == true
    local skillUpApo = SkillUp and SkillUp.IsApoEnabled and SkillUp.IsApoEnabled() == true
    local cultVis = SkillUp and SkillUp.IsCultVisible and SkillUp.IsCultVisible() == true
    local apoVis = SkillUp and SkillUp.IsApoVisible and SkillUp.IsApoVisible() == true
    local UpgradeSeed = StockPiler4.UpgradeSeed
    local upgradeOn = UpgradeSeed and UpgradeSeed.IsEnabled and UpgradeSeed.IsEnabled() == true
    local gatesKey = table.concat({
        tostring(canGrow), tostring(canBuy), tostring(autoGrow), tostring(additives),
        tostring(autoBuy), tostring(combatPause), tostring(seedBufOn), tostring(seedBuf),
        tostring(reserve), tostring(budget), tostring(spent),
        tostring(cultVis), tostring(apoVis), tostring(skillUpCult), tostring(skillUpApo),
        tostring(upgradeOn),
    }, ":")
    if StockPiler4TabWatch._skillGatesKey == gatesKey then
        return
    end
    StockPiler4TabWatch._skillGatesKey = gatesKey
    local prev = StockPiler4TabWatch._lastCanAutoGrow
    StockPiler4TabWatch._lastCanAutoGrow = canGrow
    UpdateEnableCheckbox()
    UpdateAdditivesCheckbox()
    UpdateAutoBuyCheckbox()
    UpdateCombatPauseCheckbox()
    UpdateSeedBufferEnableCheckbox()
    UpdateUpgradeSeedsCheckbox()
    UpdateSeedBufferLabel()
    UpdateAutoBuyChips()
    UpdateSkillUpCheckboxes()
    if prev == false and canGrow == true then
        if StockPiler4.Ui and StockPiler4.Ui.MarkWatchUiDirty then
            StockPiler4.Ui.MarkWatchUiDirty()
        end
    end
end

function StockPiler4TabWatch.ClearRowPaintCache()
    StockPiler4TabWatch._rowPaintKey = {}
    StockPiler4TabWatch._rowIconNum = {}
end

function StockPiler4TabWatch.InvalidateBrewChrome()
    -- Row chip paint only. Clearing Ui brew/content keys forced mid-brew RefreshWatch.
    StockPiler4TabWatch._rowPaintKey = nil
end

function StockPiler4TabWatch.Refresh(opts)
    opts = type(opts) == "table" and opts or {}
    if not DoesWindowExist(TAB_ROOT) then
        return
    end
    StockPiler4TabWatch.RefreshSkillGates()
    local prevOrder = StockPiler4TabWatch.displayOrder
    BuildVisibleList(opts)
    if not DoesWindowExist("SP4TabWatchList") then
        return
    end
    local order = StockPiler4TabWatch.displayOrder
    local orderChanged = type(prevOrder) ~= "table" or type(order) ~= "table" or #prevOrder ~= #order
    if not orderChanged and type(prevOrder) == "table" and type(order) == "table" then
        for i = 1, #order do
            if prevOrder[i] ~= order[i] then
                orderChanged = true
                break
            end
        end
    end
    if orderChanged then
        StockPiler4TabWatch._rowPaintKey = {}
        StockPiler4TabWatch._rowIconNum = {}
        ListBoxSetDisplayOrder("SP4TabWatchList", order or {})
    else
        StockPiler4TabWatch.UpdateRows()
    end
end

function StockPiler4TabWatch.UpdateRows()
    if not SP4TabWatchList then
        return
    end
    if StockPiler4.Perf and StockPiler4.Perf.Begin then
        StockPiler4.Perf.Begin("WatchRows")
    end
    local numVisible = tonumber(SP4TabWatchList.numVisibleRows) or 11
    local indices = SP4TabWatchList.PopulatorIndices
    local active = {}
    if type(indices) == "table" then
        for rowIndex, dataIndex in ipairs(indices) do
            active[rowIndex] = dataIndex
        end
    end
    StockPiler4TabWatch._rowPaintKey = StockPiler4TabWatch._rowPaintKey or {}
    local canGrow = CanAutoGrowUi()
    local listData = StockPiler4TabWatch.listData
    for rowIndex = 1, numVisible do
        local rowName = "SP4TabWatchListRow" .. rowIndex
        if DoesWindowExist(rowName) then
            local dataIndex = active[rowIndex]
            local data = dataIndex and type(listData) == "table" and listData[dataIndex] or nil
            if data then
                WindowSetShowing(rowName, true)
                if DefaultColor and DefaultColor.SetListRowTint then
                    DefaultColor.SetListRowTint(rowName .. "Background", rowIndex, false)
                end
                local brewState = GetRowCraftUiState(data)
                local craftableGreen = RowCraftableGreen(data)
                local nameR, nameG, nameB = EnsureWatchNameRarityColors(data)
                local paintKey = table.concat({
                    tostring(data.iconNum or 0),
                    tostring(data.name or ""),
                    tostring(nameR), tostring(nameG), tostring(nameB),
                    tostring(data.statusText or ""),
                    tostring(data.stockText or data.potionHave or 0),
                    tostring(data.craftableText or ""),
                    tostring(data.craftable or 0),
                    tostring(data.targetText or data.target or 0),
                    tostring(data.priorityTierText or data.priorityTier or 1),
                    tostring(data.statusKey or ""),
                    tostring(data.autoGrow == true),
                    tostring(data.hideAutoGrow == true),
                    tostring(data.hideBrew == true),
                    tostring(data.craftableShared == true),
                    tostring(data.seedBufferShort == true),
                    tostring(craftableGreen),
                    tostring(brewState),
                    tostring(canGrow),
                }, "|")
                if StockPiler4TabWatch._rowPaintKey[rowIndex] ~= paintKey then
                    local lastIcon = StockPiler4TabWatch._rowIconNum
                    if type(lastIcon) ~= "table" then
                        lastIcon = {}
                        StockPiler4TabWatch._rowIconNum = lastIcon
                    end
                    if lastIcon[rowIndex] ~= data.iconNum then
                        lastIcon[rowIndex] = data.iconNum
                        SetIconTexture(rowName .. "Icon", data.iconNum)
                    end
                    local prio = tonumber(data.priorityTier) or 1
                    if IsPlantWatchRow(data) then
                        LabelSetText(rowName .. "Prio", data.priorityTierText or L"-")
                    else
                        LabelSetText(rowName .. "Prio", data.priorityTierText or towstring(tostring(prio)))
                    end
                    TintStepper(rowName .. "PrioChipBg")
                    LabelSetTextColor(rowName .. "Prio", 255, 255, 255)
                    LabelSetText(rowName .. "Name", data.name or L"")
                    LabelSetTextColor(rowName .. "Name", nameR, nameG, nameB)
                    LabelSetText(rowName .. "Status", data.statusText or L"")
                    LabelSetText(rowName .. "Stock", data.stockText or towstring(tostring(data.potionHave or 0)))
                    if IsEphemeralWatchRow(data) or IsPlantWatchRow(data) then
                        LabelSetText(rowName .. "Craftable", L"")
                    else
                        LabelSetText(rowName .. "Craftable", data.craftableText or T("ui.dash"))
                    end
                    LabelSetText(rowName .. "Target", data.targetText or towstring(tostring(data.target or 0)))
                    TintStepper(rowName .. "TargetChipBg")
                    ApplyStatusColor(rowName .. "Status", data.statusKey)
                    local autoGrowWin = rowName .. "AutoGrow"
                    if DoesWindowExist(autoGrowWin) then
                        local hideAg = type(data) == "table" and data.hideAutoGrow == true
                        WindowSetShowing(autoGrowWin, hideAg ~= true)
                        if hideAg ~= true then
                            syncingUi = true
                            ButtonSetCheckButtonFlag(autoGrowWin, true)
                            local pressed = false
                            if IsUpgradeWatchRow(data)
                                or (IsSkillUpWatchRow(data) and tostring(data.skillUpKind or "") == "cult")
                            then
                                -- Cult SkillUp / Upgrade Seed: read-only mirror of master AutoGrow.
                                pressed = canGrow and data.autoGrow == true
                                ButtonSetPressedFlag(autoGrowWin, pressed)
                                ButtonSetDisabledFlag(autoGrowWin, true)
                            else
                                pressed = canGrow and data.autoGrow == true
                                ButtonSetPressedFlag(autoGrowWin, pressed)
                                ButtonSetDisabledFlag(autoGrowWin, (not canGrow) or IsEphemeralWatchRow(data))
                            end
                            syncingUi = false
                        end
                    end
                    LabelSetTextColor(rowName .. "Target", 255, 255, 255)
                    local target = tonumber(data.target) or 0
                    local have = tonumber(data.potionHave) or 0
                    local craftable = tonumber(data.craftable) or 0
                    local stockColor = { 255, 255, 255 }
                    if IsEphemeralWatchRow(data) then
                        stockColor = { 255, 255, 255 }
                    elseif target > 0 then
                        if have >= target then
                            stockColor = COLOR_OK
                        elseif (have + craftable) >= target then
                            stockColor = COLOR_WARN
                        else
                            stockColor = COLOR_BLOCK
                        end
                    end
                    LabelSetTextColor(rowName .. "Stock", stockColor[1], stockColor[2], stockColor[3])
                    if IsEphemeralWatchRow(data) or IsPlantWatchRow(data) then
                        LabelSetTextColor(rowName .. "Craftable", COLOR_GRAY[1], COLOR_GRAY[2], COLOR_GRAY[3])
                    else
                        local craftColor = COLOR_BLOCK
                        if craftable > 0 then
                            -- Yellow: craftable but seed buffer short. Green: buffer-safe (shared OK).
                            if data.seedBufferShort == true or data.craftableSafe == false then
                                craftColor = COLOR_WARN
                            else
                                craftColor = COLOR_OK
                            end
                        end
                        LabelSetTextColor(rowName .. "Craftable", craftColor[1], craftColor[2], craftColor[3])
                    end
                    ApplyRowBrewButton(rowName .. "Load", data)
                    StockPiler4TabWatch._rowPaintKey[rowIndex] = paintKey
                end
            else
                WindowSetShowing(rowName, false)
                StockPiler4TabWatch._rowPaintKey[rowIndex] = nil
            end
        end
    end
    if StockPiler4.Perf and StockPiler4.Perf.End then
        StockPiler4.Perf.End("WatchRows")
    end
end

function StockPiler4TabWatch.OnToggleEnabled()
    if syncingUi then
        return
    end
    if not CanAutoGrowUi() then
        UpdateEnableCheckbox()
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    row.autoGrowEnabled = ButtonGetPressedFlag(ENABLE_WIN) == true
    NotifySettings(T("watch.autogrow", { state = OnOff(row.autoGrowEnabled) }))
    if row.autoGrowEnabled ~= true and StockPiler4.Orchestrator and StockPiler4.Orchestrator.OnAutoGrowDisabled then
        StockPiler4.Orchestrator.OnAutoGrowDisabled()
    end
    AfterWatchSettingsChanged()
    StockPiler4TabWatch.RefreshSkillGates()
    StockPiler4TabWatch._rowPaintKey = nil
    StockPiler4TabWatch.UpdateRows()
end

function StockPiler4TabWatch.OnToggleAdditives()
    if syncingUi then
        return
    end
    if not CanAutoGrowUi() then
        UpdateAdditivesCheckbox()
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    row.autoGrowAdditives = ButtonGetPressedFlag(ADDITIVES_WIN) == true
    NotifySettings(T("watch.additives", { state = OnOff(row.autoGrowAdditives) }))
    AfterWatchSettingsChanged()
end

function StockPiler4TabWatch.OnToggleSeedBuffer()
    if syncingUi then
        return
    end
    if not CanAutoGrowUi() then
        UpdateSeedBufferEnableCheckbox()
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    row.growSeedBufferEnabled = ButtonGetPressedFlag(SEED_BUFFER_ENABLE_WIN) == true
    NotifySettings(T("watch.seed_buffer", { state = OnOff(row.growSeedBufferEnabled) }))
    AfterWatchSettingsChanged()
    UpdateSeedBufferEnableCheckbox()
end

function StockPiler4TabWatch.OnToggleUpgradeSeeds()
    if syncingUi then
        return
    end
    if not CanAutoGrowUi() then
        UpdateUpgradeSeedsCheckbox()
        return
    end
    local US = StockPiler4.UpgradeSeed
    local on = ButtonGetPressedFlag(UPGRADE_SEEDS_WIN) == true
    if US and US.SetEnabled then
        US.SetEnabled(on)
    else
        local row = CharRow(true)
        if type(row) == "table" then
            row.upgradeSeedsEnabled = on
        end
    end
    NotifySettings(T("watch.upgrade_seeds_state", { state = OnOff(on) }))
    AfterWatchSettingsChanged()
    UpdateUpgradeSeedsCheckbox()
end

function StockPiler4TabWatch.OnToggleAutoBuy()
    if syncingUi then
        return
    end
    if not CanAutoBuyUi() then
        UpdateAutoBuyCheckbox()
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    row.autoBuyEnabled = ButtonGetPressedFlag(AUTOBUY_WIN) == true
    NotifySettings(T("watch.autobuy", { state = OnOff(row.autoBuyEnabled) }))
    AfterSoftMoneySetting()
    if row.autoBuyEnabled == true and StockPiler4.Scheduler and StockPiler4.Scheduler.WakeAutoBuy then
        StockPiler4.Scheduler.WakeAutoBuy()
    end
    if StockPiler4.Buy and StockPiler4.Buy.InvalidateJobsCache then
        StockPiler4.Buy.InvalidateJobsCache()
    end
end

function StockPiler4TabWatch.OnToggleCombatPause()
    if syncingUi then
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    row.autoGrowPauseCombat = ButtonGetPressedFlag(COMBAT_PAUSE_WIN) == true
    NotifySettings(T("watch.combat_pause", { state = OnOff(row.autoGrowPauseCombat) }))
    AfterSoftMoneySetting()
end

function StockPiler4TabWatch.OnToggleSkillUpSkills()
    if syncingUi then
        return
    end
    local SkillUp = StockPiler4.SkillUp
    local cultVis = SkillUp and SkillUp.IsCultVisible and SkillUp.IsCultVisible() == true
    local apoVis = SkillUp and SkillUp.IsApoVisible and SkillUp.IsApoVisible() == true
    if cultVis ~= true and apoVis ~= true then
        UpdateSkillUpCheckboxes()
        return
    end
    local on = ButtonGetPressedFlag(SKILLUP_SKILLS_WIN) == true
    if cultVis == true and SkillUp.SetCultEnabled then
        SkillUp.SetCultEnabled(on)
    end
    if apoVis == true and SkillUp.SetApoEnabled then
        SkillUp.SetApoEnabled(on)
    end
    NotifySettings(T("watch.skillup_skills_state", { state = OnOff(on) }))
    AfterWatchSettingsChanged()
    UpdateSkillUpCheckboxes()
    StockPiler4TabWatch.Refresh({ forcePlan = true })
    if on and StockPiler4.Scheduler and StockPiler4.Scheduler.WakeAutoGrow then
        StockPiler4.Scheduler.WakeAutoGrow()
    end
    if StockPiler4.Buy and StockPiler4.Buy.InvalidateJobsCache then
        StockPiler4.Buy.InvalidateJobsCache()
    end
end

local function AdjustSeedBuffer(flags, dir)
    if not CanAutoGrowUi() then
        UpdateSeedBufferEnableCheckbox()
        return
    end
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    local cur = tonumber(row.growSeedBufferMin) or 5
    local nextVal = Clamp(cur + ChipDelta(flags, dir), 4, 20)
    if nextVal == cur then
        return
    end
    row.growSeedBufferMin = nextVal
    NotifySettings(T("watch.setting_eq", {
        label = T("watch.setting.seed_buffer"),
        value = tostring(nextVal),
    }))
    UpdateSeedBufferLabel()
    AfterWatchSettingsChanged()
end

local function AdjustReserve(flags, dir)
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    local cur = tonumber(row.autoBuyReserveGold) or 10
    local nextVal = Clamp(cur + ChipDelta(flags, dir), 1, 99)
    if nextVal == cur then
        return
    end
    row.autoBuyReserveGold = nextVal
    NotifySettings(T("watch.setting_eq", {
        label = T("watch.setting.reserve"),
        value = tostring(nextVal),
    }))
    UpdateAutoBuyChips()
    AfterSoftMoneySetting()
end

local function AdjustBudget(flags, dir)
    local row = CharRow(true)
    if type(row) ~= "table" then
        return
    end
    local cur = tonumber(row.autoBuyBudgetGold) or 50
    local nextVal = Clamp(cur + ChipDelta(flags, dir), 1, 999)
    if nextVal == cur then
        return
    end
    row.autoBuyBudgetGold = nextVal
    NotifySettings(T("watch.setting_eq", {
        label = T("watch.setting.budget"),
        value = tostring(nextVal),
    }))
    UpdateAutoBuyChips()
    AfterSoftMoneySetting()
end

function StockPiler4TabWatch.OnSeedBufferLButtonUp(flags)
    AdjustSeedBuffer(flags, 1)
end

function StockPiler4TabWatch.OnSeedBufferRButtonUp(flags)
    AdjustSeedBuffer(flags, -1)
end

function StockPiler4TabWatch.OnReserveLButtonUp(flags)
    AdjustReserve(flags, 1)
end

function StockPiler4TabWatch.OnReserveRButtonUp(flags)
    AdjustReserve(flags, -1)
end

function StockPiler4TabWatch.OnBudgetLButtonUp(flags)
    AdjustBudget(flags, 1)
end

function StockPiler4TabWatch.OnBudgetRButtonUp(flags)
    AdjustBudget(flags, -1)
end

function StockPiler4TabWatch.OnBudgetReset()
    if syncingUi then
        return
    end
    local Buy = StockPiler4.Buy
    local spent = Buy and Buy.GetSpentBrass and Buy.GetSpentBrass() or 0
    if spent <= 0 then
        UpdateAutoBuyChips()
        return
    end
    if Buy and Buy.ResetAllowanceSpent then
        Buy.ResetAllowanceSpent()
    elseif StockPiler4.Watch and StockPiler4.Watch.ResetAutoBuySpentBrass then
        StockPiler4.Watch.ResetAutoBuySpentBrass()
    end
    NotifySettings(T("watch.budget_reset_done"))
    UpdateAutoBuyChips()
    AfterSoftMoneySetting()
end

function StockPiler4TabWatch.OnToggleRowAutoGrow()
    if syncingUi then
        return
    end
    local data = RowDataFromActiveChild()
    if not data or not CanAutoGrowUi() then
        return
    end
    if IsEphemeralWatchRow(data) then
        -- Addon-owned SkillUp / Upgrade rows: AutoGrow is master-linked (display-only).
        StockPiler4TabWatch._rowPaintKey = nil
        StockPiler4TabWatch.UpdateRows()
        return
    end
    if IsPlantWatchRow(data) then
        local plantKey = data.plantKey or data.id or data.potionKey
        local enabled = ButtonGetPressedFlag(SystemData.ActiveWindow.name) == true
        if StockPiler4.Watch and StockPiler4.Watch.SetPlantAutoGrow then
            StockPiler4.Watch.SetPlantAutoGrow(plantKey, enabled)
        end
        data.autoGrow = enabled
        AfterWatchSettingsChanged()
        StockPiler4TabWatch._rowPaintKey = nil
        StockPiler4TabWatch.UpdateRows()
        return
    end
    local potionKey = data.potionRecipeKey or data.id or data.potionKey
    local enabled = ButtonGetPressedFlag(SystemData.ActiveWindow.name) == true
    if StockPiler4.Watch and StockPiler4.Watch.SetAutoGrow then
        StockPiler4.Watch.SetAutoGrow(potionKey, enabled)
    end
    data.autoGrow = enabled
    AfterWatchSettingsChanged()
    StockPiler4TabWatch._rowPaintKey = nil
    -- UpdateRows alone used to paint pre-reconcile status; Refresh re-patches listData.
    StockPiler4TabWatch.UpdateRows()
end

function StockPiler4TabWatch.OnTargetLButtonUp(flags)
    local data = RowDataFromActiveChild()
    AdjustTarget(data, ChipDelta(flags, 1))
end

function StockPiler4TabWatch.OnTargetRButtonUp(flags)
    local data = RowDataFromActiveChild()
    AdjustTarget(data, ChipDelta(flags, -1))
end

function StockPiler4TabWatch.OnPrioLButtonUp(flags)
    local data = RowDataFromActiveChild()
    AdjustPriority(data, ChipDelta(flags, 1))
end

function StockPiler4TabWatch.OnPrioRButtonUp(flags)
    local data = RowDataFromActiveChild()
    AdjustPriority(data, ChipDelta(flags, -1))
end

function StockPiler4TabWatch.OnLoadRow()
    local data = RowDataFromActiveChild()
    if not data or IsPlantWatchRow(data) or IsEphemeralWatchRow(data) or not StockPiler4.Brew then
        return
    end
    if StockPiler4.Brew.OnRowCraftClick then
        StockPiler4.Brew.OnRowCraftClick(data)
    end
    if StockPiler4.BrewChrome and StockPiler4.BrewChrome.RefreshBrewUi then
        StockPiler4.BrewChrome.RefreshBrewUi()
    end
end

function StockPiler4TabWatch.OnLoadRowRightClick()
    local data = RowDataFromActiveChild()
    if not data or IsEphemeralWatchRow(data) then
        return
    end
    if StockPiler4.Brew and StockPiler4.Brew.OnRowCraftRightClick then
        StockPiler4.Brew.OnRowCraftRightClick(data)
    end
    if StockPiler4.BrewChrome and StockPiler4.BrewChrome.RefreshBrewUi then
        StockPiler4.BrewChrome.RefreshBrewUi()
    end
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

local function ToNarrow(v)
    return StockPiler4.Util.ToNarrow(v)
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

function StockPiler4TabWatch.OnMouseOverEnabled()
    Tip(T("tip.watch.autogrow_master"))
end

function StockPiler4TabWatch.OnMouseOverAdditives()
    Tip(T("tip.watch.additives"))
end

function StockPiler4TabWatch.OnMouseOverAutoBuy()
    Tip(T("tip.watch.autobuy"))
end

function StockPiler4TabWatch.OnMouseOverCombatPause()
    Tip(T("tip.watch.combat_pause"))
end

function StockPiler4TabWatch.OnMouseOverSkillUpSkills()
    Tip(T("tip.watch.skillup_skills"))
end

function StockPiler4TabWatch.OnMouseOverSeedBufferEnable()
    if not CanAutoGrowUi() then
        Tip(T("tip.watch.cult_required"))
        return
    end
    Tip(T("tip.watch.seed_buffer"))
end

function StockPiler4TabWatch.OnMouseOverUpgradeSeeds()
    if not CanAutoGrowUi() then
        Tip(T("tip.watch.cult_required"))
        return
    end
    Tip(T("tip.watch.upgrade_seeds"))
end

function StockPiler4TabWatch.OnMouseOverSeedBuffer()
    if not CanAutoGrowUi() then
        Tip(T("tip.watch.cult_required"))
        return
    end
    Tip(T("tip.watch.seed_buffer"))
end

function StockPiler4TabWatch.OnMouseOverReserve()
    Tip(T("tip.watch.reserve_chip"))
end

function StockPiler4TabWatch.OnMouseOverBudget()
    local Buy = StockPiler4.Buy
    local spent = Buy and Buy.GetSpentBrass and Buy.GetSpentBrass() or 0
    local allowance = Buy and Buy.GetBudgetGold and Buy.GetBudgetGold() or 50
    local spentLabel = (Buy and Buy.FormatMoneyBrass and Buy.FormatMoneyBrass(spent))
        or tostring(spent)
    local remain = Buy and Buy.GetAllowanceRemainingBrass and Buy.GetAllowanceRemainingBrass() or 0
    local remainLabel = (Buy and Buy.FormatMoneyBrass and Buy.FormatMoneyBrass(remain))
        or tostring(remain)
    Tip(T("tip.watch.budget_chip", {
        spent = spentLabel,
        allowance = tostring(allowance) .. "g",
        remain = remainLabel,
    }))
end

function StockPiler4TabWatch.OnMouseOverBudgetReset()
    Tip(T("tip.watch.budget_reset"))
end

function StockPiler4TabWatch.OnMouseOverIcon()
    local data = RowDataFromActiveChild()
    if not data then
        return
    end
    if IsSkillUpWatchRow(data) then
        local Caps = StockPiler4.TradeSkillCaps
        local skillId = 0
        if tostring(data.skillUpKind or "") == "apo" then
            skillId = Caps and Caps.ApothecaryId and Caps.ApothecaryId() or 4
        else
            skillId = Caps and Caps.CultivationId and Caps.CultivationId() or 3
        end
        TipTradeSkill(skillId)
        return
    end
    local uid = tonumber(data.uniqueID) or tonumber(data.plantUid) or 0
    local itemData = data.itemData
    local isPlant = IsPlantWatchRow(data)
    if StockPiler4.Inventory then
        if StockPiler4.Inventory.GetSample and uid > 0 and isPlant then
            local sample = StockPiler4.Inventory.GetSample(uid)
            if type(sample) == "table" then
                itemData = sample
            end
        end
        if StockPiler4.Inventory.ResolvePotionItemData then
            itemData = StockPiler4.Inventory.ResolvePotionItemData(
                data.potionKey or data.potionBaseKey or data.plantKey,
                uid,
                itemData
            )
            if type(itemData) == "table" then
                data.itemData = itemData
                -- Refresh rarity tint if we just got a richer sample.
                data.nameR, data.nameG, data.nameB = nil, nil, nil
                EnsureWatchNameRarityColors(data)
            end
        end
    end
    local tipOpts = (isPlant or IsUpgradeWatchRow(data)) and { allowWithoutUse = true } or nil
    if StockPiler4.Inventory and StockPiler4.Inventory.ShowItemTooltip
        and StockPiler4.Inventory.ShowItemTooltip(itemData, SystemData.ActiveWindow.name, tipOpts)
    then
        return
    end
    Tip(data.name or (isPlant and T("ui.item_fallback") or T("ui.potion_fallback")))
end

function StockPiler4TabWatch.OnMouseOverName()
    StockPiler4TabWatch.OnMouseOverIcon()
end

function StockPiler4TabWatch.OnMouseOverStatus()
    local data = RowDataFromActiveChild()
    if not data then
        return
    end
    local RT = StockPiler4.RecipeTooltip
    if not RT or not RT.ShowColoredRows then
        Tip(data.statusText or T("watch.col.status"))
        return
    end

    local engineMax = (Tooltips and tonumber(Tooltips.NUM_ROWS)) or 17
    local snapGen = 0
    if StockPiler4.Inventory and StockPiler4.Inventory.GetSnapGen then
        snapGen = tonumber(StockPiler4.Inventory.GetSnapGen()) or 0
    end
    local genKey = PlanTipCacheKey() .. ":s" .. tostring(snapGen)
    local watchKey = tostring(data.potionKey or data.id or "")
        .. ":k" .. tostring(data.statusKey or "")
        .. ":t" .. ToNarrow(data.statusText or "")
    local cache = StockPiler4TabWatch._statusTipCache
    if type(cache) ~= "table" or cache.genKey ~= genKey then
        cache = { genKey = genKey, byWatch = {} }
        StockPiler4TabWatch._statusTipCache = cache
    end
    local tipRows = watchKey ~= "" and cache.byWatch[watchKey] or nil
    if type(tipRows) ~= "table" then
        tipRows = BuildStatusTooltipRows(data)
        TrimStatusTooltipRows(tipRows, engineMax)
        if watchKey ~= "" then
            cache.byWatch[watchKey] = tipRows
        end
    end

    RT.ShowColoredRows(
        SystemData.ActiveWindow.name,
        tipRows,
        Tooltips.ANCHOR_WINDOW_TOP,
        engineMax
    )
end

function StockPiler4TabWatch.OnMouseOverStock()
    local data = RowDataFromActiveChild()
    if not data then
        return
    end
    if IsUpgradeWatchRow(data) then
        Tip(T("upgrade.watch.tip"))
        return
    end
    if IsSkillUpWatchRow(data) then
        Tip(T("tip.watch.skillup_metrics"))
        return
    end
    Tip(T("tip.watch.have_target", {
        have = tostring(data.potionHave or 0),
        target = tostring(data.target or 0),
    }))
end

function StockPiler4TabWatch.OnMouseOverCraftable()
    local data = RowDataFromActiveChild()
    if not data or IsPlantWatchRow(data) then
        return
    end
    if IsUpgradeWatchRow(data) then
        Tip(T("upgrade.watch.tip"))
        return
    end
    if IsSkillUpWatchRow(data) then
        Tip(T("tip.watch.skillup_metrics"))
        return
    end
    local craftable = tonumber(data.craftable) or 0
    if craftable <= 0 then
        Tip(T("tip.watch.craftable_none"))
        return
    end
    if data.seedBufferShort == true or data.craftableSafe == false then
        Tip(T("tip.watch.craftable_seed_buffer"))
        return
    end
    Tip(T("tip.watch.craftable_ready"))
end

function StockPiler4TabWatch.OnMouseOverTarget()
    local data = RowDataFromActiveChild()
    if data and IsUpgradeWatchRow(data) then
        Tip(T("upgrade.watch.tip"))
        return
    end
    if data and IsSkillUpWatchRow(data) then
        Tip(T("tip.watch.skillup_metrics"))
        return
    end
    Tip(T("tip.watch.target_chip"))
end

function StockPiler4TabWatch.OnMouseOverPrio()
    Tip(T("tip.watch.prio_chip"))
end

function StockPiler4TabWatch.OnMouseOverRowAutoGrow()
    local data = RowDataFromActiveChild()
    if data and IsUpgradeWatchRow(data) then
        Tip(T("upgrade.watch.ag_tip"))
        return
    end
    if data and IsSkillUpWatchRow(data) and tostring(data.skillUpKind or "") == "cult" then
        Tip(T("tip.watch.skillup_cult_autogrow"))
        return
    end
    Tip(T("tip.watch.row_autogrow"))
end

function StockPiler4TabWatch.OnMouseOverLoad()
    local data = RowDataFromActiveChild()
    if StockPiler4.BrewTooltip and StockPiler4.BrewTooltip.ShowRow then
        StockPiler4.BrewTooltip.ShowRow(SystemData.ActiveWindow.name, data)
        return
    end
    Tip(T("watch.col.brew"))
end

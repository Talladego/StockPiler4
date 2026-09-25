----------------------------------------------------------------

-- StockPiler4 Planner/BrewPlan - brew intent facade

----------------------------------------------------------------



StockPiler4 = StockPiler4 or {}

StockPiler4.BrewPlan = StockPiler4.BrewPlan or {}

local BrewPlan = StockPiler4.BrewPlan



function BrewPlan.FromSnapshot(plan)

    plan = plan or (StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get and StockPiler4.PlanSnapshot.Get())

    if type(plan) ~= "table" then

        return nil

    end

    return plan.brewIntent

end



local function RecipeKeyFromRow(row)

    if type(row) ~= "table" then

        return nil

    end

    local recipe = row.recipe

    local recipeKey = row.potionRecipeKey or row.recipeSpecKey or row.id

    if type(recipe) == "table" then

        recipeKey = recipe.recipeSpecKey or recipe.key or recipe.recipeKey or recipeKey

    end

    if recipeKey == nil or tostring(recipeKey) == "" then

        recipeKey = row.potionKey

    end

    if recipeKey == nil or tostring(recipeKey) == "" then

        return nil

    end

    return tostring(recipeKey)

end



local function IntentFromRow(row, reason)

    local recipeKey = RecipeKeyFromRow(row)

    if recipeKey == nil then

        return nil

    end

    return {

        recipeKey = recipeKey,

        potionKey = row.potionKey or row.potionRecipeKey or row.id,

        reason = reason,

        craftable = row.craftable,

        potionDeficit = row.potionDeficit,

        skillUp = row.skillUp == true,

    }

end



local function PickReadyFromRows(rows)

    if type(rows) ~= "table" then

        return nil

    end

    local best = nil

    for i = 1, #rows do

        local row = rows[i]

        if type(row) == "table" then

            if row.kind == "plant" or row.isPlantWatch == true then

                -- skip

            elseif row.skillUp == true and (tonumber(row.craftable) or 0) > 0 then

                if best == nil or best.skillUp ~= true then

                    best = row

                end

            elseif row.statusKey == "ready_to_craft"

                and (tonumber(row.craftable) or 0) > 0

                and (tonumber(row.potionDeficit) or 0) > 0

            then

                if best == nil then

                    best = row

                end

            end

        end

    end

    return best

end



function BrewPlan.BuildIntent(opts)

    opts = type(opts) == "table" and opts or {}

    local Brew = StockPiler4.Brew

    if not Brew then

        return nil

    end



    local session = Brew.GetSession and Brew.GetSession()

    if type(session) == "table" then

        local phase = tostring(session.phase or "idle")

        if phase ~= "idle" then

            local recipeKey = session.recipeSpecKey or session.potionRecipeKey

            if recipeKey == nil and type(session.recipe) == "table" then

                recipeKey = session.recipe.recipeSpecKey or session.recipe.key

            end

            if recipeKey ~= nil and tostring(recipeKey) ~= "" then

                return {

                    recipeKey = tostring(recipeKey),

                    potionKey = session.potionKey or session.potionRecipeKey or session.rowId,

                    reason = session.skillUp == true and "skillup" or "session",

                    phase = phase,

                    craftable = session.craftable,

                    potionDeficit = session.potionDeficit,

                    skillUp = session.skillUp == true,

                }

            end

        end

    end



    local row = PickReadyFromRows(opts.rows)

    if row == nil and Brew.PickReadyWatch then

        row = Brew.PickReadyWatch()

    end

    if type(row) == "table" then

        local reason = row.skillUp == true and "skillup" or "watch"

        return IntentFromRow(row, reason)

    end



    local ASP = StockPiler4.ApoSkillPlan

    if ASP and ASP.ShouldApoBrew and ASP.ShouldApoBrew() == true then

        row = ASP.GetApoBrewRow and ASP.GetApoBrewRow()

        if type(row) ~= "table" and ASP.BuildApoBrewRow then

            row = ASP.BuildApoBrewRow({ quiet = true })

        end

        if type(row) == "table" and (tonumber(row.craftable) or 0) > 0 then

            return IntentFromRow(row, "skillup")

        end

    end




    return nil

end



----------------------------------------------------------------

-- StockPiler4 Planner/BuyPlan - buy intent facade

----------------------------------------------------------------



StockPiler4 = StockPiler4 or {}

StockPiler4.BuyPlan = StockPiler4.BuyPlan or {}

local BuyPlan = StockPiler4.BuyPlan



function BuyPlan.FromSnapshot(plan)

    plan = plan or (StockPiler4.PlanSnapshot and StockPiler4.PlanSnapshot.Get and StockPiler4.PlanSnapshot.Get())

    if type(plan) ~= "table" then

        return nil

    end

    return plan.buyIntent

end



function BuyPlan.BuildIntent()

    local Planner = StockPiler4.Planner

    if not Planner or not Planner.CollectVendorBuyJobs then

        return nil

    end

    local jobs = Planner.CollectVendorBuyJobs({ allowPlantBuys = true })

    if type(jobs) ~= "table" or #jobs == 0 or type(jobs[1]) ~= "table" then

        return nil

    end

    local bj = jobs[1]

    local uid = tonumber(bj.uid or bj.uniqueID) or 0

    local deficit = tonumber(bj.deficit) or 0

    if uid <= 0 or deficit <= 0 then

        return nil

    end

    local reason = tostring(bj.kind or "buy")

    if reason == "" then

        reason = "buy"

    end

    return {

        uid = uid,

        deficit = deficit,

        reason = reason,

        specKey = bj.specKey,

        need = bj.need or bj.qty,

        bottleGap = bj.bottleGap,

        role = bj.role,

        growable = bj.growable == true,

    }

end



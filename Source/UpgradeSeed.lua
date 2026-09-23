----------------------------------------------------------------
-- DEPRECATED: climb/deficit logic lives in Source/Planner/ClimbPlan.lua
-- (StockPiler4.ClimbPlan). This file is not loaded by StockPiler4.mod.
--
-- ClimbPlan sets StockPiler4.UpgradeSeed = StockPiler4.ClimbPlan at load time
-- so legacy callers (SkillUp, Grow, Buy, UI) keep working without this shim.
--
-- If you maintain a fork that still lists UpgradeSeed.lua in the .mod Files
-- section, remove that entry and add Source/Planner/ClimbPlan.lua before Grow.lua.
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}

if StockPiler4.ClimbPlan then
    StockPiler4.UpgradeSeed = StockPiler4.ClimbPlan
else
    d("StockPiler4: UpgradeSeed.lua shim loaded without ClimbPlan — fix .mod load order.")
end

# One-off: extract PlantPlan.lua from Grow.lua (Phase 3)
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
grow_path = ROOT / "Source" / "Grow.lua"
out_path = ROOT / "Source" / "Planner" / "PlantPlan.lua"

lines = grow_path.read_text(encoding="utf-8").splitlines(keepends=True)
pick_helpers = lines[243:770]
pick_block = lines[1080:1682]

header = """----------------------------------------------------------------
-- StockPiler4 Planner/PlantPlan -- plant candidate selection
-- Absorbed from Grow.PickPlantCandidate (Phase 3).
----------------------------------------------------------------

StockPiler4 = StockPiler4 or {}
StockPiler4.PlantPlan = StockPiler4.PlantPlan or {}
local PlantPlan = StockPiler4.PlantPlan
local Grow = StockPiler4.Grow

"""

extra_helpers = """
local function SpecRole(spec)
    if type(spec) ~= "table" then
        return "ingredient"
    end
    local role = tostring(spec.role or spec.materialRole or "")
    if role == "" then
        return "ingredient"
    end
    return role
end

local ROLE_PICK_ORDER = {
    main = 1,
    stabilizer = 2,
    goldweed = 2,
    extender = 3,
    multiplier = 4,
    stimulant = 4,
    container = 5,
    ingredient = 6,
}

local function RoleRank(role)
    return ROLE_PICK_ORDER[tostring(role or "")] or 99
end

local function NormalizeStage(stage)
    return tonumber(stage) or 0
end

local function StageEmpty()
    if GameData and GameData.CultivationStage then
        return GameData.CultivationStage.EMPTY or 0
    end
    return 0
end

local function IsPlotEmptyRow(row)
    if type(row) ~= "table" then
        return false
    end
    if row.locked == true then
        return false
    end
    return NormalizeStage(row.stage) == StageEmpty()
end

local function CountInGroundSeeds(seedUid)
    if Grow and Grow.CountInGroundSeeds then
        return Grow.CountInGroundSeeds(seedUid)
    end
    return 0
end

local function CountSeedPlotCredit(seedUid)
    if Grow and Grow.CountSeedPlotCredit then
        return Grow.CountSeedPlotCredit(seedUid)
    end
    return 0
end

local function CanUseSeedUid(seedUid)
    seedUid = tonumber(seedUid) or 0
    if seedUid <= 0 then
        return false
    end
    local Inv = StockPiler4.Inventory
    local snapGen = Inv and Inv.GetSnapGen and Inv.GetSnapGen() or 0
    if Grow._skillSkipSnapGen ~= snapGen then
        Grow._skillSkipByUid = {}
        Grow._skillSkipSnapGen = snapGen
    end
    if Grow._skillSkipByUid[seedUid] == true then
        return false
    end
    local sample = Inv and Inv.GetSample and Inv.GetSample(seedUid)
    if type(sample) == "table" and Inv and Inv.CanUseCraftingItem then
        if Inv.CanUseCraftingItem(sample) ~= true then
            Grow._skillSkipByUid[seedUid] = true
            return false
        end
    end
    return true
end

local function LogGrow(msg)
    if StockPiler4.Debug and StockPiler4.Debug.LogOp then
        StockPiler4.Debug.LogOp("grow", msg)
    end
end

"""

intent_api = """
function PlantPlan.ReasonFromJob(job)
    if type(job) ~= "table" then
        return nil
    end
    local pr = tostring(job.plantReason or "")
    local pm = tostring(job.pickMode or "")
    if pr == "skill_up" then
        return "skillup"
    end
    if pr == "seed_buffer" or pm == "buffer" then
        return "buffer_fill"
    end
    if pr == "upgrade" or pm == "upgrade" or job.upgradeClimb == true then
        return "upgrade_climb"
    end
    if pm == "watch-lift" or pr == "potion_stock" then
        return "watch_deficit"
    end
    if pr == "plant_stock" or pm == "plant_stock" then
        return "watch_deficit"
    end
    if pr == "surplus" or pm == "surplus" then
        return "buffer_fill"
    end
    return "watch_deficit"
end

function PlantPlan.BuildPlantIntent(job)
    if type(job) ~= "table" then
        return nil
    end
    local seedUid = tonumber(job.seedUid) or 0
    if seedUid <= 0 then
        return nil
    end
    local plotNum = 0
    if Grow and Grow.FindNextEmptyPlot then
        plotNum = tonumber(Grow.FindNextEmptyPlot()) or 0
    end
    return {
        seedUid = seedUid,
        plotNum = plotNum,
        reason = PlantPlan.ReasonFromJob(job),
        plantUid = tonumber(job.plantUid) or nil,
        watchKey = job.watchKey,
        pickMode = job.pickMode or job.plantReason,
        role = job.role,
        plantReason = job.plantReason,
        specKey = job.specKey,
    }
end

"""

body = "".join(pick_helpers) + "".join(pick_block)
body = body.replace("function Grow.PickPlantCandidate()", "function PlantPlan.PickPlantJob()")
body = body.replace("    ClampSeedCommitsToBag()", "    if Grow.ClampSeedCommitsToBag then Grow.ClampSeedCommitsToBag() end")

footer = """
function PlantPlan.BuildPlantIntentFromCached()
    local job = Grow and Grow.GetPlantJob and Grow.GetPlantJob() or nil
    return PlantPlan.BuildPlantIntent(job)
end
"""

out = header + extra_helpers + intent_api + body + footer
out_path.write_text(out, encoding="utf-8", newline="\n")
print("Wrote", out_path, "lines", len(out.splitlines()))

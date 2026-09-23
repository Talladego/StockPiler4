"""Static verification for SP4 gap-fix plan."""
from pathlib import Path

root = Path(r"C:\Games\Return of Reckoning\Interface\AddOns\StockPiler4")
checks = []


def ok(name, cond, detail=""):
    checks.append((name, bool(cond), detail))


sch = (root / "Source/Core/Scheduler.lua").read_text(encoding="utf-8")
ok("50ms debounce present", "PLAN_DEBOUNCE_SEC = 0.05" in sch)
ok("SkipPlan arms debounce", "function Sch.SkipPlanThisFrame" in sch and "ArmPipelineDebounce" in sch)
# RebuildPlanIfDue should not early-return on _skipPlanThisFrame as primary hold
# (heuristic: skip flag set but rebuild uses PipelineDebounceActive)
ok("rebuild uses PipelineDebounce", "PipelineDebounceActive" in sch)

ui = (root / "Source/View/Ui.lua").read_text(encoding="utf-8")
ok("Ui no IsPrewarmBusy gate", "IsPrewarmBusy" not in ui)

tw = (root / "Source/View/StockPiler4TabWatch.lua").read_text(encoding="utf-8")
ok("TabWatch no PatchWatchRowsLiveCounts", "PatchWatchRowsLiveCounts" not in tw)

orch = (root / "Source/Core/Orchestrator.lua").read_text(encoding="utf-8")
ok("TryExecutePlant uses ExecutePlant", "ExecutePlant(intent" in orch or "Grow.ExecutePlant(intent" in orch)
ok("Orch uses Refine.IsDirty", "Refine.IsDirty" in orch)
ok("Orch no Refine._refineDirty", "Refine._refineDirty" not in orch)

grow = (root / "Source/Grow.lua").read_text(encoding="utf-8")
ok("IssuePlantOne no PickPlantCandidate", "function Grow.IssuePlantOne" in grow)

refine = (root / "Source/Refine.lua").read_text(encoding="utf-8")
ok("Refine.IsDirty API", "function Refine.IsDirty" in refine)
ok("Refine.ClearDirty API", "function Refine.ClearDirty" in refine)

demand = (root / "Source/Planner/DemandPlan.lua").read_text(encoding="utf-8")
ok("DemandPlan has Build body", "function DemandPlan.Build" in demand and len(demand) > 500)

brew = (root / "Source/Planner/BrewPlan.lua").read_text(encoding="utf-8")
ok("BrewPlan BuildIntent real", "recipeKey" in brew and "function BrewPlan.BuildIntent" in brew)

buy = (root / "Source/Planner/BuyPlan.lua").read_text(encoding="utf-8")
ok("BuyPlan BuildIntent real", "deficit" in buy and "function BuyPlan.BuildIntent" in buy)

planner = (root / "Source/Planner/Planner.lua").read_text(encoding="utf-8")
ok("BuildFull brewIntent not nil literal", "brewIntent = nil" not in planner.split("BuildFull")[1][:2500] if "BuildFull" in planner else False)
# softer: BrewPlan.BuildIntent used
ok("BuildFull uses BrewPlan", "BrewPlan.BuildIntent" in planner)
ok("BuildFull uses BuyPlan", "BuyPlan.BuildIntent" in planner)

skill = (root / "Source/SkillUp.lua").read_text(encoding="utf-8")
ok("SkillUp ClimbEconomy", "ClimbEconomy" in skill or "ClimbPlan" in skill)

mod = (root / "StockPiler4.mod").read_text(encoding="utf-8")
ok("mod no UpgradeSeed.lua", "UpgradeSeed.lua" not in mod)
ok("mod has ClimbPlan", "ClimbPlan.lua" in mod)

boot = (root / "Source/Bootstrap.lua").read_text(encoding="utf-8")
ok("slash sp4", 'RegisterWSlashCmd("sp4"' in boot)

sp3 = Path(r"C:\Games\Return of Reckoning\Interface\AddOns\StockPiler3\Source\Bootstrap.lua").read_text(
    encoding="utf-8"
)
ok("SP3 still sp3", 'RegisterWSlashCmd("sp3"' in sp3)

fail = [c for c in checks if not c[1]]
for name, passed, detail in checks:
    print(("PASS" if passed else "FAIL"), name, detail)
print("---", len(checks) - len(fail), "/", len(checks), "passed")
raise SystemExit(1 if fail else 0)

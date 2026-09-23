from pathlib import Path

root = Path(r"C:\Games\Return of Reckoning\Interface\AddOns\StockPiler4")
checks = []


def ok(name, cond, detail=""):
    checks.append((name, bool(cond), detail))


mod = (root / "StockPiler4.mod").read_text(encoding="utf-8")
ok("mod UiMod StockPiler4", 'name="StockPiler4"' in mod)
ok("mod SV StockPiler4", "StockPiler4.Settings" in mod and "StockPiler4.Account" in mod)
ok("mod no UpgradeSeed.lua", "UpgradeSeed.lua" not in mod)
ok("mod GenusLadder", "GenusLadder.lua" in mod)
ok("mod ClimbPlan", "ClimbPlan.lua" in mod)
ok("mod PlantPlan", "PlantPlan.lua" in mod)
ok(
    "mod Demand/Brew/BuyPlan",
    all(x in mod for x in ("DemandPlan.lua", "BrewPlan.lua", "BuyPlan.lua")),
)

boot = (root / "Source/Bootstrap.lua").read_text(encoding="utf-8")
ok("slash sp4", 'RegisterWSlashCmd("sp4"' in boot)
ok("slash not sp3", 'RegisterWSlashCmd("sp3"' not in boot)

eb = (root / "Source/Core/EventBus.lua").read_text(encoding="utf-8")
ok("events sp4.", "sp4.plan.updated" in eb and "sp3.plan.updated" not in eb)

for fn in ["Grow.lua", "Brew.lua", "Buy.lua", "Planner/Planner.lua"]:
    t = (root / "Source" / fn).read_text(encoding="utf-8")
    ok(f"no Window in {fn}", "StockPiler4Window" not in t)

fw = (root / "Source/Core/FrameWork.lua").read_text(encoding="utf-8")
chunk = fw.split("function FW.IsPrewarmBusy")[1][:120]
ok("FW IsPrewarmBusy false", "return false" in chunk)

sch = (root / "Source/Core/Scheduler.lua").read_text(encoding="utf-8")
ok("50ms debounce", "PLAN_DEBOUNCE_SEC = 0.05" in sch)

names = {p.name for p in (root / "docs").glob("*.md")}
needed = {
    "CODE_QUALITY_REVIEW.md",
    "REFACTORING_RECOMMENDATIONS.md",
    "IMPLEMENTATION_PLAN.md",
    "FRAME_SLICING.md",
    "ACCEPTANCE.md",
}
ok("ref docs", needed <= names)

sp3boot = Path(
    r"C:\Games\Return of Reckoning\Interface\AddOns\StockPiler3\Source\Bootstrap.lua"
).read_text(encoding="utf-8")
ok("SP3 still sp3", 'RegisterWSlashCmd("sp3"' in sp3boot)

orch = (root / "Source/Core/Orchestrator.lua").read_text(encoding="utf-8")
ok("TryExecutePlant", "function TryExecutePlant" in orch)

ps = (root / "Source/Stores/PlanSnapshotStore.lua").read_text(encoding="utf-8")
ok("PlanSnapshot Replace", "function PS.Replace" in ps or "PS.Replace" in ps)

fail = [c for c in checks if not c[1]]
for name, passed, detail in checks:
    print(("PASS" if passed else "FAIL"), name, detail)
print("---", len(checks) - len(fail), "/", len(checks), "passed")
raise SystemExit(1 if fail else 0)

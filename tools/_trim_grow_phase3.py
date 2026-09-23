from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "Source" / "Grow.lua"
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

# Extract ClampSeedCommitsToBag body
clamp_body_lines = []
in_clamp = False
for ln in lines:
    if ln.startswith("local function ClampSeedCommitsToBag"):
        in_clamp = True
        continue
    if in_clamp:
        if ln.startswith("local function GetReadyHarvestPlots"):
            break
        clamp_body_lines.append(ln)

pick_wrappers = (
    "----------------------------------------------------------------\n"
    "-- Plant pick (Phase 3: Planner/PlantPlan.lua)\n"
    "----------------------------------------------------------------\n\n"
    "function Grow.ClampSeedCommitsToBag()\n"
    + "".join(clamp_body_lines)
    + "\nfunction Grow.PickPlantCandidate()\n"
    + "    local PP = StockPiler4.PlantPlan\n"
    + "    if PP and PP.PickPlantJob then\n"
    + "        return PP.PickPlantJob()\n"
    + "    end\n"
    + "    return nil\n"
    + "end\n\n"
    + "function Grow.GetPlantJob()\n"
    + "    if Grow._plantQueueDirty ~= true and Grow._plantJobProbed == true then\n"
    + "        return Grow._cachedPlantJob\n"
    + "    end\n"
    + "    local job = Grow.PickPlantCandidate()\n"
    + "    Grow.MarkPlantJobProbed(job)\n"
    + "    return job\n"
    + "end\n\n"
)

# Keep: [0:243) + [770:1080) + wrappers + [1694:)
part1 = lines[:243]
mid = lines[770:1080]
part3 = lines[1694:]

new_content = "".join(part1) + "".join(mid) + pick_wrappers + "".join(part3)
path.write_text(new_content, encoding="utf-8", newline="\n")
print("Grow.lua lines:", len(new_content.splitlines()))

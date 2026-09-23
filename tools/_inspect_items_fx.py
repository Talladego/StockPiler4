from pathlib import Path
import re

raw = Path(r"C:\Games\Return of Reckoning\logs\uilog.log").read_bytes()
text = raw.decode("utf-16-le")
acc = Path(
    r"C:\Games\Return of Reckoning\user\settings\GLOBAL\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")

# All brew recipe keys from dump stats (truncated in log!)
for line in text.splitlines():
    if "--- brew (recipe) ---" in line or (
        "key=containerx" in line and "attempts=" in line and "StockPiler4|" in line
    ):
        print(line[line.find("StockPiler4|") :][:220])

# Count recipes and list mains
keys = re.findall(r'\n\t\t\["(containerx[^"]+)"\]', acc)
print("\nDisk recipes:", len(keys))
for k in keys:
    main = re.search(r"mainx[^|]*(?:\|uid:\d+|\|fx:\d+)", k)
    print(" ", main.group(0) if main else "?", "len", len(k))

# Check if Items store has effectId for 83543/83580 vs 83507/83516
for uid in (83543, 83580, 83507, 83516, 190537):
    m = re.search(rf'\["uid:{uid}"\]\s*=\s*\{{(.*?)\n\t\t\}}', acc, re.DOTALL)
    if not m:
        # try numeric key
        m = re.search(rf'\[{uid}\]\s*=\s*\{{(.*?)\n\t\t\}}', acc, re.DOTALL)
    if not m:
        print(f"item {uid}: NOT FOUND")
        continue
    body = m.group(1)[:500]
    eff = re.search(r"effectId\s*=\s*([\d]+)", body)
    inc = re.search(r"incomplete\s*=\s*(true|false)", body)
    print(f"item {uid}: effectId={eff.group(1) if eff else None} incomplete={inc.group(1) if inc else None}")

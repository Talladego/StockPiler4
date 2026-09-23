from pathlib import Path
import re

acc = Path(r"C:\Games\Return of Reckoning\user\settings\GLOBAL\StockPiler4\SavedVariables.lua").read_text(
    encoding="utf-8", errors="replace"
)

# Extract potion recipeKeys array strings for Power and Rejuvenating
for uid, main in (("3000649", "83543"), ("3000409", "83580"), ("3000209", "83507")):
    # find potion block
    m = re.search(rf'\["uid:{uid}"\]\s*=\s*\{{(.*?)\n\t\t\}}', acc, re.DOTALL)
    if not m:
        print(uid, "potion block NOT FOUND")
        continue
    body = m.group(1)
    # recipeKeys entries
    keys = re.findall(r'\[\d+\]\s*=\s*"([^"]*)"', body)
    active = re.search(r'activeRecipeKey\s*=\s*"([^"]*)"', body)
    print(f"\n=== uid:{uid} ===")
    print("active len", len(active.group(1)) if active else None)
    if active:
        print("active==full recipe", active.group(1) in acc[acc.find("recipes"):acc.find("recipes")+50000] if False else "")
    for i, k in enumerate(keys):
        print(f" recipeKeys[{i+1}] len={len(k)}")
        # compare to recipes table key containing main
        fps = re.findall(r'\["(containerx[^"]+)"\]', acc)
        match = next((fp for fp in fps if f"uid:{main}" in fp or (main == "83507" and f"uid:{main}" in fp)), None)
        if match:
            print(" vs recipes key len", len(match), "EQUAL" if k == match else "DIFF")
            if k != match:
                print(" key starts", k[:80])
                print(" rec starts", match[:80])
                for j, (a, b) in enumerate(zip(k, match)):
                    if a != b:
                        print(" diff at", j)
                        break
                else:
                    print(" prefix equal lens", len(k), len(match))

from pathlib import Path
import re

acc = Path(
    r"C:\Games\Return of Reckoning\user\settings\GLOBAL\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")
char = Path(
    r"C:\Games\Return of Reckoning\user\settings\Martyrs Square\SharedProfile\SharedProfile\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")

# potions count
potion_keys = re.findall(r'\n\t\t\["(uid:\d+)"\]', acc)
# only under potions section - rough
print("uid-like keys in GLOBAL", len(potion_keys))

# Find potions table block
pm = re.search(r"\tpotions\s*=\s*\{(.*?)\n\t\},", acc, re.DOTALL)
if pm:
    body = pm.group(1)
    pks = re.findall(r'\["(uid:\d+)"\]', body)
    print("potions in table", len(pks), pks)

# watches enabled
for m in re.finditer(r'\["(uid:\d+\|rk:[^"]+)"\]\s*=\s*\{([^}]*)\}', char):
    key, body = m.group(1), m.group(2)
    en = re.search(r"enabled\s*=\s*(true|false)", body)
    uid = key.split("|")[0]
    rk = key.split("|rk:", 1)[1]
    print(uid, "enabled=", en.group(1) if en else "?", "rk in recipes", f'["{rk}"]' in acc)

# Simulate IsIncompleteMainUpgrade: any fx recipe that would dominate uid watches?
recipe_keys = re.findall(r'\n\t\t\["(containerx[^"]+)"\]', acc)
print("\nAll recipe mains:")
for k in recipe_keys:
    main = re.search(r"mainx[^|]*(?:\|uid:\d+|\|fx:\d+)[^|]*", k)
    print(" ", main.group(0) if main else k[:60])

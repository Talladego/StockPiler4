from pathlib import Path
import re

raw = Path(r"C:\Games\Return of Reckoning\logs\uilog.log").read_bytes()
text = raw.decode("utf-16-le")
acc = Path(
    r"C:\Games\Return of Reckoning\user\settings\GLOBAL\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")
char = Path(
    r"C:\Games\Return of Reckoning\user\settings\Martyrs Square\SharedProfile\SharedProfile\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")

lines = text.splitlines()
rows = []
for i, l in enumerate(lines):
    if "key=uid:" in l and "status=" in l and "StockPiler4|" in l:
        a = l.find(" key=")
        b = l.find(" status=")
        if a > 0 and b > a:
            name = l[l.find("] ") + 2 : a]
            key = l[a + 5 : b]
            status = l[b + 8 :].split()[0]
            rows.append((i + 1, name, key, status))

print("rows", len(rows))
for r in rows[-10:]:
    print(r[0], r[1], r[3], "keylen", len(r[2]))

print(
    "Account.recipes count on disk",
    len(re.findall(r'\n\t\t\["containerx', acc)),
)

for r in rows:
    if 179350 <= r[0] <= 179379:
        rk = r[2].split("|rk:", 1)[1]
        print(
            r[1],
            r[3],
            "rk in recipes",
            f'["{rk}"]' in acc,
            "watch in char",
            f'["{r[2]}"]' in char,
        )

for name, uid, main in [
    ("Power", "3000649", "83543"),
    ("Rejuv", "3000409", "83580"),
    ("DraughtRec", "3000209", "83507"),
]:
    for r in rows:
        if 179350 <= r[0] <= 179379 and r[2].startswith("uid:" + uid):
            rk = r[2].split("|rk:", 1)[1]
            keys = re.findall(r'\n\t\t\["(containerx[^"]+)"\]', acc)
            match = [k for k in keys if f"uid:{main}" in k or f"fx:" in k and main == "x"]
            match = [k for k in keys if f"uid:{main}" in k]
            print(f"\n{name} dump status={r[3]}")
            if match:
                k = match[0]
                print(" equal", k == rk, "lens", len(k), len(rk))
                if k != rk:
                    for j, (a, b) in enumerate(zip(k, rk)):
                        if a != b:
                            print("diff", j, repr(a), repr(b))
                            print("ctx k", k[max(0, j - 30) : j + 30])
                            print("ctx r", rk[max(0, j - 30) : j + 30])
                            break
                    else:
                        print("prefix ok lens", len(k), len(rk))
            else:
                print("NO matching recipe for main", main)
            break

# Check potion recipeKeys for Power vs watch
print("\n=== potion recipeKeys vs watch rk ===")
for uid in ("3000649", "3000409", "3000209"):
    m = re.search(rf'\["uid:{uid}"\]\s*=\s*\{{(.*?)\n\t\t\}}', acc, re.DOTALL)
    if not m:
        print(uid, "missing potion")
        continue
    body = m.group(1)
    rks = re.findall(r'\[\d+\]\s*=\s*"([^"]*)"', body)
    # watch
    wm = re.search(rf'\["(uid:{uid}\|rk:[^"]+)"\]', char)
    wrk = wm.group(1).split("|rk:", 1)[1] if wm else None
    print(uid, "recipeKeys", len(rks), "watch rk match any", wrk in rks if wrk else None)
    for i, k in enumerate(rks):
        print(f"  [{i}] ==watch", k == wrk, "in recipes", f'["{k}"]' in acc)

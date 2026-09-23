from pathlib import Path
import re

acc = Path(
    r"C:\Games\Return of Reckoning\user\settings\GLOBAL\StockPiler4\SavedVariables.lua"
).read_text(encoding="utf-8", errors="replace")

# Inspect recipe bodies for Power and Rejuv - outcomes, slots slim form
for label, token in [("Power", "uid:83543"), ("Rejuv", "uid:83580"), ("Draught", "uid:83507"), ("Elixir", "uid:83516"), ("Unguent", "fx:13")]:
    m = re.search(rf'\["(containerx[^"]*{re.escape(token)}[^"]*)"\]\s*=\s*\{{', acc)
    if not m:
        print(label, "NO RECIPE")
        continue
    key = m.group(1)
    start = m.end() - 1
    # brace match
    i = start
    depth = 0
    while i < len(acc):
        if acc[i] == "{":
            depth += 1
        elif acc[i] == "}":
            depth -= 1
            if depth == 0:
                body = acc[start : i + 1]
                break
        i += 1
    else:
        body = "?"
    outcomes = re.findall(r'\["(\d+)"\]', body[body.find("outcomes") : body.find("outcomes") + 400] if "outcomes" in body else "")
    print(f"\n{label} keylen={len(key)}")
    print("  outcomes uids", outcomes[:8])
    print("  has slots", "slots" in body)
    print("  brewAttempts", re.search(r"brewAttempts\s*=\s*([\d.]+)", body))
    # slot roles
    roles = re.findall(r'role\s*=\s*"(\w+)"', body)
    print("  roles", roles)
    # incomplete flags
    print("  incomplete count", body.count("incomplete"))

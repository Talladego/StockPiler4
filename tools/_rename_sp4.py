# One-shot: normalize SP3->SP4 strings after tree copy.
import os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
exts = {".lua", ".xml", ".mod", ".md", ".py", ".txt"}
replacements = [
    ("StockPiler4", "StockPiler4"),
    ("stockpiler4", "stockpiler4"),
    ("STOCKPILER4", "STOCKPILER4"),
    ("/sp4", "/sp4"),
    ("SP4Tab", "SP4Tab"),
    ("SP4_", "SP4_"),
]

count_files = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__")]
    for fn in filenames:
        path = os.path.join(dirpath, fn)
        ext = os.path.splitext(fn)[1].lower()
        if ext not in exts and fn != ".gitignore":
            continue
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        orig = text
        for a, b in replacements:
            text = text.replace(a, b)
        if fn == "StockPiler4.mod":
            text = text.replace('version="0.4.0"', 'version="0.4.0"')
            text = text.replace(
                "lean cult/apo stock automation. Parallel-safe with StockPiler / StockPiler2.",
                "clean-core cult/apo stock automation. Parallel-safe with StockPiler4.",
            )
        text = text.replace('L"0.4.0"', 'L"0.4.0"')
        text = text.replace('"0.4.0"', '"0.4.0"')
        if text != orig:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            count_files += 1
            print("updated", os.path.relpath(path, root))

print("Updated", count_files, "files under", root)

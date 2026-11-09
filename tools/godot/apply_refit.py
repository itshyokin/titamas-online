"""Merges tools/godot/refit_out.json (written by refit_rigid.gd) into data/items.json and
data/appearance.json, changing only the "fit" entries and keeping the files' formatting."""
import json, os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
fits = json.load(open(os.path.join(here, "refit_out.json")))

def fix(v):
    # Whole numbers stay ints (Godot's JSON writes them as floats).
    if isinstance(v, float) and v.is_integer() and abs(v) < 1e9:
        return int(v) if False else v
    if isinstance(v, list): return [fix(x) for x in v]
    if isinstance(v, dict): return {k: fix(x) for k, x in v.items()}
    return v

for name, lists in (("items.json", ["items"]), ("appearance.json", ["hair_styles", "facial_hair"])):
    path = os.path.join(root, "data", name)
    data = json.load(open(path))
    n = 0
    for key in lists:
        for e in data.get(key, []):
            if e.get("id") in fits and "fit" in e:
                e["fit"] = fix(fits[e["id"]]); n += 1
    open(path, "w").write(json.dumps(data, indent="\t", ensure_ascii=False) + "\n")
    print(name, n, "fits")

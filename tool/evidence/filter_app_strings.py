import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from extract_strings import build_corpus
S, roots = sys.argv[1], sys.argv[2:]
strs = json.load(open(f"{S}/strs2/snapshot_strings.json"))
corpus, n = build_corpus(roots)
def script_ok(s):
    # keep Latin text and Indic-script text (the app ships hi/bn/gu/kn/mr/ta/te)
    bad = 0
    for ch in s:
        o = ord(ch)
        if o < 0x250 or 0x0900 <= o <= 0x0DFF or o in (0x2013,0x2014,0x2018,0x2019,0x201c,0x201d,0x20b9,0x2022,0x2026,0x200c,0x200d):
            continue
        bad += 1
    return bad == 0
keep = [s for s in strs if script_ok(s) and s not in corpus and s.strip() not in corpus and len(s) >= 2]
latin = [s for s in keep if all(ord(c) < 0x250 for c in s)]
indic = [s for s in keep if any(0x0900 <= ord(c) <= 0x0DFF for c in s)]
os.makedirs(f"{S}/strs3", exist_ok=True)
json.dump(latin, open(f"{S}/strs3/latin.json", "w"), ensure_ascii=False, indent=0)
json.dump(indic, open(f"{S}/strs3/indic.json", "w"), ensure_ascii=False, indent=0)
print("corpus files", n, "kept", len(keep), "latin", len(latin), "indic", len(indic))

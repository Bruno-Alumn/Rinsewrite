"""Held-out eval: messages never trained on, corrupted with a fixed seed, scored per grammar level.

  RINSEWRITE_ADAPTER=0 .venv/bin/python finetune/eval_valid.py      # current app (few-shot prompt)
  .venv/bin/python finetune/eval_valid.py                         # with finetune/adapter
Score = exact match after normalizing case/punctuation, and word-level F1 vs the target.
"""
import json, os, random, re, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "engine"))
sys.path.insert(0, HERE)
os.environ.setdefault("RINSEWRITE_ADAPTER", os.path.join(HERE, "adapter"))
import build_dataset as bd  # noqa: E402
import prompts  # noqa: E402
from engine import Engine  # noqa: E402


def words(t):
    return re.findall(r"[\wÀ-ÿ']+", t.lower().replace("’", "'"))


def f1(out, ref):
    o, r = Counter(words(out)), Counter(words(ref))
    hit = sum((o & r).values())
    if not hit:
        return 0.0
    p, rc = hit / sum(o.values()), hit / sum(r.values())
    return 2 * p * rc / (p + rc)


def main():
    rows = []
    import glob
    for path in sorted(glob.glob(os.path.join(HERE, "data", "*_raw*.jsonl"))):
        rows += [json.loads(l) for l in open(path) if l.strip()]
    banned = bd.test_sentences()
    rows = [r for r in rows if bd._norm(r.get("broken", r.get("ai", ""))) not in banned]
    random.seed(7)
    random.shuffle(rows)  # same order as build_dataset -> first n are the valid split
    valid = rows[: max(20, len(rows) // 12)]
    random.seed(123)
    e = Engine(max_modes=15)
    print("adapter:", e.adapter)
    keys = ["broken", "light", "standard", "polished", "formal"]
    stats = {k: [0, 0.0, 0] for k in keys}
    stats["humanize"] = [0, 0.0, 0]
    t0 = time.time()
    for r in valid:
        if "ai" in r:
            out = e.correct(r["ai"], 0.5, 0.5)["text"]
            s = stats["humanize"]
            s[0] += words(out) == words(r["natural"]); s[1] += f1(out, r["natural"]); s[2] += 1
            continue
        src = bd.corrupt(r["broken"], 0.22)
        for g, k in enumerate(keys):
            tgt = bd.keep_emojis(r["broken"], r[k])
            out = e.correct(src, g / 4, 0)["text"]
            s = stats[k]
            s[0] += words(out) == words(tgt); s[1] += f1(out, tgt); s[2] += 1
    for k, (ex, f, n) in stats.items():
        if n:
            print(f"{k:9} exact {ex}/{n} ({ex/n:.0%})  F1 {f/n:.3f}")
    tot = sum(v[1] for v in stats.values()) / max(1, sum(v[2] for v in stats.values()))
    print(f"overall F1 {tot:.3f}  ({time.time()-t0:.0f}s)")


if __name__ == "__main__":
    main()

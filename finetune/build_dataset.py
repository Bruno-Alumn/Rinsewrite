"""Build LoRA training data: corrupt hand-written messages with fast-typing typos and render
them in the exact short prompt the app uses with the adapter. Output: finetune/data/{train,valid}.jsonl"""
import glob, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "engine"))
import prompts  # noqa: E402

random.seed(7)
LANG = {"en": "English", "es": "Spanish", "fr": "French"}
KEYS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
NEAR = {}
for r, row in enumerate(KEYS):
    for c, ch in enumerate(row):
        n = set()
        for dr in (-1, 0, 1):
            rr = r + dr
            if 0 <= rr < 3:
                for dc in (-1, 0, 1):
                    cc = c + dc
                    if 0 <= cc < len(KEYS[rr]) and (dr or dc):
                        n.add(KEYS[rr][cc])
        NEAR[ch] = "".join(sorted(n))


def typo(word: str) -> str:
    if len(word) < 3 or not word.isalpha():
        return word
    i = random.randrange(len(word))
    kind = random.random()
    low = word.lower()
    if kind < 0.35 and i < len(word) - 1:                     # swap neighbours: teh
        return word[:i] + word[i + 1] + word[i] + word[i + 2:]
    if kind < 0.55:                                           # missed key: realy
        return word[:i] + word[i + 1:]
    if kind < 0.70:                                           # doubled key: reallly
        return word[:i] + word[i] + word[i:]
    ch = low[i]
    if ch in NEAR:
        alt = random.choice(NEAR[ch])
        if kind < 0.88:                                       # neighbour key: wany
            return word[:i] + alt + word[i + 1:]
        return word[:i] + alt + word[i:]                      # extra neighbour: wanmt
    return word


def corrupt(text: str, rate: float) -> str:
    out = []
    for tok in text.split(" "):
        out.append(typo(tok) if random.random() < rate else tok)
    return " ".join(out)


_EMOJI = re.compile("[\U0001F000-\U0001FAFF\u2600-\u27BF]")


def keep_emojis(src: str, target: str) -> str:
    """The app keeps emojis at every level; add back any a target dropped."""
    missing = [e for e in _EMOJI.findall(src) if e not in target]
    return target + (" " + "".join(missing) if missing else "")


def _norm(t: str) -> str:
    return re.sub(r"[^\w]+", " ", t.lower()).strip()


def load_split() -> tuple[list, list]:
    """Raw messages minus test-set overlaps, shuffled with a fixed seed: (valid, train)."""
    rows = []
    for path in sorted(glob.glob(os.path.join(HERE, "data", "*_raw*.jsonl"))):
        with open(path, encoding="utf-8") as f:
            rows += [json.loads(l) for l in f if l.strip()]
    banned = test_sentences()
    before = len(rows)
    rows = [r for r in rows if _norm(r.get("broken", r.get("ai", ""))) not in banned]
    print(f"dropped {before - len(rows)} messages that overlap the test sets")
    random.seed(7)
    random.shuffle(rows)
    n_valid = max(20, len(rows) // 12)
    return rows[:n_valid], rows[n_valid:]


def test_sentences() -> set[str]:
    """Sentences used by the eval scripts; kept out of training so scores stay honest."""
    sys.path.insert(0, os.path.join(HERE, "..", "engine", "tests"))
    import test_drift, test_language, test_typos  # noqa: E401

    sents = [t for t, _ in test_typos.CASES]
    sents += test_drift.ES + test_drift.EN + test_drift.FR
    sents += [t for v in test_language.CASES.values() for t in v]
    return {_norm(t) for t in sents}


def render(mode: int, src: str, lang: str, target: str) -> dict:
    prompt = prompts.prefix(mode, shots=False) + prompts.suffix(src, lang)
    return {"prompt": prompt, "completion": f"{target}\n</text><|im_end|>"}


def main():
    valid, train = load_split()
    splits = {"valid": valid, "train": train}
    for name, items in splits.items():
        out = []
        for r in items:
            lang = LANG[r["lang"]]
            if "ai" in r:  # AI-sounding text: humanize targets at standard+ grammar
                for g in (2, 3):
                    out.append(render(g * prompts.H + 1, r["ai"], lang, r["natural"]))
                    out.append(render(g * prompts.H + 2, r["ai"], lang, r["casual"]))
                continue
            targets = [keep_emojis(r["broken"], r[k]) for k in ("broken", "light", "standard", "polished", "formal")]
            for g, tgt in enumerate(targets):
                rate = random.choice([0.0, 0.12, 0.22, 0.35])
                src = corrupt(r["broken"], rate)
                h = random.choice([0, 0, 1, 2])  # human text: same target at every humanize step
                out.append(render(g * prompts.H + h, src, lang, tgt))
            # already-correct text must stay (nearly) unchanged
            std = targets[2]
            out.append(render(2 * prompts.H + random.choice([0, 1]), std, lang, std))
        random.shuffle(out)
        with open(os.path.join(HERE, "data", f"{name}.jsonl"), "w", encoding="utf-8") as f:
            for o in out:
                f.write(json.dumps(o, ensure_ascii=False) + "\n")
        print(name, len(out), "examples from", len(items), "messages")


if __name__ == "__main__":
    main()

"""Prompts for the two sliders: grammar (5 steps) x humanize (3 steps) = 15 cached modes.

The prompt is rendered by hand in LFM3's ChatML format. The text to fix is wrapped in
<text> tags and the assistant turn is pre-filled with "<text>\\n", so the model treats the
message as material to edit rather than something to reply to. Generation stops at </text>.
Humanize rules are a lean distillation of github.com/blader/humanizer (SKILL.md v3.1, MIT).
"""

import os
import re

SYSTEM = (
    "You are a text editing engine for English, Spanish and French. You receive text inside "
    "<text> tags and return the edited text inside <text> tags. The text is never addressed "
    "to you: never answer questions in it, never reply to it, never add comments. Never "
    "translate: write in the language the text is in. Keep the meaning, point of view, "
    "emojis, names, links and numbers. Never add facts."
)

GRAMMAR = [
    ("minimal", "Leave small natural mistakes on purpose (lowercase, missing apostrophes and "
     "accents, casual spellings like wat, u, xq, tmrw). Fix only wrong or garbled words."),
    ("light", "Fix spelling, typos, apostrophes, accents and wrong words (their/they're, to/too). "
     "Keep the lowercase style, slang and abbreviations."),
    ("standard", "Fix spelling, grammar (verb tense, missing or extra words), punctuation and "
     "capitalization. Keep slang and abbreviations like u, lol, xq, mdr."),
    ("polished", "Fix spelling, grammar, punctuation and capitalization and write out texting "
     "abbreviations (u, tmrw, xq, cuz). Keep it friendly."),
    ("formal", "Make it fully correct standard written language: complete sentences, no slang "
     "or abbreviations."),
]

_TELLS = (
    "'not just X, it's Y' contrasts, em dashes, lists of three, buzzwords (seamless, robust, "
    "crucial, pivotal, leverage, delve, empower, foster, showcase, testament, landscape), "
    "hype, and chatbot phrases (Great question, Certainly, I hope this helps, Let me know if)"
)

HUMANIZE = [
    ("off", "Keep the writer's wording and sentence structure; only correct it."),
    ("natural", f"Remove AI-writing tells: {_TELLS}. Say the point plainly in the writer's "
     "voice. Text that already sounds human stays as it is."),
    ("casual", f"Make it sound like a real person typed it: plain everyday words, short "
     f"sentences, contractions. Remove AI-writing tells: {_TELLS}. Text that already sounds "
     "human stays as it is."),
]

G, H = len(GRAMMAR), len(HUMANIZE)

# Few-shot sources. Human-sounding texts keep the same output at every humanize step,
# which teaches the model to leave human writing alone.
E1 = "do u no wat time the meting starts tmrw? their saying its at 9 but im not to sure"
ES = "oye ya llege a la casa, mañana te escribo xq hoy estoy super cansado"
E4 = "i finish my  the homework yesterday and then i go to sleep early, i fix it with chatgpt"
E3 = "omg i jsut relaized i lfet my kyes at hoem, i rlly wnat to go back"
ES3 = "perdon no vi tu mensjae, ahorita lo leo"
ES2 = "ya voy saliendo del trabajo, necesitas q pase por algo?"
FR = "ce soir je peux pas venir, je suis trop fatiguer"
E2 = "lol i totaly forgot about it, ill be ther in like 10 min"
AI2 = ("I wanted to delve into the feedback you shared. It's crucial that we leverage these "
       "insights to foster a more seamless experience. Ultimately, it's about trust.")
AI = ("Great question! Our new app isnt just a tool — its a seamless, robust solution that "
      "empowers teams to colaborate, innovate, and grow. I hope this helps!")

HUMAN_OUT = {  # by grammar step
    E1: [
        "do u know wat time the meeting starts tmrw? their saying its at 9 but im not to sure",
        "do u know what time the meeting starts tmrw? they're saying it's at 9 but im not too sure",
        "Do u know what time the meeting starts tmrw? They're saying it's at 9, but I'm not too sure.",
        "Do you know what time the meeting starts tomorrow? They're saying it's at 9, but I'm not too sure.",
        "Do you know what time the meeting starts tomorrow? They are saying it is at 9, but I am not entirely sure.",
    ],
    E2: [
        "lol i totally forgot about it, ill be there in like 10 min",
        "lol i totally forgot about it, i'll be there in like 10 min",
        "Lol, I totally forgot about it. I'll be there in like 10 min.",
        "Haha, I totally forgot about it. I'll be there in about 10 minutes.",
        "I completely forgot about it. I will be there in approximately ten minutes.",
    ],
    ES: [
        "oye ya llegue a la casa, mañana te escribo xq hoy estoy super cansado",
        "oye ya llegué a la casa, mañana te escribo xq hoy estoy súper cansado",
        "Oye, ya llegué a la casa. Mañana te escribo xq hoy estoy súper cansado.",
        "Oye, ya llegué a la casa. Mañana te escribo porque hoy estoy súper cansado.",
        "Ya llegué a casa. Mañana te escribo, porque hoy estoy muy cansado.",
    ],
    E4: [  # grammar: tense, stray word, double space left by a deleted word
        "i finish my homework yesterday and then i go to sleep early, i fix it with chatgpt",
        "i finish my homework yesterday and then i go to sleep early, i fix it with chatgpt",
        "I finished my homework yesterday and then I went to sleep early. I fixed it with ChatGPT.",
        "I finished my homework yesterday and then I went to sleep early. I fixed it with ChatGPT.",
        "I finished my homework yesterday, and then I went to sleep early. I fixed it with ChatGPT.",
    ],
    E3: [
        "omg i just realized i left my keys at home, i rlly want to go back",
        "omg i just realized i left my keys at home, i rlly want to go back",
        "Omg, I just realized I left my keys at home. I rlly want to go back.",
        "Oh my God, I just realized I left my keys at home. I really want to go back.",
        "I just realized that I left my keys at home. I really want to go back.",
    ],
    ES3: [
        "perdon no vi tu mensaje, ahorita lo leo",
        "perdón no vi tu mensaje, ahorita lo leo",
        "Perdón, no vi tu mensaje. Ahorita lo leo.",
        "Perdón, no vi tu mensaje. Ahorita lo leo.",
        "Perdón, no vi tu mensaje. Ahora lo leo.",
    ],
    ES2: [
        "ya voy saliendo del trabajo, necesitas q pase por algo?",
        "ya voy saliendo del trabajo, necesitas q pase por algo?",
        "Ya voy saliendo del trabajo, necesitas q pase por algo?",
        "Ya voy saliendo del trabajo. Necesitas que pase por algo?",
        "Ya estoy saliendo del trabajo. Necesitas que pase a comprar algo?",
    ],
    FR: [
        "ce soir je peux pas venir, je suis trop fatigué",
        "ce soir je peux pas venir, je suis trop fatigué",
        "Ce soir, je peux pas venir, je suis trop fatigué.",
        "Ce soir, je ne peux pas venir, je suis trop fatigué.",
        "Je ne peux pas venir ce soir, car je suis trop fatigué.",
    ],
}

AI_OUT = [  # [humanize][grammar]
    [
        "Great question! Our new app isnt just a tool — its a seamless, robust solution that empowers teams to collaborate, innovate, and grow. I hope this helps!",
        "Great question! Our new app isn't just a tool — it's a seamless, robust solution that empowers teams to collaborate, innovate, and grow. I hope this helps!",
        "Great question! Our new app isn't just a tool — it's a seamless, robust solution that empowers teams to collaborate, innovate, and grow. I hope this helps!",
        "Great question! Our new app isn't just a tool — it's a seamless, robust solution that empowers teams to collaborate, innovate, and grow. I hope this helps!",
        "Great question! Our new app is not just a tool; it is a seamless, robust solution that empowers teams to collaborate, innovate, and grow. I hope this helps!",
    ],
    [
        "Our new app makes it easier for teams to work together and get more done.",
        "Our new app makes it easier for teams to work together and get more done.",
        "Our new app makes it easier for teams to work together and get more done.",
        "Our new app makes it easier for teams to work together and get more done.",
        "Our new application makes it easier for teams to work together and accomplish more.",
    ],
    [
        "Our new app makes it way easier for teams to work together",
        "Our new app makes it way easier for teams to work together",
        "Our new app makes it way easier for teams to work together.",
        "Our new app makes it a lot easier for teams to work together.",
        "Our new app makes it much easier for teams to work together.",
    ],
]

AI2_OUT = [  # [humanize][grammar]
    [AI2] * 4 + ["I wanted to examine the feedback you shared. It is crucial that we leverage "
                 "these insights to foster a more seamless experience. Ultimately, it is about trust."],
    ["I went through your feedback. We should use it to make the app smoother to use."] * 4
    + ["I have reviewed your feedback. We should use it to make the application easier to use."],
    ["I read your feedback, let's use it to make things smoother"] * 2
    + ["I read your feedback. Let's use it to make things smoother."] * 2
    + ["I have read your feedback. Let us use it to make things smoother."],
]

_GREETINGS = {  # very short messages the statistical detector can't settle on its own
    "Spanish": {"hola", "gracias", "sí", "si", "vale", "claro", "jaja", "jajaja", "porfa", "buenas", "adiós", "chao", "oye", "bueno", "dale"},
    "French": {"salut", "merci", "oui", "ouais", "mdr", "bisous", "coucou", "bonjour", "bonsoir", "stp", "svp", "d'accord", "je", "tu"},
    "English": {"hey", "thanks", "yes", "yeah", "lol", "hi", "hello", "sure", "thx", "pls", "yep", "nope"},
}
_detector = None


def _lingua():
    global _detector
    if _detector is None:
        from lingua import Language, LanguageDetectorBuilder

        _detector = LanguageDetectorBuilder.from_languages(
            Language.ENGLISH, Language.SPANISH, Language.FRENCH
        ).build()
    return _detector


_NAMES = {"ENGLISH": "English", "SPANISH": "Spanish", "FRENCH": "French"}


def detect(text: str) -> tuple[str | None, float]:
    """(language, confidence) for EN/ES/FR; language is None when it's too ambiguous to call."""
    words = re.findall(r"[a-zà-ÿñ']+", text.lower())
    if not words:
        return None, 0.0
    scores = {_NAMES[c.language.name]: c.value for c in _lingua().compute_language_confidence_values(text)}
    for lang, vocab in _GREETINGS.items():
        scores[lang] = scores.get(lang, 0) + 0.5 * sum(w in vocab for w in words) / len(words)
    # Word votes: each word counts for the language where it is clearly most common. This copes
    # with typo-heavy text that the statistical detector misreads ("im so tierd i cant evne").
    for w in words:
        k = w.replace("'", "")
        zs = {lang: _freqs(code).get(k, 0.0) for lang, code in _CODES.items()}
        best_l = max(zs, key=zs.get)
        rest = max(z for l, z in zs.items() if l != best_l)
        if zs[best_l] >= 3.0 and zs[best_l] - rest >= 0.7:
            scores[best_l] = scores.get(best_l, 0) + 1.0 / len(words)
    if re.search(r"[ñ¿¡]", text):
        scores["Spanish"] += 0.5
    if re.search(r"[çœèêë]", text):
        scores["French"] += 0.5
    best = max(scores, key=scores.get)
    total = sum(scores.values()) or 1.0
    conf = scores[best] / total
    return (best if conf >= 0.45 else None), conf


def detect_lang(text: str) -> str | None:
    return detect(text)[0]


OPEN_ASSISTANT = "<|im_start|>assistant\n<think></think><text>\n"
STOP = "</text>"


def _step(v: float, n: int) -> int:
    v = min(max(float(v), 0.0), 1.0)
    return min(int(round(v * (n - 1))), n - 1)


def mode_for(grammar: float, humanize: float) -> int:
    return _step(grammar, G) * H + _step(humanize, H)


def split_mode(mode: int) -> tuple[int, int]:
    return divmod(mode, H)


def _instr(g: int, h: int) -> str:
    return f"Grammar: {GRAMMAR[g][0]}. Style: {HUMANIZE[h][0]}.\n<text>\n"


def prefix(mode: int, shots: bool = True) -> str:
    """Everything up to (and including) the opening <text> tag of the final user turn.
    shots=False is the short prompt used with the fine-tuned adapter (it learned the task)."""
    g, h = split_mode(mode)
    system = (f"{SYSTEM}\nGrammar ({GRAMMAR[g][0]}): {GRAMMAR[g][1]}\n"
              f"Style ({HUMANIZE[h][0]}): {HUMANIZE[h][1]}")
    examples = [(E4, HUMAN_OUT[E4][g], "English"), (E1, HUMAN_OUT[E1][g], "English"), (AI, AI_OUT[h][g], "English"),
             (ES, HUMAN_OUT[ES][g], "Spanish"), (E2, HUMAN_OUT[E2][g], "English"),
             (FR, HUMAN_OUT[FR][g], "French"), (AI2, AI2_OUT[h][g], "English"),
             (ES2, HUMAN_OUT[ES2][g], "Spanish"), (E3, HUMAN_OUT[E3][g], "English"),
             (ES3, HUMAN_OUT[ES3][g], "Spanish")]
    s = f"<|startoftext|><|im_start|>system\n{system}<|im_end|>\n"
    if not shots:
        return s + f"<|im_start|>user\n{_instr(g, h)}"
    for src, dst, lang in examples:
        s += f"<|im_start|>user\n{_instr(g, h)}{src}\n</text>\n{hint_line(src, lang)}{_lang(lang)}<|im_end|>\n"
        s += f"{OPEN_ASSISTANT}{dst}\n</text><|im_end|>\n"
    return s + f"<|im_start|>user\n{_instr(g, h)}"


def _lang(lang: str) -> str:
    return f"Language: {lang}. Write the result in {lang}."


def suffix(text: str, lang: str | None) -> str:
    hint = _lang(lang) if lang else "Language: the same language as the text. Do not translate."
    return f"{text}\n</text>\n{hint_line(text, lang)}{hint}<|im_end|>\n{OPEN_ASSISTANT}"


_RESIDUE = re.compile(
    r"(?i)(^|(?<=[.!?]) )("
    r"great question[!.]?|certainly[!.]|of course[!.]|absolutely[!.]|"
    r"i hope (this|that) helps[^.!?]*[.!?]?|"
    r"(please )?(feel free to |don't hesitate to )?let me know if [^.!?]*[.!?]?|"
    r"(would you like|want me to|should i continue)[^.!?]*\?"
    r")\s*"
)


_BUZZ = {  # English AI words → plain words (applied only when humanize is on)
    "seamless": "smooth", "seamlessly": "smoothly", "robust": "solid", "leverage": "use",
    "leveraging": "using", "utilize": "use", "utilizing": "using", "delve into": "look into",
    "delve": "dig", "foster": "build", "fostering": "building", "empower": "help",
    "empowers": "helps", "empowering": "helping", "crucial": "important", "pivotal": "important",
    "showcase": "show", "showcases": "shows", "showcasing": "showing", "underscore": "show",
    "underscores": "shows", "plays a crucial role in": "matters for", "plays a key role in":
    "matters for", "a testament to": "proof of", "cutting-edge": "modern", "game-changer":
    "big help", "embark on": "start", "meticulous": "careful", "meticulously": "carefully",
    "vibrant": "lively", "in today's fast-paced world": "these days",
}


def _swap(m: re.Match) -> str:
    w = m.group(0)
    rep = _BUZZ[w.lower()]
    return rep[:1].upper() + rep[1:] if w[:1].isupper() and rep else rep


def humanize_post(text: str, lang: str | None = "English") -> str:
    """Deterministic clean-up for the tells a 1.7B model reliably misses."""
    if lang == "English":
        text = re.sub(r"(?i)\b(" + "|".join(sorted(map(re.escape, _BUZZ), key=len, reverse=True)) + r")(?=\W|$)",
                      _swap, text)
        text = re.sub(r"(?i)\b(ultimately|additionally|furthermore|moreover),\s*(\w)",
                      lambda m: m.group(2).upper() if m.start() == 0 or text[m.start() - 2] in ".!?"
                      else m.group(2), text)
    t = re.sub(r"\s*[—–]\s*", ", ", text)          # em/en dashes → comma
    t = re.sub(r"\s+-\s+", ", ", t)                  # spaced hyphen used as dash
    t = t.replace("“", '"').replace("”", '"').replace("‘", "'").replace("’", "'")
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t)           # bold
    t = _RESIDUE.sub(lambda m: m.group(1), t).strip()
    t = re.sub(r",\s*,", ",", t)
    return t or text


def strip_inverted(out: str, src: str) -> str:
    """Spanish ¿ ¡ only if the writer used them; most people texting don't."""
    if "¿" not in src:
        out = out.replace("¿", "")
    if "¡" not in src:
        out = out.replace("¡", "")
    return re.sub(r"^\s+", "", out)


# words that legitimately appear when abbreviations are written out (asap, cuz, xq, stp, ...)
_EXPANSIONS = {
    "soon", "possible", "because", "tomorrow", "tonight", "you", "your", "you're", "please", "thanks",
    "laughing", "minutes", "birthday", "probably", "though", "something", "someone", "going", "want",
    "que", "porque", "favor", "cumpleaños", "también", "mañana", "nada", "verdad", "minutos",
    "plaît", "plait", "aujourd'hui", "rien", "beaucoup", "quelque", "chose", "bisous", "anniversaire",
}

_STOP = _EXPANSIONS.union(*[v for v in (
    {"the", "a", "an", "and", "to", "of", "it", "is", "you", "i", "me", "my", "so", "but", "that", "this", "for", "in", "on", "at", "are", "be", "do", "too", "very", "really", "just", "about", "would", "will", "am", "have", "has", "with", "your", "please", "because", "tomorrow", "okay", "haha", "minutes", "been", "hello", "anything"},
    {"el", "la", "los", "las", "un", "una", "y", "que", "de", "a", "en", "por", "favor", "porque", "es", "lo", "le", "se", "me", "te", "mi", "muy", "con", "para", "ya", "pero", "también", "entonces", "como", "estoy", "esta", "está"},
    {"le", "la", "les", "un", "une", "et", "de", "à", "a", "en", "pour", "que", "je", "tu", "il", "ne", "pas", "est", "ce", "ça", "moi", "car", "très", "s'il", "plaît", "plait", "il"},
)])


def _norm(w: str) -> str:
    import unicodedata

    return "".join(c for c in unicodedata.normalize("NFD", w.lower()) if unicodedata.category(c) != "Mn")


_PERSON = [  # pronoun groups; a change between groups flips who is speaking or addressed
    {"i", "me", "my", "mine", "myself", "yo", "mi", "mí", "conmigo", "je", "j", "moi", "mon", "ma", "mes"},
    {"you", "your", "yours", "u", "ur", "tu", "tú", "te", "ti", "contigo", "toi", "ton", "ta", "tes"},
]


def person_changed(src: str, out: str) -> bool:
    """True if a speaker/addressee pronoun group appears in only one of the two texts,
    or the 'me' words became 'te' words (e.g. "me mandas" -> "te mando")."""
    def groups(t):
        ws = {_norm(w) for w in re.findall(r"[\wÀ-ÿ]+", t)}
        # Spanish attached pronouns: mandarme, avisame, dime, decirte
        for w in list(ws):
            if len(w) > 4 and w.endswith(("rme", "ame", "eme", "ime")):
                ws.add("me")
            if len(w) > 4 and w.endswith(("rte", "ete")):
                ws.add("te")
        return [bool(ws & {_norm(x) for x in g}) for g in _PERSON]
    (s_me, s_you), (o_me, o_you) = groups(src), groups(out)
    # a swap, not a removal: "me mandas" -> "te mando" counts; dropping "yo" in Spanish doesn't
    return (s_me and not s_you and o_you and not o_me) or (s_you and not s_me and o_me and not o_you)


def dropped_words(src: str, out: str) -> list[str]:
    """Content words of src with nothing resembling them in out (the model skipped a word)."""
    from difflib import SequenceMatcher

    ow = [_norm(w) for w in re.findall(r"[\wÀ-ÿ']+", out)]
    dropped = []
    for w in re.findall(r"[\wÀ-ÿ']+", src):
        n = _norm(w)
        if len(n) < 4 or n in _STOP or n in _SLANG or n.isdigit() or n in ow:
            continue
        if not any(SequenceMatcher(None, n, o).ratio() >= 0.5 for o in ow):
            dropped.append(w)
    return dropped


def novel_words(src: str, out: str) -> list[str]:
    """Content words in out that don't resemble any word in src (signals invented meaning)."""
    from difflib import SequenceMatcher

    sw = [_norm(w) for w in re.findall(r"[\wÀ-ÿ']+", src)]
    novel, from_shots = [], []
    for w in re.findall(r"[\wÀ-ÿ']+", out):
        n = _norm(w)
        if n in _STOP or len(n) <= 2 or n.isdigit() or n in sw:
            continue
        if any(SequenceMatcher(None, n, s).ratio() >= 0.75 for s in sw):
            continue
        # Grammar fixes bring in common words (went, bought, doesn't); those are fine. Flag words
        # copied from the built-in examples, or rare words the model made up ("Obliviso").
        common = max(_freqs(c).get(n.replace("'", ""), 0.0) for c in ("en", "es", "fr")) >= 4.0
        if not common:
            novel.append(w)
        elif n in _shot_vocab():
            from_shots.append(w)
    # one common example word is usually a real fix ("went"); several mean a copied phrase
    return novel + (from_shots if len(from_shots) >= 2 else [])


_SHOT_VOCAB: set[str] | None = None


def _shot_vocab() -> set[str]:
    """Content words that appear in the few-shot examples (what contamination looks like)."""
    global _SHOT_VOCAB
    if _SHOT_VOCAB is None:
        texts = [E1, E2, E3, E4, ES, ES2, ES3, FR, AI, AI2]
        texts += [o for outs in HUMAN_OUT.values() for o in outs]
        texts += [o for outs in AI_OUT + AI2_OUT for o in outs]
        words = {_norm(w) for t in texts for w in re.findall(r"[\wÀ-ÿ']+", t)}
        _SHOT_VOCAB = {w for w in words if len(w) > 3 and w not in _STOP}
    return _SHOT_VOCAB


# -- spelling hints ----------------------------------------------------------------------
# A 1.7B model often leaves fast-typing typos ("tahts waht i siad") alone or misreads them.
# We flag rare words and list common words one keystroke away (swap, missing, extra or
# wrong letter), and pass them to the model as "Likely typos" — it still decides in context.

_WORDS: dict[str, dict[str, float]] = {}
_DISPLAY: dict[tuple[str, str], str] = {}
_CODES = {"English": "en", "Spanish": "es", "French": "fr"}
_ALPHA = {
    "en": "abcdefghijklmnopqrstuvwxyz'",
    "es": "abcdefghijklmnopqrstuvwxyzáéíóúñü",
    "fr": "abcdefghijklmnopqrstuvwxyzàâçéèêëîïôûùüÿœ'",
}
_SLANG = {
    "lol", "lmao", "omg", "omw", "tbh", "brb", "idk", "imo", "btw", "ur", "u", "ya", "yea", "pls",
    "plz", "thx", "tmrw", "rn", "ngl", "fr", "gonna", "wanna", "gotta", "kinda", "lmk", "asap",
    "q", "xq", "pq", "porfa", "jaja", "jajaja", "jeje", "wey", "neta", "chido", "tqm", "bss",
    "mdr", "stp", "svp", "jsp", "ptdr", "slt", "bjr", "dsl", "tkt", "cc",
}


def _freqs(code: str) -> dict[str, float]:
    if code not in _WORDS:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), f"words_{code}.tsv")
        d = {}
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    w, z = line.rstrip("\n").split("\t")
                    d[w] = float(z)
                for w, z in list(d.items()):  # "cant" -> can't, "thats" -> that's
                    k = w.replace("'", "")
                    if k != w and d.get(k, 0) < z:
                        d[k] = z
                        _DISPLAY[(code, k)] = w
        except FileNotFoundError:
            pass
        _WORDS[code] = d
    return _WORDS[code]


def _edits1(w: str, alpha: str) -> set[str]:
    splits = [(w[:i], w[i:]) for i in range(len(w) + 1)]
    out = {a + b[1:] for a, b in splits if b}
    out |= {a + b[1] + b[0] + b[2:] for a, b in splits if len(b) > 1}
    out |= {a + c + b[1:] for a, b in splits if b for c in alpha}
    out |= {a + c + b for a, b in splits for c in alpha}
    return out


def typo_hints(text: str, lang: str | None) -> list[tuple[str, list[str]]]:
    code = _CODES.get(lang or "", None)
    if not code:
        return []
    freq = _freqs(code)
    if not freq:
        return []
    hints = []
    for m in re.finditer(r"[^\W\d_]+(?:'[^\W\d_]+)?", text):
        raw = m.group(0)
        w = raw.lower()
        if len(w) < 3 or w in _SLANG or (raw[0].isupper() and m.start() > 0):
            continue  # short words, slang, and capitalized names are left to the model
        if freq.get(w, 0.0) >= 2.8:
            continue
        alpha = _ALPHA[code].replace("'", "")
        e1 = _edits1(w, alpha)
        # Rank by frequency, preferring what fast typing produces: same first letter,
        # swapped neighbours, and one keystroke over two.
        swaps = {w[:i] + w[i + 1] + w[i] + w[i + 2:] for i in range(len(w) - 1)}
        scored = {}
        for c in e1:
            z = freq.get(c, 0)
            if z >= 3.3:
                scored[c] = z + (c[0] == w[0]) * 1.0 + (c in swaps) * 0.5
        best2 = None
        if 4 <= len(w) <= 8:  # two keystrokes away ("reely" -> really), same first letter only
            for c1 in e1:
                for c in _edits1(c1, alpha):
                    z = freq.get(c, 0)
                    if z >= 4.0 and c not in scored and c[0] == w[0] and sorted(c) != sorted(w) or (
                        z >= 4.0 and c not in scored and sorted(c) == sorted(w)
                    ):
                        scored[c] = z - 0.5 + (sorted(c) == sorted(w)) * 1.0  # same letters, shuffled
                        if best2 is None or scored[c] > scored[best2]:
                            best2 = c
        if not scored:
            continue
        cands = sorted(((z, c) for c, z in scored.items()), reverse=True)
        top = cands[0][0]
        keep = [c for z, c in cands if z >= top - 2.5][:3]
        if best2 and best2 not in keep:  # always offer the strongest two-keystroke fix ("wath" -> what)
            keep = keep[:2] + [best2]
        picks = [_DISPLAY.get((code, c), c) for c in keep]
        if (raw, picks) not in hints:
            hints.append((raw, picks))
    return hints


def hint_line(text: str, lang: str | None) -> str:
    h = typo_hints(text, lang)
    if not h:
        return ""
    return "Likely typos: " + ", ".join(f"{w} → {' or '.join(c)}" for w, c in h) + "\n"

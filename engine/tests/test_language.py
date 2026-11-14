"""Checks that corrections never change the language, across every slider combination."""
import os
import sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import prompts
from engine import Engine

CASES = {
    "English": [
        "hey i cant make it tonite, im super tired from work",
        "did u finish the report? the boss was asking about it this morning",
        "lol thats so funny, send me the video",
        "ok",
        "im going to the store do u need anything",
        "Thank you for the opportunity. I look forward to hearing from you soon",
        "the meeting got moved to 3pm, can u let everyone know",
    ],
    "Spanish": [
        "oye ya llegaste a la casa? avisame cuando llegues",
        "no puedo ir hoy, tengo mucho trabajo",
        "jaja q chistoso, mandame el video",
        "gracias por todo, nos vemos mañana",
        "voy al super necesitas algo",
        "la reunion la cambiaron para las 3, avisale a todos porfa",
        "te quiero mucho",
        "ok perfecto",
    ],
    "French": [
        "salut ca va? tu fais quoi ce soir",
        "je peux pas venir aujourdhui jai trop de travail",
        "mdr trop drole envoie moi la video",
        "merci pour tout a demain",
        "je vais au supermarché tu as besoin de quelque chose",
        "la reunion a ete deplacee a 15h, previens tout le monde stp",
        "je t'aime",
    ],
}
if __name__ == "__main__":
    e = Engine(max_modes=15)
    fallbacks = {}
    bad = total = 0
    t = time.time()
    for g in range(prompts.G):
        for h in range(prompts.H):
            gv, hv = g / (prompts.G - 1), h / (prompts.H - 1)
            for lang, texts in CASES.items():
                for txt in texts:
                    det = prompts.detect_lang(txt) or lang
                    res = e.correct(txt, gv, hv)
                    out = res["text"]
                    if "fallback" in res:
                        fallbacks[(g, h, txt)] = res["fallback"]
                    got = prompts.detect_lang(out) or lang
                    total += 1
                    if det != lang or got != lang:
                        bad += 1
                        print(f"g{g} h{h} [{lang} detected={det} out={got}] {txt!r} -> {out!r}")
    print(f"fallbacks: {len(fallbacks)}", fallbacks)
    print(f"\n{bad}/{total} language problems ({time.time()-t:.0f}s)")

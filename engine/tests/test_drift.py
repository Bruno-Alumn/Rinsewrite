"""Meaning-drift check: counts invented content words, mainly for Spanish."""
import os
import sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import prompts
from engine import Engine

ES = [
    "voy al super necesitas algo", "ok perfecto", "la reunion la cambiaron para las 3, avisale a todos porfa",
    "jaja q chistoso, mandame el video", "oye ya llegaste a la casa? avisame cuando llegues",
    "no puedo ir hoy, tengo mucho trabajo", "te quiero mucho", "mañana paso por ti a las 8, estate lista",
    "q haces? quieres ir al cine en la noche", "se me olvido el cargador en tu casa, me lo guardas?",
    "ya comiste? te traigo algo de cenar", "felicidades!! q te la pases super bien en tu cumple",
    "llego tarde, hay mucho trafico", "me mandas la ubicacion porfa", "estoy enferma no voy a ir a clase",
]
EN = ["im going to the store do u need anything", "can u send me the adress again i lost it",
      "the meeting got moved to 3pm, can u let everyone know", "did u eat yet? i can bring u something"]
FR = ["je vais au supermarché tu as besoin de quelque chose", "tu peux m'envoyer l'adresse stp"]
if __name__ == "__main__":
    e = Engine(max_modes=15)
    grid = [(0.5, 0.5), (0.5, 0), (1, 0), (1, 1), (0, 0.5)]
    show = "-v" in sys.argv
    for lang, cases in (("es", ES), ("en", EN), ("fr", FR)):
        drift = n = inv = 0
        ms = []
        for g, h in grid:
            for t in cases:
                r = e.correct(t, g, h); ms.append(r["ms"])
                nv = prompts.novel_words(t, r["text"])
                inv += ("¿" in r["text"]) or ("¡" in r["text"])
                n += 1; drift += bool(nv)
                if nv and show:
                    print(f"  g{g} h{h} {t!r} -> {r['text']!r}  novel={nv}")
        guards = 0
        print(f"{lang}: drifted {drift}/{n}, inverted marks {inv}, median {sorted(ms)[len(ms)//2]}ms")

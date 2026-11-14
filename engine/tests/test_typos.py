"""Fast-typing typos (swaps, missed/doubled keys). Scores word-level match vs a reference."""
import re, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

CASES = [  # (typed, what was meant — compared case/punctuation-insensitively)
    ("danm i reely wany know", "damn i really wanna know"),
    ("omw be ther in 5 mni", "omw be there in 5 min"),
    ("tahts waht i siad lol", "that's what i said lol"),
    ("i dont thinl so tbh", "i don't think so tbh"),
    ("cna u call me whne ur free", "can u call me when ur free"),
    ("im so tierd i cant evne", "i'm so tired i can't even"),
    ("wath time si the gaem tonihgt", "what time is the game tonight"),
    ("brb gonna grba some fod", "brb gonna grab some food"),
    ("thnaks for teh help yesterdya", "thanks for the help yesterday"),
    ("ya lo se peor no quiero ir", "ya lo sé pero no quiero ir"),
    ("q onda, ya etsas listo?", "q onda, ya estás listo?"),
    ("te veo maññana en la esuela", "te veo mañana en la escuela"),
    ("je sius en retrad desole", "je suis en retard désolé"),
    ("tu veux venir ce siro?", "tu veux venir ce soir?"),
    # grammar
    ("sent or arrived also where was the dude located also I fix my  this with my vibe coded app 😛",
     "sent or arrived also where was the dude located also i fixed this with my vibe coded app 😛"),
    ("yesterday i go to the store and buy some milk", "yesterday i went to the store and bought some milk"),
    ("she dont know what she want", "she doesn't know what she wants"),
    ("me and him was going to the the party", "he and i were going to the party"),
    ("ayer yo voy al cine con mis amigo", "ayer fui al cine con mis amigos"),
]


def words(t):
    return re.findall(r"[\wÀ-ÿ']+", t.lower().replace("’", "'"))


def score(out, ref):
    o, r = words(out), words(ref)
    hit = sum(1 for w in r if w in o)
    return hit / len(r), len(o) - len(r)


if __name__ == "__main__":
    from engine import Engine
    e = Engine()
    g = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5
    tot = 0
    for typed, ref in CASES:
        r = e.correct(typed, g, 0)
        s, dlen = score(r["text"], ref)
        tot += s
        mark = "ok " if s == 1 and dlen == 0 else "BAD"
        print(f"{mark} {s:.2f} [{r['ms']}ms] {typed!r} -> {r['text']!r}")
    print(f"word accuracy {tot/len(CASES):.3f}")

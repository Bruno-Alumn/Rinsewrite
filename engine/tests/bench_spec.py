import os
import sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import Engine
LONG = ("hey so i talked to sarah about the trip and she said shes down to go but only if we leave on friday "
        "morning instead of thursday night cuz she has a exam on thursday afternoon that she cant miss. "
        "i think thats fine honestly, we can just drive striaght there and get to the cabin by like 2pm. "
        "also her brother might come to, he has a truck so we could fit all the gear and the kayaks in the back "
        "wich would be super helpfull. let me know what u think and if u already booked anything we might need "
        "to change the dates, i dont want us to lose the deposit lol")
MED = "Im so sorry i couldnt make it yesterday, my car broke down on the highway and i had to wait 3 hours for the tow truck 😩"
SHORT = "can u send me the adress again i lost it"
e = Engine()
for name, txt in [("short", SHORT), ("med", MED), ("long", LONG)]:
    for s in (0.0, 0.5, 1.0):
        res = {}
        for spec in (False, True):
            e.speculative = spec
            e.correct(txt, s, 0)  # warm this shape
            ts = []
            for _ in range(3):
                t = time.time(); r = e.correct(txt, s, 0); ts.append((time.time() - t) * 1000)
            dt = sorted(ts)[1]
            res[spec] = (r, dt, dict(e.last_stats) if spec else {})
        same = res[False][0]["text"] == res[True][0]["text"]
        print(f"{name:5} s={s} plain={res[False][1]:.0f}ms spec={res[True][1]:.0f}ms "
              f"x{res[False][1]/res[True][1]:.2f} tokens={res[True][0]['tokens']} {res[True][2]} same={same}")
        if not same:
            print("  PLAIN:", res[False][0]["text"]); print("  SPEC: ", res[True][0]["text"])

import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from engine import Engine
CASES = [
    "hey man i was thinkin we shoud go to the beech tomorow if its not to cold, what do u think? let me no asap cuz i need to tell my mom",
    "Im so sorry i couldnt make it yesterday, my car broke down on the highway and i had to wait 3 hours for the tow truck 😩",
    "what time does the store close today",
    "Thank you so much for reaching out! Our team is dedicated to delivering a seamless, robust, and innovative experience — and your feedback plays a crucial role in that journey. I hope this helps!",
    "hola q tal, ayer fuimos a la playa y el agua estaba helada pero nos divertimos un monton",
    "salut, tu veux venir diner chez moi samedi? jai fait une tarte au pomme",
]
e = Engine()
grid = [(0, 0), (0, 1), (0.5, 0), (0.5, 0.5), (0.5, 1), (1, 0), (1, 1)]
for g, h in grid:
    print(f"\n===== grammar {g}  humanize {h}")
    for c in CASES:
        r = e.correct(c, g, h)
        print(f"[{r['ms']}ms] {r['text']}")

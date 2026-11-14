"""Rinsewrite inference server: JSON lines over stdin/stdout, model kept warm.

Request:  {"id": 1, "text": "...", "grammar": 0.5, "humanize": 0.5}   (both 0…1)
Commands: {"cmd": "warm", "grammar": g, "humanize": h}  pre-fill that mode (loads model if needed)
          {"cmd": "unload"}                             free the model; next request reloads it
Response: {"id": 1, "text": "...", "ms": 210, ...}   or   {"id": 1, "error": "..."}
Events:   {"event": "ready", "load_ms": ...}
"""

import json
import os
import sys
import time
import traceback

# Keep fd 1 private for the protocol; anything libraries print goes to stderr.
_proto = os.fdopen(os.dup(1), "w", buffering=1)
os.dup2(2, 1)
sys.stdout = sys.stderr

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def send(obj):
    _proto.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _proto.flush()


def main():
    t = time.time()
    try:
        from engine import Engine

        engine = Engine()
        g, h = (float(sys.argv[1]), float(sys.argv[2])) if len(sys.argv) == 3 else (0.5, 0.5)
        engine.warm(g, h)
        engine.correct("warm up", g, h)
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        send({"event": "fatal", "error": f"{type(e).__name__}: {e}"})
        return 1
    send({"event": "ready", "load_ms": round((time.time() - t) * 1000)})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        rid = None
        try:
            req = json.loads(line)
            rid = req.get("id")
            cmd = req.get("cmd", "correct")
            g, h = float(req.get("grammar", 0.5)), float(req.get("humanize", 0.5))
            if cmd == "warm":
                t = time.time()
                engine.warm(g, h)
                send({"event": "warmed", "ms": round((time.time() - t) * 1000)})
            elif cmd == "unload":
                engine.unload()
                send({"event": "unloaded"})
            else:
                was_loaded = engine.loaded
                r = engine.correct(req["text"], g, h)
                r["id"] = rid
                r["reloaded"] = not was_loaded
                send(r)
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            send({"id": rid, "error": f"{type(e).__name__}: {e}"})
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""LoRA fine-tune LFM3-1.7B (4-bit) on the Rinsewrite correction task. Loss on the completion only.

  .venv/bin/python finetune/train.py --epochs 2
Writes finetune/adapter/adapters.safetensors (+ adapter_config.json), keeping the best
validation checkpoint.
"""
import argparse, json, math, os, random, sys, time

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "engine"))
from engine import model_path  # noqa: E402
from mlx_vlm import load  # noqa: E402
from mlx_vlm.trainer.peft.utils import get_peft_model, save_adapter  # noqa: E402


def encode(tok, rows, max_len):
    out = []
    for r in rows:
        p = tok.encode(r["prompt"], add_special_tokens=False)
        c = tok.encode(r["completion"], add_special_tokens=False)
        ids = (p + c)[:max_len]
        out.append((ids, len(p)))
    return out


def batches(data, bs, shuffle):
    # bucket by length to cut padding
    idx = sorted(range(len(data)), key=lambda i: len(data[i][0]))
    groups = [idx[i:i + bs] for i in range(0, len(idx), bs)]
    if shuffle:
        random.shuffle(groups)
    for g in groups:
        L = max(len(data[i][0]) for i in g)
        x = [data[i][0] + [0] * (L - len(data[i][0])) for i in g]
        m = [[1 if (j >= data[i][1] - 1 and j < len(data[i][0]) - 1) else 0 for j in range(L - 1)] for i in g]
        yield mx.array(x), mx.array(m, dtype=mx.float32)


def loss_fn(model, x, mask):
    out = model(x[:, :-1])
    logits = getattr(out, "logits", out).astype(mx.float32)
    ce = nn.losses.cross_entropy(logits, x[:, 1:]) * mask
    return ce.sum() / mx.maximum(mask.sum(), 1)


def evaluate(model, data, bs):
    tot = n = 0.0
    for x, m in batches(data, bs, False):
        l = loss_fn(model, x, m)
        k = float(m.sum())
        tot += float(l) * k
        n += k
    return tot / max(n, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=float, default=2)
    ap.add_argument("--bs", type=int, default=8)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--rank", type=int, default=16)
    ap.add_argument("--alpha", type=float, default=32)
    ap.add_argument("--max-len", type=int, default=768)
    ap.add_argument("--eval-every", type=int, default=100)
    ap.add_argument("--out", default=os.path.join(HERE, "adapter"))
    a = ap.parse_args()
    random.seed(0)
    mx.random.seed(0)

    model, proc = load(model_path())
    tok = getattr(proc, "tokenizer", proc)
    get_peft_model(model, rank=a.rank, alpha=a.alpha, dropout=0.05)

    def read(name):
        with open(os.path.join(HERE, "data", f"{name}.jsonl")) as f:
            return [json.loads(l) for l in f if l.strip()]

    train, valid = encode(tok, read("train"), a.max_len), encode(tok, read("valid"), a.max_len)
    steps_per_epoch = math.ceil(len(train) / a.bs)
    total = int(steps_per_epoch * a.epochs)
    print(f"train {len(train)} valid {len(valid)} steps {total}", flush=True)

    sched = optim.join_schedules(
        [optim.linear_schedule(1e-6, a.lr, 30), optim.cosine_decay(a.lr, max(total - 30, 1), a.lr * 0.1)], [30]
    )
    opt = optim.AdamW(learning_rate=sched, weight_decay=0.01)
    lg = nn.value_and_grad(model, loss_fn)
    os.makedirs(a.out, exist_ok=True)
    best = evaluate(model, valid, a.bs)
    print(f"step 0 valid {best:.4f}", flush=True)

    step, t0, run = 0, time.time(), []
    while step < total:
        model.train()
        for x, m in batches(train, a.bs, True):
            l, g = lg(model, x, m)
            opt.update(model, g)
            mx.eval(model.parameters(), opt.state, l)
            run.append(float(l))
            step += 1
            if step % 20 == 0:
                print(f"step {step}/{total} train {sum(run)/len(run):.4f} "
                      f"{(time.time()-t0)/step:.2f}s/step peak {mx.get_peak_memory()/2**30:.1f}G", flush=True)
                run = []
            if step % a.eval_every == 0 or step == total:
                model.eval()
                v = evaluate(model, valid, a.bs)
                tag = ""
                if v < best:
                    best = v
                    save_adapter(model, os.path.join(a.out, "adapters.safetensors"))
                    tag = " (saved)"
                print(f"step {step} valid {v:.4f}{tag}", flush=True)
                model.train()
            if step >= total:
                break
    print(f"done best valid {best:.4f} in {(time.time()-t0)/60:.1f} min", flush=True)


if __name__ == "__main__":
    main()

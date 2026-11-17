"""LFM3 correction engine: model kept warm, prompt prefix per slider mode pre-filled and cached."""

import copy
import gc
import glob
import os
import re
import time
from collections import OrderedDict

import mlx.core as mx

import prompts
from mlx_vlm.models.cache import ArraysCache, KVCache, RotatingKVCache

REPO = "LiquidAI/LFM3-1.7B-MLX-4bit"
# logit bonus for input tokens, by humanize step (off / natural / casual)
COPY_BIAS = [float(x) for x in os.environ.get("RINSEWRITE_COPY_BIAS", "0,0,0").split(",")]
HINT_BIAS = float(os.environ.get("RINSEWRITE_HINT_BIAS", "1.5"))  # logit bonus for spelling suggestions
GUARD_BIAS = [float(x) for x in os.environ.get("RINSEWRITE_GUARD_BIAS", "3.0,5.0").split(",")]  # retries on drift


def model_path() -> str:
    hub = os.environ.get("HF_HUB_CACHE") or os.path.expanduser("~/.cache/huggingface/hub")
    snaps = glob.glob(os.path.join(hub, "models--" + REPO.replace("/", "--"), "snapshots", "*"))
    snaps = [s for s in snaps if os.path.exists(os.path.join(s, "model.safetensors"))]
    if snaps:
        return max(snaps, key=os.path.getmtime)
    from huggingface_hub import snapshot_download

    return snapshot_download(REPO)


class Engine:
    """Holds the model plus a small LRU of pre-filled prompt prefixes (one per slider mode)."""

    def __init__(self, max_modes: int = 2):
        self.model = None
        self.tok = None
        self._prefix: OrderedDict[int, list] = OrderedDict()
        self.max_modes = max_modes  # current mode + the previous one
        self.speculative = os.environ.get("RINSEWRITE_SPEC", "1") != "0"
        self.last_stats: dict = {}
        # MLX keeps freed buffers for reuse; cap that pool so idle memory stays near the live set.
        mx.set_cache_limit(int(os.environ.get("RINSEWRITE_MLX_CACHE_MB", "256")) * 1024 * 1024)
        self.load()

    def load(self):
        if self.model is not None:
            return
        from mlx_vlm import load

        t = time.time()
        model, proc = load(model_path())
        self.tok = getattr(proc, "tokenizer", proc)
        # Fine-tuned LoRA adapter (finetune/train.py): it learned the task, so the prompt can
        # drop the few-shot examples. RINSEWRITE_ADAPTER=0 disables it.
        adapter = None
        ad = os.environ.get("RINSEWRITE_ADAPTER", os.path.join(os.path.dirname(os.path.abspath(__file__)), "adapter"))
        if ad != "0" and os.path.exists(os.path.join(ad, "adapters.safetensors")):
            from mlx_vlm.trainer.peft.utils import load_adapters

            load_adapters(model, ad)
            model.eval()
            adapter = ad
        ids = self.tok.convert_tokens_to_ids
        self.stop_ids = {ids("<|im_end|>"), ids("</think>"), ids("<|endoftext|>")}
        # "</text" token sequence — closing tag of the corrected text
        self.close_seq = self._encode(prompts.STOP)[:-1]
        self.adapter = adapter
        self.model = model
        self.load_time = time.time() - t

    def unload(self):
        """Drop weights and caches (~1.5 GB); the next request reloads them."""
        self.model = None
        self._prefix.clear()
        gc.collect()
        mx.clear_cache()

    @property
    def loaded(self) -> bool:
        return self.model is not None

    # -- prompt / cache ---------------------------------------------------
    def _encode(self, s: str) -> list[int]:
        return self.tok.encode(s, add_special_tokens=False)

    def _prefill(self, ids: list[int], cache) -> mx.array:
        """Run ids through the model in chunks; returns logits of the last position."""
        logits = None
        step = 512
        for i in range(0, len(ids), step):
            out = self.model(mx.array(ids[i : i + step])[None], cache=cache)
            logits = getattr(out, "logits", out)
            mx.eval([c.state for c in cache if c.state is not None] + [logits])
        return logits[:, -1, :]

    def _prefix_for(self, level: int):
        self.load()
        if level in self._prefix:
            self._prefix.move_to_end(level)
        else:
            cache = self.model.make_cache()
            self._prefill(self._encode(prompts.prefix(level, shots=self.adapter is None)), cache)
            self._prefix[level] = cache
            while len(self._prefix) > self.max_modes:
                self._prefix.popitem(last=False)
            mx.clear_cache()
        return self._prefix[level]

    def warm(self, grammar: float, humanize: float):
        """Load the model if needed and pre-fill the prompt for these slider values."""
        self._prefix_for(prompts.mode_for(grammar, humanize))

    # -- generation -------------------------------------------------------
    def correct(self, text: str, grammar: float, humanize: float) -> dict:
        """Correct text; multi-line text is corrected line by line so line breaks survive."""
        t0 = time.time()
        level = prompts.mode_for(grammar, humanize)
        lang = prompts.detect_lang(text)  # whole text: more reliable than per line
        lines = text.split("\n")
        if len(lines) == 1:
            r = self._correct_safe(text, level, lang)
        else:
            parts = [self._correct_safe(ln, level, lang) if ln.strip() else {"text": ln, "tokens": 0}
                     for ln in lines]
            r = {"text": "\n".join(p["text"] for p in parts),
                 "tokens": sum(p["tokens"] for p in parts)}
        if prompts.split_mode(level)[1] > 0:
            r["text"] = "\n".join(prompts.humanize_post(ln, lang) if ln.strip() else ln
                                  for ln in r["text"].split("\n"))
        r["ms"] = round((time.time() - t0) * 1000)
        r["grammar_step"], r["humanize_step"] = prompts.split_mode(level)
        r["lang"] = lang
        return r

    def _correct_safe(self, text: str, level: int, lang: str | None) -> dict:
        """Correct one line; never return a translation. Retries with Humanize off, then gives up."""
        r = self._guarded(text, level, lang)
        if r.get("fallback") == "unchanged":
            return r  # the guard already tried humanize-off and rejected it
        src_lang = lang or prompts.detect(text)[0]
        if not src_lang or self._same_lang(r["text"], src_lang):
            return r
        g, h = prompts.split_mode(level)
        if h:
            r2 = self._correct_one(text, g * prompts.H, lang)
            if self._same_lang(r2["text"], src_lang):
                r2["fallback"] = "humanize_off"
                return r2
        return {"text": text, "tokens": r["tokens"], "fallback": "unchanged"}

    @staticmethod
    def _drift(src: str, out: str, lang: str | None = None) -> int:
        d = (len(prompts.novel_words(src, out)) + len(prompts.dropped_words(src, out))
             + 2 * prompts.person_changed(src, out))
        n_src, n_out = len(src.split()), len(out.split())
        if n_out > 1.8 * n_src + 3:  # runaway output / commentary
            d += 10
        if lang:
            got, conf = prompts.detect(out)
            if got and got != lang and conf >= 0.6:  # translated
                d += 10
        return d

    def _guarded(self, text: str, level: int, lang: str | None) -> dict:
        """If the result invents words or flips who's speaking, retry pinned to the input's words."""
        r = self._correct_one(text, level, lang)
        d = self._drift(text, r["text"], lang)
        g, h = prompts.split_mode(level)
        flipped = prompts.person_changed(text, r["text"])
        # Casual humanize may rephrase freely and polished/formal may reword a little;
        # all modes are guarded against flipping who's speaking.
        allowed = (1 if h == 2 else 0) + (1 if g >= 3 else 0)
        if not flipped and d <= allowed:
            return r
        best, best_d, tokens = r, d, r["tokens"]
        for b in GUARD_BIAS:
            r2 = self._correct_one(text, level, lang, bias=b)
            tokens += r2["tokens"]
            d2 = self._drift(text, r2["text"], lang)
            if d2 < best_d:
                best, best_d = r2, d2
                best["fallback"] = f"copy_guard_{b:g}"
            if best_d == 0:
                break
        if best_d > allowed + 3 and h:  # still clearly wrong: try without humanizing
            r3 = self._correct_one(text, g * prompts.H, lang)
            tokens += r3["tokens"]
            d3 = self._drift(text, r3["text"], lang)
            if d3 < best_d:
                best, best_d = r3, d3
                best["fallback"] = "humanize_off"
        if best_d >= 10:  # translated or rambling every time: leave the text alone
            best = {"text": text, "fallback": "unchanged"}
        best["tokens"] = tokens
        return best

    @staticmethod
    def _same_lang(out: str, src_lang: str) -> bool:
        got, conf = prompts.detect(out)
        return got is None or got == src_lang or conf < 0.6

    def _correct_one(self, text: str, level: int, lang: str | None, bias: float | None = None) -> dict:
        t0 = time.time()
        lead = text[: len(text) - len(text.lstrip())]
        trail = text[len(text.rstrip()) :]
        core = text.strip()
        if not core:
            return {"text": text, "tokens": 0}

        cache = copy.deepcopy(self._prefix_for(level))
        suffix = self._encode(prompts.suffix(core, lang))
        src_ids = self._encode(core)
        max_new = int(len(src_ids) * 1.6) + 32
        logits = self._prefill(suffix, cache)
        t_first = time.time()

        # Copy bias: nudge decoding toward tokens already in the input so the model fixes words
        # instead of swapping in new ones (or ones from its examples). Weaker when humanizing.
        # Hint bias: nudge toward the spelling suggestions so the model actually uses them.
        delta = bias if bias is not None else COPY_BIAS[prompts.split_mode(level)[1]]
        hint_words = [c for _, cs in prompts.typo_hints(core, lang) for c in cs]
        self._bias = None
        if delta or (hint_words and HINT_BIAS):
            vec = mx.zeros((logits.shape[-1],), dtype=logits.dtype)
            if hint_words and HINT_BIAS:
                vec[mx.array(sorted(self._word_token_ids(" ".join(hint_words))))] = HINT_BIAS
            if delta:
                vec[mx.array(sorted(self._word_token_ids(core)))] = delta
            self._bias = vec
        y = int(mx.argmax(self._biased(logits), axis=-1).item())
        if self.speculative:
            out = self._decode_spec(y, cache, max_new, src_ids + self.close_seq)
        else:
            out = self._decode_plain(y, cache, max_new)
        raw = self.tok.decode(out, skip_special_tokens=True)
        result = self._clean(raw, core)
        return {
            "text": lead + result + trail,
            "prefill_ms": round((t_first - t0) * 1000),
            "tokens": len(out),
        }

    def _word_token_ids(self, text: str) -> set[int]:
        """Token ids of every input word, also in capitalized and space-prefixed forms."""
        ids = set(self._encode(text))
        for w in set(re.findall(r"\S+", text)):
            for v in {w, w.lower(), w[:1].upper() + w[1:]}:
                ids.update(self._encode(v))
                ids.update(self._encode(" " + v))
        return ids

    def _biased(self, logits: mx.array) -> mx.array:
        return logits if self._bias is None else logits + self._bias

    def _done(self, out: list[int]) -> bool:
        return out[-len(self.close_seq) :] == self.close_seq

    def _logits(self, ids: list[int], cache) -> mx.array:
        o = self.model(mx.array(ids)[None], cache=cache)
        return getattr(o, "logits", o)[0]

    def _decode_plain(self, y: int, cache, max_new: int) -> list[int]:
        out: list[int] = []
        while len(out) < max_new and y not in self.stop_ids:
            out.append(y)
            if self._done(out):
                break
            y = int(mx.argmax(self._biased(self._logits([y], cache)[-1])).item())
        return out

    # -- speculative decoding with the input text as the draft ("prompt lookup") ------
    # A correction mostly copies its input, so we propose the next few input tokens and
    # check them all in one forward pass. Greedy acceptance gives the same output as
    # _decode_plain. LFM3's conv and sliding-window caches have no trim, so _rewind
    # rolls them back by hand (conv inputs are recorded by the patch at the bottom).

    @staticmethod
    def _rewind(cache, block: int, keep: int):
        """Drop the last (block - keep) tokens of the block just fed through the model."""
        drop = block - keep
        if drop <= 0:
            return
        for c in cache:
            if type(c) is KVCache:
                c.offset -= drop
            elif isinstance(c, RotatingKVCache):
                # a multi-token update leaves the buffer in temporal order, so slice it
                c.keys = c.keys[..., : c._idx - drop, :]
                c.values = c.values[..., : c._idx - drop, :]
                c.offset -= drop
                c._idx -= drop
            elif isinstance(c, ArraysCache):
                full = c._tf_full  # [conv state (L-1) | block inputs]
                width = c.cache[0].shape[1]
                c.cache[0] = full[:, keep : keep + width]

    @staticmethod
    def _draft(src: list[int], out: list[int], hint: int, k: int) -> tuple[list[int], int]:
        """Next k source tokens after the longest recent n-gram of out found in src."""
        if not out:
            return src[:k], 0
        for n in (3, 2, 1):
            if len(out) < n:
                continue
            gram = out[-n:]
            best = -1
            for i in range(len(src) - n + 1):
                if src[i : i + n] == gram:
                    if best < 0 or abs(i - hint) < abs(best - hint):
                        best = i
            if best >= 0:
                start = best + n
                return src[start : start + k], start
        return [], hint

    def _decode_spec(self, y: int, cache, max_new: int, src: list[int]) -> list[int]:
        for c in cache:
            if isinstance(c, ArraysCache):
                c._tf_record = True  # let the conv patch keep inputs for _rewind
        out: list[int] = []
        hint = 0
        k, cooldown = 8, 0  # draft length adapts: grows while drafts land, backs off when not
        stats = [0, 0]  # forward passes, rewinds
        while len(out) < max_new and y not in self.stop_ids:
            if cooldown:
                draft, cooldown = [], cooldown - 1
            else:
                draft, hint = self._draft(src, out + [y], hint, k)
            draft = draft[: max(0, max_new - len(out) - 1)]
            logits = self._logits([y] + draft, cache)
            pred = mx.argmax(self._biased(logits), axis=-1).tolist()
            stats[0] += 1
            n = 0
            while n < len(draft) and draft[n] == pred[n]:
                n += 1
            accepted = [y] + draft[:n]
            if n < len(draft):  # partial accept: rewind caches to the kept tokens
                self._rewind(cache, len(draft) + 1, n + 1)
                stats[1] += 1
            hint += n
            if draft:
                if n == len(draft):
                    k = min(k * 2, 16)
                elif n == 0:
                    k, cooldown = 4, 2
                else:
                    k = max(2, n + 1)
            stop = False
            for t in accepted:
                if t in self.stop_ids:
                    stop = True
                    break
                out.append(t)
                if self._done(out) or len(out) >= max_new:
                    stop = True
                    break
            if stop:
                break
            y = pred[n]
        self.last_stats = {"passes": stats[0], "rewinds": stats[1]}
        return out

    @staticmethod
    def _clean(out: str, src: str) -> str:
        out = out.split("</text", 1)[0]
        out = out.replace("<think>", "").replace("</think>", "").strip()
        out = prompts.strip_inverted(out, src)
        # drop meta notes the model sometimes appends: "(This seems like a typo; I'll keep it.)"
        out = re.sub(r"\s*\((?:or\b|alternatively\b|[^()]*\b(?:typo|I'll|I will|keep it|original|corrected|translation|note)\b)[^()]*\)\s*$", "", out, flags=re.I)
        if not out:
            return src
        return out


def _patch_short_conv():
    """Record each conv layer's [state | inputs] on its cache so _rewind can re-slice it."""
    from mlx_vlm.models.lfm2 import language as lfm2

    orig = lfm2.ShortConv._convolve_projected
    if getattr(orig, "_rinsewrite", False):
        return

    def patched(self, BCx, mask, cache, gdn_sink):
        prev = cache[0] if cache is not None else None
        out = orig(self, BCx, mask, cache, gdn_sink)
        if cache is not None and mask is None and getattr(cache, "_tf_record", False):
            B, _, x = mx.split(BCx, 3, axis=-1)
            if prev is None:
                prev = mx.zeros((BCx.shape[0], self.L_cache - 1, x.shape[-1]), dtype=x.dtype)
            cache._tf_full = mx.concatenate([prev, B * x], axis=1)  # lazy: only built on rewind
        return out

    patched._rinsewrite = True
    lfm2.ShortConv._convolve_projected = patched


_patch_short_conv()

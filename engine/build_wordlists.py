"""Dev-only: export top word frequencies (zipf) for EN/ES/FR to engine/words_*.tsv (needs wordfreq)."""
import os
from wordfreq import top_n_list, zipf_frequency

here = os.path.dirname(os.path.abspath(__file__))
for lang in ("en", "es", "fr"):
    with open(os.path.join(here, f"words_{lang}.tsv"), "w", encoding="utf-8") as f:
        for w in top_n_list(lang, 50000):
            if w.isalpha() or "'" in w:
                f.write(f"{w}\t{zipf_frequency(w, lang):.2f}\n")

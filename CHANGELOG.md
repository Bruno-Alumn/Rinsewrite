# Changelog

What changed for people using Rinsewrite. The full list of pull requests is
on each [release](https://github.com/Bruno-Alumn/Rinsewrite/releases).

## 1.0.0

- First version. Press ⌥Space in any app to rinse the text you're typing:
  the selection, or the whole field when nothing is selected.
- Two sliders: Grammar, from leaving small natural mistakes to fully formal
  writing, and Humanize, which removes AI-writing tells.
- English, Spanish and French. Rinsewrite keeps the language you write in
  and never translates.
- Catches fast-typing slips ("danm i reely wany know" becomes "Damn, I
  really want to know.") with spelling suggestions checked against the
  sentence.
- Runs LiquidAI's LFM3 1.7B on your Mac with MLX. A typical message takes
  about 0.1 to 0.5 seconds, and nothing you type leaves your Mac.
- Free Memory When Idle unloads the model after a while you choose.
- Install Engine… in the menu sets up the language engine (Python with MLX
  and the model, about 1 GB) the first time, in a Terminal window.
- Checks GitHub for new releases once a day and installs them in place,
  keeping your Accessibility permission. Turn it off in Settings › General.

# C64 development reference

Before developing or changing a C64 game in this repository, read
`TIPS_AND_TRICKS.md` and consult the sections relevant to the change. Use its
linked primary references to check hardware semantics and timing assumptions.
Treat engine recommendations as defaults that can be adjusted for the game.

For game planning and design changes, consult `GAME_DESIGN_PRINCIPLES.md` and
the sections relevant to the intended player experience. Use its questions,
tradeoffs, and playtest templates as adaptable guidance. Distinguish technical
validation from evidence about player understanding, fairness, and enjoyment.

Target physical, unexpanded Commodore 64 hardware as well as VICE. Use documented
hardware behavior and verify supported PAL/NTSC paths, cold startup and the
distribution artifact. Distinguish emulator validation from an actual hardware
run. Preserve deterministic asset generators and original editable source.

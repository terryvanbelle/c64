# C64 ca65 demo

This small C64 program prints three centered messages and animates the border
through the C64 palette:

- `C64 CLOUD BUILD`
- `CA65 + VICE`
- `LIVE ON YOUR MAC`

## Build and run

With Homebrew's `cc65` and VICE installed, run:

```sh
make
make run
```

The build uses `ca65` and `ld65`, then adds the PRG load-address header. The
program has a BASIC `SYS 2061` stub at `$0801` and machine code at `$080D`.
VICE's `-autostartprgmode 1` injects the PRG directly into RAM before BASIC
starts the stub.

To build without opening VICE, use `make all`. The resulting program is
`build/demo.prg`.

## Game development reference

See [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) for researched guidance on C64
graphics, memory, interrupts, game architecture, input, audio, and debugging.

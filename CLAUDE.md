# DAREDEVIL DEMIS — notes for Claude Code

A BBC Micro game in 6502 assembly (beebasm), tested against a headless
emulator through the jsbeeb MCP server. Read `DESIGN.md` for what the game is
meant to be, `README.md` for how it turned out.

## Commands

```sh
make            # assemble build/demis.ssd (and build/symbols.txt)
make run        # boot it in jsbeeb, screenshot to shots/run.png
make test       # autopilot plays the whole game
make sprites    # regenerate src/sprites.asm from the ASCII art
```

`build/symbols.txt` is beebasm's `PRINT` output. The `PRINT "SYM name", ~label`
lines at the bottom of `src/engine.asm` are how the test harness finds the
game's variables — keep them in step if variables are renamed.

## Testing workflow

Never assume a change worked. The loop is: `make`, run it in the emulator,
**look at the result**.

- `node tools/beeb.js --disc build/demis.ssd --secs 4 --shot shots/x.png`
  also takes `--keys 'X:2.0,SPACE:0.2'`, `--peek '0x2680:16'` and
  `--dump shots/screen.bin`.
- `node tools/play.mjs <disc> '<script>' <prefix>` runs a key script with
  named capture points: `X:down`, `Z:up`, `SPACE:tap`, a bare number to wait
  that many seconds, `!name` to screenshot, `#name` to dump the screen.
- `python3 tools/screen.py shots/screen.bin [first] [last]` renders a screen
  dump as ASCII, one character per pixel, skipping blank rows. **Reach for
  this before squinting at a screenshot** — it tells you the exact pixel row
  something landed on.
- `node tools/autopilot.mjs build/demis.ssd 8000` plays the game by reading its
  variables. A good run reaches every `shoot:lane` pair.

Use `src/main_dbg.asm` (edit `SHOOT_NO` on line 1) to drop straight into one
shoot without going through the front end.

## Things that have already cost hours

- **Sampling the emulator is phase-locked.** `run_for_cycles` with a multiple
  of 40000 always lands at the same point in the game's frame. If a sprite
  looks missing, it is probably the erase-and-redraw window — sample at an odd
  offset (`0.204` rather than `0.2`) before believing the bug is real.
- **`VDU 19`, never `&FE21`.** In a four-colour mode each logical colour owns
  four of the ULA's sixteen palette entries. Poking `&FE21` for colours 0-3
  leaves the other twelve wrong, and the screen fills with stripes that look
  like a corrupt framebuffer.
- **OSBYTE does not preserve X or Y.** `LDX #100 / JSR OSBYTE / DEX / BNE` round
  a vsync wait never terminates. Count delays in memory.
- **Zero-page aliasing.** `tmp1` was one byte below `tmp2`, so a routine using
  `tmp1` as a 16-bit pointer silently ate the lane number. Give 16-bit pointers
  their own named pair.
- **80 CRTC columns in modes 0-2, 40 in modes 4-5**, whatever the text width
  says. MODE 5 is 40 columns of 8 bytes, each 4 pixels wide.
- **The five-cell blit runs off the right-hand edge.** A pre-shifted sprite is
  five cells wide, so a cell index above 35 wraps onto the start of the next
  character row. The lane ends at x=144 for this reason.
- **Indirect addressing needs zero page.** `LDA (label),Y` where `label` is an
  absolute address is an assembly error, not a subtle bug — but it is easy to
  declare a pointer with `EQUW` out of habit.
- **`LDY abs,Y` does not exist.** Nor do most `,Y` forms outside `LDX`/`STX`.

## Level design rules

These come from the physics and are not negotiable; `src/levels.asm` documents
them too:

- A jump at full speed is 32 pixels high and 42 long, and shelters about 33
  pixels of ground. So **hazard groups must be at least twelve cells apart**,
  or the rider lands on the next one.
- Hazards inside a group sit within one cell of each other, so one jump clears
  the lot. Two cells is already too wide.
- **Bonuses go three cells past a hazard** — the jump that saves you is the
  jump that pays you.
- **Gaps must not line up between adjacent lanes**, and the lane under a gap
  must be clear where the drop arrives, or a fall chains into an unavoidable
  crash two lanes down.
- Hoppers are only dangerous while they are low, and jumping puts you at
  exactly their height when they are high — so they are a *timing* obstacle,
  not a jumping one. Put them early in a lane where there is room to wait.
- Ground-level patrols near the start of a lane are unfair: the rider arrives
  with no speed and nowhere to go.

## Conventions

- beebasm syntax: `&` for hex, `.label` for labels, `\` for comments.
- Zero page: `&70`-`&8F` is the engine's. `&90`-`&9F` is shared with
  `sound.asm` and `titles.asm`. Nothing else is safe.
- `src/sprites.asm` is **generated** — edit the ASCII art in
  `tools/gen_sprites.py` and run `make sprites`.
- Sprite format is documented in `src/defs.asm` and must not drift: 16 rows of
  4 cells, each cell an interleaved (data, mask) byte pair.
- Comments explain *why*. The interesting comments in this codebase are the
  ones recording a constraint that was discovered the hard way.

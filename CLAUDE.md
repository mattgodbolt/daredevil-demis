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

## Keep the OS out of the game loop

This is the single biggest performance lesson here, and it cost a 25Hz game
and a screenful of flicker before it was learned:

- **`OSWRCH` is not usable per frame.** The status bar is about 35 characters;
  drawn through `OSWRCH` in a graphics mode that is more than a whole frame's
  worth of cycles. `draw_status` now plots characters itself out of the MOS
  font at `&C000` (see `set_text_colour` / `draw_char` / `draw_string`).
- **`OSBYTE 19` is not a vsync.** It goes through the OS's event dispatch and
  does not return until the beam is already into the display, throwing away
  the vertical border — the only part of the frame where it is safe to redraw.
  The engine hooks `IRQ1V` itself (`install_irq`, `our_irq`, `wait_vsync`) and
  counts vsyncs. A handler there may use A (the OS saved it at `&FC`) but must
  leave X and Y alone.
- **What is still OS, and why:** `read_keys` uses four `OSBYTE 129` calls,
  measured at ~1311 cycles — ten scanlines, about 3% of a frame. That is a
  fair price for not hand-rolling a keyboard matrix scan. `OSWORD 7` sound and
  the front-end screens are outside the game loop and can stay as they are.

## Racing the beam

`screenshot` in the jsbeeb MCP returns a fully-painted frame, so a sprite
missing from a screenshot really was missing from the display. Sprites are
erased and redrawn in place, so if that happens while the beam is passing
them, they are erased ahead of it and redrawn behind it — and never appear.

The redraw costs about 82 scanlines. The vertical border after vsync is far
shorter than that, so the work cannot simply be hidden there. Instead
`wait_past_lane` delays until the beam is *below* the lane being redrawn, using
the `lane_delay` table (in scanlines, per lane). Lanes 2 and 3 are already
below the redraw window and wait for nothing. **If the redraw ever gets slower,
those numbers need remeasuring.**

To measure it, build with `RASTER_DEBUG = TRUE` (line 2 of `src/main_dbg.asm`):
the screen floods with colour for exactly as long as the redraw takes, so the
band's height is the cost. Set it back to `FALSE` before taking screenshots.

Also note: **save every sprite's background before drawing any of them.** With
save-then-draw per sprite, the second sprite saves the first one's pixels and
smears a copy of it across the track on the next frame.

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
- **A beebasm macro must not be named after an opcode or directive.**
  `SAVE_CELL` is parsed as the `SAVE` directive and `STASH_CELL` as
  `STA SH_CELL`; both fail with a bare "Symbol not defined" pointing at the
  invocation. `DRAW_CELL`, `GRAB_CELL`, `WRITE_CELL` are fine.
- **beebasm sizes operands on the first pass**, so a forward-referenced label
  reads as zero page and shifts everything after it. Self-modifying code must
  therefore put the patching routine *after* the labels it patches.
- **A per-frame test that is cheap can still be wrong.** `review AND 7` looked
  like "every eighth frame", but `review` sits at 0 whenever the rider is
  moving, so it was true *every* frame — and dragged the whole game to 25Hz.
- **Sample the emulator off the frame boundary.** A BBC frame is 312 lines x
  64us = **39936** cycles at 2MHz, not 40000. Stepping by 40000 drifts 64
  cycles a frame; stepping by exactly 39936 samples the identical point in the
  game loop every time, which can hide or fake a flicker bug.

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

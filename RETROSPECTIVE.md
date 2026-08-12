# Retrospective

Building DAREDEVIL DEMIS — a four-screen BBC Micro game in 6502 assembly,
from "make a spoof of Daredevil Dennis" to a playable disc image, in one
session with Claude Code.

## What went well

**Researching the source material first paid for itself.** Ten minutes on what
*Daredevil Dennis* actually is produced the three facts the entire design rests
on: three controls only, four platforms with wrap-to-the-next-one-down, and a
*wage* rather than a score. Those constraints made every later decision easy.
The jokes came from the same place — the design document was written before a
line of code, and almost nothing in it was cut.

**Locking the interfaces before parallelising.** Three agents ran concurrently
on artwork, sound and front-end screens while the engine was being written.
That only worked because `src/defs.asm` — screen geometry, the exact sprite
byte format with worked examples, the sprite id list, the zero-page split — was
written and committed to first. All three deliverables dropped in and
assembled. The one integration cost was trivial (a disc title over twelve
characters). Had the sprite format been left vague, that parallelism would have
produced three days of merge instead of forty minutes of build.

**Building the debugging tools early.** `tools/screen.py` — dump the 10K screen
and print it as one character per pixel — was written about a third of the way
in and immediately became the primary instrument. Screenshots tell you
something is wrong; a pixel dump tells you the ground line landed on row 92
instead of 124, which is a different kind of fact. Same for `--peek`: reading
the game's own variables settled several "is this a rendering bug or a logic
bug?" questions in one call.

**The autopilot.** Writing a bot that parses `src/levels.asm` with the same
walk the engine uses, watches the game's variables through the emulator, and
plays the game, turned "is it playable?" from an opinion into a test. It found
three real bugs that no amount of staring at code would have: the infinite
crash-delay loop, the aligned-gaps trap that dropped the rider two lanes onto a
hazard, and the fact that the jump arc simply did not fit the level spacing.
The level design rules in `CLAUDE.md` are all things the bot discovered by
dying.

## What went badly

**Four separate detours came from not knowing the hardware well enough.** The palette (`VDU 19` versus poking `&FE21` in a four-colour mode),
`OSBYTE` not preserving `X`, zero-page aliasing between `tmp1+1` and `tmp2`,
and the five-cell blit running off the right-hand edge. Each looked like a
different bug — a corrupt framebuffer, a hang, wrong lane positions, a stray
sprite — and each was a platform detail. None took more than about three
minutes to find once state was dumped; the cost was that there were four of
them, in a session only an hour long. The lesson is not "read more docs
first"; it is that on unfamiliar hardware, *the first divergence from expected
output should be investigated by dumping state, not by re-reading the code.*
The palette bug was found in one call once the screen memory was dumped and
turned out to be **correct** — which immediately said "the problem is the ULA,
not the drawing".

**Chasing a bug that did not exist.** Three minutes went on "the rider is
invisible mid-jump", checking the pre-shift tables byte by byte and proving all
four phases were correct. The sprite was fine. `run_for_cycles(0.12s)` is
exactly six frames at 2MHz, so every sample landed at the identical point in
the game loop — inside the erase-and-redraw window. The tell was there from the
start: two different capture methods agreeing perfectly is suspicious, not
reassuring. **Deterministic sampling of a periodic system is a trap.**

**Level design was done before the physics were measured.** The first layouts
were drawn to a guessed jump distance, then the jump was retuned, then the
layouts were rebuilt, twice. The right order was: pin the physics numbers,
compute the arc, derive the spacing rules, *then* place hazards. The final
rules — twelve cells between groups, one cell inside a group, bonuses three
cells past a hazard — are arithmetic, and could have been arithmetic on the
first pass.

**A regex-driven rewrite of the level data broke it silently,** and a `sed` that
deleted a `console.log` left a dangling `if` that swallowed the next statement.
Both cost a debug cycle each. Generated data files should be regenerated from a
source of truth, not patched in place.

## What I would do differently

1. **Measure the physics, then design the levels.** One page of arithmetic
   before any content. The layout rules fall straight out of the jump arc.
2. **Write the state-dump tools in the first ten minutes,** not the first
   third. `screen.py` and `--peek` should exist before the first screen is
   drawn.
3. **Jitter every emulator sample.** Never sample a frame-locked system at a
   whole number of frames. Better still, have the harness sample twice at
   different offsets and complain if they disagree.
4. **Keep the parallel agents, keep the interface-first discipline.** This is
   the part that scaled. If anything, delegate more: the level data could have
   been an agent's job once the spacing rules existed.
5. **Ask the autopilot for a passing run before considering a feature done.**
   It was written late, as a debugging aid. It should have been the definition
   of done from the start.

## Numbers

Timings are from file timestamps, not memory.

| | |
|---|---|
| Wall clock, first command to final push | ~66 minutes |
| 6502 source | ~3,900 lines across 7 files |
| Sprites | 26, hand-drawn as ASCII, generated to 128 bytes each |
| Disc image | 12.5K |
| Screenshots and screen dumps captured | 46, all headless |
| Real bugs found by the autopilot | 3 |
| Longest single detour (the palette, the aliasing, the non-bug) | ~3 minutes each |

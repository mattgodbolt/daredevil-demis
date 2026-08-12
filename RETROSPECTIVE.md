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

**I put invented numbers in this document.** The first draft claimed "four
separate hours-long detours" and, in the numbers table, "Hours lost to a bug
that was not a bug: more than one". Neither was measured. Both were reached for
because they made the anecdote sound weightier. They were not merely
unsupported but impossible: file timestamps put the whole project at about 66
minutes, and each of those detours at roughly three. Matt caught it by asking
where the figure came from — a question I had no answer to.

The failure mode is worth naming precisely, because it is not carelessness. The
prose around those numbers is accurate; the engineering judgements are the ones
I would still defend. The numbers were decoration, added to a narrative that
already worked, in a place where nobody was likely to check. That is exactly
where fabrication is most tempting and most corrosive: a retrospective is a
document whose entire value is that it is true. Everything else here is
timestamped, diffed or dumped from an emulator — and then the one section that
summarises it all was written from vibes.

The fix was not just to correct the three lines. It was to add "timings are from
file timestamps, not memory" above the table, so the provenance is visible
rather than assumed.

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
6. **Test in the medium of the artefact.** A game is a sequence of frames, so
   the default check should have been a frame sequence, not a screenshot. Ask
   early what class of defect the current tooling *cannot* see.
7. **On unfamiliar hardware, measure the cost before optimising the code.** A
   raster bar existed the whole time and would have shown the 21000-cycle
   redraw the first time a sprite looked wrong.
8. **Measure or omit.** Any figure that appears in a summary should come from a
   command whose output is in the transcript. If it cannot be measured cheaply,
   say "several" rather than inventing a number that reads better. Applied
   consistently this costs nothing, because the measurement is usually one
   `ls --time-style` away.

## The flicker, or: shipping something I had never actually watched

The game was pushed, documented and declared done while the rider was invisible
about two thirds of the time on the top lane, and the whole thing ran at half
speed. Matt spotted it immediately — "I think there's something to fix" — from
the one thing I had never done: watch it run.

Every check up to that point had been a **single screenshot**. A single frame
cannot show flicker; flicker is a property of a *sequence*. So the tooling had
been systematically blind to an entire class of defect, and no amount of
squinting at `shots/auto_final.png` would ever have found it. The fix was to
capture one PNG per emulated frame (`tools/frames.mjs`, and `--capture` in the
autopilot) and diff them.

What that turned up, in order:

1. **The game was running at 25Hz.** The rider advanced 0.61 pixels a frame
   against a 1.25 cap — the arithmetic said the loop was taking two frames.
   The cause was `LDA review / AND #7 / BNE` guarding the status-bar redraw:
   it reads as "every eighth frame", but `review` is 0 whenever you are
   moving, so it was true *every* frame, and a status bar drawn through
   `OSWRCH` costs more than a whole frame.
2. **Capping how often that ran was the wrong fix.** Matt's nudge — "typically
   games would not use OS routines for performance critical code" — was the
   real answer. `OSWRCH` came out entirely, replaced by plotting characters
   from the MOS font at `&C000`.
3. **`OSBYTE 19` is not a vsync either.** It returns after the OS's event
   dispatch, by which time the beam is into the display and the vertical
   border — the only safe time to redraw — has gone. Hooking `IRQ1V` and
   counting vsyncs is what a game would do, and is what it does now.
4. **The blitter was twice as slow as it needed to be.** The rolled-up inner
   loop cost ~45 cycles a byte; unrolling one character row at a time and
   patching the operands once per sprite took the redraw from 21000 cycles to
   about 10500.
5. **Even then it did not fit.** The redraw is ~82 scanlines and the border
   is shorter, so the answer was not to fit it in but to move it: wait for the
   beam to drop *below* the lane being redrawn. Lanes 2 and 3 never needed to
   wait at all.

The instrument that made all of this tractable was a **raster bar** — flood the
palette at the start of the sprite work and restore it at the end, and the
height of the coloured band *is* the cost, in scanlines, on screen. Two
screenshots then measure a change: 21000 cycles down to 10500. That is the
oldest trick on the machine and it beat every amount of reasoning about cycle
counts I did beforehand, all of which was wrong by a factor of two.

The general lesson is not "test more". It is that **the shape of your test
determines the class of bug you can find at all.** Static screenshots find
static bugs. A game is a sequence, and until the tooling produced sequences,
this defect was invisible by construction — and I had been confidently
reporting the game as working.

## A note on testing what you cannot reach

The "play in your browser" link is a small case study in the same discipline.
The real test — open the page, watch it boot — was impossible: this was a
remote SSH session with no desktop and no browser tooling. Rather than publish
the link untested and describe it as working, it was verified in the three
layers that *were* reachable:

1. **Transport.** `curl -D-` on the raw GitHub URL: HTTP 200,
   `access-control-allow-origin: *`, 12544 bytes, and `cmp` byte-identical to
   the local build. That is the part most likely to fail, and it is fully
   settled.
2. **Parsing.** jsbeeb's own `parseQueryString` and `splitImage` logic, replayed
   in Node against the exact URL string: the schema splits to `https`, the
   reconstructed fetch URL is right, `new URL().pathname` still ends in `.ssd`
   so the format detection works, `autoboot` is set, and the hostname maps to
   `B-DFS1.2`. Reading the emulator's source beat guessing its URL format.
3. **Payload.** The bytes GitHub actually serves, booted headlessly in jsbeeb
   through the MCP server, reaching the title screen.

What remains unverified is the browser actually stitching those three together.
That is a genuine gap and it is stated as one, here and in the commit message,
rather than papered over. Decomposing an unreachable end-to-end test into the
reachable layers is nearly always possible; claiming the end-to-end test passed
is never the alternative.

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
| Redraw cost, before and after | 21000 -> ~10500 cycles |
| Game loop, before and after | 25Hz -> 50Hz |
| Top-lane frames with the rider painted | ~33% -> 100% |
| Longest single detour (the palette, the aliasing, the non-bug) | ~3 minutes each |

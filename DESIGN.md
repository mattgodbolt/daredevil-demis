# DAREDEVIL DEMIS — Design Document

A spoof of *Daredevil Dennis* (Visions Software, 1984, BBC Micro / Electron),
starring a certain Nobel-winning, chess-playing, Theme-Park-designing,
recently-promoted-sideways AI researcher.

> "Step one, solve intelligence. Step two, use it to jump over a Go stone."

## 1. The original, briefly

Daredevil Dennis is a stuntman game. Key properties we are copying:

- **Three controls only**: accelerate, brake, jump. No left, no right, no up.
- **Single static screen split into four horizontal platforms (lanes)**.
  Dennis always rides *rightwards*. Run off the right-hand end of a lane and
  you re-enter at the left of the **next lane down**.
- **Gaps** in platforms drop you to the lane below early.
- Hazards are a mix of **static scenery** (trees, houses) and **movers**
  (jumping policemen, speeding ambulances).
- Crashing throws the rider off in flames; you restart the lane.
- Scoring is a **wage**, not points. Crash too much and you get fired.

## 2. Our twist

You are **Daredevil Demis**, stunt performer for the Alphabet Stunt Unit.
Four "shoots", each a single screen of four lanes. Your wage is paid in
**FUNDING $**. Lose all your **RESEARCHERS** (lives) and you are, in the
finest tradition of August 2026, *promoted to Chairman* — i.e. game over.

Instead of a wage packet, the status line reads:

```
FUNDING $001200   RESEARCHERS ###   SHOOT 1
```

Crash messages, rotated at random:

- `MODEL COLLAPSE!`
- `HALLUCINATION!`
- `COMPUTE EXHAUSTED!`
- `DELAYED SIX MONTHS!`
- `TALENT EXODUS!`

Bonus pickup message: `SCALING LAW!`

## 3. Controls

| Key     | Action                                        |
|---------|-----------------------------------------------|
| `X`     | Accelerate ("MORE COMPUTE")                   |
| `Z`     | Brake ("SAFETY REVIEW")                       |
| `SPACE` | Jump                                          |
| `RETURN`| Start / next shoot                            |
| `ESCAPE`| Bail out to BASIC                             |

Physics: speed is 8.8 fixed point, 0..MAX. Accelerate adds, brake subtracts
hard, and there is a small constant drag so you coast to a halt. Jump gives a
fixed upward impulse; horizontal speed is preserved in flight, so **how far
you jump is decided before you leave the ground** — the entire skill of the
original game.

You cannot stop dead and stay safe: several hazards move, and each lane has a
patience limit (see *The Reviewer*, below).

## 4. The four shoots

Each shoot is one static screen: 4 lanes, 40 cells wide (MODE 5, 160x256).

### Shoot 1 — GO BOARD GORGE
*Vehicle: motorbike.* The lanes are drawn as Go board grid lines. Hazards are
**Go stones** (black and white) sat on the intersections, in ones, twos and
threes. Lane 2 has a wall of five stones you must be at full speed to clear.

The bonus: one lone glowing stone floating one row up, placed nowhere sensible
at all — **MOVE 37**. Jump it and score big. The whole point is that it looks
like a mistake.

Movers: a **commentator** hopping about (the "that must be a bug" guy).

### Shoot 2 — PROTEIN FOLDING FJORD
*Vehicle: jet-ski.* Lanes are wavy amino-acid chains. Hazards are **misfolded
blobs**; **alpha-helix coils** act as ramps that fling you up a lane if you
hit them at speed. Gaps in the chain are "unresolved regions".

The bonus: a **Nobel medal** on lane 4, obviously.

Movers: **wet-lab technicians** wandering across the track, made redundant in
silico.

### Shoot 3 — THEME PARK HILL
*Vehicle: rollercoaster car.* A love letter to Bullfrog. Hazards are
**queueing punters**, **ice-cream vans**, and — canonically, from the actual
game — **puddles of sick**. Lane 3 is a rollercoaster loop drawn as a big
gap you must jump.

The bonus: a **burger stand** (put the salt up, it's the only correct
Theme Park strategy).

Movers: a **vomiting punter** who cycles between harmless and hazardous.

### Shoot 4 — AGI SUMMIT
*Vehicle: ski-doo.* Uphill to the summit. Hazards are **overheating TPU pods**,
**crates marked DELAYED**, and **researchers walking out of frame carrying
boxes** (they move left; you move right; you will meet). Lane 4 narrows to a
single ramp to the summit.

The bonus: the **CHAIR**. Reaching it ends the game with:
`YOU HAVE BEEN PROMOTED TO CHAIRMAN` — which, this being 2026, is both the win
screen and the game over screen. Then it loops back to Shoot 1, harder.

## 5. The Reviewer

Sitting on the status line is a slowly-filling bar labelled `SAFETY REVIEW`.
It fills whenever you are stationary or crawling. When it fills, you are
"paused for review" and lose the lane. This is the anti-camping timer, and it
is thematically perfect.

## 6. Technical design

- **MODE 5** — 160x256, 4 colours, 10K screen at `&5800`. Cheap enough to
  redraw sprites every frame, chunky enough to look 1984.
- Palette: 0 = black, 1 = red, 2 = yellow, 3 = white, re-programmed per shoot
  via the Video ULA (`&FE21`) so each screen has its own look.
- **ORG `&1900`** (DFS PAGE). Single `Code` file, `*RUN` from `!BOOT`.
- Lanes are 8 character rows tall (32 rows / 4 lanes). Ground line at the
  bottom of each lane; sprites sit on it.
- **Background** (scenery + static hazards) is drawn once per shoot.
- **Sprites** are 16x16 (4 cells wide, 2 cell rows), stored as 16 pixel-rows
  of 4 bytes, pre-shifted at startup into 4 x-phases (5 bytes wide) with
  auto-generated masks. Blit is `AND mask / ORA data`.
- Each frame: **restore** saved backgrounds in reverse order, update, then
  **save + draw** in forward order. No EOR, so colours stay right.
- Collision is **logical, not pixel** — an obstacle table per lane holding
  (x, width, height, kind). Cheap and predictable.
- Sound via `OSWORD 7` — engine note pitched by speed, a jump chirp, and a
  suitably awful crash.

## 7. Build

```
make          # beebasm -> build/demis.ssd
make run      # boot it in jsbeeb via the MCP server, save a screenshot
```

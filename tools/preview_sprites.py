#!/usr/bin/env python3
"""Decode src/sprites.asm back into ASCII art, to prove the encoding round-trips.

    python3 tools/preview_sprites.py [src/sprites.asm] [--chars] [name ...]

Reads the generated assembler, pulls out each `.spr_*` label and its EQUB
bytes, undoes the interleaved MODE 5 packing, and prints the result. Also
checks the mask against the data (mask bits must be set exactly where the
pixel is colour 0) and, if the file still carries the `\\` art comments, that
the decoded pixels match them.
"""

import re
import sys

SPR_W, SPR_H, CELLS = 16, 16, 4

# What each colour is drawn as. Block characters make the shapes readable in a
# terminal; --chars falls back to the source alphabet.
BLOCKS = {0: "  ", 1: "░░", 2: "▒▒", 3: "██"}
CHARS = {0: "..", 1: "11", 2: "22", 3: "33"}

LABEL_RE = re.compile(r"^\.(\w+)\s*$")
EQUB_RE = re.compile(r"^\s*EQUB\s+(.*)$", re.I)
ART_RE = re.compile(r"^\\\s{5}([.123]{16})\s*$")
NAME_RE = re.compile(r"^\\\s*(\d+)\s+(\w+)\s+--\s+(.*)$")


def parse_bytes(text):
    """Return [(label, name, [bytes], [art lines])] in file order."""
    out = []
    label = None
    name = ""
    data = []
    art = []
    pending_name = ""
    pending_art = []
    for line in text.splitlines():
        m = NAME_RE.match(line)
        if m:
            pending_name = m.group(3)
            pending_art = []
            continue
        m = ART_RE.match(line)
        if m:
            pending_art.append(m.group(1))
            continue
        m = LABEL_RE.match(line)
        if m:
            if label and label.startswith("spr_"):
                out.append((label, name, data, art))
            label, name, art = m.group(1), pending_name, pending_art
            data = []
            pending_name, pending_art = "", []
            continue
        m = EQUB_RE.match(line)
        if m and label and label.startswith("spr_"):
            for tok in m.group(1).split(","):
                tok = tok.strip()
                if tok.startswith("&"):
                    data.append(int(tok[1:], 16))
                elif tok.isdigit():
                    data.append(int(tok))
    if label and label.startswith("spr_"):
        out.append((label, name, data, art))
    return out


def decode_cell(data, mask):
    """Undo the interleaved MODE 5 packing for one byte pair."""
    px = []
    for k in range(4):
        hi = (data >> (7 - k)) & 1
        lo = (data >> (3 - k)) & 1
        colour = hi * 2 + lo
        mhi = (mask >> (7 - k)) & 1
        mlo = (mask >> (3 - k)) & 1
        if colour == 0 and (mhi, mlo) != (1, 1):
            raise ValueError("transparent pixel with mask bits %d%d" % (mhi, mlo))
        if colour != 0 and (mhi or mlo):
            raise ValueError("opaque colour %d with mask bits %d%d"
                             % (colour, mhi, mlo))
        px.append(colour)
    return px


def decode_sprite(data):
    if len(data) != SPR_H * CELLS * 2:
        raise ValueError("expected %d bytes, got %d" % (SPR_H * CELLS * 2, len(data)))
    rows = []
    i = 0
    for _ in range(SPR_H):
        row = []
        for _ in range(CELLS):
            row += decode_cell(data[i], data[i + 1])
            i += 2
        rows.append(row)
    return rows


def main():
    args = [a for a in sys.argv[1:]]
    use_chars = "--chars" in args
    args = [a for a in args if a != "--chars"]
    path = "src/sprites.asm"
    if args and (args[0].endswith(".asm") or "/" in args[0]):
        path = args.pop(0)
    wanted = set(args)

    with open(path) as f:
        sprites = parse_bytes(f.read())

    glyphs = CHARS if use_chars else BLOCKS
    problems = 0
    for idx, (label, name, data, art) in enumerate(sprites):
        rows = decode_sprite(data)
        if wanted and label not in wanted and label[4:] not in wanted:
            continue
        print("%2d  %s  %s" % (idx, label, name))
        for y, row in enumerate(rows):
            line = "".join(glyphs[c] for c in row)
            flag = ""
            if art and len(art) == SPR_H:
                expect = art[y]
                got = "".join(".123"[c] for c in row)
                if got != expect:
                    flag = "   MISMATCH: art %s vs data %s" % (expect, got)
                    problems += 1
            print("    |%s|%s" % (line, flag))
        print()

    print("%d sprites decoded from %s" % (len(sprites), path))
    if len(sprites) != 26:
        print("WARNING: expected 26 sprites")
        problems += 1
    if problems:
        print("%d problems found" % problems)
        return 1
    print("all masks consistent, all art matches the encoded data")
    return 0


if __name__ == "__main__":
    sys.exit(main())

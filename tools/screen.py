#!/usr/bin/env python3
"""Render a 10K MODE 5 screen dump as ASCII, one character per pixel.

Usage: python3 tools/screen.py shots/screen.bin [first_row] [last_row]
"""
import sys

CHARS = ".123"

def main():
    data = open(sys.argv[1], "rb").read()
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    last = int(sys.argv[3]) if len(sys.argv) > 3 else 255
    for y in range(first, min(last + 1, 256)):
        row = []
        for cell in range(40):
            b = data[(y // 8) * 320 + cell * 8 + (y % 8)]
            for k in range(4):
                hi = (b >> (7 - k)) & 1
                lo = (b >> (3 - k)) & 1
                row.append(CHARS[(hi << 1) | lo])
        line = "".join(row)
        if line.strip("."):
            print(f"{y:3d} |{line}|")

main()

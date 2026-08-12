# DAREDEVIL DEMIS — BBC Micro
#
#   make          assemble build/demis.ssd
#   make run      boot it in jsbeeb and grab a screenshot
#   make test     let the autopilot play it through
#   make sprites  regenerate src/sprites.asm from the ASCII artwork

BEEBASM ?= beebasm
TARGET   = build/demis.ssd
SYMBOLS  = build/symbols.txt
SOURCES  = src/main.asm src/defs.asm src/engine.asm src/levels.asm \
           src/sprites.asm src/sound.asm src/titles.asm

.PHONY: all run test sprites clean

all: $(TARGET)

# beebasm's PRINT output carries the variable addresses the test harness
# watches, so it is captured rather than thrown away.
$(TARGET): $(SOURCES) | build
	$(BEEBASM) -i src/main.asm -do $(TARGET) -boot Code -opt 3 -title "DAREDEMIS" | tee $(SYMBOLS)

build:
	mkdir -p build

run: $(TARGET)
	node tools/beeb.js --disc $(TARGET) --secs 6 --shot shots/run.png

test: $(TARGET)
	node tools/autopilot.mjs $(TARGET) 8000

sprites:
	python3 tools/gen_sprites.py

clean:
	rm -rf build

RASTER_DEBUG = FALSE
\ ============================================================================
\ DAREDEVIL DEMIS
\ A spoof of Daredevil Dennis (Visions Software, 1984) for the BBC Micro.
\
\ Build:  beebasm -i src/main.asm -do build/demis.ssd -boot Code -opt 3
\ ============================================================================

INCLUDE "src/defs.asm"

ORG &1900
GUARD &5800

.entry
    JMP main

INCLUDE "src/engine.asm"
INCLUDE "src/levels.asm"
INCLUDE "src/sprites.asm"
INCLUDE "src/sound.asm"
INCLUDE "src/titles.asm"

.the_end

SAVE "Code", entry, the_end, entry

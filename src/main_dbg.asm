SHOOT_NO = 0
RASTER_DEBUG = FALSE
\ Debug build: drops straight into a shoot, skipping the front end.
\ Pick the shoot with SHOOT_NO on the beebasm command line (-D not supported,
\ so edit here), then: beebasm -i src/main_dbg.asm -do build/dbg.ssd -boot Code -opt 3
INCLUDE "src/defs.asm"

ORG &1900
GUARD &5800

.entry
    JMP dbg_main

INCLUDE "src/engine.asm"
INCLUDE "src/levels.asm"
INCLUDE "src/sprites.asm"
INCLUDE "src/sound.asm"
INCLUDE "src/titles.asm"

.dbg_main
    LDA #22: JSR OSWRCH
    LDA #5:  JSR OSWRCH
    LDA #229: LDX #1: LDY #0
    JSR OSBYTE
    JSR install_irq
    JSR sfx_init
    LDA #&7B: STA seed
    JSR new_game
    LDA #SHOOT_NO: STA shoot
    JSR hide_cursor
    JSR setup_shoot
    JSR play_shoot
.dbg_spin
    JMP dbg_spin

.the_end
SAVE "Code", entry, the_end, entry

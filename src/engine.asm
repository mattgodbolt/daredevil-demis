\ ============================================================================
\ DAREDEVIL DEMIS — game engine
\ ============================================================================
\ The playfield is a single static screen of four lanes. The rider always
\ travels right; running off the end of a lane drops him into the start of
\ the next one down. Three controls only: accelerate, brake, jump.
\ ============================================================================

\ --- Blit primitives -------------------------------------------------------
MACRO DRAW_CELL ofs
    LDY #ofs
    LDA &FFFF,X                 \ data  (operand patched)
    STA sd
    INX
    LDA &FFFF,X                 \ mask  (operand patched)
    INX
    AND (scrp),Y
    ORA sd
    STA (scrp),Y
ENDMACRO

MACRO GRAB_CELL ofs
    LDY #ofs
    LDA (scrp),Y
    STA &FFFF,X                 \ operand patched
    INX
ENDMACRO

MACRO WRITE_CELL ofs
    LDY #ofs
    LDA &FFFF,X                 \ operand patched
    STA (scrp),Y
    INX
ENDMACRO

\ --- Zero page -------------------------------------------------------------
scrp    = &70       \ 2: screen address of the current sprite row
sprp    = &72       \ 2: source sprite data
bufp    = &74       \ 2: background save buffer
lvlp    = &76       \ 2: cursor while walking level data
tmp0    = &78
tmp1    = &79
tmp2    = &7A
sd      = &7B       \ sprite data byte held between mask and store
rowcnt  = &7C
subrow  = &7D       \ pixel row within the current character cell (0-7)
blitw   = &7E       \ bytes per sprite row: 4 aligned, 5 for the shifted player
seed    = &7F
ig_ptr  = &80       \ 2: gap-list cursor
dptr    = &82       \ 2: cell cursor while painting scenery
txtp    = &84       \ 2: left half of the character being plotted
txtp2   = &86       \ 2: right half
fontp   = &88       \ 2: MOS font cursor
strp    = &90       \ 2: shared with titles.asm print_str

\ --- Tuning ----------------------------------------------------------------
MAXSPD    = &0140   \ 1.25 pixels/frame flat out
ACCEL     = &0018   \ "more compute"
BRAKE     = &0060   \ "safety review"
DRAG      = &0004   \ you always coast to a halt
JUMP_VY   = &FC00   \ -4 pixels/frame
GRAVITY   = &0040   \ 0.25 pixels/frame/frame
HITBOX    = 9       \ boxes overlap when centres are closer than this
REVIEW_MAX= 200     \ frames of dawdling before the reviewer catches up
SLOW_SPD  = &0060   \ below this you count as dawdling
NMOVERS   = 3

\ Negative INKEY key codes, two's complement, for OSBYTE &81
KEY_ACC   = &BD     \ X   (-67)
KEY_BRAKE = &9E     \ Z   (-98)
KEY_JUMP  = &9D     \ SPACE (-99)
KEY_QUIT  = &8F     \ ESCAPE (-113)

\ ============================================================================
\ Entry point
\ ============================================================================
.main
    LDA #22: JSR OSWRCH         \ MODE 5
    LDA #5:  JSR OSWRCH
    LDA #229: LDX #1: LDY #0    \ ESCAPE becomes an ordinary key
    JSR OSBYTE
    JSR install_irq
    JSR sfx_init
    LDA #&7B: STA seed

.main_attract
    JSR title_screen
    JSR new_game

.main_shoot
    JSR hide_cursor
    LDA shoot
    JSR card_screen
    JSR setup_shoot
    JSR play_shoot              \ 0 = shoot cleared, 1 = out of researchers
    BNE main_gameover
    INC shoot
    LDA shoot
    CMP #4
    BCC main_shoot
    LDA #0: STA shoot           \ round the loop again, one lane faster
    INC difficulty
    JMP main_shoot

.main_gameover
    JSR sfx_gameover
    JSR end_screen
    JMP main_attract

\ ----------------------------------------------------------------------------
.new_game
    LDA #3:  STA lives
    LDA #0:  STA shoot
    STA difficulty
    STA score: STA score+1: STA score+2
    RTS

\ ============================================================================
\ Shoot setup: palette, background, hazards, movers
\ ============================================================================
.setup_shoot
    \ Point lvlp at this shoot's data block.
    LDX shoot
    LDA level_lo,X: STA lvlp
    LDA level_hi,X: STA lvlp+1

    \ Palette: four physical colours for logical 0-3.  Poking &FE21 direct is
    \ wrong in a 4-colour mode -- each logical colour occupies four of the
    \ ULA's sixteen entries -- so let VDU 19 do the work.
    LDY #0
.ss_pal
    STY tmp0
    LDA #19: JSR OSWRCH
    LDA tmp0: JSR OSWRCH        \ logical colour
    LDY tmp0
    LDA (lvlp),Y: JSR OSWRCH    \ physical colour
    LDA #0: JSR OSWRCH
    JSR OSWRCH
    JSR OSWRCH
    LDY tmp0
    INY
    CPY #4
    BNE ss_pal

    LDY #4: LDA (lvlp),Y: STA vehicle
    LDY #5: LDA (lvlp),Y: STA gnd_a
    LDY #6: LDA (lvlp),Y: STA gnd_b
    LDY #7: LDA (lvlp),Y: STA decor

    \ Walk the four lane blocks, recording where each one's gap list and
    \ object list start, then leave lvlp on the mover block.
    LDA lvlp: CLC: ADC #8: STA lvlp
    LDA lvlp+1: ADC #0: STA lvlp+1

    LDX #0
.ss_lane
    LDA lvlp: STA lane_gaps_lo,X
    LDA lvlp+1: STA lane_gaps_hi,X
    LDY #0
    LDA (lvlp),Y                \ gap count
    ASL A                       \ two bytes each
    SEC: ADC lvlp: STA lvlp     \ +1 for the count byte via the SEC
    LDA lvlp+1: ADC #0: STA lvlp+1

    LDA lvlp: STA lane_objs_lo,X
    LDA lvlp+1: STA lane_objs_hi,X
    LDY #0
    LDA (lvlp),Y                \ object count
    STA tmp0
    ASL A: CLC: ADC tmp0        \ three bytes each
    SEC: ADC lvlp: STA lvlp
    LDA lvlp+1: ADC #0: STA lvlp+1

    INX
    CPX #4
    BNE ss_lane

    LDA lvlp: STA movers_p
    LDA lvlp+1: STA movers_p+1

    JSR build_player_gfx
    JSR draw_playfield
    LDA #0: STA lane
    STA bonus_gone: STA bonus_gone+1
    STA bonus_gone+2: STA bonus_gone+3
    RTS

\ ============================================================================
\ Pre-shift the current vehicle's two frames into the four pixel phases.
\ Each phase is 5 cells wide, stored as interleaved (data, mask) pairs, so
\ 160 bytes per phase and 640 bytes per frame.
\ ============================================================================
.build_player_gfx
    LDA #0: STA bpg_frame
.bpg_next_frame
    LDA vehicle
    CLC: ADC bpg_frame
    TAX
    LDA sprite_lo,X: STA sprp
    LDA sprite_hi,X: STA sprp+1

    LDA #0: STA bpg_phase
.bpg_next_phase
    \ dst = pl_gfx + (frame*4 + phase) * 160
    LDA bpg_frame
    ASL A: ASL A
    CLC: ADC bpg_phase
    TAX
    LDA #LO(pl_gfx): STA bufp
    LDA #HI(pl_gfx): STA bufp+1
.bpg_offset
    CPX #0
    BEQ bpg_offset_done
    LDA bufp: CLC: ADC #160: STA bufp
    LDA bufp+1: ADC #0: STA bufp+1
    DEX
    JMP bpg_offset
.bpg_offset_done

    LDA #0: STA bpg_row
.bpg_next_row
    \ Gather this row's four data bytes (skipping the source masks).
    LDA bpg_row
    ASL A: ASL A: ASL A         \ row * 8 bytes
    TAY
    LDX #0
.bpg_gather
    LDA (sprp),Y
    STA bpg_src,X
    INY: INY
    INX
    CPX #4
    BNE bpg_gather

    \ Shift into five output bytes: out[i] = cur(src[i]) | prev(src[i-1]).
    LDX #0
.bpg_shift
    LDA #0: STA tmp1
    CPX #4
    BEQ bpg_no_cur              \ the fifth byte is spill only
    LDA bpg_src,X
    LDY bpg_phase
    AND ph_and_cur,Y
    LDY bpg_phase
    BEQ bpg_cur_done
.bpg_cur_shift
    LSR A
    DEY
    BNE bpg_cur_shift
.bpg_cur_done
    STA tmp1
.bpg_no_cur
    CPX #0
    BEQ bpg_no_prev             \ the first byte has nothing to its left
    LDA bpg_src-1,X
    STX bpg_i
    LDY bpg_phase
    AND ph_and_prv,Y
    LDX bpg_phase
    LDY ph_shl_prv,X
    BEQ bpg_prev_done
.bpg_prev_shift
    ASL A
    DEY
    BNE bpg_prev_shift
.bpg_prev_done
    LDX bpg_i
    ORA tmp1
    STA tmp1
.bpg_no_prev
    LDA tmp1
    STA bpg_out,X
    INX
    CPX #5
    BNE bpg_shift

    \ Emit the row as (data, mask) pairs: ten bytes per row.
    LDA bpg_row
    ASL A: ASL A: ASL A         \ row * 8
    STA tmp0
    LDA bpg_row
    ASL A                       \ row * 2
    CLC: ADC tmp0               \ row * 10
    TAY
    LDX #0
.bpg_emit
    LDA bpg_out,X
    STA (bufp),Y
    INY
    STX bpg_i
    TAX
    LDA masktab,X
    STA (bufp),Y
    INY
    LDX bpg_i
    INX
    CPX #5
    BNE bpg_emit

    INC bpg_row
    LDA bpg_row
    CMP #16
    BEQ bpg_row_done
    JMP bpg_next_row
.bpg_row_done

    INC bpg_phase
    LDA bpg_phase
    CMP #4
    BEQ bpg_phase_done
    JMP bpg_next_phase
.bpg_phase_done

    INC bpg_frame
    LDA bpg_frame
    CMP #2
    BEQ bpg_all_done
    JMP bpg_next_frame
.bpg_all_done
    RTS

.ph_and_cur EQUB &FF, &EE, &CC, &88
.ph_shr_cur EQUB 0, 1, 2, 3
.ph_and_prv EQUB &00, &11, &33, &77
.ph_shl_prv EQUB 0, 3, 2, 1

\ ============================================================================
\ Draw the static playfield: ground lines, decoration, hazards, bonuses
\ ============================================================================
.draw_playfield
    JSR clear_play
    LDX #0
.dp_lane
    STX tmp2
    JSR draw_ground
    LDX tmp2
    JSR draw_decor
    LDX tmp2
    JSR draw_lane_objects
    LDX tmp2
    INX
    CPX #4
    BNE dp_lane
    JSR draw_status
    RTS

\ Wipe the whole 10K of screen; the status bar is redrawn afterwards.
.clear_play
    LDA #0: STA scrp
    LDA #HI(SCREEN): STA scrp+1
    LDX #40                     \ pages
    LDY #0
    TYA
.cp_page
    STA (scrp),Y
    INY
    BNE cp_page
    INC scrp+1
    DEX
    BNE cp_page
    RTS

\ X = lane. Draw the 4-pixel ground line, skipping this lane's gaps.
.draw_ground
    JSR lane_top_row            \ A = character row of the lane top
    CLC: ADC #6                 \ ground occupies pixel rows 52..55 of the lane
    TAY                         \ Y = character row holding the ground
    LDA rowbase_lo,Y: STA scrp
    LDA rowbase_hi,Y: STA scrp+1
    LDA #0: STA tmp0            \ cell counter
.dg_cell
    LDX tmp2
    LDA tmp0
    JSR in_gap
    BCS dg_skip
    \ Ground line: one bright row then three of the body colour.
    LDY tmp0
    LDA colofs_lo,Y: CLC: ADC scrp: STA dptr
    LDA colofs_hi,Y: ADC scrp+1: STA dptr+1
    LDY #4
    LDA gnd_a: STA (dptr),Y
    INY
    LDA gnd_b
.dg_fill
    STA (dptr),Y
    INY
    CPY #8
    BNE dg_fill
.dg_skip
    INC tmp0
    LDA tmp0
    CMP #CELL_W
    BNE dg_cell
    RTS

\ A scatter of decoration a little above the ground, for a bit of scenery.
.draw_decor
    JSR lane_top_row
    CLC: ADC #2
    TAY
    LDA rowbase_lo,Y: STA scrp
    LDA rowbase_hi,Y: STA scrp+1
    LDA #0: STA tmp0
.dd_cell
    LDY tmp0
    LDA colofs_lo,Y: CLC: ADC scrp: STA dptr
    LDA colofs_hi,Y: ADC scrp+1: STA dptr+1
    LDY #3
    LDA decor
    STA (dptr),Y
    LDA tmp0: CLC: ADC #5: STA tmp0
    CMP #CELL_W
    BCC dd_cell
    RTS

\ X = lane: paint this lane's hazards and bonus into the background.
.draw_lane_objects
    LDA lane_objs_lo,X: STA lvlp
    LDA lane_objs_hi,X: STA lvlp+1
    LDY #0
    LDA (lvlp),Y
    STA dlo_count
    BEQ dlo_done
    LDA #1: STA dlo_index
.dlo_next
    LDY dlo_index
    LDA (lvlp),Y: STA dlo_cell
    INY
    LDA (lvlp),Y: TAX
    INY
    LDA (lvlp),Y                \ kind: 0 hazard, 1 bonus
    STA dlo_kind
    BEQ dlo_draw
    LDY tmp2
    LDA bonus_gone,Y
    BNE dlo_skip
.dlo_draw
    LDA sprite_lo,X: STA sprp
    LDA sprite_hi,X: STA sprp+1
    LDX tmp2
    JSR lane_top_px
    LDX dlo_kind
    BEQ dlo_ground
    CLC: ADC #BONUS_OFF
    JMP dlo_place
.dlo_ground
    CLC: ADC #REST_OFF
.dlo_place
    LDY dlo_cell
    JSR calc_scrp
    LDA #4: STA blitw
    JSR draw_masked
.dlo_skip
    LDA dlo_index: CLC: ADC #3: STA dlo_index
    LDA dlo_count
    ASL A: CLC: ADC dlo_count   \ count * 3
    TAX
    INX
    CPX dlo_index
    BNE dlo_next
.dlo_done
    RTS
.dlo_count  EQUB 0
.dlo_index  EQUB 0
.dlo_cell   EQUB 0
.dlo_kind   EQUB 0

BONUS_OFF = 16                  \ bonuses float, so you have to jump for them

\ X = lane -> A = character row of the lane top
.lane_top_row
    LDA lane_top_tab,X
    LSR A: LSR A: LSR A
    RTS

\ X = lane -> A = pixel row of the lane top
.lane_top_px
    LDA lane_top_tab,X
    RTS

.lane_top_tab
    EQUB LANE0_TOP, LANE0_TOP + LANE_H, LANE0_TOP + 2 * LANE_H, LANE0_TOP + 3 * LANE_H

\ X = lane, A = cell. Carry set if that cell is a gap in the ground.
.in_gap
    STA ig_cell
    LDA lane_gaps_lo,X: STA ig_ptr
    LDA lane_gaps_hi,X: STA ig_ptr+1
    LDY #0
    LDA (ig_ptr),Y
    BEQ ig_no
    STA ig_count
    LDY #1
.ig_next
    LDA (ig_ptr),Y              \ gap start cell
    STA ig_start
    INY
    LDA (ig_ptr),Y              \ gap length
    CLC: ADC ig_start
    STA ig_end
    INY
    LDA ig_cell
    CMP ig_start
    BCC ig_skip
    CMP ig_end
    BCC ig_yes
.ig_skip
    DEC ig_count
    BNE ig_next
.ig_no
    CLC
    RTS
.ig_yes
    SEC
    RTS
.ig_cell  EQUB 0
.ig_count EQUB 0
.ig_start EQUB 0
.ig_end   EQUB 0

\ ============================================================================
\ Screen addressing
\ ============================================================================
\ Y = cell column (0-39), A = pixel row (0-255) -> scrp, subrow
.calc_scrp
    STA tmp0
    AND #7
    STA subrow
    LDA tmp0
    LSR A: LSR A: LSR A
    TAX
    LDA rowbase_lo,X
    CLC: ADC colofs_lo,Y
    STA scrp
    LDA rowbase_hi,X
    ADC colofs_hi,Y
    STA scrp+1
    LDA scrp
    CLC: ADC subrow
    STA scrp
    LDA scrp+1
    ADC #0
    STA scrp+1
    RTS

\ Advance scrp by one pixel row, stepping to the next character row when the
\ current cell runs out.
.next_row
    INC subrow
    LDA subrow
    AND #7
    BNE nr_same_cell
    LDA #0: STA subrow
    LDA scrp: CLC: ADC #LO(ROW_BYTES - 7): STA scrp
    LDA scrp+1: ADC #HI(ROW_BYTES - 7): STA scrp+1
    RTS
.nr_same_cell
    INC scrp
    BNE nr_done
    INC scrp+1
.nr_done
    RTS

\ ============================================================================
\ Sprite blitting.  Source is interleaved (data, mask) pairs; the blit is
\ screen = (screen AND mask) OR data.
\
\ These three routines are the whole frame budget. The rolled-up version cost
\ ~45 cycles a byte, which put the redraw 21000 cycles long -- two thirds of
\ the visible screen -- so anything in the top two lanes was erased before the
\ beam arrived and redrawn after it had gone. Unrolling one character row at a
\ time gets the whole redraw inside the vertical border, where nobody can see
\ it happen.
\
\ Registers: X indexes the sprite (or the save buffer) and rises monotonically,
\ so the operand of every unrolled load is patched once per sprite, not per
\ row. Y holds the screen offset, an immediate per unrolled cell.
\ Inputs: sprp, scrp, subrow, blitw (4 or 5)
\ ============================================================================


.draw_masked
    JSR dm_patch                \ point the unrolled loads at this sprite
    LDX #0
    LDA #SPR_H: STA rowcnt
.dm_row
.dm_c0
    DRAW_CELL 0
.dm_c1
    DRAW_CELL 8
.dm_c2
    DRAW_CELL 16
.dm_c3
    DRAW_CELL 24
    LDA blitw
    CMP #5
    BNE dm_narrow
.dm_c4
    DRAW_CELL 32
.dm_narrow
    JSR next_row
    DEC rowcnt
    BNE dm_row
    RTS

.dm_patch
    LDA sprp:   STA dm_c0+3: STA dm_c0+9:  STA dm_c1+3: STA dm_c1+9
    STA dm_c2+3: STA dm_c2+9:  STA dm_c3+3: STA dm_c3+9
    STA dm_c4+3: STA dm_c4+9
    LDA sprp+1: STA dm_c0+4: STA dm_c0+10: STA dm_c1+4: STA dm_c1+10
    STA dm_c2+4: STA dm_c2+10: STA dm_c3+4: STA dm_c3+10
    STA dm_c4+4: STA dm_c4+10
    RTS


\ Copy the screen under a sprite into bufp.
.save_bg
    JSR sb_patch
    LDX #0
    LDA #SPR_H: STA rowcnt
.sb_row
.sb_c0
    GRAB_CELL 0
.sb_c1
    GRAB_CELL 8
.sb_c2
    GRAB_CELL 16
.sb_c3
    GRAB_CELL 24
    LDA blitw
    CMP #5
    BNE sb_narrow
.sb_c4
    GRAB_CELL 32
.sb_narrow
    JSR next_row
    DEC rowcnt
    BNE sb_row
    RTS

.sb_patch
    LDA bufp:   STA sb_c0+5: STA sb_c1+5: STA sb_c2+5: STA sb_c3+5: STA sb_c4+5
    LDA bufp+1: STA sb_c0+6: STA sb_c1+6: STA sb_c2+6: STA sb_c3+6: STA sb_c4+6
    RTS


\ Put it back.
.restore_bg
    JSR rb_patch
    LDX #0
    LDA #SPR_H: STA rowcnt
.rb_row
.rb_c0
    WRITE_CELL 0
.rb_c1
    WRITE_CELL 8
.rb_c2
    WRITE_CELL 16
.rb_c3
    WRITE_CELL 24
    LDA blitw
    CMP #5
    BNE rb_narrow
.rb_c4
    WRITE_CELL 32
.rb_narrow
    JSR next_row
    DEC rowcnt
    BNE rb_row
    RTS

.rb_patch
    LDA bufp:   STA rb_c0+3: STA rb_c1+3: STA rb_c2+3: STA rb_c3+3: STA rb_c4+3
    LDA bufp+1: STA rb_c0+4: STA rb_c1+4: STA rb_c2+4: STA rb_c3+4: STA rb_c4+4
    RTS

\ Blank a 4-cell by 16-row area (used when a bonus is collected).
.blank_sprite
    LDA #SPR_H: STA rowcnt
.bl_row
    LDY #0
    LDX blitw
    LDA #0
.bl_byte
    STA (scrp),Y
    TYA: CLC: ADC #8: TAY
    LDA #0
    DEX
    BNE bl_byte
    JSR next_row
    DEC rowcnt
    BNE bl_row
    RTS

\ ============================================================================
\ Playing a shoot
\ ============================================================================
\ Returns A = 0 if the shoot was completed, 1 if the researchers ran out.
.play_shoot
    LDA #0: STA lane
    JSR start_lane
.ps_frame
    JSR frame
    LDA game_flag
    BEQ ps_frame
    CMP #FLAG_LANE_DONE
    BNE ps_not_lane
    JSR sfx_lane
    LDA #&00: LDX #&01          \ 100 for finishing a lane
    JSR add_score
    LDA sp_lo: STA carry_sp_lo
    LDA sp_hi: STA carry_sp_hi
    INC lane
    LDA lane
    CMP #4
    BCS ps_shoot_done
    JSR start_lane
    JMP ps_frame
.ps_not_lane
    CMP #FLAG_CRASH
    BNE ps_quit
    DEC lives
    JSR do_crash
    LDA lives
    BEQ ps_gameover
    JSR start_lane
    JMP ps_frame
.ps_shoot_done
    JSR sfx_fanfare
    LDA #0
    RTS
.ps_gameover
    LDA #1
    RTS
.ps_quit
    LDA #1
    RTS

FLAG_NONE      = 0
FLAG_LANE_DONE = 1
FLAG_CRASH     = 2
FLAG_QUIT      = 3

\ Put the rider back at the left-hand end of the current lane.
.start_lane
    LDA #0
    STA px_lo: STA px_hi
    STA vy_lo: STA vy_hi
    STA airborne
    STA review
    STA game_flag
    STA py_lo
    LDA #REST_OFF: STA py_hi
    LDA carry_sp_lo: STA sp_lo
    LDA carry_sp_hi: STA sp_hi
    LDA #0: STA carry_sp_lo: STA carry_sp_hi
    JSR init_movers
    JSR clear_msg
    JSR draw_status
    JSR save_all
    RTS

\ Read the current lane's mover list into the runtime slots.
.init_movers
    LDX #0
.im_clear
    LDA #0: STA mv_active,X
    INX
    CPX #NMOVERS
    BNE im_clear

    LDA movers_p: STA lvlp
    LDA movers_p+1: STA lvlp+1
    LDY #0
    LDA (lvlp),Y
    STA im_total
    BEQ im_done
    LDA #1: STA im_index
    LDX #0                      \ slot
.im_next
    LDY im_index
    LDA (lvlp),Y                \ lane
    CMP lane
    BNE im_skip
    INY: LDA (lvlp),Y: STA mv_type,X
    INY: LDA (lvlp),Y: STA mv_cell,X
    INY: LDA (lvlp),Y: STA mv_min,X
    INY: LDA (lvlp),Y: STA mv_max,X
    INY: LDA (lvlp),Y: STA mv_spr,X
    INY: LDA (lvlp),Y: STA mv_delay,X
    LDA #1: STA mv_active,X
    LDA #0: STA mv_tick,X: STA mv_phase,X
    LDA #1: STA mv_dir,X
    INX
.im_skip
    LDA im_index: CLC: ADC #7: STA im_index
    DEC im_total
    BEQ im_done
    CPX #NMOVERS
    BNE im_next
.im_done
    RTS
.im_total EQUB 0
.im_index EQUB 0

\ ============================================================================
\ One frame
\ ============================================================================
.frame
    JSR read_keys
    JSR update_player
    JSR update_movers
    LDA game_flag
    BNE fr_skip_collide
    JSR collide
.fr_skip_collide
    JSR wait_vsync              \ our own vsync, not the OS's
    JSR wait_past_lane          \ ...then let the beam clear this lane
IF RASTER_DEBUG
    LDA #1: JSR raster_mark     \ paint the screen red while the sprites are
ENDIF
    JSR restore_all
    JSR save_all
IF RASTER_DEBUG
    LDA #0: JSR raster_mark     \ ...being redrawn: the band shows the cost
ENDIF
    \ Give the engine note the whole speed range, not just its integer part.
    LDA sp_lo
    LSR A
    STA tmp0
    LDA sp_hi
    ROR A
    LSR A
    ROR tmp0
    LDA sp_hi
    ASL A: ASL A: ASL A: ASL A
    ASL A: ASL A: ASL A
    ORA tmp0
    JSR sfx_engine
    RTS

IF RASTER_DEBUG
\ Flood every palette entry with one physical colour, so the time between two
\ calls shows up as a coloured band down the screen: a raster bar.
.raster_mark
    EOR #7
    STA rm_col
    LDX #15
.rm_loop
    TXA
    ASL A: ASL A: ASL A: ASL A
    ORA rm_col
    STA &FE21
    DEX
    BPL rm_loop
    RTS
.rm_col EQUB 0
ENDIF

IRQ1V   = &0204
VIA_IFR = &FE4D

\ OSBYTE 19 goes through the OS's event dispatch and does not return until the
\ beam is already ~22 lines into the display, which throws away the whole
\ vertical border -- the only time in the frame when it is safe to redraw
\ anything. So we hook IRQ1V ourselves, count vsyncs, and chain to whatever
\ was there before. A handler on IRQ1V may use A (the OS has already saved it
\ at &FC) but must leave X and Y alone.
.install_irq
    SEI
    LDA IRQ1V:   STA old_irq
    LDA IRQ1V+1: STA old_irq+1
    LDA #LO(our_irq): STA IRQ1V
    LDA #HI(our_irq): STA IRQ1V+1
    CLI
    RTS

.our_irq
    LDA VIA_IFR
    AND #2                      \ bit 1 = vsync
    BEQ our_irq_chain
    INC vsync_count
.our_irq_chain
    JMP (old_irq)

.wait_vsync
    LDA vsync_count
.wv_spin
    CMP vsync_count
    BEQ wv_spin
    RTS

.old_irq     EQUW 0
.vsync_count EQUB 0

\ Even off our own vsync the redraw is longer than the vertical border, and the
\ redraw takes some 80 lines -- so anything in the top lane would be erased
\ ahead of the beam and redrawn behind it, and never appear at all. Instead we
\ let the beam get past the lane we are about to redraw; by the time it comes
\ round again the new frame is sitting there waiting for it. Lanes 2 and 3 are
\ already below the redraw window, so they wait for nothing.
.wait_past_lane
    LDX lane
    LDA lane_delay,X
    BEQ wpl_done
    TAX
.wpl_row
    LDY #25                     \ 25 * 5 = 125 cycles, near enough one 128-cycle line
.wpl_inner
    DEY
    BNE wpl_inner
    DEX
    BNE wpl_row
.wpl_done
    RTS

\ Scanlines to wait before redrawing, per lane.
.lane_delay
    EQUB 75, 131, 0, 0

.read_keys
    LDX #KEY_JUMP: JSR keydown
    BEQ rk_nojump
    LDA airborne
    BNE rk_nojump
    LDA #LO(JUMP_VY): STA vy_lo
    LDA #HI(JUMP_VY): STA vy_hi
    LDA #1: STA airborne
    JSR sfx_jump
.rk_nojump
    LDX #KEY_ACC: JSR keydown
    BEQ rk_noacc
    LDA sp_lo: CLC: ADC #LO(ACCEL): STA sp_lo
    LDA sp_hi: ADC #HI(ACCEL): STA sp_hi
    CMP #HI(MAXSPD)
    BCC rk_noacc
    BNE rk_clamp
    LDA sp_lo
    CMP #LO(MAXSPD)
    BCC rk_noacc
.rk_clamp
    LDA #LO(MAXSPD): STA sp_lo
    LDA #HI(MAXSPD): STA sp_hi
.rk_noacc
    LDX #KEY_BRAKE: JSR keydown
    BEQ rk_nobrake
    LDA sp_lo: SEC: SBC #LO(BRAKE): STA sp_lo
    LDA sp_hi: SBC #HI(BRAKE): STA sp_hi
    BCS rk_nobrake
    LDA #0: STA sp_lo: STA sp_hi
.rk_nobrake
    \ Constant drag.
    LDA sp_lo: SEC: SBC #LO(DRAG): STA sp_lo
    LDA sp_hi: SBC #HI(DRAG): STA sp_hi
    BCS rk_nodrag
    LDA #0: STA sp_lo: STA sp_hi
.rk_nodrag
    LDX #KEY_QUIT: JSR keydown
    BEQ rk_done
    LDA #FLAG_QUIT: STA game_flag
.rk_done
    RTS

\ X = negative INKEY code. Returns A != 0 (and Z clear) when held.
.keydown
    LDA #&81
    LDY #&FF
    JSR OSBYTE
    TYA
    RTS

.update_player
    \ Horizontal.
    LDA px_lo: CLC: ADC sp_lo: STA px_lo
    LDA px_hi: ADC sp_hi: STA px_hi
    \ The lane ends when the rider's trailing edge leaves the screen. Going
    \ any further would put the five-cell blit past column 39, which wraps
    \ round onto the start of the next character row.
    CMP #144
    BCC up_onscreen
    LDA #143: STA px_hi
    LDA #0:   STA px_lo
    LDA #FLAG_LANE_DONE: STA game_flag
    RTS
.up_onscreen
    \ Vertical.
    LDA airborne
    BEQ up_grounded
    LDA vy_lo: CLC: ADC #LO(GRAVITY): STA vy_lo
    LDA vy_hi: ADC #HI(GRAVITY): STA vy_hi
    LDA py_lo: CLC: ADC vy_lo: STA py_lo
    LDA py_hi: ADC vy_hi: STA py_hi
    LDA vy_hi
    BMI up_review               \ still rising
.up_landcheck
    LDA py_hi
    CMP #REST_OFF
    BCC up_review               \ not down to ground level yet
    JSR player_cell
    LDX lane
    JSR in_gap
    BCC up_land
    \ Falling through a gap: drop into the lane below.
    LDA lane
    CMP #3
    BEQ up_fell_off
    INC lane
    JSR init_movers
    LDA py_hi: SEC: SBC #LANE_H: STA py_hi
    JMP up_landcheck
.up_fell_off
    LDA #FLAG_CRASH: STA game_flag
    RTS
.up_land
    LDA #REST_OFF: STA py_hi
    LDA #0: STA py_lo: STA vy_lo: STA vy_hi
    STA airborne
    JMP up_review
.up_grounded
    \ Walk off the edge of a gap and you drop.
    JSR player_cell
    LDX lane
    JSR in_gap
    BCC up_review
    LDA #1: STA airborne
    LDA #0: STA vy_lo: STA vy_hi
.up_review
    \ The reviewer catches up with anyone dawdling.
    LDA sp_hi
    BNE up_moving
    LDA sp_lo
    CMP #LO(SLOW_SPD)
    BCS up_moving
    INC review
    LDA review
    CMP #REVIEW_MAX
    BCC up_rdone
    LDA #FLAG_CRASH: STA game_flag
    LDA #1: STA review_death
    RTS
.up_moving
    LDA review
    BEQ up_rdone
    DEC review
.up_rdone
    \ Only repaint the status bar when the reviewer's bar actually changes.
    \ Testing `review AND 7` looked cheap but is zero every frame once review
    \ falls back to 0 -- which is the normal case while moving -- so this was
    \ running thirty-odd OSWRCH calls per frame, overrunning the frame and
    \ dropping the whole game to 25Hz.
    LDA review
    LSR A: LSR A: LSR A: LSR A: LSR A
    CMP last_bar
    BEQ up_nodraw
    STA last_bar
    JSR draw_status
.up_nodraw
    RTS

\ A = the cell the rider's centre is over.
.player_cell
    LDA px_hi
    CLC: ADC #8
    LSR A: LSR A
    RTS

\ ============================================================================
\ Movers
\ ============================================================================
\ Height of a hopper above the ground, indexed by its 16-step phase. It sits
\ up long enough that you can wait for it and drive underneath.
.hop_lift
    EQUB 0, 0, 4, 10, 16, 20, 22, 22, 22, 22, 20, 16, 10, 4, 0, 0

.update_movers
    LDX #0
.um_next
    LDA mv_active,X
    BEQ um_skip
    INC mv_tick,X
    LDA mv_tick,X
    CMP mv_delay,X
    BCC um_skip
    LDA #0: STA mv_tick,X
    LDA mv_type,X
    BNE um_hop
    \ Patrol left and right between min and max.
    LDA mv_dir,X
    BMI um_left
    INC mv_cell,X
    LDA mv_cell,X
    CMP mv_max,X
    BCC um_skip
    LDA #&FF: STA mv_dir,X
    JMP um_skip
.um_left
    DEC mv_cell,X
    LDA mv_cell,X
    CMP mv_min,X
    BCS um_skip
    LDA #1: STA mv_dir,X
    JMP um_skip
.um_hop
    \ Bob up and down on the spot.
    INC mv_phase,X
    LDA mv_phase,X
    AND #15
    STA mv_phase,X
.um_skip
    INX
    CPX #NMOVERS
    BNE um_next
    RTS

\ X = mover slot -> A = its pixel row
.mover_y
    LDA mv_type,X
    BEQ my_ground
    LDY mv_phase,X
    LDA hop_lift,Y
    STA tmp0
    LDA #REST_OFF
    SEC: SBC tmp0
    JMP my_add_lane
.my_ground
    LDA #REST_OFF
.my_add_lane
    STA tmp0
    LDX lane
    LDA lane_top_tab,X
    CLC: ADC tmp0
    RTS

\ ============================================================================
\ Drawing everything that moves
\ ============================================================================
.save_all
    \ Two passes. Pass one captures the background under every sprite BEFORE
    \ anything is drawn -- otherwise the second sprite saves the first sprite's
    \ pixels and smears a copy of it across the track next frame.
    \ Pass two draws, rider first, because the beam is chasing us down the
    \ screen and he is the thing you actually watch.
    JSR player_setup
    LDA scrp:   STA pl_scrp
    LDA scrp+1: STA pl_scrp+1
    LDA subrow: STA pl_subrow
    JSR save_bg

    LDX #0
.sa_next
    STX sa_slot
    LDA mv_active,X
    STA mv_drawn,X
    BEQ sa_skip
    JSR mover_setup
    LDX sa_slot
    LDA scrp:   STA mv_scrp_lo,X
    LDA scrp+1: STA mv_scrp_hi,X
    LDA subrow: STA mv_subrow,X
    JSR save_bg
.sa_skip
    LDX sa_slot
    INX
    CPX #NMOVERS
    BNE sa_next

    JSR player_setup_scrp_only
    JSR draw_masked

    LDX #0
.sd_next
    STX sa_slot
    LDA mv_drawn,X
    BEQ sd_skip
    LDA mv_spr,X
    TAX
    LDA sprite_lo,X: STA sprp
    LDA sprite_hi,X: STA sprp+1
    LDX sa_slot
    JSR mover_setup_scrp_only
    JSR draw_masked
.sd_skip
    LDX sa_slot
    INX
    CPX #NMOVERS
    BNE sd_next
    RTS
.sa_slot EQUB 0

.restore_all
    JSR restore_player
    LDX #NMOVERS - 1
.ra_next
    STX sa_slot
    LDA mv_drawn,X
    BEQ ra_skip
    LDA mv_scrp_lo,X: STA scrp
    LDA mv_scrp_hi,X: STA scrp+1
    LDA mv_subrow,X:  STA subrow
    JSR mover_bufp
    LDA #4: STA blitw
    JSR restore_bg
.ra_skip
    LDX sa_slot
    DEX
    BPL ra_next
    RTS

\ Put back whatever was under the rider where he was last drawn.
.restore_player
    LDA pl_scrp:   STA scrp
    LDA pl_scrp+1: STA scrp+1
    LDA pl_subrow: STA subrow
    LDA #LO(pl_bg): STA bufp
    LDA #HI(pl_bg): STA bufp+1
    LDA #5: STA blitw
    JMP restore_bg

\ Set scrp/bufp/blitw for mover slot X.
.mover_setup
    STX tmp1
    JSR mover_bufp
    LDX tmp1
.mover_setup_scrp_only
    STX tmp1
    JSR mover_y
    PHA
    LDX tmp1
    LDY mv_cell,X
    PLA
    JSR calc_scrp
    LDA #4: STA blitw
    LDX tmp1
    RTS

.mover_bufp
    LDA #LO(mv_bg): STA bufp
    LDA #HI(mv_bg): STA bufp+1
.mb_loop
    CPX #0
    BEQ mb_done
    LDA bufp: CLC: ADC #64: STA bufp
    LDA bufp+1: ADC #0: STA bufp+1
    DEX
    JMP mb_loop
.mb_done
    RTS

\ Set scrp/sprp/bufp/blitw for the rider.
.player_setup
    LDA #LO(pl_bg): STA bufp
    LDA #HI(pl_bg): STA bufp+1
.player_setup_scrp_only
    LDX lane
    LDA lane_top_tab,X
    CLC: ADC py_hi
    STA tmp0
    LDA px_hi
    LSR A: LSR A
    TAY
    LDA tmp0
    JSR calc_scrp
    LDA #5: STA blitw
    \ Source is the pre-shifted buffer: (frame * 4 + phase) * 160.
    LDA airborne
    ASL A: ASL A
    STA tmp0
    LDA px_hi
    AND #3
    CLC: ADC tmp0
    TAX
    LDA #LO(pl_gfx): STA sprp
    LDA #HI(pl_gfx): STA sprp+1
.pl_off
    CPX #0
    BEQ pl_off_done
    LDA sprp: CLC: ADC #160: STA sprp
    LDA sprp+1: ADC #0: STA sprp+1
    DEX
    JMP pl_off
.pl_off_done
    RTS

\ ============================================================================
\ Collision
\ ============================================================================
.collide
    \ Static hazards and the bonus for this lane.
    LDX lane
    LDA lane_objs_lo,X: STA lvlp
    LDA lane_objs_hi,X: STA lvlp+1
    LDY #0
    LDA (lvlp),Y
    BEQ co_movers
    STA co_count
    LDA #1: STA co_index
.co_next
    LDY co_index
    LDA (lvlp),Y: STA co_cell
    INY: INY
    LDA (lvlp),Y: STA co_kind
    \ x overlap?
    LDA co_cell
    ASL A: ASL A                \ cell -> pixels
    STA co_x
    LDA px_hi
    SEC: SBC co_x
    JSR abs_a
    CMP #HITBOX
    BCS co_step
    \ y overlap?
    LDA co_kind
    BEQ co_hazard_y
    LDA #BONUS_OFF
    JMP co_ytest
.co_hazard_y
    LDA #REST_OFF
.co_ytest
    STA co_y
    LDA py_hi
    SEC: SBC co_y
    JSR abs_a
    CMP #HITBOX
    BCS co_step
    \ Hit.
    LDA co_kind
    BEQ co_hazard
    JSR take_bonus
    JMP co_step
.co_hazard
    LDA #FLAG_CRASH: STA game_flag
    RTS
.co_step
    LDA co_index: CLC: ADC #3: STA co_index
    DEC co_count
    BEQ co_movers
    JMP co_next

.co_movers
    LDX #0
.cm_next
    STX sa_slot
    LDA mv_active,X
    BEQ cm_skip
    LDA mv_cell,X
    ASL A: ASL A
    STA co_x
    LDA px_hi
    SEC: SBC co_x
    JSR abs_a
    CMP #HITBOX
    BCS cm_skip
    LDX sa_slot
    JSR mover_y
    SEC
    LDX lane
    SBC lane_top_tab,X          \ back to lane-relative
    STA co_y
    LDA py_hi
    SEC: SBC co_y
    JSR abs_a
    CMP #HITBOX
    BCS cm_skip
    LDA #FLAG_CRASH: STA game_flag
    RTS
.cm_skip
    LDX sa_slot
    INX
    CPX #NMOVERS
    BNE cm_next
    RTS

.co_count EQUB 0
.co_index EQUB 0
.co_cell  EQUB 0
.co_kind  EQUB 0
.co_x     EQUB 0
.co_y     EQUB 0

.abs_a
    CMP #&80
    BCC aa_done
    EOR #&FF
    CLC: ADC #1
.aa_done
    RTS

\ Collecting the bonus: erase it, score it, say something smug.
.take_bonus
    LDX lane
    LDA bonus_gone,X
    BNE tb_done
    LDA #1: STA bonus_gone,X
    LDA co_cell
    TAY
    LDX lane
    LDA lane_top_tab,X
    CLC: ADC #BONUS_OFF
    JSR calc_scrp
    LDA #4: STA blitw
    JSR blank_sprite
    JSR sfx_bonus
    LDA #&00: LDX #&05          \ 500 for a bonus
    JSR add_score
    LDA #LO(msg_scaling): STA strp
    LDA #HI(msg_scaling): STA strp+1
    JSR show_msg
.tb_done
    RTS

\ ============================================================================
\ Crashing
\ ============================================================================
.do_crash
    LDA #0: STA carry_sp_lo: STA carry_sp_hi
    JSR sfx_crash
    \ Swap the rider for the explosion and let it sit there a moment.
    JSR restore_player
    JSR player_setup_scrp_only  \ recompute scrp; overwrites sprp
    LDX #SPR_CRASH
    LDA sprite_lo,X: STA sprp
    LDA sprite_hi,X: STA sprp+1
    LDA #4: STA blitw
    JSR draw_masked
    \ Pick something suitably bleak to say.
    LDA review_death
    BEQ dc_random
    LDA #0: STA review_death
    LDA #LO(msg_review): STA strp
    LDA #HI(msg_review): STA strp+1
    JMP dc_show
.dc_random
    JSR random
    AND #7
.dc_mod
    CMP #NUM_CRASH_MSGS
    BCC dc_ok
    SEC: SBC #NUM_CRASH_MSGS
    JMP dc_mod
.dc_ok
    TAX
    LDA crash_msg_ptrs_lo,X: STA strp
    LDA crash_msg_ptrs_hi,X: STA strp+1
.dc_show
    JSR show_msg
    \ Count the pause in memory: OSBYTE does not preserve X, so a DEX loop
    \ round a vsync wait never finishes.
    LDA #100: STA dc_timer
.dc_wait
    LDA #19: JSR OSBYTE
    DEC dc_timer
    BNE dc_wait
    JSR clear_msg
    \ Repaint the lane so the wreckage and any scars are gone.
    JSR draw_playfield
    RTS

\ ============================================================================
\ Text
\ ============================================================================
\ OSWRCH is far too slow for the game loop -- thirty-odd characters of status
\ bar cost more than a whole frame, which dropped the game to 25Hz and left
\ the top lane's sprites redrawn after the beam had already passed them.
\ So we plot characters ourselves out of the MOS font at &C000.
\
\ A MODE 5 character is 8 pixels wide: two CRTC cells, i.e. two bytes per
\ pixel row. A font byte's high nybble is the left four pixels and its low
\ nybble the right four, so each nybble becomes one MODE 5 byte via `expand`,
\ a 16-entry table rebuilt whenever the colour changes.
FONT = &C000                    \ MOS character definitions, 8 bytes from ' '

\ A = logical colour 0-3
.set_text_colour
    STA txt_col
    LDX #0
.stc_loop
    LDA #0: STA tmp0
    LDA txt_col
    AND #2
    BEQ stc_nohi
    TXA
    ASL A: ASL A: ASL A: ASL A  \ the four pixels' high bits
    STA tmp0
.stc_nohi
    LDA txt_col
    AND #1
    BEQ stc_nolo
    TXA
    ORA tmp0
    STA tmp0
.stc_nolo
    LDA tmp0
    STA expand,X
    INX
    CPX #16
    BNE stc_loop
    RTS

\ Y = character row (0-31), column taken from txt_col_pos (0-19)
.set_text_pos
    TYA
    TAX                         \ X = row for the rowbase lookup
    LDA txt_col_pos
    ASL A                       \ character column -> CRTC cell
    TAY
    LDA rowbase_lo,X
    CLC: ADC colofs_lo,Y
    STA txtp
    LDA rowbase_hi,X
    ADC colofs_hi,Y
    STA txtp+1
    LDA txtp: CLC: ADC #8: STA txtp2
    LDA txtp+1: ADC #0: STA txtp2+1
    RTS

\ A = character. Plots it and steps on one character to the right.
.draw_char
    SEC: SBC #32
    STA tmp0
    LDA #0: STA tmp1
    ASL tmp0: ROL tmp1
    ASL tmp0: ROL tmp1
    ASL tmp0: ROL tmp1          \ (char - 32) * 8
    LDA tmp0: CLC: ADC #LO(FONT): STA fontp
    LDA tmp1: ADC #HI(FONT): STA fontp+1
    LDY #7
.dch_row
    LDA (fontp),Y
    PHA
    LSR A: LSR A: LSR A: LSR A
    TAX
    LDA expand,X
    STA (txtp),Y
    PLA
    AND #15
    TAX
    LDA expand,X
    STA (txtp2),Y
    DEY
    BPL dch_row
    \ Next character is two cells (16 bytes) further on.
    LDA txtp:  CLC: ADC #16: STA txtp
    LDA txtp+1: ADC #0: STA txtp+1
    LDA txtp2: CLC: ADC #16: STA txtp2
    LDA txtp2+1: ADC #0: STA txtp2+1
    RTS

\ Plot the zero-terminated string at strp.
.draw_string
    LDY #0
.dstr_loop
    LDA (strp),Y
    BEQ dstr_done
    STY tmp2
    JSR draw_char
    LDY tmp2
    INY
    BNE dstr_loop
.dstr_done
    RTS

\ Plot A as two BCD digits.
.draw_bcd
    PHA
    LSR A: LSR A: LSR A: LSR A
    CLC: ADC #'0'
    JSR draw_char
    PLA
    AND #15
    CLC: ADC #'0'
    JMP draw_char

\ ============================================================================
\ Status bar and messages
\ ============================================================================
.draw_status
    LDA #COL_HI: JSR set_text_colour
    LDA #0: STA txt_col_pos
    LDY #0
    JSR set_text_pos
    LDA #LO(txt_funding): STA strp
    LDA #HI(txt_funding): STA strp+1
    JSR draw_string
    LDX #2
.ds_digits
    STX tmp2
    LDA score,X
    JSR draw_bcd
    LDX tmp2
    DEX
    BPL ds_digits

    LDA #COL_MID: JSR set_text_colour
    LDA #0: STA txt_col_pos
    LDY #1
    JSR set_text_pos
    LDA #LO(txt_phd): STA strp
    LDA #HI(txt_phd): STA strp+1
    JSR draw_string
    LDA lives
    CLC: ADC #'0'
    JSR draw_char
    LDA #LO(txt_rvw): STA strp
    LDA #HI(txt_rvw): STA strp+1
    JSR draw_string
    \ Eight characters of reviewer patience, filling as you dawdle.
    LDA review
    LSR A: LSR A: LSR A: LSR A
    LSR A                       \ 0..200 -> 0..6
    STA tmp0
    STA last_bar
    LDX #0
.ds_bar
    CPX tmp0
    BCS ds_empty
    LDA #'#'
    JMP ds_emit
.ds_empty
    LDA #'.'
.ds_emit
    STX tmp2
    JSR draw_char
    LDX tmp2
    INX
    CPX #7
    BNE ds_bar
    RTS

.print_bcd
    PHA
    LSR A: LSR A: LSR A: LSR A
    CLC: ADC #'0'
    JSR OSWRCH
    PLA
    AND #15
    CLC: ADC #'0'
    JSR OSWRCH
    RTS

\ A = low BCD byte to add, X = high BCD byte. So 100 is A=&00, X=&01.
.add_score
    STA tmp0
    STX tmp1
    SED
    LDA score
    CLC: ADC tmp0
    STA score
    LDA score+1
    ADC tmp1
    STA score+1
    LDA score+2
    ADC #0
    STA score+2
    CLD
    JSR draw_status
    RTS

\ Print the string at strp on the message line.
.show_msg
    JSR clear_msg
    LDA #COL_ACC: JSR set_text_colour
    LDA #0: STA txt_col_pos
    LDY #30
    JSR set_text_pos
    JSR draw_string
    RTS

.clear_msg
    LDA #LO(SCREEN + 30 * ROW_BYTES): STA scrp
    LDA #HI(SCREEN + 30 * ROW_BYTES): STA scrp+1
    LDA #0
    LDY #0
    LDX #2
.cmsg_page
    STA (scrp),Y
    INY
    BNE cmsg_page
    INC scrp+1
    DEX
    BNE cmsg_page
.cmsg_tail
    STA (scrp),Y
    INY
    CPY #128
    BNE cmsg_tail
    RTS

.hide_cursor
    LDA #23: JSR OSWRCH
    LDA #1:  JSR OSWRCH
    LDA #0:  JSR OSWRCH
    LDX #7
.hc_pad
    LDA #0: JSR OSWRCH
    DEX
    BNE hc_pad
    RTS

\ ============================================================================
\ Odds and ends
\ ============================================================================
.random
    LDA seed
    ASL A
    BCC rnd_no
    EOR #&1D
.rnd_no
    STA seed
    RTS

.txt_funding EQUS "FUNDING $", 0
.txt_phd     EQUS "PHD ", 0
.txt_rvw     EQUS " RVW ", 0
.msg_scaling EQUS "SCALING LAW!", 0
.msg_review  EQUS "PAUSED FOR REVIEW", 0

\ ============================================================================
\ Assembly-time tables
\ ============================================================================
\ Transparency mask for every possible MODE 5 data byte: both bits set for
\ each pixel whose colour is 0.
.masktab
FOR b, 0, 255
    o  = (b AND &F0) OR ((b MOD 16) * 16)
    mh = (o EOR &F0) AND &F0
    EQUB mh OR (mh DIV 16)
NEXT

.rowbase_lo
FOR r, 0, 31
    EQUB LO(SCREEN + r * ROW_BYTES)
NEXT
.rowbase_hi
FOR r, 0, 31
    EQUB HI(SCREEN + r * ROW_BYTES)
NEXT

.colofs_lo
FOR c, 0, CELL_W - 1
    EQUB LO(c * 8)
NEXT
.colofs_hi
FOR c, 0, CELL_W - 1
    EQUB HI(c * 8)
NEXT

\ ============================================================================
\ Variables
\ ============================================================================
.score      SKIP 3              \ BCD, least significant byte first
.lives      SKIP 1
.shoot      SKIP 1
.difficulty SKIP 1
.lane       SKIP 1
.vehicle    SKIP 1
.gnd_a      SKIP 1
.gnd_b      SKIP 1
.decor      SKIP 1
.game_flag  SKIP 1
.review     SKIP 1
.review_death SKIP 1
.airborne   SKIP 1
.px_lo      SKIP 1
.px_hi      SKIP 1
.py_lo      SKIP 1
.py_hi      SKIP 1
.sp_lo      SKIP 1
.sp_hi      SKIP 1
.vy_lo      SKIP 1
.vy_hi      SKIP 1
.movers_p   SKIP 2
.lane_gaps_lo SKIP 4
.lane_gaps_hi SKIP 4
.lane_objs_lo SKIP 4
.lane_objs_hi SKIP 4
.bonus_gone   SKIP 4
.carry_sp_lo  SKIP 1
.carry_sp_hi  SKIP 1
.dc_timer     SKIP 1
.last_bar     SKIP 1
.txt_col      SKIP 1
.txt_col_pos  SKIP 1
.expand       SKIP 16
.pl_scrp      SKIP 2
.pl_subrow    SKIP 1
.mv_scrp_lo   SKIP NMOVERS
.mv_scrp_hi   SKIP NMOVERS
.mv_subrow    SKIP NMOVERS
.mv_drawn     SKIP NMOVERS

.mv_active  SKIP NMOVERS
.mv_type    SKIP NMOVERS
.mv_cell    SKIP NMOVERS
.mv_min     SKIP NMOVERS
.mv_max     SKIP NMOVERS
.mv_spr     SKIP NMOVERS
.mv_delay   SKIP NMOVERS
.mv_tick    SKIP NMOVERS
.mv_dir     SKIP NMOVERS
.mv_phase   SKIP NMOVERS

.bpg_frame  SKIP 1
.bpg_phase  SKIP 1
.bpg_row    SKIP 1
.bpg_i      SKIP 1
.bpg_src    SKIP 4
.bpg_out    SKIP 5

ALIGN &100
.pl_gfx     SKIP 1280           \ 2 frames x 4 phases x 160 bytes
.pl_bg      SKIP 80
.mv_bg      SKIP NMOVERS * 64

\ Symbol addresses for the test harness (harmless at run time).
PRINT "SYM score", ~score
PRINT "SYM lives", ~lives
PRINT "SYM shoot", ~shoot
PRINT "SYM lane", ~lane
PRINT "SYM game_flag", ~game_flag
PRINT "SYM airborne", ~airborne
PRINT "SYM px_hi", ~px_hi
PRINT "SYM py_hi", ~py_hi
PRINT "SYM sp_hi", ~sp_hi
PRINT "SYM review", ~review
PRINT "SYM mv_active", ~mv_active
PRINT "SYM mv_type", ~mv_type
PRINT "SYM mv_cell", ~mv_cell
PRINT "SYM mv_phase", ~mv_phase
PRINT "SYM vsync_count", ~vsync_count

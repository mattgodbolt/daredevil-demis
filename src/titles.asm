\ ============================================================================
\ DAREDEVIL DEMIS — front-end screens
\   .title_screen  .card_screen  .end_screen  .print_str
\   .crash_msg_ptrs_lo / .crash_msg_ptrs_hi / NUM_CRASH_MSGS
\
\ MODE 5 throughout: 20 columns x 32 rows, 4 colours.  Every string here is
\ hand-counted to fit inside 20 columns from its printing position.
\
\ Zero page: this module touches ONLY &90-&9F (see defs.asm).
\   &90/&91  string pointer for print_str (public contract with the engine)
\   &92/&93  flashing-prompt column / row
\   &94/&95  layout-list walker pointer
\   &96/&97  big-text glyph list pointer
\   &98 &99 &9A   big-text x, y, colour
\   &9B &9C &9D   big-text row, glyph index, bit scratch
\   &9E      title-screen stunt rider column (&FF = no rider)
\   &9F      frame counter (drives flash + animation)
\ ============================================================================

ttl_str    = &90            \ + &91
ttl_fcol   = &92
ttl_frow   = &93
ttl_lst    = &94            \ + &95
ttl_gp     = &96            \ + &97
ttl_bx     = &98
ttl_by     = &99
ttl_bcol   = &9A
ttl_brow   = &9B
ttl_bidx   = &9C
ttl_tmp    = &9D
ttl_rider  = &9E
ttl_frame  = &9F

\ Characters we redefine (224-255 are user-definable on a stock machine).
TTL_BLOCK  = 224            \ solid 8x8 block: the "pixel" of the big font
TTL_BIKE_L = 225            \ stunt rider, left half
TTL_BIKE_R = 226            \ stunt rider, right half

\ Negative INKEY key numbers, as OSBYTE &81 wants them (256 + key).
TTL_K_SPACE  = &9D          \ -99
TTL_K_RETURN = &B6          \ -74

\ ---------------------------------------------------------------------------
\ print_str — print the zero-terminated string at (&90).  Engine-facing.
\ OSWRCH preserves A/X/Y, so Y can stay live across the call.
\ ---------------------------------------------------------------------------
.print_str
    TXA:PHA
    TYA:PHA
    LDY #0
.ttl_ps_loop
    LDA (ttl_str),Y
    BEQ ttl_ps_done
    JSR OSWRCH
    INY
    BNE ttl_ps_loop
.ttl_ps_done
    PLA:TAY
    PLA:TAX
    RTS

\ ---------------------------------------------------------------------------
\ THE TITLE SCREEN
\ ---------------------------------------------------------------------------
.title_screen
    JSR ttl_setup_mode
    LDY #0
    JSR ttl_stripe                  \ clapperboard band across the top

    LDA #LO(ttl_title_text)
    STA ttl_lst
    LDA #HI(ttl_title_text)
    STA ttl_lst+1
    JSR ttl_layout

    LDA #LO(ttl_big_demis)          \ the big blocky "DEMIS"
    STA ttl_gp
    LDA #HI(ttl_big_demis)
    STA ttl_gp+1
    LDA #0:STA ttl_bx
    LDA #4:STA ttl_by
    LDA #COL_HI:STA ttl_bcol
    JSR ttl_big

    LDY #27                         \ ground line for the stunt rider
    LDA #COL_ACC
    JSR ttl_solid

    LDA #LO(ttl_msg_press1)         \ flashing prompt, row 24
    STA ttl_str
    LDA #HI(ttl_msg_press1)
    STA ttl_str+1
    LDA #0:STA ttl_fcol
    LDA #24:STA ttl_frow
    LDA #0:STA ttl_rider            \ rider enabled, starting at column 0
    JMP ttl_wait_start              \ ...and wait for SPACE / RETURN

\ ---------------------------------------------------------------------------
\ THE SHOOT CARD.  A = shoot number 0-3.
\ ---------------------------------------------------------------------------
.card_screen
    AND #3
    PHA                             \ keep the shoot number
    JSR ttl_palette
    JSR ttl_defchars
    JSR ttl_cls

    LDY #0
    JSR ttl_stripe
    LDY #30
    JSR ttl_stripe

    LDA #LO(ttl_big_shoot)          \ big blocky "SHOOT"
    STA ttl_gp
    LDA #HI(ttl_big_shoot)
    STA ttl_gp+1
    LDA #0:STA ttl_bx
    LDA #2:STA ttl_by
    LDA #COL_MID:STA ttl_bcol
    JSR ttl_big

    PLA
    PHA
    CLC
    ADC #BG_1                       \ ...and the shoot number, big, below it
    STA ttl_big_digit
    LDA #LO(ttl_big_digit)
    STA ttl_gp
    LDA #HI(ttl_big_digit)
    STA ttl_gp+1
    LDA #8:STA ttl_bx
    LDA #8:STA ttl_by
    LDA #COL_HI:STA ttl_bcol
    JSR ttl_big

    PLA                             \ per-shoot name + briefing
    TAX
    LDA ttl_card_lo,X
    STA ttl_lst
    LDA ttl_card_hi,X
    STA ttl_lst+1
    JSR ttl_layout

    LDA #LO(ttl_card_common)
    STA ttl_lst
    LDA #HI(ttl_card_common)
    STA ttl_lst+1
    JSR ttl_layout

    LDA #15:LDX #0:JSR OSBYTE       \ flush the keyboard buffer
    LDA #&81                        \ read a key, giving up after 200cs (2s)
    LDX #200
    LDY #0
    JSR OSBYTE
    RTS

\ ---------------------------------------------------------------------------
\ THE END SCREEN.  Prints the 6-digit BCD score held at `score` (engine).
\ ---------------------------------------------------------------------------
.end_screen
    JSR ttl_setup_mode
    LDY #0
    JSR ttl_stripe

    LDA #LO(ttl_end_text)
    STA ttl_lst
    LDA #HI(ttl_end_text)
    STA ttl_lst+1
    JSR ttl_layout

    LDA #LO(ttl_big_chair)          \ THE CHAIR, in the largest letters we have
    STA ttl_gp
    LDA #HI(ttl_big_chair)
    STA ttl_gp+1
    LDA #0:STA ttl_bx
    LDA #8:STA ttl_by
    LDA #COL_HI:STA ttl_bcol
    JSR ttl_big

    LDX #6                          \ FUNDING total: "$" then 6 BCD digits
    LDY #17
    JSR ttl_tab
    LDA #COL_HI
    JSR ttl_ink
    LDA #'$'
    JSR OSWRCH
    LDX #2:JSR ttl_bcd              \ score is little-endian: print high first
    LDX #1:JSR ttl_bcd
    LDX #0:JSR ttl_bcd

    LDY #30
    JSR ttl_stripe

    LDA #LO(ttl_msg_press2)
    STA ttl_str
    LDA #HI(ttl_msg_press2)
    STA ttl_str+1
    LDA #4:STA ttl_fcol
    LDA #27:STA ttl_frow
    LDA #&FF:STA ttl_rider          \ no stunt rider on this one
    JMP ttl_wait_start

\ Print score,X as two packed BCD digits.
.ttl_bcd
    LDA score,X
    PHA
    LSR A:LSR A:LSR A:LSR A
    JSR ttl_digit
    PLA
    AND #&0F
.ttl_digit
    CLC
    ADC #'0'
    JMP OSWRCH

\ ---------------------------------------------------------------------------
\ Waiting for SPACE or RETURN, with the screen still moving.
\ Ticks on vsync so it never spins hot and never misses a key.
\ ---------------------------------------------------------------------------
.ttl_wait_start
    LDA #15:LDX #0:JSR OSBYTE       \ discard anything typed during the game
    LDA #0
    STA ttl_frame
.ttl_wait_loop
    LDA #19:JSR OSBYTE              \ wait for vertical sync (50Hz)
    INC ttl_frame

    LDA ttl_frame                   \ every 8th frame: shuffle the rider on
    AND #7                          \ and blink the prompt (on 3 beats in 4)
    BNE ttl_wait_nokey
    JSR ttl_ride
    LDA ttl_frame
    AND #&18
    BEQ ttl_wait_off
    LDA #COL_HI
    BNE ttl_wait_show
.ttl_wait_off
    LDA #COL_BG
.ttl_wait_show
    JSR ttl_flash

.ttl_wait_nokey
    LDA #&81                        \ INKEY(-99): SPACE
    LDX #TTL_K_SPACE
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BEQ ttl_wait_done
    LDA #&81                        \ INKEY(-74): RETURN
    LDX #TTL_K_RETURN
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE ttl_wait_loop
.ttl_wait_done
    LDA #15:LDX #0:JSR OSBYTE       \ don't let the key leak into the game
    RTS

\ Redraw the prompt in colour A (colour 0 = invisible = "off").
.ttl_flash
    PHA
    LDX ttl_fcol
    LDY ttl_frow
    JSR ttl_tab
    PLA
    JSR ttl_ink
    JMP print_str

\ Shuffle the little stunt rider one column to the right along row 22.
.ttl_ride
    LDA ttl_rider
    BMI ttl_ride_done
    LDX ttl_rider
    LDY #26
    JSR ttl_tab
    LDA #' ':JSR OSWRCH
    LDA #' ':JSR OSWRCH
    INC ttl_rider
    LDA ttl_rider
    CMP #19
    BCC ttl_ride_draw
    LDA #0
    STA ttl_rider
.ttl_ride_draw
    LDX ttl_rider
    LDY #26
    JSR ttl_tab
    LDA #COL_HI
    JSR ttl_ink
    LDA #TTL_BIKE_L:JSR OSWRCH
    LDA #TTL_BIKE_R:JSR OSWRCH
.ttl_ride_done
    RTS

\ ---------------------------------------------------------------------------
\ Screen plumbing
\ ---------------------------------------------------------------------------

\ MODE 5 (which also clears), our palette, our characters, no cursor.
.ttl_setup_mode
    LDA #22:JSR OSWRCH
    LDA #5:JSR OSWRCH
    JSR ttl_palette
    JMP ttl_defchars

\ Clear the screen without a mode change (used by the shoot card).
.ttl_cls
    LDA #17:JSR OSWRCH              \ background back to logical 0
    LDA #128:JSR OSWRCH
    LDA #12:JSR OSWRCH
    RTS

\ Force the four logical colours back to the front-end palette, whatever the
\ engine last poked into the Video ULA for its own shoot.
.ttl_palette
    LDX #0
.ttl_pal_loop
    LDA ttl_pal_data,X
    JSR OSWRCH
    INX
    CPX #(ttl_pal_end - ttl_pal_data)
    BNE ttl_pal_loop
    RTS

.ttl_pal_data
    EQUB 19, 0, 0, 0,0,0            \ 0 = black
    EQUB 19, 1, 1, 0,0,0            \ 1 = red
    EQUB 19, 2, 3, 0,0,0            \ 2 = yellow
    EQUB 19, 3, 7, 0,0,0            \ 3 = white
.ttl_pal_end

\ Define the block and the stunt rider, and switch the caret off.
.ttl_defchars
    LDX #0
.ttl_dc_loop
    LDA ttl_chr_data,X
    JSR OSWRCH
    INX
    CPX #(ttl_chr_end - ttl_chr_data)
    BNE ttl_dc_loop
    RTS

.ttl_chr_data
    EQUB 23, 1, 0,0,0,0, 0,0,0,0            \ cursor off
    EQUB 23, TTL_BLOCK
    EQUB &FF,&FF,&FF,&FF,&FF,&FF,&FF,&FF    \ solid block
    EQUB 23, TTL_BIKE_L             \ stunt rider, hunched over the tank
    EQUB %00000011
    EQUB %00000011
    EQUB %00001111
    EQUB %00011110
    EQUB %00111111
    EQUB %01111111
    EQUB %11100111
    EQUB %11100000
    EQUB 23, TTL_BIKE_R
    EQUB %10000000
    EQUB %10000000
    EQUB %11100000
    EQUB %00111000
    EQUB %00111000
    EQUB %11100000
    EQUB %11100111
    EQUB %00000111
.ttl_chr_end

\ VDU 31,X,Y — move the text cursor.  X = column, Y = row.
.ttl_tab
    LDA #31:JSR OSWRCH
    TXA:JSR OSWRCH
    TYA:JSR OSWRCH
    RTS

\ VDU 17,A — set the text foreground colour.
.ttl_ink
    PHA
    LDA #17:JSR OSWRCH
    PLA
    JMP OSWRCH

\ A whole row of solid blocks in colour A, on row Y.
.ttl_solid
    PHA
    LDX #0
    JSR ttl_tab
    PLA
    JSR ttl_ink
    LDX #20
.ttl_sol_loop
    LDA #TTL_BLOCK
    JSR OSWRCH
    DEX
    BNE ttl_sol_loop
    RTS

\ A clapperboard band on row Y: alternating red and white blocks.
.ttl_stripe
    LDX #0
    JSR ttl_tab
    LDA #0
    STA ttl_tmp
.ttl_str_loop
    LDA ttl_tmp
    AND #1
    ASL A
    ORA #1                          \ 0 -> colour 1, 1 -> colour 3
    JSR ttl_ink
    LDA #TTL_BLOCK
    JSR OSWRCH
    INC ttl_tmp
    LDA ttl_tmp
    CMP #20
    BNE ttl_str_loop
    RTS

\ ---------------------------------------------------------------------------
\ Layout lists.  A compact way to say "text here, in this colour":
\     x, y, colour, "string", 0    ... repeated ... &FF
\ ---------------------------------------------------------------------------
.ttl_layout
.ttl_lay_next
    JSR ttl_get                     \ x, or &FF for end of list
    CMP #&FF
    BEQ ttl_lay_done
    TAX
    JSR ttl_get                     \ y
    TAY
    JSR ttl_tab
    JSR ttl_get                     \ colour
    JSR ttl_ink
.ttl_lay_char
    JSR ttl_get
    BEQ ttl_lay_next
    JSR OSWRCH
    JMP ttl_lay_char
.ttl_lay_done
    RTS

\ A = *ttl_lst++, with the flags reflecting A (not the pointer increment).
.ttl_get
    LDY #0
    LDA (ttl_lst),Y
    INC ttl_lst
    BNE ttl_get_done
    INC ttl_lst+1
.ttl_get_done
    CMP #0
    RTS

\ ---------------------------------------------------------------------------
\ The big blocky font: 3 blocks wide, 5 blocks tall, one glyph per id.
\ Glyph lists are terminated with &FF.  Five glyphs (3 wide plus a 1-column
\ gap) come to exactly 19 columns, which is why every big word here is
\ five letters long.
\ ---------------------------------------------------------------------------
BG_A = 0
BG_C = 1
BG_D = 2
BG_E = 3
BG_H = 4
BG_I = 5
BG_M = 6
BG_O = 7
BG_R = 8
BG_S = 9
BG_T = 10
BG_1 = 11
BG_2 = 12
BG_3 = 13
BG_4 = 14

.ttl_font
    EQUB %111,%101,%111,%101,%101   \ A
    EQUB %111,%100,%100,%100,%111   \ C
    EQUB %110,%101,%101,%101,%110   \ D
    EQUB %111,%100,%110,%100,%111   \ E
    EQUB %101,%101,%111,%101,%101   \ H
    EQUB %111,%010,%010,%010,%111   \ I
    EQUB %101,%111,%111,%101,%101   \ M
    EQUB %111,%101,%101,%101,%111   \ O
    EQUB %110,%101,%110,%101,%101   \ R
    EQUB %111,%100,%111,%001,%111   \ S
    EQUB %111,%010,%010,%010,%010   \ T
    EQUB %010,%110,%010,%010,%111   \ 1
    EQUB %111,%001,%111,%100,%111   \ 2
    EQUB %111,%001,%111,%001,%111   \ 3
    EQUB %101,%101,%111,%001,%001   \ 4

.ttl_big_demis  EQUB BG_D,BG_E,BG_M,BG_I,BG_S, &FF
.ttl_big_shoot  EQUB BG_S,BG_H,BG_O,BG_O,BG_T, &FF
.ttl_big_chair  EQUB BG_C,BG_H,BG_A,BG_I,BG_R, &FF
.ttl_big_digit  EQUB BG_1, &FF     \ patched with the shoot number

\ Draw the glyph list at (&96) at column &98, row &99, in colour &9A.
\ Drawn a whole row of blocks at a time so the cursor only moves five times.
.ttl_big
    LDA ttl_bcol
    JSR ttl_ink
    LDA #0
    STA ttl_brow
.ttl_big_row
    LDX ttl_bx
    LDA ttl_by
    CLC
    ADC ttl_brow
    TAY
    JSR ttl_tab
    LDA #0
    STA ttl_bidx
.ttl_big_glyph
    LDY ttl_bidx
    LDA (ttl_gp),Y
    CMP #&FF
    BEQ ttl_big_eol
    STA ttl_tmp
    ASL A                           \ id * 5 + row  ->  font offset
    ASL A
    CLC
    ADC ttl_tmp
    CLC
    ADC ttl_brow
    TAY
    LDA ttl_font,Y
    ASL A:ASL A:ASL A:ASL A:ASL A   \ leftmost block into bit 7
    STA ttl_tmp
    LDX #3
.ttl_big_bit
    ASL ttl_tmp
    LDA #' '
    BCC ttl_big_emit
    LDA #TTL_BLOCK
.ttl_big_emit
    JSR OSWRCH
    DEX
    BNE ttl_big_bit
    INC ttl_bidx                    \ one blank column between glyphs, but
    LDY ttl_bidx                    \ never after the last one (that would
    LDA (ttl_gp),Y                  \ push us off the right-hand edge)
    CMP #&FF
    BEQ ttl_big_eol
    LDA #' '
    JSR OSWRCH
    JMP ttl_big_glyph
.ttl_big_eol
    INC ttl_brow
    LDA ttl_brow
    CMP #5
    BNE ttl_big_row
    RTS

\ ---------------------------------------------------------------------------
\ Screen copy.  Column counts are in the comments; nothing reaches column 20.
\ ---------------------------------------------------------------------------

.ttl_title_text
    EQUB  1, 2,COL_MID : EQUS "D A R E D E V I L"      : EQUB 0   \ 17
    EQUB  1,10,COL_ACC : EQUS "SOLVE INTELLIGENCE"     : EQUB 0   \ 18
    EQUB  1,12,COL_ACC : EQUS "THEN JUMP OVER IT."     : EQUB 0   \ 18
    EQUB  6,14,COL_HI  : EQUS "CONTROLS"               : EQUB 0   \  8
    EQUB  2,16,COL_MID : EQUS "X = MORE COMPUTE"       : EQUB 0   \ 16
    EQUB  2,18,COL_MID : EQUS "Z = SAFETY REVIEW"      : EQUB 0   \ 17
    EQUB  2,20,COL_MID : EQUS "SPACE = JUMP"           : EQUB 0   \ 12
    EQUB  2,22,COL_MID : EQUS "ESCAPE = RESIGN"        : EQUB 0   \ 15
    EQUB  0,29,COL_ACC : EQUS "ALPHABET STUNT UNIT"    : EQUB 0   \ 19
    EQUB  1,31,COL_MID : EQUS "(C) 1984 DEEPMIND"      : EQUB 0   \ 17
    EQUB &FF

.ttl_msg_press1
    EQUS "PRESS SPACE TO FILM" : EQUB 0                           \ 19
.ttl_msg_press2
    EQUS "PRESS SPACE" : EQUB 0                                   \ 11

.ttl_end_text
    EQUB  3, 2,COL_ACC : EQUS "THAT'S A WRAP."         : EQUB 0   \ 14
    EQUB  3, 4,COL_MID : EQUS "YOU HAVE BEEN"          : EQUB 0   \ 13
    EQUB  4, 6,COL_MID : EQUS "PROMOTED TO"            : EQUB 0   \ 11
    EQUB 16,13,COL_HI  : EQUS "MAN"                    : EQUB 0   \  3
    EQUB  3,15,COL_MID : EQUS "FINAL FUNDING"          : EQUB 0   \ 13
    EQUB  1,19,COL_ACC : EQUS "YOU NOW REPORT TO"      : EQUB 0   \ 17
    EQUB  3,21,COL_ACC : EQUS "A SPREADSHEET."         : EQUB 0   \ 14
    EQUB  0,23,COL_ACC : EQUS "NO RESEARCHERS WERE"    : EQUB 0   \ 19
    EQUB  1,25,COL_ACC : EQUS "HARMED. THEY LEFT."     : EQUB 0   \ 18
    EQUB &FF

.ttl_card_common
    EQUB  3,26,COL_MID : EQUS "ROLL CAMERA..."         : EQUB 0   \ 14
    EQUB  6,28,COL_HI  : EQUS "ACTION!"                : EQUB 0   \  7
    EQUB &FF

.ttl_card_lo
    EQUB LO(ttl_card1), LO(ttl_card2), LO(ttl_card3), LO(ttl_card4)
.ttl_card_hi
    EQUB HI(ttl_card1), HI(ttl_card2), HI(ttl_card3), HI(ttl_card4)

.ttl_card1
    EQUB  3,15,COL_HI  : EQUS "GO BOARD GORGE"         : EQUB 0   \ 14
    EQUB  3,18,COL_MID : EQUS "BLACK TO PLAY."         : EQUB 0   \ 14
    EQUB  2,20,COL_MID : EQUS "WHITE TO CRASH."        : EQUB 0   \ 15
    EQUB  0,22,COL_ACC : EQUS "MOVE 37 IS UP THERE"    : EQUB 0   \ 19
    EQUB  1,24,COL_ACC : EQUS "NOBODY KNOWS WHY."      : EQUB 0   \ 17
    EQUB &FF

.ttl_card2
    EQUB  2,14,COL_HI  : EQUS "PROTEIN FOLDING"        : EQUB 0   \ 15
    EQUB  7,16,COL_HI  : EQUS "FJORD"                  : EQUB 0   \  5
    EQUB  1,18,COL_MID : EQUS "STRUCTURE: SOLVED."     : EQUB 0   \ 18
    EQUB  1,20,COL_MID : EQUS "JET-SKI: UNSOLVED."     : EQUB 0   \ 18
    EQUB  2,22,COL_ACC : EQUS "MIND THE BLOBS."        : EQUB 0   \ 15
    EQUB  1,24,COL_ACC : EQUS "RAMPS ARE HELICES."     : EQUB 0   \ 18
    EQUB &FF

.ttl_card3
    EQUB  2,15,COL_HI  : EQUS "THEME PARK HILL"        : EQUB 0   \ 15
    EQUB  3,18,COL_MID : EQUS "MIND THE SICK."         : EQUB 0   \ 14
    EQUB  3,20,COL_MID : EQUS "DODGE THE VANS."        : EQUB 0   \ 15
    EQUB  2,22,COL_ACC : EQUS "PUT THE SALT UP."       : EQUB 0   \ 16
    EQUB  4,24,COL_ACC : EQUS "IT IS CANON."           : EQUB 0   \ 12
    EQUB &FF

.ttl_card4
    EQUB  5,15,COL_HI  : EQUS "AGI SUMMIT"             : EQUB 0   \ 10
    EQUB  1,18,COL_MID : EQUS "UPHILL. ALL OF IT."     : EQUB 0   \ 18
    EQUB  1,20,COL_MID : EQUS "TPUS ARE ON FIRE."      : EQUB 0   \ 17
    EQUB  1,22,COL_ACC : EQUS "SO IS THE ROADMAP."     : EQUB 0   \ 18
    EQUB  2,24,COL_ACC : EQUS "REACH THE CHAIR."       : EQUB 0   \ 16
    EQUB &FF

\ ---------------------------------------------------------------------------
\ Crash messages.  These go on the 20-column message line, so 20 characters
\ is the hard limit — all of these are 19 or shorter.
\ ---------------------------------------------------------------------------
NUM_CRASH_MSGS = 12

.crash_msg_ptrs_lo
    EQUB LO(ttl_cm0),  LO(ttl_cm1),  LO(ttl_cm2),  LO(ttl_cm3)
    EQUB LO(ttl_cm4),  LO(ttl_cm5),  LO(ttl_cm6),  LO(ttl_cm7)
    EQUB LO(ttl_cm8),  LO(ttl_cm9),  LO(ttl_cm10), LO(ttl_cm11)
.crash_msg_ptrs_hi
    EQUB HI(ttl_cm0),  HI(ttl_cm1),  HI(ttl_cm2),  HI(ttl_cm3)
    EQUB HI(ttl_cm4),  HI(ttl_cm5),  HI(ttl_cm6),  HI(ttl_cm7)
    EQUB HI(ttl_cm8),  HI(ttl_cm9),  HI(ttl_cm10), HI(ttl_cm11)

.ttl_cm0    EQUS "MODEL COLLAPSE!"      : EQUB 0      \ 15
.ttl_cm1    EQUS "HALLUCINATION!"       : EQUB 0      \ 14
.ttl_cm2    EQUS "COMPUTE EXHAUSTED!"   : EQUB 0      \ 18
.ttl_cm3    EQUS "DELAYED SIX MONTHS!"  : EQUB 0      \ 19
.ttl_cm4    EQUS "TALENT EXODUS!"       : EQUB 0      \ 14
.ttl_cm5    EQUS "BENCHMARK OVERFIT!"   : EQUB 0      \ 18
.ttl_cm6    EQUS "GPU SHORTAGE!"        : EQUB 0      \ 13
.ttl_cm7    EQUS "ALIGNMENT FAILURE!"   : EQUB 0      \ 18
.ttl_cm8    EQUS "PIVOT TO AGENTS!"     : EQUB 0      \ 16
.ttl_cm9    EQUS "BURN RATE EXCEEDED!"  : EQUB 0      \ 19
.ttl_cm10   EQUS "TRAINING RUN LOST!"   : EQUB 0      \ 18
.ttl_cm11   EQUS "PROMOTED SIDEWAYS!"   : EQUB 0      \ 18

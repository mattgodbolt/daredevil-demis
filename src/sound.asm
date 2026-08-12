\ ============================================================================
\ DAREDEVIL DEMIS — sound module
\
\ All sound goes through the OS: OSWORD 7 (SOUND) and OSWORD 8 (ENVELOPE).
\ No SN76489 pokes, no interrupt handler, nothing that blocks the game loop.
\
\ Channel allocation:
\   0  noise    — crash only
\   1  tone     — the engine, and nothing else (see sfx_engine)
\   2  tone     — foreground effects: jump, bonus, fanfare/gameover melody
\   3  tone     — secondary effects: lane blip, harmony/drone
\
\ Zero page used: &90-&93 only (sfx_ptr/sfx_idx). Everything else is local
\ absolute storage at the end of this file.
\ ============================================================================

\ --- OSWORD 7 parameter block layout (8 bytes, all little-endian words) -----
\   +0/+1  channel   (low nibble = channel 0-3, high nibble 1 = flush & play
\                     immediately, 0 = queue behind whatever is playing)
\   +2/+3  amplitude (0 to -15 for a fixed level, +1 to +16 = envelope number)
\   +4/+5  pitch     (0-255, 4 units per semitone; middle C = 53)
\   +6/+7  duration  (1/20ths of a second; -1 = play until replaced)

sfx_ptr    = &90            \ 16-bit pointer into a note sequence
sfx_idx    = &92            \ byte offset within that sequence
sfx_tmp    = &93            \ engine pitch scratch

SFX_NUM_ENV   = 5
SFX_ENV_ENG   = 1           \ engine growl (repeating pitch wobble, sustains)
SFX_ENV_CHIRP = 2           \ swooping upward blip
SFX_ENV_BANG  = 3           \ instant attack, long ragged decay
SFX_ENV_PLUCK = 4           \ bright plucked note
SFX_ENV_SAD   = 5           \ slow swell and fade

SFX_ENG_BASE  = 20          \ pitch of engine band 0, + 6 per band
SFX_SEQ_END   = &FF         \ sequence terminator (never a legal channel byte)

\ ============================================================================
\ sfx_init — called once at startup. Enable sound, define the envelopes,
\            and leave every channel quiet.
\ ============================================================================
.sfx_init
    LDA #210                \ OSBYTE 210: sound suppression, new = (old AND Y)
    LDX #0                  \ EOR X, so X=Y=0 means "sound on"
    LDY #0
    JSR OSBYTE

    LDA #LO(sfx_envelopes)
    STA sfx_ptr
    LDA #HI(sfx_envelopes)
    STA sfx_ptr+1
    LDA #SFX_NUM_ENV
    STA sfx_idx             \ reused here as an envelope counter
.sfx_init_loop
    LDX sfx_ptr
    LDY sfx_ptr+1
    LDA #8                  \ OSWORD 8 = ENVELOPE
    JSR OSWORD
    CLC
    LDA sfx_ptr
    ADC #14                 \ envelope blocks are 14 bytes each
    STA sfx_ptr
    BCC sfx_init_nohi
    INC sfx_ptr+1
.sfx_init_nohi
    DEC sfx_idx
    BNE sfx_init_loop
    JMP sfx_silence         \ (also resets the remembered engine band)

\ ============================================================================
\ sfx_engine — call every frame with the player's speed in A (0 = stopped).
\
\ Speed is squashed to 17 bands (0 = silent, 1-16 = rising pitch) and a sound
\ command is only issued when the band actually changes, so a steady speed
\ costs a compare and an RTS. The note is continuous (duration -1) and is
\ therefore replaced rather than queued: a queued note would never get to
\ play behind an endless one, so band changes use the flush flag on channel 1.
\ That is a handful of calls a second, not the per-frame flushing that would
\ chop the note up. Nothing here can block: a flushing OSWORD 7 always has
\ room in the queue.
\ ============================================================================
.sfx_engine
    LDX #0                  \ X = band
    CMP #0
    BEQ sfx_eng_got         \ stopped: band 0
    LSR A
    LSR A
    LSR A
    LSR A                   \ 0-15
    TAX
    INX                     \ 1-16
.sfx_eng_got
    CPX sfx_band
    BEQ sfx_eng_done
    STX sfx_band
    TXA
    BEQ sfx_eng_off

    ASL A                   \ band*2
    STA sfx_tmp
    ASL A                   \ band*4
    CLC
    ADC sfx_tmp             \ band*6  (max 96, no carry)
    ADC #SFX_ENG_BASE       \ 26..116
    STA sfx_blk+4
    LDA #SFX_ENV_ENG
    STA sfx_blk+2
    LDA #0
    STA sfx_blk+3           \ envelope number is positive
    LDA #&FF
    STA sfx_blk+6
    STA sfx_blk+7           \ duration -1: play until replaced
.sfx_eng_emit
    LDA #&11                \ channel 1, flush and play now
    STA sfx_blk
    LDA #0
    STA sfx_blk+1
    STA sfx_blk+5           \ pitch high byte
    JMP sfx_osword7
.sfx_eng_off
    STA sfx_blk+2           \ A is 0 here: amplitude 0 = silence
    STA sfx_blk+3
    STA sfx_blk+4           \ pitch 0
    LDA #1
    STA sfx_blk+6
    LDA #0
    STA sfx_blk+7           \ duration 1
    BEQ sfx_eng_emit        \ always
.sfx_eng_done
    RTS

\ ============================================================================
\ The effects. Each is a canned note sequence; see the data at the end.
\ ============================================================================

\ A short upward chirp — Demis leaves the ground.
.sfx_jump
    LDX #LO(sfx_seq_jump)
    LDY #HI(sfx_seq_jump)
    JMP sfx_play_seq

\ Noise burst plus a low tone rumble underneath: MODEL COLLAPSE.
.sfx_crash
    JSR sfx_engine_off
    LDX #LO(sfx_seq_crash)
    LDY #HI(sfx_seq_crash)
    JMP sfx_play_seq

\ Bright ascending arpeggio — SCALING LAW!
.sfx_bonus
    LDX #LO(sfx_seq_bonus)
    LDY #HI(sfx_seq_bonus)
    JMP sfx_play_seq

\ Tiny blip for completing a lane.
.sfx_lane
    LDX #LO(sfx_seq_lane)
    LDY #HI(sfx_seq_lane)
    JMP sfx_play_seq

\ Triumphant "ta-ta-ta-daa" in two parts for finishing a shoot.
.sfx_fanfare
    JSR sfx_engine_off
    LDX #LO(sfx_seq_fanfare)
    LDY #HI(sfx_seq_fanfare)
    JMP sfx_play_seq

\ Descending phrase over a drone — promoted to Chairman.
.sfx_gameover
    JSR sfx_engine_off
    LDX #LO(sfx_seq_gameover)
    LDY #HI(sfx_seq_gameover)
    JMP sfx_play_seq

\ Everything off, right now: flush all four sound buffers, then push a
\ silent flushing note into each channel to kill whatever was sounding.
.sfx_silence
    LDX #4                  \ buffers 4-7 are sound channels 0-3
.sfx_sil_loop
    LDA #21                 \ OSBYTE 21: flush buffer X
    JSR OSBYTE
    INX
    CPX #8
    BNE sfx_sil_loop
    LDA #0
    STA sfx_band            \ engine will re-issue as soon as speed returns
    LDX #LO(sfx_seq_quiet)
    LDY #HI(sfx_seq_quiet)
    JMP sfx_play_seq

\ Silence channel 1 alone and forget the band, so the engine restarts by
\ itself the moment the player is moving again.
.sfx_engine_off
    LDA #0
    STA sfx_band
    LDX #LO(sfx_seq_engoff)
    LDY #HI(sfx_seq_engoff)
    \ fall through

\ ============================================================================
\ sfx_play_seq — X/Y = lo/hi address of a sequence of 4-byte notes
\                (channel, amplitude-or-envelope, pitch, duration), &FF ends.
\
\ Each byte is widened into the OSWORD 7 block's little-endian word: channel
\ and pitch are always positive, amplitude and duration are sign extended so
\ that -15 and -1 come out as &FFF1 and &FFFF.
\
\ Sequences never queue more than four notes on one channel and always start
\ each channel with a flushing note, so the OS queue cannot fill up and
\ OSWORD 7 can never stall the caller.
\ ============================================================================
.sfx_play_seq
    STX sfx_ptr
    STY sfx_ptr+1
    LDA #0
    STA sfx_idx
.sfx_seq_next
    LDY sfx_idx
    LDA (sfx_ptr),Y
    CMP #SFX_SEQ_END
    BEQ sfx_seq_end
    STA sfx_blk             \ channel
    LDA #0
    STA sfx_blk+1
    INY
    LDA (sfx_ptr),Y         \ amplitude or envelope
    STA sfx_blk+2
    JSR sfx_signhi
    STA sfx_blk+3
    INY
    LDA (sfx_ptr),Y         \ pitch
    STA sfx_blk+4
    LDA #0
    STA sfx_blk+5
    INY
    LDA (sfx_ptr),Y         \ duration
    STA sfx_blk+6
    JSR sfx_signhi
    STA sfx_blk+7
    INY
    STY sfx_idx             \ OSWORD is not guaranteed to preserve Y
    JSR sfx_osword7
    JMP sfx_seq_next
.sfx_seq_end
    RTS

\ A -> &FF if A had bit 7 set, else &00. Y preserved.
.sfx_signhi
    CMP #&80
    LDA #0
    BCC sfx_signhi_done
    LDA #&FF
.sfx_signhi_done
    RTS

.sfx_osword7
    LDX #LO(sfx_blk)
    LDY #HI(sfx_blk)
    LDA #7
    JMP OSWORD

\ ============================================================================
\ Envelopes (OSWORD 8 blocks: number, step-length, 3 pitch steps, 3 section
\ lengths, attack/decay/sustain/release rates, attack and decay targets).
\ A step length with bit 7 set stops the pitch envelope auto-repeating.
\ ============================================================================
.sfx_envelopes
\ 1: engine — a 2 step pitch wobble repeating at 50Hz gives the growl, and
\    the amplitude jumps to full and stays there until the note is replaced.
    EQUB 1,   1,   3,  -3,   0,   1,   1,   0
    EQUB 127,  0,   0, -20, 100, 100
\ 2: jump chirp — 18 semitones up in a tenth of a second, then fade.
    EQUB 2, &81,   8,   4,   0,   6,   6,   0
    EQUB 100, -6,   0, -25, 110,  70
\ 3: crash — slam to maximum, then a long unpleasant decay.
    EQUB 3, &81,   0,   0,   0,   0,   0,   0
    EQUB 127, -3,  -1,  -8, 126,  80
\ 4: pluck — bright and short, for bonuses, blips and the fanfare.
    EQUB 4, &81,   0,   0,   0,   0,   0,   0
    EQUB 110, -8,  -2, -30, 120,  60
\ 5: sad — slower swell, long fade, for the game over phrase.
    EQUB 5, &81,   0,   0,   0,   0,   0,   0
    EQUB 40,  -2,  -1, -12, 100,  70

\ ============================================================================
\ Note sequences: channel, amplitude/envelope, pitch, duration.
\ Pitch reference: C=53, D=61, E=69, F=73, G=81, A=89, B=97, C'=105
\ (4 per semitone, 48 per octave). Duration is in 20ths of a second.
\ ============================================================================

.sfx_seq_jump
    EQUB &12, SFX_ENV_CHIRP,  90,   6
    EQUB SFX_SEQ_END

.sfx_seq_crash
    EQUB &10, SFX_ENV_BANG,    6,  18   \ noise channel: low white noise
    EQUB &12, SFX_ENV_BANG,    9,  18   \ subsonic rumble
    EQUB &13, SFX_ENV_BANG,   17,  14   \ and a dirty low tone over it
    EQUB SFX_SEQ_END

.sfx_seq_bonus
    EQUB &12, SFX_ENV_PLUCK,  53,   3
    EQUB &02, SFX_ENV_PLUCK,  69,   3
    EQUB &02, SFX_ENV_PLUCK,  81,   3
    EQUB &02, SFX_ENV_PLUCK, 105,   6
    EQUB SFX_SEQ_END

.sfx_seq_lane
    EQUB &13, SFX_ENV_PLUCK,  97,   2
    EQUB SFX_SEQ_END

.sfx_seq_fanfare
    EQUB &12, SFX_ENV_PLUCK,  81,   3   \ G  G  G  C'
    EQUB &02, SFX_ENV_PLUCK,  81,   3
    EQUB &02, SFX_ENV_PLUCK,  81,   3
    EQUB &02, SFX_ENV_PLUCK, 105,  10
    EQUB &13, SFX_ENV_PLUCK,  33,   3   \ an octave down underneath
    EQUB &03, SFX_ENV_PLUCK,  33,   3
    EQUB &03, SFX_ENV_PLUCK,  33,   3
    EQUB &03, SFX_ENV_PLUCK,  57,  10
    EQUB SFX_SEQ_END

.sfx_seq_gameover
    EQUB &12, SFX_ENV_SAD,    81,   6   \ G  F  Eb  C
    EQUB &02, SFX_ENV_SAD,    73,   6
    EQUB &02, SFX_ENV_SAD,    65,   6
    EQUB &02, SFX_ENV_SAD,    53,  16
    EQUB &13, SFX_ENV_SAD,     5,  34   \ drone underneath the lot
    EQUB SFX_SEQ_END

.sfx_seq_quiet
    EQUB &10, 0, 0, 1
    EQUB &11, 0, 0, 1
    EQUB &12, 0, 0, 1
    EQUB &13, 0, 0, 1
    EQUB SFX_SEQ_END

.sfx_seq_engoff
    EQUB &11, 0, 0, 1
    EQUB SFX_SEQ_END

\ --- storage ---------------------------------------------------------------
.sfx_band
    EQUB 0                  \ engine band last played (0 = silent)
.sfx_blk
    EQUD 0                  \ OSWORD 7 parameter block (8 bytes)
    EQUD 0

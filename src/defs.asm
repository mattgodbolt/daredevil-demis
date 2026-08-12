\ ============================================================================
\ DAREDEVIL DEMIS — shared definitions
\ Included first by main.asm; every module may rely on these.
\ ============================================================================

\ --- OS entry points -------------------------------------------------------
OSWRCH  = &FFEE
OSBYTE  = &FFF4
OSWORD  = &FFF1
OSCLI   = &FFF7

\ --- Screen geometry (MODE 5: 160x256, 4 colours) --------------------------
SCREEN     = &5800          \ start of screen memory
ROW_BYTES  = 320            \ bytes per character row (40 CRTC cols * 8)
CELL_W     = 40             \ CRTC columns across (each 4 pixels wide)
CHAR_ROWS  = 32

\ Vertical layout, in pixel rows:
\   0..15    status bar (2 char rows)
\   16..71   lane 0        \ each lane is 56 pixels tall
\   72..127  lane 1
\   128..183 lane 2
\   184..239 lane 3
\   240..255 message line (2 char rows)
STATUS_H   = 16
LANE_H     = 56
LANE0_TOP  = 16
MSG_TOP    = 240

\ A resting sprite's top pixel row within a lane (sprite is 16 tall, the
\ ground line occupies the 4 pixels at lane_top+52..55).
REST_OFF   = 36

\ --- Sprite format ---------------------------------------------------------
\ Every sprite is 16 pixels wide (4 CRTC cells) by 16 pixel rows.
\ Stored row-major as 16 rows of 4 cells, each cell being an interleaved
\ (data, mask) byte pair -- so 8 bytes per row, 128 bytes per sprite:
\
\   row 0: d0 m0 d1 m1 d2 m2 d3 m3
\   row 1: d0 m0 d1 m1 d2 m2 d3 m3   ... 16 rows
\
\ `data` is a MODE 5 pixel byte (4 pixels, 2bpp interleaved: pixel k uses
\ bit 7-k as its high bit and bit 3-k as its low bit).
\ `mask` has both bits SET for every pixel that is transparent (colour 0)
\ and CLEAR for every pixel the sprite paints. Blitting is therefore:
\     screen = (screen AND mask) OR data
SPR_BYTES  = 128
SPR_W      = 4              \ cells wide
SPR_H      = 16             \ pixel rows

\ --- Sprite ids (index into sprite_lo/sprite_hi, defined in sprites.asm) ---
SPR_BIKE       = 0          \ shoot 1 vehicle: motorbike + rider, on ground
SPR_BIKE_AIR   = 1          \ ...mid-leap
SPR_SKI        = 2          \ shoot 2 vehicle: jet-ski
SPR_SKI_AIR    = 3
SPR_COASTER    = 4          \ shoot 3 vehicle: rollercoaster car
SPR_COASTER_AIR= 5
SPR_SKIDOO     = 6          \ shoot 4 vehicle: ski-doo
SPR_SKIDOO_AIR = 7
SPR_STONE_B    = 8          \ shoot 1: black Go stone
SPR_STONE_W    = 9          \ shoot 1: white Go stone
SPR_MOVE37     = 10         \ shoot 1: the glowing bonus stone
SPR_COMMENT    = 11         \ shoot 1: hopping commentator (mover)
SPR_BLOB       = 12         \ shoot 2: misfolded protein blob
SPR_HELIX      = 13         \ shoot 2: alpha-helix coil
SPR_MEDAL      = 14         \ shoot 2: Nobel medal (bonus)
SPR_LABTECH    = 15         \ shoot 2: wet-lab technician (mover)
SPR_PUNTER     = 16         \ shoot 3: queueing punter
SPR_VAN        = 17         \ shoot 3: ice-cream van
SPR_SICK       = 18         \ shoot 3: puddle of sick
SPR_BURGER     = 19         \ shoot 3: burger stand (bonus)
SPR_VOMITER    = 20         \ shoot 3: vomiting punter (mover)
SPR_TPU        = 21         \ shoot 4: overheating TPU pod
SPR_CRATE      = 22         \ shoot 4: crate marked DELAYED
SPR_LEAVER     = 23         \ shoot 4: departing researcher with a box (mover)
SPR_CHAIR      = 24         \ shoot 4: THE CHAIR (bonus)
SPR_CRASH      = 25         \ explosion / rider on fire
NUM_SPRITES    = 26

\ --- Logical colours -------------------------------------------------------
\ The physical palette is reprogrammed per shoot, but the roles are fixed:
\   0 = background   1 = accent (dark)   2 = mid tone   3 = highlight
COL_BG  = 0
COL_ACC = 1
COL_MID = 2
COL_HI  = 3

\ --- Zero page -------------------------------------------------------------
\ &70-&8F belongs to the engine. Other modules must use &90-&9F or their own
\ absolute storage.
zp_engine  = &70
zp_shared  = &90            \ sound.asm / titles.asm scratch: &90-&9F

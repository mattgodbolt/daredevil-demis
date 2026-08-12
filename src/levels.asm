\ ============================================================================
\ DAREDEVIL DEMIS — the four shoots
\ ============================================================================
\ Level block layout:
\   +0  four physical palette colours for logical colours 0-3
\   +4  vehicle sprite id (the airborne frame is always this + 1)
\   +5  ground line top-row byte
\   +6  ground line body byte
\   +7  decoration byte, dotted along each lane
\   +8  four lane blocks, each:
\           EQUB gap_count,  then (start_cell, length) per gap
\           EQUB obj_count,  then (cell, sprite_id, kind) per object
\                            kind 0 = hazard, 1 = bonus
\       then EQUB mover_count, then per mover:
\           EQUB lane, type, cell, min_cell, max_cell, sprite_id, delay
\           type 0 = patrols left and right, 1 = hops on the spot
\
\ Layout rules, learned the hard way from watching the autopilot land on
\ things: a jump at full pelt covers 35 pixels, so hazard GROUPS must be at
\ least twelve cells apart or the rider comes down on top of the next one.
\ Hazards inside a group sit within three cells of each other so a single
\ jump clears the lot. Bonuses go three cells past a hazard, so the jump that
\ saves you is also the jump that pays you. Hoppers are only a hazard while
\ they are down, so they go early in the lane where there is room to wait.
\ ============================================================================

MV_PATROL = 0
MV_HOP    = 1
KIND_HAZ  = 0
KIND_BONUS= 1

.level_lo
    EQUB LO(shoot1), LO(shoot2), LO(shoot3), LO(shoot4)
.level_hi
    EQUB HI(shoot1), HI(shoot2), HI(shoot3), HI(shoot4)

\ ----------------------------------------------------------------------------
\ SHOOT 1 - GO BOARD GORGE
\ Black and white stones on the intersections, and one placed somewhere no
\ human would ever have put it.
\ ----------------------------------------------------------------------------
.shoot1
    EQUB 0, 1, 3, 7             \ black, red, yellow, white
    EQUB SPR_BIKE
    EQUB &FF, &F0, &90

    \ Lane 0 - a gentle warm-up
    EQUB 0
    EQUB 2
    EQUB 16, SPR_STONE_B,  KIND_HAZ
    EQUB 29, SPR_STONE_W,  KIND_HAZ

    \ Lane 1 - stones in twos
    EQUB 1
    EQUB 30, 5
    EQUB 2
    EQUB 16, SPR_STONE_W,  KIND_HAZ
    EQUB 17, SPR_STONE_B,  KIND_HAZ

    \ Lane 2 - a hole in the board
    EQUB 1
    EQUB 26, 5
    EQUB 1
    EQUB 16, SPR_STONE_B,  KIND_HAZ

    \ Lane 3 - MOVE 37, placed where nobody would have put it
    EQUB 0
    EQUB 2
    EQUB 16, SPR_STONE_B,  KIND_HAZ
    EQUB 19, SPR_MOVE37,   KIND_BONUS
    EQUB 2
    EQUB 0, MV_HOP,    5, 5, 5, SPR_COMMENT, 3
    EQUB 2, MV_HOP,    6, 6, 6, SPR_COMMENT, 4

\ ----------------------------------------------------------------------------
\ SHOOT 2 - PROTEIN FOLDING FJORD
\ Two hundred million structures and not one of them gets out of the way.
\ ----------------------------------------------------------------------------
.shoot2
    EQUB 4, 1, 6, 7             \ blue water, red, cyan, white
    EQUB SPR_SKI
    EQUB &FF, &50, &A0

    \ Lane 0
    EQUB 0
    EQUB 2
    EQUB 16, SPR_BLOB,     KIND_HAZ
    EQUB 29, SPR_HELIX,    KIND_HAZ

    \ Lane 1
    EQUB 1
    EQUB 30, 6
    EQUB 2
    EQUB 16, SPR_HELIX,    KIND_HAZ
    EQUB 17, SPR_BLOB,     KIND_HAZ

    \ Lane 2 - an unresolved region
    EQUB 1
    EQUB 26, 5
    EQUB 1
    EQUB 16, SPR_BLOB,     KIND_HAZ

    \ Lane 3 - the medal, three cells past the blob that guards it
    EQUB 0
    EQUB 2
    EQUB 16, SPR_BLOB,     KIND_HAZ
    EQUB 19, SPR_MEDAL,    KIND_BONUS
    EQUB 3
    EQUB 0, MV_HOP,    5, 5, 5, SPR_LABTECH, 3
    EQUB 1, MV_HOP,    6, 6, 6, SPR_LABTECH, 4
    EQUB 3, MV_HOP,    5, 5, 5, SPR_LABTECH, 3

\ ----------------------------------------------------------------------------
\ SHOOT 3 - THEME PARK HILL
\ Put the salt up. Put the salt up. Put the salt up.
\ ----------------------------------------------------------------------------
.shoot3
    EQUB 0, 2, 3, 7             \ night shoot, green, yellow, white
    EQUB SPR_COASTER
    EQUB &FF, &0F, &F0

    \ Lane 0 - the queue
    EQUB 0
    EQUB 3
    EQUB 16, SPR_PUNTER,   KIND_HAZ
    EQUB 17, SPR_PUNTER,   KIND_HAZ
    EQUB 29, SPR_VAN,      KIND_HAZ

    \ Lane 1
    EQUB 1
    EQUB 30, 5
    EQUB 2
    EQUB 16, SPR_SICK,     KIND_HAZ
    EQUB 17, SPR_VAN,      KIND_HAZ

    \ Lane 2 - the loop the loop
    EQUB 1
    EQUB 26, 6
    EQUB 1
    EQUB 16, SPR_PUNTER,   KIND_HAZ

    \ Lane 3
    EQUB 0
    EQUB 3
    EQUB 16, SPR_SICK,     KIND_HAZ
    EQUB 19, SPR_BURGER,   KIND_BONUS
    EQUB 29, SPR_PUNTER,   KIND_HAZ
    EQUB 3
    EQUB 0, MV_HOP,    5, 5, 5, SPR_VOMITER, 3
    EQUB 2, MV_HOP,    6, 6, 6, SPR_VOMITER, 3
    EQUB 3, MV_HOP,    5, 5, 5, SPR_VOMITER, 4

\ ----------------------------------------------------------------------------
\ SHOOT 4 - AGI SUMMIT
\ Everything is six months away, including the exit.
\ ----------------------------------------------------------------------------
.shoot4
    EQUB 0, 1, 6, 7             \ black, red, cyan, white
    EQUB SPR_SKIDOO
    EQUB &FF, &F0, &0F

    \ Lane 0
    EQUB 0
    EQUB 3
    EQUB 16, SPR_TPU,      KIND_HAZ
    EQUB 17, SPR_CRATE,    KIND_HAZ
    EQUB 29, SPR_TPU,      KIND_HAZ

    \ Lane 1
    EQUB 1
    EQUB 30, 5
    EQUB 2
    EQUB 16, SPR_CRATE,    KIND_HAZ
    EQUB 17, SPR_TPU,      KIND_HAZ

    \ Lane 2
    EQUB 1
    EQUB 26, 4
    EQUB 1
    EQUB 16, SPR_TPU,      KIND_HAZ

    \ Lane 3 - the summit, and the chair
    EQUB 0
    EQUB 3
    EQUB 16, SPR_CRATE,    KIND_HAZ
    EQUB 19, SPR_CHAIR,    KIND_BONUS
    EQUB 29, SPR_TPU,      KIND_HAZ
    EQUB 3
    EQUB 0, MV_HOP,    5, 5, 5, SPR_LEAVER, 3
    EQUB 2, MV_HOP,    6, 6, 6, SPR_LEAVER, 4
    EQUB 3, MV_HOP,    5, 5, 5, SPR_LEAVER, 3


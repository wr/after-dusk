; Effect 14: Fish! An aquarium: fish, a crab, seaweed, bubbles and jellyfish
; over a sea floor (the randomizer wipes first).
;
; Its code, art and floor all live in FX2, behind the code. init copies the
; art into page 2, which Fish! never shows, and the floor into FXRAM, builds
; the tables the drawing needs, and draws the floor across the bottom of
; page 1. So far that is all: the step does nothing yet.

.include "config.inc"

.export fish_init, fish_step
.export FISH_BG, FISH_FLOOR, FISH_SHT, FISH_REV, FLOOR_TOP

.import aux_fetch, row_lo, row_hi
.import __FISHART_LOAD__, __FISHART_RUN__, __FISHART_SIZE__
.import __FISHFLOOR_LOAD__, __FISHFLOOR_RUN__, __FISHFLOOR_SIZE__

FLOOR_TOP   = 156               ; the floor is the bottom 36 rows
FLOOR_BYTES = (192 - FLOOR_TOP) * 40

; The memory map in config.inc, held to what the linker and the art need.
.assert __FISHART_RUN__ = FISH_ART, lderror, "FISHRAM must start at FISH_ART"
.assert __FISHFLOOR_RUN__ = FISH_FLOOR, lderror, "FLOORRAM must start at FISH_FLOOR"
.assert FISH_BG + FLOOR_BYTES <= FISH_REV, error, "FISH_BG runs into FISH_REV"
.assert FISH_REV + 128 <= FISH_FLOOR, error, "FISH_REV runs into FISH_FLOOR"
.assert FISH_FLOOR + $0600 <= FISH_SHT, error, "FISH_FLOOR's copy runs into FISH_SHT"
.assert FISH_SHT + 7 * 256 <= FISH_STATE, error, "FISH_SHT runs into FISH_STATE"

; ---- zero page ----
SRC   = FXZ             ; 2
DST   = FXZ+2           ; 2
LO    = FXZ+4           ; a value being shifted, low and high
HI    = FXZ+5
K     = FXZ+6           ; shift, 0-6

.segment "FX14"
        jmp fish_init           ; the overlay's entry points
        jmp fish_step

; ================================================================ init
fish_init:
        lda #<__FISHART_LOAD__  ; the art, from FX2 into page 2
        sta LSRC
        lda #>__FISHART_LOAD__
        sta LSRC+1
        lda #<__FISHART_RUN__
        sta LDST
        lda #>__FISHART_RUN__
        sta LDST+1
        ldx #>(__FISHART_SIZE__ + 255)  ; whole pages, never 0
        jsr aux_fetch
        lda #<__FISHFLOOR_LOAD__        ; the floor, into FXRAM
        sta LSRC
        lda #>__FISHFLOOR_LOAD__
        sta LSRC+1
        lda #<__FISHFLOOR_RUN__
        sta LDST
        lda #>__FISHFLOOR_RUN__
        sta LDST+1
        ldx #>(__FISHFLOOR_SIZE__ + 255)
        jsr aux_fetch
        jsr make_sht
        jsr make_rev
        jsr floor_to_bg
        jmp bg_to_screen

; ================================================================ step
fish_step:
        rts

; ================================================================ set-up
; make_sht: FISH_SHT page k holds, for a byte b of 7 dots shifted k dots
; right on the screen (left in the byte), the dots that stay in this byte,
; (b << k) & $7F, at entry b, and the dots that spill into the next byte,
; b >> (7 - k), at entry 128 + b.
make_sht:
        stz DST
        lda #>FISH_SHT
        sta DST+1
        stz K
@page:  ldy #127
@b:     sty LO                  ; HI:LO = b << k
        stz HI
        ldx K
        beq @put
@shl:   asl LO
        rol HI
        dex
        bne @shl
@put:   lda LO
        and #$7F
        sta (DST),y             ; entry b: the dots that stay
        asl LO                  ; HI = (b << k) >> 7
        rol HI
        tya
        ora #$80
        tay
        lda HI
        sta (DST),y             ; entry 128 + b: the dots that spill
        tya
        and #$7F
        tay
        dey
        bpl @b
        inc DST+1
        inc K
        lda K
        cmp #7
        bne @page
        rts

; make_rev: FISH_REV entry b is b's 7 dots in the opposite order, for drawing
; a creature facing left.
make_rev:
        ldx #127
@b:     txa
        ldy #7
@bit:   lsr a                   ; b's dots from the left, each pushed in at
        rol LO                  ; LO's left, so the first ends up rightmost
        dey
        bne @bit
        lda LO
        and #$7F
        sta FISH_REV,x
        dex
        bpl @b
        rts

; floor_to_bg: the live background starts as the floor alone.
floor_to_bg:
        ldx #0
@copy:
.repeat FLOOR_BYTES / 256, p
        lda FISH_FLOOR + p * 256,x
        sta FISH_BG + p * 256,x
.endrepeat
        cpx #<FLOOR_BYTES       ; the last, partial page
        bcs :+
        lda FISH_FLOOR + (FLOOR_BYTES & $FF00),x
        sta FISH_BG + (FLOOR_BYTES & $FF00),x
:       inx
        bne @copy
        rts

; bg_to_screen: draw FISH_BG on page 1, rows FLOOR_TOP-191.
bg_to_screen:
        lda #<FISH_BG
        sta SRC
        lda #>FISH_BG
        sta SRC+1
        ldx #FLOOR_TOP
@row:   lda row_lo,x
        sta DST
        lda row_hi,x
        sta DST+1
        ldy #39
:       lda (SRC),y
        sta (DST),y
        dey
        bpl :-
        lda SRC
        clc
        adc #40
        sta SRC
        bcc :+
        inc SRC+1
:       inx
        cpx #192
        bne @row
        rts

; The art's tables, frames and floor (generated). Last: it changes segments.
.include "fish_art.inc"

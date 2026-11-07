; Effect 14: Fish! An aquarium: fish, a crab, seaweed, bubbles and jellyfish
; over a sea floor (the randomizer wipes first).
;
; Its code, art and floor all live in FX2, behind the code. init copies the
; art into page 2, which Fish! never shows, and after it the drawing code
; that doesn't fit the overlay (FISHCODE); copies the floor into FXRAM;
; builds the tables the drawing needs; and draws the floor across the bottom
; of page 1. The row renderer (fish_draw.inc) draws creatures from the state
; arrays; nothing moves them yet, and the step does nothing.

.include "config.inc"

.export fish_init, fish_step
.export FISH_BG, FISH_FLOOR, FISH_SHT, FISH_REV, FISH_IREV, FLOOR_TOP
.export fish_n, fish_kind, fish_frame, fish_dir, fish_xl, fish_xh, fish_yl, fish_yh
.export FISH_MAX, fish_box, fish_rect_begin, fish_rect_rows, fish_bg_rect
.export FR_C0, FR_C1, FR_R0, FR_R1, FR_ROW, FR_LEFT, FR_ZP_END, FISH_RD_END
.export FC_CALL, FC_EVENT, FC_EVPER, FC_SETUP, FC_PATCH, FC_SWITCH, FC_EMPTY
.export FC_SEA_N, FC_SEA_M, FC_FLR_N, FC_FLR_M, FC_MIX, FC_MIXPER, FC_MIXNP
.export FC_BEGIN, FC_BEGPER, FC_BEGFAR, FC_BGROW, FC_BGWEED, FC_BGWROW

.import aux_fetch, vbl_poll, row_lo, row_hi, xbyte_lo, xbyte_hi, xmod_lo, xmod_hi
.import __FISHART_LOAD__, __FISHART_RUN__, __FISHART_SIZE__
.import __FISHFLOOR_LOAD__, __FISHFLOOR_RUN__, __FISHFLOOR_SIZE__
.import __FISHCODE_LOAD__, __FISHCODE_RUN__, __FISHCODE_SIZE__

FLOOR_TOP   = 156               ; the floor is the bottom 36 rows
FLOOR_BYTES = (192 - FLOOR_TOP) * 40

; The memory map in config.inc, held to what the linker and the art need.
.assert __FISHART_RUN__ = FISH_ART, lderror, "FISHRAM must start at FISH_ART"
.assert __FISHFLOOR_RUN__ = FISH_FLOOR, lderror, "FLOORRAM must start at FISH_FLOOR"
.assert __FISHCODE_RUN__ = FISH_CODE, lderror, "FISHCODEMEM must start at FISH_CODE"
.assert __FISHART_RUN__ + __FISHART_SIZE__ <= FISH_BLKB, lderror, "the art runs into block B"
.assert FISH_BG + FLOOR_BYTES <= FISH_REV, error, "FISH_BG runs into FISH_REV"
.assert FISH_REV + 128 <= FISH_IREV, error, "FISH_REV runs into FISH_IREV"
.assert FISH_IREV + 128 <= FISH_FLOOR, error, "FISH_IREV runs into FISH_FLOOR"
.assert (FISH_REV & $7F) = 0 && (FISH_IREV & $7F) = 0, error, "REV and IREV must start on a half page"
.assert FISH_FLOOR + $0600 <= FISH_SHT, error, "FISH_FLOOR's copy runs into FISH_SHT"
.assert FISH_SHT + 7 * 256 <= FISH_STATE, error, "FISH_SHT runs into FISH_STATE"

; ---- zero page ----
SRC   = FXZ             ; 2
DST   = FXZ+2           ; 2
LO    = FXZ+4           ; a value being shifted, low and high
HI    = FXZ+5
K     = FXZ+6           ; shift, 0-6

; ---- creature state (FISH_STATE): slot i is entry i of each array ----
fish_n     = FISH_STATE         ; slots in use
fish_kind  = FISH_STATE + 1     ; 10 bytes each
fish_frame = FISH_STATE + 11    ; 0 or 1
fish_dir   = FISH_STATE + 21    ; 0 heading right, 1 left
fish_xl    = FISH_STATE + 31    ; x: the cell's left dot, signed 16-bit
fish_xh    = FISH_STATE + 41
fish_yl    = FISH_STATE + 51    ; y: the cell's top row, signed 16-bit
fish_yh    = FISH_STATE + 61

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
        lda #<__FISHCODE_LOAD__         ; the drawing code, after it
        sta LSRC
        lda #>__FISHCODE_LOAD__
        sta LSRC+1
        lda #<__FISHCODE_RUN__
        sta LDST
        lda #>__FISHCODE_RUN__
        sta LDST+1
        ldx #>(__FISHCODE_SIZE__ + 255)
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
        jsr fish_draw_init
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
; a creature facing left; FISH_IREV is the same with the dots inverted.
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
        eor #$7F
        sta FISH_IREV,x
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

; ================================================================ drawing
.include "fish_draw.inc"

; The art's tables, frames and floor (generated). Last: it changes segments.
.include "fish_art.inc"

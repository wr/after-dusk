; Effect 7: String Theory, after the original. Two ribbons of straight
; strings, each string joining two points on the screen's edge roughly across
; the screen from each other. A ribbon has a position s on the edge (940 dots
; round, clockwise from the top-left corner), a speed v (0.375-1 dots a step,
; drifting) and a phase ph: its newest string runs from s to s + 940 (0.5 +
; 0.17 sin ph). Each ribbon keeps its last 56 strings. Every step first rubs
; out each ribbon's oldest string, then draws each ribbon's newest, solid
; (dots are set or cleared, never flipped), so a ribbon stays still where it
; isn't moving; only where strings cross do a few dots go missing.
;
; Strings are drawn by a line routine of its own, unrolled for each dot
; position in a byte: four strings up to a screen wide or tall a step must fit
; 5 ticks. Drawn straight onto page 1.

.include "config.inc"

.export fx_strings_init, fx_strings_step, str_line
.export str_xal, str_xah, str_ya, str_xcl, str_xch, str_yc
.export str_sf, str_sl, str_sh, str_vl, str_vh, str_pl, str_ph, str_head, str_count
.export str_lx0, str_ly0, str_lx1, str_ly1, str_mode

.import rng_next, rng_below, show_page1, vbl_poll
.import row_lo, row_hi, xbyte_lo, xbit_lo, xmod_lo, xbyte_hi, xmod_hi

NRIB    = 2                     ; ribbons
KEEP    = 56                    ; strings kept per ribbon
RING    = 64                    ; ring slots per ribbon
PERIM   = 2 * (279 + 191)       ; the screen's edge: 940 dots round
HALF    = PERIM / 2
V_MIN   = 96                    ; slowest, 8.8: 0.375 dots a step (fastest 1.0, $0100)
PH_STEP = 52                    ; phase a step, 65536 = a full turn (0.005 radians)

; ---- state in FXRAM ----
str_xal   = FXRAM               ; strings, slot = ribbon * 64 + ring index:
str_xah   = str_xal + 128       ;   near end x (lo, hi), y
str_ya    = str_xah + 128
str_xcl   = str_ya + 128        ;   far end x (lo, hi), y
str_xch   = str_xcl + 128
str_yc    = str_xch + 128
str_sf    = str_yc + 128        ; per ribbon: s, fraction
str_sl    = str_sf + NRIB       ;   s, whole dots (0-939)
str_sh    = str_sl + NRIB
str_vl    = str_sh + NRIB       ;   v, 8.8
str_vh    = str_vl + NRIB
str_pl    = str_vh + NRIB       ;   phase, 65536 = a full turn
str_ph    = str_pl + NRIB
str_head  = str_ph + NRIB       ;   ring slot the next string goes in
str_count = str_head + NRIB     ;   strings kept

; ---- zero page ----
LX0     = FXZ                   ; line: one end x (2), y; the other end x (2), y
LY0     = FXZ+2                 ; (edge writes these at offset 0 or 3)
LX1     = FXZ+3
LY1     = FXZ+5
LMODE   = FXZ+6                 ; 0 rub out, 1 draw
LW      = FXZ+7                 ; dx (0-255)
LH      = FXZ+8                 ; |dy|
LE      = FXZ+9                 ; error
LCNT    = FXZ+10                ; wide: bytes still to enter; tall: dots left
LTC     = FXZ+11                ; wide, last byte: dots left
LMSK    = FXZ+12                ; ... and the next dot's mask
LSM     = FXZ+13                ; row step less one: 0 down, $FE up
LPTR    = FXZ+14                ; 2: row address
LVEC    = FXZ+16                ; 2: where the unrolled drawing starts
LK      = FXZ+18                ; first dot's bit
LFB     = FXZ+19                ; first dot's byte
LMX     = FXZ+20                ; 2: split: middle x, y
LMY     = FXZ+22
LXE     = FXZ+23                ; 2: split: far end x, y
LYE     = FXZ+25
G       = FXZ+26                ; ribbon
T0      = FXZ+27
T1      = FXZ+28
T2      = FXZ+29
T3      = FXZ+30
DL      = FXZ+31                ; 2: d, how far round the far end is
EPL     = FXZ+33                ; 2: a position on the edge, for edge
EPH     = FXZ+34

str_lx0  = LX0
str_ly0  = LY0
str_lx1  = LX1
str_ly1  = LY1
str_mode = LMODE

.segment "FX7"
        jmp fx_strings_init        ; the overlay's entry points
        jmp fx_strings_step

; ================================================================ init
fx_strings_init:
        jsr show_page1
        ldx #NRIB - 1
@rib:   stx G
@s:     jsr rng_next            ; s: anywhere round the edge
        and #3
        sta T0
        jsr rng_next
        cmp #<PERIM
        tay
        lda T0
        sbc #>PERIM
        bcs @s
        ldx G
        tya
        sta str_sl,x
        lda T0
        sta str_sh,x
        jsr rng_next
        sta str_sf,x
        lda #112                ; v: 0.44-0.875 dots a step
        jsr rng_below
        clc
        adc #113
        ldx G
        sta str_vl,x
        stz str_vh,x
        jsr rng_next            ; phase: anywhere
        sta str_pl,x
        jsr rng_next
        sta str_ph,x
        stz str_head,x
        stz str_count,x
        dex
        bpl @rib
        rts

; ================================================================ step
fx_strings_step:
        ldx #0                  ; first each full ribbon's oldest string goes,
@rub:   lda str_count,x         ; so the newest are always drawn whole
        cmp #KEEP
        bcc :+
        stx G
        jsr rub_oldest
        ldx G
:       inx
        cpx #NRIB
        bcc @rub
        ldx #0                  ; then each ribbon moves on and draws its newest
@new:   stx G
        jsr move
        jsr add_string
        ldx G
        inx
        cpx #NRIB
        bcc @new
        rts

; rub_oldest: rub out ribbon X's oldest string.
rub_oldest:
        lda str_head,x
        sec
        sbc str_count,x
        jsr slot
        lda str_xal,y
        sta LX0
        lda str_xah,y
        sta LX0+1
        lda str_ya,y
        sta LY0
        lda str_xcl,y
        sta LX1
        lda str_xch,y
        sta LX1+1
        lda str_yc,y
        sta LY1
        stz LMODE
        dec str_count,x
        jmp str_line

; slot: Y = ribbon X's slot for ring index A. Keeps X.
slot:   and #RING - 1
        cpx #0
        beq :+
        ora #RING
:       tay
        rts

; move: ribbon X's speed drifts, it moves on, its phase turns.
move:
        lda #7                  ; v += -3..3 (of 256): about +/-0.0125
        jsr rng_below
        ldx G
        ldy #0
        sec
        sbc #3
        bcs :+
        dey
:       clc
        adc str_vl,x
        sta str_vl,x
        tya
        adc str_vh,x
        sta str_vh,x
        beq @slow               ; within 0.375-1.0
        stz str_vl,x            ; 1.0 or more: 1.0
        bra @go
@slow:  lda str_vl,x
        cmp #V_MIN
        bcs @go
        lda #V_MIN
        sta str_vl,x
@go:    clc                     ; s += v
        lda str_sf,x
        adc str_vl,x
        sta str_sf,x
        lda str_sl,x
        adc str_vh,x
        sta str_sl,x
        bcc :+
        inc str_sh,x
:       sec                     ; past the last position: round again
        lda str_sl,x
        sbc #<PERIM
        tay
        lda str_sh,x
        sbc #>PERIM
        bcc :+
        sta str_sh,x
        tya
        sta str_sl,x
:       clc                     ; the phase turns
        lda str_pl,x
        adc #PH_STEP
        sta str_pl,x
        bcc :+
        inc str_ph,x
:       rts

; add_string: ribbon X's newest string, from s to s + d, kept and drawn.
add_string:
        lda str_pl,x            ; d = 470 +/- 159.8 sin ph: the table's entry for
        sta T0                  ; the phase's high byte, plus the way to the next
        ldy str_ph,x            ; entry times the low byte (rounded)
        stz T2
        lda str_amp+1,y
        sec
        sbc str_amp,y           ; -4..4
        beq @plus
        sta T3
        bpl :+
        eor #$FF
        inc a
:       tax
        lda #$80
@mul:   clc
        adc T0
        bcc :+
        inc T2
:       dex
        bne @mul
        lda T3
        bpl @plus
        lda str_amp,y
        sec
        sbc T2
        bra @swing
@plus:  lda str_amp,y
        clc
        adc T2
@swing: sta T1                  ; 0-160
        cpy #128                ; the first half turn adds, the second takes away
        bcs @minus
        clc
        lda #<HALF
        adc T1
        sta DL
        lda #>HALF
        adc #0
        sta DL+1
        bra @ends
@minus: sec
        lda #<HALF
        sbc T1
        sta DL
        lda #>HALF
        sbc #0
        sta DL+1
@ends:  ldx G                   ; near end at s
        lda str_sl,x
        sta EPL
        lda str_sh,x
        sta EPH
        ldx #0
        jsr edge
        clc                     ; far end at s + d
        lda EPL
        adc DL
        sta EPL
        lda EPH
        adc DL+1
        sta EPH
        sec
        lda EPL
        sbc #<PERIM
        tay
        lda EPH
        sbc #>PERIM
        bcc :+
        sta EPH
        sty EPL
:       ldx #3
        jsr edge
        ldx G                   ; keep it
        lda str_head,x
        jsr slot
        lda LX0
        sta str_xal,y
        lda LX0+1
        sta str_xah,y
        lda LY0
        sta str_ya,y
        lda LX1
        sta str_xcl,y
        lda LX1+1
        sta str_xch,y
        lda LY1
        sta str_yc,y
        lda str_head,x
        inc a
        and #RING - 1
        sta str_head,x
        inc str_count,x
        lda #1                  ; and draw it
        sta LMODE
        jmp str_line

; edge: the point EPL/EPH (0-939) dots clockwise round the screen's edge
; from the top-left corner (the sample's edgePt), into LX0/LY0 (X = 0) or
; LX1/LY1 (X = 3).
edge:
        lda EPL
        cmp #<279
        lda EPH
        sbc #>279
        bcs @right
        lda EPL                 ; top: (p, 0)
        sta LX0,x
        lda EPH
        sta LX0+1,x
        stz LY0,x
        rts
@right: lda EPL
        cmp #<470
        lda EPH
        sbc #>470
        bcs @bottom
        lda #<279               ; right: (279, p - 279)
        sta LX0,x
        lda #>279
        sta LX0+1,x
        lda EPL
        sec
        sbc #<279
        sta LY0,x
        rts
@bottom:
        lda EPL
        cmp #<749
        lda EPH
        sbc #>749
        bcs @left
        sec                     ; bottom: (749 - p, 191)
        lda #<749
        sbc EPL
        sta LX0,x
        lda #>749
        sbc EPH
        sta LX0+1,x
        lda #191
        sta LY0,x
        rts
@left:  stz LX0,x               ; left: (0, 940 - p)
        stz LX0+1,x
        sec
        lda #<PERIM
        sbc EPL
        sta LY0,x
        rts

; ================================================================ str_line
; A string from (LX0, LY0) to (LX1, LY1), x 0-279, y 0-191, wholly on page
; 1, in LMODE (0 rub out, 1 draw). Bresenham, always left to right, so a
; string and its reverse cover the same dots. More than 255 dots across, it
; is two halves meeting at (within half a dot of) its middle. About 25 cycles
; a dot plus 28 a row change when wider than tall, 56 a dot when taller.
; Counts vertical blanks after each half; no half takes 13,000 cycles.
; Leaves LX0-LY1 changed.
str_line:
        lda LX1                 ; left to right
        cmp LX0
        lda LX1+1
        sbc LX0+1
        bcs @ordered
        ldx LX0
        lda LX1
        sta LX0
        stx LX1
        ldx LX0+1
        lda LX1+1
        sta LX0+1
        stx LX1+1
        ldx LY0
        lda LY1
        sta LY0
        stx LY1
@ordered:
        sec                     ; more than 255 dots across?
        lda LX1
        sbc LX0
        sta LMX
        lda LX1+1
        sbc LX0+1
        bne @split
        jsr segment
        jmp vbl_poll
@split: lsr a                   ; the middle: x0 + dx/2 ...
        ror LMX
        clc
        lda LMX
        adc LX0
        sta LMX
        lda LX0+1
        adc #0
        sta LMX+1
        lda LY1                 ; ... and y0 +/- |dy|/2
        sec
        sbc LY0
        bcc @up
        lsr a
        clc
        adc LY0
        bra @ym
@up:    eor #$FF
        inc a
        lsr a
        eor #$FF
        sec
        adc LY0
@ym:    sta LMY
        lda LX1                 ; first half, to the middle
        sta LXE
        lda LX1+1
        sta LXE+1
        lda LY1
        sta LYE
        lda LMX
        sta LX1
        lda LMX+1
        sta LX1+1
        lda LMY
        sta LY1
        jsr segment
        jsr vbl_poll
        lda LMX                 ; second half, from the middle
        sta LX0
        lda LMX+1
        sta LX0+1
        lda LMY
        sta LY0
        lda LXE
        sta LX1
        lda LXE+1
        sta LX1+1
        lda LYE
        sta LY1
        jsr segment
        jmp vbl_poll

; segment: (LX0, LY0) to (LX1, LY1), LX0 <= LX1 <= LX0 + 255.
segment:
        sec
        lda LX1
        sbc LX0
        sta LW
        ldx #0                  ; |dy| and its direction
        lda LY1
        sec
        sbc LY0
        bcs :+
        eor #$FF
        inc a
        ldx #$FE
:       sta LH
        stx LSM
        ldx LX0                 ; the first dot's byte and bit...
        lda LX0+1
        bne :+
        ldy xbyte_lo,x
        lda xmod_lo,x
        bra :++
:       ldy xbyte_hi,x
        lda xmod_hi,x
:       sta LK
        sty LFB
        ldx LY0                 ; ...and row
        lda row_lo,x
        sta LPTR
        lda row_hi,x
        sta LPTR+1
        lda LW
        cmp LH
        bcc @tall
        lsr a                   ; wider than tall: err = dx / 2
        sta LE
        ldx LX1                 ; the last dot's bit and byte
        lda LX1+1
        bne :+
        lda xmod_lo,x
        sta LTC
        lda xbyte_lo,x
        bra :++
:       lda xmod_hi,x
        sta LTC
        lda xbyte_hi,x
:       sec
        sbc LFB
        sta LCNT                ; bytes after the first
        bne @wide
        ldx LK                  ; all in one byte: a dot at a time
        lda xbit_lo,x
        sta LMSK
        lda LW
        inc a
        sta LTC
        ldx LY0
        sec
        jmp xtail
@wide:  inc LTC                 ; the last byte's dots, from its first
        lda #1
        sta LMSK
        lda LMODE               ; variant: mode, +2 taller than wide
        bra @go
@tall:  lda LH                 ; taller than wide: err = dy / 2, dy + 1 dots
        lsr a
        sta LE
        lda LH
        inc a
        sta LCNT
        lda LMODE
        ora #2
@go:    tax
        lda times7,x
        clc
        adc LK
        tax
        lda entry_lo,x
        sta LVEC
        lda entry_hi,x
        sta LVEC+1
        ldx LY0
        sec
        jmp (LVEC)

times7: .byte 0, 7, 14, 21

; Unrolled drawing, one block per dot position in a byte. Throughout: X =
; row, Y = byte, (LPTR) = row address, carry set (the error's below-zero
; flag; every path leaves it set).

; the next row up or down: X + LSM + 1
.macro ROWSTEP
        txa
        adc LSM
        tax
        sec
.endmacro

; wider than tall: a dot right each time, a row up or down when the error
; says; the last byte goes to xtail.
.macro XRUN pre, mode
  .repeat 7, K
.ident(.sprintf("%s%d", pre, K)):
        lda (LPTR),y
    .if mode
        ora #(1 << K)
    .else
        and #($7F ^ (1 << K))
    .endif
        sta (LPTR),y
        lda LE                  ; err -= dy; below zero: err += dx, next row
        sbc LH
        sta LE
    .if K < 6
        bcs .ident(.sprintf("%s%d", pre, K + 1))
    .else
        bcs .ident(.sprintf("%sa", pre))
    .endif
        adc LW
        sta LE
        ROWSTEP
        lda row_lo,x
        sta LPTR
        lda row_hi,x
        sta LPTR+1
  .endrepeat
.ident(.sprintf("%sa", pre)):
        iny                     ; the next byte
        dec LCNT
        beq :+
        jmp .ident(.sprintf("%s0", pre))
:       jmp xtail
.endmacro

; taller than wide: a row up or down each time, a dot right when the error
; says.
.macro YRUN pre, mode
  .repeat 7, K
.ident(.sprintf("%s%d", pre, K)):
        lda (LPTR),y
    .if mode
        ora #(1 << K)
    .else
        and #($7F ^ (1 << K))
    .endif
        sta (LPTR),y
        dec LCNT
        bne :+
        rts
:
        ROWSTEP
        lda row_lo,x
        sta LPTR
        lda row_hi,x
        sta LPTR+1
        lda LE                  ; err -= dx; below zero: err += dy, a dot right
        sbc LW
        sta LE
        bcs .ident(.sprintf("%s%d", pre, K))
        adc LH
        sta LE
    .if K = 6
        iny
        jmp .ident(.sprintf("%s0", pre))
    .endif
  .endrepeat
.endmacro

        XRUN "xc", 0
        XRUN "xs", 1
        YRUN "yc", 0
        YRUN "ys", 1

; where each variant starts, for each first dot's bit: variant * 7 + bit,
; variant = taller * 2 + mode
.macro ENTLO pre
  .repeat 7, K
        .byte <.ident(.sprintf("%s%d", pre, K))
  .endrepeat
.endmacro
.macro ENTHI pre
  .repeat 7, K
        .byte >.ident(.sprintf("%s%d", pre, K))
  .endrepeat
.endmacro
entry_lo:
        ENTLO "xc"
        ENTLO "xs"
        ENTLO "yc"
        ENTLO "ys"
entry_hi:
        ENTHI "xc"
        ENTHI "xs"
        ENTHI "yc"
        ENTHI "ys"

; xtail: the last byte of a wider-than-tall line, a dot at a time from
; LMSK, LTC dots, in LMODE.
xtail:
@dot:   lda LMODE
        beq @clr
        lda (LPTR),y
        ora LMSK
        bra @put
@clr:   lda LMSK
        eor #$7F
        and (LPTR),y
@put:   sta (LPTR),y
        dec LTC
        beq @done
        asl LMSK
        sec                     ; err -= dy; below zero: err += dx, next row
        lda LE
        sbc LH
        sta LE
        bcs @dot
        adc LW
        sta LE
        ROWSTEP
        lda row_lo,x
        sta LPTR
        lda row_hi,x
        sta LPTR+1
        bra @dot
@done:  rts

.include "strings_tables.inc"

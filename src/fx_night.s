; Effect 6: Nightlines, after the original (Shape: Line, Symmetry: Both,
; Persistence 20). One line between two ends, A and B, drawn four times: as it
; is and mirrored left-right (x -> 279 - x) and top-bottom (y -> 191 - y). Each
; end starts near the middle of the screen with a random direction and a speed
; of 2.5-4.5 dots a step (its x part stretched 1.1 for the IIc's dot shape) and
; keeps that velocity, going straight on; where it would cross an edge of the
; screen it is put back on the edge and that part of its speed turns round.
; Each line lies a few dots from the last, so they fan out into bundles of
; parallel lines that sweep into curved envelopes. The last 20 generations
; stay on screen; each step the oldest is rubbed out first and the newest
; drawn whole after it. Drawn straight onto page 1.
;
; One routine draws all four copies of a line at once, walking the line and
; setting (or clearing) each dot and its three mirror images. That makes the
; picture exactly symmetric (four separate lines drawn left to right would
; differ by a dot here and there) and costs about half of what four separate
; lines would: a step rubbing out and drawing lines from corner to corner of
; the screen still fits its 5 ticks.

.include "config.inc"

.export fx_night_init, fx_night_step, quad_line
.export nl_q, nl_a, nl_gaxl, nl_gaxh, nl_gay, nl_gbxl, nl_gbxh, nl_gby, nl_head, nl_count

.import rng_next, rng_below, show_page1, vbl_poll
.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi

KEEP    = 20                    ; generations kept
XMAX    = 279                   ; the screen's last column...
YMAX    = 191                   ; ...and row
SPD_MIN = 81                    ; speed in 1/32 dots a step: 2.53-4.47
SPD_N   = 63                    ;   (81 + 0..62)
XSTRETCH = 26                   ; x speeds times 1 + 26/256 (1.1)

; ---- state in FXRAM ----
nl_rblo  = FXRAM                ; 192: the row 191 - y, for each y
nl_rbhi  = nl_rblo + 192
nl_gaxl  = nl_rbhi + 192        ; generation ring, KEEP each: the ends' dots
nl_gaxh  = nl_gaxl + KEEP       ; as drawn (A's x low and high, A's y, then
nl_gay   = nl_gaxh + KEEP       ; B's likewise)
nl_gbxl  = nl_gay + KEEP
nl_gbxh  = nl_gbxl + KEEP
nl_gby   = nl_gbxh + KEEP
nl_head  = nl_gby + KEEP        ; the slot the next generation goes in
nl_count = nl_head + 1          ; generations kept
nl_a     = nl_count + 1         ; 10 an end, A then B. Per axis (x at +0, y at
                                ; +5): position in dots with 8 fraction bits
                                ; (3 bytes, 0 to 279.0 or 191.0), then the
                                ; speed, signed 8.8

; ---- zero page ----
nl_q  = FXZ                     ; quad_line's line: x0 (2), y0, x1 (2), y1, mode
QX0   = nl_q
QY0   = nl_q+2
QX1   = nl_q+3
QY1   = nl_q+5
QCOL  = nl_q+6                  ; 0 clear, 1 set
PT    = FXZ+7                   ; 2: the row in the top half
PB    = FXZ+9                   ; 2: its mirror in the bottom half
BL    = FXZ+11                  ; byte of the dot...
BR    = FXZ+12                  ; ...and of its left-right mirror
ML    = FXZ+13                  ; their masks
MR    = FXZ+14
QDX   = FXZ+15                  ; dx, low byte
QDY   = FXZ+16                  ; |dy| (0-191)
QSY   = FXZ+17                  ; 1 or $FF: row direction
QERR  = FXZ+18                  ; the error, low byte
QCNT  = FXZ+19                  ; dots left in this run (0 = 256)
QMORE = FXZ+20                  ; dots after this run (lines over 256 dots)
T     = FXZ+21                  ; 3
LIMLO = FXZ+24                  ; the far edge being moved against
LIMHI = FXZ+25
EOFF  = FXZ+26                  ; the end being set up: 0 = A, 10 = B
SPD   = FXZ+27                  ; its speed, 1/32 dots a step
ANG   = FXZ+28                  ; its direction, 256 a turn
NEG   = FXZ+29                  ; bit 7: the speed being made is negative
MUL   = FXZ+30
P     = FXZ+31                  ; 2: a product

.segment "FX6"
        jmp fx_night_init        ; the overlay's entry points
        jmp fx_night_step

; ================================================================ init
fx_night_init:
        jsr show_page1
        ldx #0                  ; rows, mirrored top-bottom
        ldy #YMAX
:       lda row_lo,y
        sta nl_rblo,x
        lda row_hi,y
        sta nl_rbhi,x
        dey
        inx
        cpx #YMAX+1
        bne :-
        stz nl_head
        stz nl_count
        ldx #0                  ; A
        jsr new_end
        ldx #10                 ; B
        ; fall through

; new_end: X = 0 for A, 10 for B. Near the middle (x 125-154, y 85-106,
; and a random fraction), heading in a random direction at a random speed.
new_end:
        stx EOFF
        jsr rng_next            ; x
        sta nl_a,x
        lda #30
        jsr rng_below
        clc
        adc #125
        ldx EOFF
        sta nl_a+1,x
        stz nl_a+2,x
        jsr rng_next            ; y
        sta nl_a+5,x
        lda #22
        jsr rng_below
        clc
        adc #85
        ldx EOFF
        sta nl_a+6,x
        stz nl_a+7,x
        lda #SPD_N              ; speed
        jsr rng_below
        clc
        adc #SPD_MIN
        sta SPD
        jsr rng_next            ; direction
        sta ANG
        jsr trig                ; vy = speed sin(direction)
        ldy SPD
        jsr scale
        ldx EOFF
        lda P
        sta nl_a+8,x
        lda P+1
        sta nl_a+9,x
        lda SPD                 ; x speed stretched: SPD (1 + 26/256), rounded
        ldy #XSTRETCH
        jsr mul8
        lda P
        cmp #$80
        lda P+1
        adc SPD
        sta SPD
        lda ANG                 ; vx = that cos(direction)
        clc
        adc #64
        jsr trig
        ldy SPD
        jsr scale
        ldx EOFF
        lda P
        sta nl_a+3,x
        lda P+1
        sta nl_a+4,x
        rts

; trig: A = an angle, 256 a turn. Returns A = |sin| (256 = 1, at most 255)
; and carry set when sin is negative. Angles sit half a step off the axes,
; so neither part of a direction is ever 0.
trig:   sta T
        and #$3F
        bit T                   ; second or fourth quarter: count back
        bvc :+
        eor #$3F
:       tay
        lda T                   ; second half: negative
        asl a
        lda sines,y
        rts

; scale: P = A Y / 32, negated when carry is set.
scale:  ror NEG
        jsr mul8
        ldx #5
:       lsr P+1
        ror P
        dex
        bne :-
        bit NEG
        bpl :+
        sec
        lda #0
        sbc P
        sta P
        lda #0
        sbc P+1
        sta P+1
:       rts

; mul8: P = A Y, unsigned.
mul8:   sty MUL
        sta P
        lda #0
        ldx #8
        lsr P
@l:     bcc :+
        clc
        adc MUL
:       ror a
        ror P
        dex
        bne @l
        sta P+1
        rts

; |sin| at (i + 1/2) / 256 of a turn, i = 0-63: 256 sin, at most 255
sines:  .byte   3,   9,  16,  22,  28,  34,  41,  47,  53,  59,  65,  71,  77,  83,  89,  95
        .byte 101, 107, 112, 118, 123, 129, 134, 140, 145, 150, 155, 160, 165, 170, 174, 179
        .byte 183, 188, 192, 196, 200, 204, 207, 211, 215, 218, 221, 224, 227, 230, 233, 235
        .byte 238, 240, 242, 244, 246, 248, 249, 250, 252, 253, 254, 254, 255, 255, 255, 255

; ================================================================ step
fx_night_step:
        lda nl_count            ; all 20 kept: the oldest goes first, so the
        cmp #KEEP               ; newest is always drawn whole
        bcc @move
        ldx nl_head
        jsr load_gen
        stz QCOL
        jsr quad_line
        jsr vbl_poll
@move:  ldx #0                  ; A
        jsr move_x
        ldx #5
        jsr move_y
        ldx #10                 ; B
        jsr move_x
        ldx #15
        jsr move_y
        ldx #0                  ; the newest, at the ends' nearest dots
        jsr whole
        ldx nl_head
        sta nl_gaxl,x
        tya
        sta nl_gaxh,x
        ldx #5
        jsr whole
        ldx nl_head
        sta nl_gay,x
        ldx #10
        jsr whole
        ldx nl_head
        sta nl_gbxl,x
        tya
        sta nl_gbxh,x
        ldx #15
        jsr whole
        ldx nl_head
        sta nl_gby,x
        jsr load_gen
        lda #1
        sta QCOL
        jsr quad_line
        inc nl_head             ; round the ring
        lda nl_head
        cmp #KEEP
        bcc :+
        stz nl_head
:       lda nl_count
        cmp #KEEP
        bcs :+
        inc nl_count
:       rts

; load_gen: generation X into quad_line's line.
load_gen:
        lda nl_gaxl,x
        sta QX0
        lda nl_gaxh,x
        sta QX0+1
        lda nl_gay,x
        sta QY0
        lda nl_gbxl,x
        sta QX1
        lda nl_gbxh,x
        sta QX1+1
        lda nl_gby,x
        sta QY1
        rts

; whole: the position at X in nl_a, to the nearest dot: A = low byte, Y = high.
whole:  ldy nl_a+2,x
        lda nl_a,x              ; half a dot or more rounds up
        cmp #$80
        lda nl_a+1,x
        adc #0
        bcc :+
        iny
:       rts

; ================================================================ motion
; move_x, move_y: X = the axis's offset in nl_a. p += v; past an edge, p is
; put back on the edge and v turns round.
move_x: lda #<XMAX
        ldy #>XMAX
        bra move
move_y: lda #YMAX
        ldy #0
move:   sta LIMLO
        sty LIMHI
        ldy #0                  ; v's sign, for the top byte
        lda nl_a+4,x
        bpl :+
        dey
:       sty T+2
        clc                     ; T = p + v
        lda nl_a,x
        adc nl_a+3,x
        sta T
        lda nl_a+1,x
        adc nl_a+4,x
        sta T+1
        lda nl_a+2,x
        adc T+2
        sta T+2
        bmi @low                ; below 0
        sec                     ; past the far edge: the edge - T borrows
        lda #0
        sbc T
        lda LIMLO
        sbc T+1
        lda LIMHI
        sbc T+2
        bcs @store
        stz T                   ; back on the far edge
        lda LIMLO
        sta T+1
        lda LIMHI
        sta T+2
        bra @turn
@low:   stz T                   ; back on 0
        stz T+1
        stz T+2
@turn:  sec                     ; turn round
        lda #0
        sbc nl_a+3,x
        sta nl_a+3,x
        lda #0
        sbc nl_a+4,x
        sta nl_a+4,x
@store: lda T
        sta nl_a,x
        lda T+1
        sta nl_a+1,x
        lda T+2
        sta nl_a+2,x
        rts

; ================================================================ quad_line
; quad_line: the line from (QX0, QY0) to (QX1, QY1), x 0-279, y 0-191, and
; its mirror images (279 - x, y), (x, 191 - y) and (279 - x, 191 - y), on
; page 1, in mode QCOL (0 clear, 1 set). The same dots as fline would draw
; for the first copy: left to right, both ends included, the error starting
; at half the longer side. The two ends may be swapped on return. Counts
; vertical blanks as it goes: at every byte across, and halfway down.
;
; The left-right copies share a row and their bytes mirror each other
; (x = 7 b + m sits at 279 - x = 7 (39 - b) + (6 - m)), so both masks wrap
; to the next byte on the same dot. The row is kept in X throughout.

.macro QPLOT mode
        ldy BL
  .if mode
        lda (PT),y
        ora ML
        sta (PT),y
        lda (PB),y
        ora ML
        sta (PB),y
        ldy BR
        lda (PT),y
        ora MR
        sta (PT),y
        lda (PB),y
        ora MR
        sta (PB),y
  .else
        lda ML
        eor #$7F
        and (PT),y
        sta (PT),y
        lda ML
        eor #$7F
        and (PB),y
        sta (PB),y
        ldy BR
        lda MR
        eor #$7F
        and (PT),y
        sta (PT),y
        lda MR
        eor #$7F
        and (PB),y
        sta (PB),y
  .endif
.endmacro

.macro QNEXTROW
        txa
        clc
        adc QSY
        tax
        lda row_lo,x
        sta PT
        lda row_hi,x
        sta PT+1
        lda nl_rblo,x
        sta PB
        lda nl_rbhi,x
        sta PB+1
.endmacro

; one dot right on the left copy, one left on the right copy
.macro QWRAP
        lda #1
        sta ML
        lda #$40
        sta MR
        inc BL
        dec BR
        jsr vbl_poll            ; a byte done: keep the frame count right
.endmacro

; a run of dots done: a line over 256 dots wide has more to come
.macro QDONE cont
        lda QMORE
        beq :+
        stz QMORE
        sta QCNT
        jmp cont
:       rts
.endmacro

; wider than tall, dx under 256: a dot right every time, a row when the
; error says
.macro QLINE_X mode
        .local dot, wrap, err, done
dot:    QPLOT mode
        dec QCNT
        beq done
        asl ML
        bmi wrap
        lsr MR
err:    sec                     ; err -= dy; below zero (carry clear):
        lda QERR                ; err += dx, next row
        sbc QDY
        sta QERR
        bcs dot
        adc QDX
        sta QERR
        QNEXTROW
        jmp dot
wrap:   QWRAP
        bra err
done:   rts
.endmacro

; wider than tall, dx 256 or more (dx = 256 + QDX): as QLINE_X, with the
; error's ninth bit kept by which half of the loop is running.
.macro QLINE_W mode
        .local dot0, adv0, wrap0, err0, row1, done0, dot1, adv1, wrap1, err1, done1
dot0:   QPLOT mode              ; the error under 256
        dec QCNT
        beq done0
adv0:   asl ML
        bmi wrap0
        lsr MR
err0:   sec                     ; err -= dy; below zero (carry clear):
        lda QERR                ; err += dx, next row
        sbc QDY
        sta QERR
        bcs dot0
        adc QDX
        sta QERR
        bcs row1                ; now 256 or more
        QNEXTROW
        jmp dot0
row1:   QNEXTROW
        jmp dot1
wrap0:  QWRAP
        bra err0
done0:  QDONE adv0
dot1:   QPLOT mode              ; the error 256 or more: no row this time
        dec QCNT
        beq done1
adv1:   asl ML
        bmi wrap1
        lsr MR
err1:   sec                     ; err -= dy; under 256 again (carry clear):
        lda QERR                ; back to the first half
        sbc QDY
        sta QERR
        bcs dot1
        jmp dot0
wrap1:  QWRAP
        bra err1
done1:  QDONE adv1
.endmacro

; taller than wide: a row every time, a dot right when the error says
.macro QLINE_Y mode
        .local dot, wrap, err, done
dot:    QPLOT mode
        dec QCNT
        beq done
        QNEXTROW
        cpx #96                 ; halfway down: keep the frame count right
        bne err
        jsr vbl_poll
err:    sec                     ; err -= dx; below zero (carry clear):
        lda QERR                ; err += dy, one dot right
        sbc QDX
        sta QERR
        bcs dot
        adc QDY
        sta QERR
        asl ML
        bmi wrap
        lsr MR
        jmp dot
wrap:   QWRAP
        jmp dot
done:   rts
.endmacro

quad_line:
        jsr vbl_poll
        lda QX1                 ; left to right: swap the ends if needed
        cmp QX0
        lda QX1+1
        sbc QX0+1
        bcs @ordered
        ldx QX0
        lda QX1
        sta QX0
        stx QX1
        ldx QX0+1
        lda QX1+1
        sta QX0+1
        stx QX1+1
        ldx QY0
        lda QY1
        sta QY0
        stx QY1
@ordered:
        ldx #1                  ; QDY = |dy|, QSY = its direction
        sec
        lda QY1
        sbc QY0
        bcs :+
        eor #$FF
        inc a
        ldx #$FF
:       sta QDY
        stx QSY
        ldx QX0                 ; the first dot's byte and mask, and its mirror's
        lda QX0+1
        bne :+
        lda xbyte_lo,x
        ldy xmod_lo,x
        bra :++
:       lda xbyte_hi,x
        ldy xmod_hi,x
:       sta BL
        lda #39
        sec
        sbc BL
        sta BR
        lda bits,y
        sta ML
        lda rbits,y
        sta MR
        ldx QY0                 ; its row, and the mirror row
        lda row_lo,x
        sta PT
        lda row_hi,x
        sta PT+1
        lda nl_rblo,x
        sta PB
        lda nl_rbhi,x
        sta PB+1
        stz QMORE
        sec                     ; QDX = dx
        lda QX1
        sbc QX0
        sta QDX
        lda QX1+1
        sbc QX0+1
        bne @wide               ; 256 or more
        lda QDX                 ; wider than tall, or taller?
        cmp QDY
        bcc @tall
        inc a                   ; dx + 1 dots (1-256, 0 = 256)
        sta QCNT
        lda QDX                 ; err = dx / 2
        lsr a
        sta QERR
        lda QCOL
        beq :+
        jmp ql_xs
:       jmp ql_xc
@wide:  stz QCNT                ; 256 dots, then the rest: dx + 1 - 256
        lda QDX
        inc a
        sta QMORE
        lda QDX                 ; err = dx / 2 = 128 + QDX / 2
        lsr a
        ora #$80
        sta QERR
        lda QCOL
        beq :+
        jmp ql_ws
:       jmp ql_wc
@tall:  lda QDY                 ; dy + 1 dots
        inc a
        sta QCNT
        lda QDY                 ; err = dy / 2
        lsr a
        sta QERR
        lda QCOL
        beq :+
        jmp ql_ys
:       jmp ql_yc

ql_xs:  QLINE_X 1
ql_xc:  QLINE_X 0
ql_ws:  QLINE_W 1
ql_wc:  QLINE_W 0
ql_ys:  QLINE_Y 1
ql_yc:  QLINE_Y 0

bits:   .byte $01, $02, $04, $08, $10, $20, $40     ; dot m of a byte
rbits:  .byte $40, $20, $10, $08, $04, $02, $01     ; dot 6 - m

; Effect 6: Nightlines. One line between two wandering ends, A and B, drawn
; four times: as it is and mirrored left-right and top-bottom. The ends stay
; in the top-left quarter (x 0-139, y 0-95), so the four copies each keep to
; their own quarter and meet in the middle. The last 20 generations stay on
; screen; each step the oldest is rubbed out first and the newest drawn whole
; after it. The ends move with momentum (v = 0.9 v + a small random push,
; bouncing off the quarter's edges), so the lines bunch into slowly bending
; bundles. It starts as a cross: A near the middle, B near the corner.
; Drawn straight onto page 1.
;
; One routine draws all four copies of a line at once, walking the line in the
; top-left quarter and setting (or clearing) each dot and its three mirror
; images. That makes the picture exactly symmetric (four separate lines drawn
; left to right would differ by a dot here and there) and costs about half of
; what four separate lines would.

.include "config.inc"

.export fx_night_init, fx_night_step, quad_line
.export nl_q, nl_a, nl_b, nl_gax, nl_gay, nl_gbx, nl_gby, nl_head, nl_count

.import rng_next, rng_below, show_page1, vbl_poll
.import row_lo, row_hi, xbyte_lo, xmod_lo

KEEP    = 20                    ; generations kept

; ---- state in FXRAM ----
nl_rblo  = FXRAM                ; 96: the row 191 - y, for y 0-95 (bottom half)
nl_rbhi  = nl_rblo + 96
nl_gax   = nl_rbhi + 96         ; generation ring, KEEP each: the ends' whole
nl_gay   = nl_gax + KEEP        ; dots as drawn
nl_gbx   = nl_gay + KEEP
nl_gby   = nl_gbx + KEEP
nl_head  = nl_gby + KEEP        ; the slot the next generation goes in
nl_count = nl_head + 1          ; generations kept
nl_a     = nl_count + 1         ; 8: end A: x, y (8.8, 0 <= x < 140, 0 <= y < 96),
nl_b     = nl_a + 8             ; then vx, vy (signed 8.8). End B likewise.

; ---- zero page ----
nl_q  = FXZ                     ; quad_line's line: x0, y0, x1, y1, mode
QX0   = nl_q
QY0   = nl_q+1
QX1   = nl_q+2
QY1   = nl_q+3
QCOL  = nl_q+4                  ; 0 clear, 1 set
PT    = FXZ+5                   ; 2: the row in the top half
PB    = FXZ+7                   ; 2: its mirror in the bottom half
BL    = FXZ+9                   ; byte of the dot in the left half...
BR    = FXZ+10                  ; ...and of its mirror in the right half
ML    = FXZ+11                  ; their masks
MR    = FXZ+12
QDX   = FXZ+13                  ; dx (0-139)
QDY   = FXZ+14                  ; |dy| (0-95)
QSY   = FXZ+15                  ; 1 or $FF: row direction
QERR  = FXZ+16
QCNT  = FXZ+17                  ; dots left
V     = FXZ+18                  ; 2: a speed being worked on
N     = FXZ+20                  ; 2: the push
T     = FXZ+22                  ; 2
U     = FXZ+24                  ; 2
SGN   = FXZ+26                  ; $FF when V was negative
EOFF  = FXZ+27                  ; the end being moved: 0 = A, 8 = B
VLIM  = FXZ+28                  ; speed limit, whole dots
PLIM  = FXZ+29                  ; the edge: 140 or 96

.segment "FX6"
        jmp fx_night_init        ; the overlay's entry points
        jmp fx_night_step

; ================================================================ init
fx_night_init:
        jsr show_page1
        ldx #0                  ; bottom-half rows, mirrored
        ldy #191
:       lda row_lo,y
        sta nl_rblo,x
        lda row_hi,y
        sta nl_rbhi,x
        dey
        inx
        cpx #96
        bne :-
        stz nl_head
        stz nl_count
        lda #24                 ; A: x 115-139, y 75-95
        jsr rng_below
        clc
        adc #115
        sta nl_a+1
        jsr rng_next
        sta nl_a
        lda #20
        jsr rng_below
        clc
        adc #75
        sta nl_a+3
        jsr rng_next
        sta nl_a+2
        lda #20                 ; B: x 0-20, y 0-15
        jsr rng_below
        sta nl_b+1
        jsr rng_next
        sta nl_b
        lda #15
        jsr rng_below
        sta nl_b+3
        jsr rng_next
        sta nl_b+2
        ldx #3                  ; both still
:       stz nl_a+4,x
        stz nl_b+4,x
        dex
        bpl :-
        rts

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
@move:  ldx #0
        jsr move                ; A
        ldx #8
        jsr move                ; B
        ldx nl_head             ; the newest, at the ends' whole dots
        lda nl_a+1
        sta nl_gax,x
        lda nl_a+3
        sta nl_gay,x
        lda nl_b+1
        sta nl_gbx,x
        lda nl_b+3
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
        lda nl_gax,x
        sta QX0
        lda nl_gay,x
        sta QY0
        lda nl_gbx,x
        sta QX1
        lda nl_gby,x
        sta QY1
        rts

; ================================================================ motion
; move: X = 0 for end A, 8 for B. A push for each axis, then the move.
move:
        stx EOFF
        jsr push_x
        lda #4
        sta VLIM
        lda #140
        sta PLIM
        ldx EOFF
        jsr axis
        jsr push_y
        lda #3
        sta VLIM
        lda #96
        sta PLIM
        lda EOFF
        ora #2                  ; y follows x in the record
        tax
        ; fall through

; axis: X = the position's offset in nl_a (its speed is at X+4), N = the push.
; v = 0.9 v + N, held within VLIM either way; p += v; past an edge, p stops
; at the edge and v turns round.
axis:
        stz SGN                 ; V = |v|
        lda nl_a+4,x
        sta V
        lda nl_a+5,x
        sta V+1
        bpl :+
        dec SGN
        jsr negv
:       lda V                   ; T = 2 |v|
        asl a
        sta T
        lda V+1
        rol a
        sta T+1
        lda T                   ; U = 8 |v|
        asl a
        sta U
        lda T+1
        rol a
        sta U+1
        asl U
        rol U+1
        clc                     ; T = 10 |v|
        lda T
        adc U
        sta T
        lda T+1
        adc U+1
        sta T+1
        asl U                   ; U = 16 |v|
        rol U+1
        clc                     ; A = 26 |v| / 256, about a tenth
        lda T
        adc U
        lda T+1
        adc U+1
        sta T
        sec                     ; |v| -= that: about 0.9 of the speed kept,
        lda V                   ; the same in either direction
        sbc T
        sta V
        bcs :+
        dec V+1
:       bit SGN
        bpl :+
        jsr negv
:       clc                     ; v += the push
        lda V
        adc N
        sta V
        lda V+1
        adc N+1
        sta V+1
        bmi @neg
        cmp VLIM                ; above +VLIM: hold it there
        bcc @vok
        bne @vhi
        lda V
        beq @vok
@vhi:   stz V
        lda VLIM
        sta V+1
        bra @vok
@neg:   clc                     ; below -VLIM: hold it there
        adc VLIM
        bpl @vok
        stz V
        lda VLIM
        eor #$FF
        inc a
        sta V+1
@vok:   lda V
        sta nl_a+4,x
        lda V+1
        sta nl_a+5,x
        clc                     ; T = p + v
        lda nl_a,x
        adc V
        sta T
        lda nl_a+1,x
        adc V+1
        sta T+1
        bit V+1
        bmi @back
        cmp PLIM                ; heading right or down: past the far edge?
        bcc @store
        ldy PLIM                ; stop on the last dot
        dey
        sty T+1
        stz T
        bra @turn
@back:  bcs @store              ; heading left or up: no carry = below 0
        stz T
        stz T+1
@turn:  sec                     ; turn round
        lda #0
        sbc V
        sta nl_a+4,x
        lda #0
        sbc V+1
        sta nl_a+5,x
@store: lda T
        sta nl_a,x
        lda T+1
        sta nl_a+1,x
        rts

negv:   sec                     ; V = -V
        lda #0
        sbc V
        sta V
        lda #0
        sbc V+1
        sta V+1
        rts

; push_x: N = 3 s, s even over -102..102: up to 1.2 dots either way (8.8).
push_x:
        lda #205
        jsr rng_below
        sec
        sbc #102
        sta N
        ldy #0
        cmp #$80
        bcc :+
        dey
:       sty N+1
        asl a                   ; T = 2 s
        sta T
        tya
        rol a
        sta T+1
        clc                     ; N = 3 s
        lda N
        adc T
        sta N
        lda N+1
        adc T+1
        sta N+1
        rts

; push_y: N = 2 s, s even over -127..127: up to 1 dot either way.
push_y:
        lda #255
        jsr rng_below
        sec
        sbc #127
        ldy #0
        cmp #$80
        bcc :+
        dey
:       asl a
        sta N
        tya
        rol a
        sta N+1
        rts

; ================================================================ quad_line
; quad_line: the line from (QX0, QY0) to (QX1, QY1), both in the top-left
; quarter, and its mirror images (279 - x, y), (x, 191 - y) and (279 - x,
; 191 - y), on page 1, in mode QCOL (0 clear, 1 set). The same dots as fline
; would draw for the first copy: left to right, both ends included. The two
; ends may be swapped on return. Counts vertical blanks as it goes.
;
; The left and right copies share a row and their bytes mirror each other
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

; wider than tall: a dot right every time, a row when the error says
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
        bra dot
wrap:   QWRAP
        bra err
done:   rts
.endmacro

; taller than wide: a row every time, a dot right when the error says
.macro QLINE_Y mode
        .local dot, wrap, done
dot:    QPLOT mode
        dec QCNT
        beq done
        QNEXTROW
        sec                     ; err -= dx; below zero (carry clear):
        lda QERR                ; err += dy, one dot right
        sbc QDX
        sta QERR
        bcs dot
        adc QDY
        sta QERR
        asl ML
        bmi wrap
        lsr MR
        bra dot
wrap:   QWRAP
        bra dot
done:   rts
.endmacro

quad_line:
        jsr vbl_poll
        lda QX1                 ; left to right: swap the ends if needed
        cmp QX0
        bcs @ordered
        ldx QX0
        sta QX0
        stx QX1
        lda QY0
        ldx QY1
        sta QY1
        stx QY0
@ordered:
        sec                     ; QDX = dx
        lda QX1
        sbc QX0
        sta QDX
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
        lda xbyte_lo,x
        sta BL
        lda #39
        sec
        sbc BL
        sta BR
        ldy xmod_lo,x
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
        lda QDX                 ; wider than tall, or taller?
        cmp QDY
        bcc @tall
        inc a                   ; dx + 1 dots (1-140)
        sta QCNT
        lda QDX                 ; err = dx / 2
        lsr a
        sta QERR
        lda QCOL
        beq :+
        jmp ql_xs
:       jmp ql_xc
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
ql_ys:  QLINE_Y 1
ql_yc:  QLINE_Y 0

bits:   .byte $01, $02, $04, $08, $10, $20, $40     ; dot m of a byte
rbits:  .byte $40, $20, $10, $08, $04, $02, $01     ; dot 6 - m

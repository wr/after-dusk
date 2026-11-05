; Effect 12: Bouncing Ball, after the original (Speed 10, Size 10). One solid
; white ball of radius 3 glides in a straight line, 3.8 dots a step (about
; 115 a second, as fast as the original; the x part stretched 1.1 for the
; IIc's dot shape), and bounces off all four
; edges: where a step would take it past an edge, it is put back on the edge
; and that part of its speed turns round. No gravity. It starts anywhere,
; heading 0.45-1.1 radians off an axis in any of the four quadrants.
;
; Each step draws the new disc first and then rubs out what is left of the
; old one, so the ball is never missing from the screen while the beam goes
; by. Drawn straight onto page 1.

.include "config.inc"

.export fx_ball_init, fx_ball_step
.export bb_x, bb_y, bb_vx, bb_vy, bb_lx, bb_ly, bb_drawn

.import rng_next, rng_below, hspan, show_page1

R       = 3                     ; radius
XMIN    = R                     ; the centre stays within these
XMAX    = 279 - R
YMIN    = R
YMAX    = 191 - R
NEAR    = 4                     ; the old disc within this many dots: rub out
                                ; only the part the new one doesn't cover
BIAS    = 16                    ; added to small signed offsets to keep them positive

; ---- state in FXRAM ----
bb_x     = FXRAM                ; 3: x, 8 fraction bits (fraction, low, high)
bb_y     = bb_x + 3             ; 2: y, 8.8
bb_vx    = bb_y + 2             ; 2: speed, signed 8.8
bb_vy    = bb_vx + 2            ; 2
bb_lx    = bb_vy + 2            ; 2: centre of the disc on screen
bb_ly    = bb_lx + 2            ; 1
bb_drawn = bb_ly + 1            ; 0 until the first disc is drawn

; ---- zero page ----
NX   = FXZ                      ; 2: the new centre
NY   = FXZ+2
CX   = FXZ+3                    ; 2: centre the spans are drawn round
CY   = FXZ+5
I    = FXZ+6                    ; row of the disc, 0-6 (dy + 3)
SL   = FXZ+7                    ; a span's ends, relative to CX, + BIAS
SR   = FXZ+8
DXO  = FXZ+9                    ; old centre - new, + BIAS
DYO  = FXZ+10                   ; old centre - new, signed
OL   = FXZ+11                   ; old row's ends, relative, + BIAS
OR_  = FXZ+12
NL   = FXZ+13                   ; new row's ends, relative, + BIAS
NR   = FXZ+14
QD   = FXZ+15                   ; quarter turns, 0-3

.segment "FX12"
        jmp fx_ball_init        ; the overlay's entry points
        jmp fx_ball_step

; ================================================================ init
fx_ball_init:
        jsr show_page1
        stz bb_drawn
        stz bb_x                ; on a whole dot, x 20-260, y 20-170
        stz bb_y
        lda #241
        jsr rng_below
        clc
        adc #20
        sta bb_x+1
        lda #0
        adc #0
        sta bb_x+2
        lda #151
        jsr rng_below
        clc
        adc #20
        sta bb_y+1
        jsr rng_next            ; one of 16 headings...
        and #15
        asl a
        asl a
        tax
        jsr rng_next            ; ...turned 0-3 quarter turns
        and #3
        sta QD
        lsr a                   ; odd turns swap the x and y parts
        bcs @odd
        lda bb_heads,x          ; cos 4.18, sin 3.8
        ldy bb_heads+3,x
        bra @set
@odd:   lda bb_heads+1,x        ; sin 4.18, cos 3.8
        ldy bb_heads+2,x
@set:   stz bb_vx+1             ; 1/64 dot to 8.8
        asl a
        rol bb_vx+1
        asl a
        rol bb_vx+1
        sta bb_vx
        stz bb_vy+1
        tya
        asl a
        rol bb_vy+1
        asl a
        rol bb_vy+1
        sta bb_vy
        lda QD                  ; signs: turns 0 (+,+), 1 (-,+), 2 (-,-), 3 (+,-)
        dec a
        cmp #2
        bcs :+
        ldx #0
        jsr neg
:       lda QD
        cmp #2
        bcc :+
        ldx #2
        jsr neg
:       rts

; neg: turn round speed X (0 = x, 2 = y).
neg:    sec
        lda #0
        sbc bb_vx,x
        sta bb_vx,x
        lda #0
        sbc bb_vx+1,x
        sta bb_vx+1,x
        rts

; ================================================================ step
fx_ball_step:
        lda #PAGE1
        sta PAGE

        ldx #0                  ; x += vx
        lda bb_vx+1
        bpl :+
        dex
:       clc
        lda bb_x
        adc bb_vx
        sta bb_x
        lda bb_x+1
        adc bb_vx+1
        sta bb_x+1
        txa
        adc bb_x+2
        sta bb_x+2
        bmi @xlo                ; off the left
        bne @xr                 ; 256 or more
        lda bb_x+1
        cmp #XMIN
        bcc @xlo
        bra @xok
@xr:    lda bb_x+1              ; past 276?
        cmp #<XMAX
        bcc @xok
        bne @xhi
        lda bb_x
        beq @xok
@xhi:   lda #<XMAX
        ldy #>XMAX
        bra @xb
@xlo:   lda #XMIN
        ldy #0
@xb:    sta bb_x+1              ; back on the edge, heading the other way
        sty bb_x+2
        stz bb_x
        ldx #0
        jsr neg
@xok:
        clc                     ; y += vy
        lda bb_y
        adc bb_vy
        sta bb_y
        lda bb_y+1
        adc bb_vy+1
        sta bb_y+1
        ldx bb_vy+1
        bpl :+
        bcc @ylo                ; heading up and past 0
        bra @ychk
:       bcs @yhi                ; heading down and past 255
@ychk:  cmp #YMIN
        bcc @ylo
        cmp #YMAX
        bcc @yok
        bne @yhi
        lda bb_y
        beq @yok
@yhi:   lda #YMAX
        bra @yb
@ylo:   lda #YMIN
@yb:    sta bb_y+1
        stz bb_y
        ldx #2
        jsr neg
@yok:
        lda bb_x                ; the new centre: rounded to the nearest dot
        cmp #$80
        lda bb_x+1
        adc #0
        sta NX
        lda bb_x+2
        adc #0
        sta NX+1
        lda bb_y
        cmp #$80
        lda bb_y+1
        adc #0
        sta NY

        lda bb_drawn
        beq @new                ; nothing on screen yet
        sec                     ; how far the disc moves
        lda bb_lx
        sbc NX
        sta DXO
        lda bb_lx+1
        sbc NX+1
        tax
        clc                     ; near: -NEAR <= old - new <= NEAR, each way
        lda DXO
        adc #NEAR
        sta SL
        txa
        adc #0
        bne @far
        lda SL
        cmp #2 * NEAR + 1
        bcs @far
        sec
        lda bb_ly
        sbc NY
        sta DYO
        clc
        adc #NEAR
        cmp #2 * NEAR + 1
        bcs @far
        lda DXO
        clc
        adc #BIAS
        sta DXO
        jsr draw_new            ; near: the new disc, then what's left of the old
        jsr rub_rest
        bra @done
@far:   lda bb_lx               ; far (only when moved by hand): all of the old
        sta CX                  ; one, then the new
        lda bb_lx+1
        sta CX+1
        lda bb_ly
        sta CY
        stz PCOL
        jsr whole
@new:   jsr draw_new
@done:  lda NX
        sta bb_lx
        lda NX+1
        sta bb_lx+1
        lda NY
        sta bb_ly
        lda #1
        sta bb_drawn
        rts

; draw_new: the disc at (NX, NY), set.
draw_new:
        lda NX
        sta CX
        lda NX+1
        sta CX+1
        lda NY
        sta CY
        lda #1
        sta PCOL
        ; fall through
; whole: the disc at (CX, CY) in mode PCOL, a span a row.
whole:  ldx #6
@row:   stx I
        jsr row_y
        lda #BIAS
        sec
        sbc wid,x
        sta SL
        lda #BIAS
        clc
        adc wid,x
        sta SR
        jsr span
        ldx I
        dex
        bpl @row
        rts

; rub_rest: clear the old disc's dots that the new one (CX = NX, CY = NY)
; doesn't cover: on each of its rows, up to two pieces either side of the
; new disc's row.
rub_rest:
        stz PCOL
        ldx #6
@row:   stx I
        lda bb_ly               ; PY = old centre + i - 3
        clc
        adc I
        sec
        sbc #R
        sta PY
        stz PY+1
        lda DXO                 ; the old row's ends
        sec
        sbc wid,x
        sta OL
        lda DXO
        clc
        adc wid,x
        sta OR_
        txa                     ; the new disc's row there, 0-6, if any
        clc
        adc DYO
        tay
        cpy #7
        bcs @all
        lda #BIAS
        sec
        sbc wid,y
        sta NL
        lda #BIAS
        clc
        adc wid,y
        sta NR
        lda OL                  ; left of it: OL to min(OR, NL - 1)
        sta SL
        lda NL
        dec a
        cmp OR_
        bcc :+
        lda OR_
:       sta SR
        jsr span
        lda NR                  ; right of it: max(OL, NR + 1) to OR
        inc a
        cmp OL
        bcs :+
        lda OL
:       sta SL
        lda OR_
        sta SR
        jsr span
        bra @next
@all:   lda OL                  ; no new row here: all of it
        sta SL
        lda OR_
        sta SR
        jsr span
@next:  ldx I
        dex
        bpl @row
        rts

; row_y: PY = CY + I - 3. Keeps X.
row_y:  lda CY
        clc
        adc I
        sec
        sbc #R
        sta PY
        stz PY+1
        rts

; span: dots CX + SL - BIAS to CX + SR - BIAS on row PY, in mode PCOL;
; nothing when SR < SL.
span:   lda SL
        jsr offset
        sta PX
        sty PX+1
        lda SR
        jsr offset
        sta PX2
        sty PX2+1
        jmp hspan

; offset: A (+ BIAS) to CX + A - BIAS, low in A, high in Y.
offset: ldy #0
        sec
        sbc #BIAS
        bcs :+
        dey
:       clc
        adc CX
        pha
        tya
        adc CX+1
        tay
        pla
        rts

wid:    .byte 1, 2, 3, 3, 3, 2, 1       ; half-widths of the disc's rows, r*r + r = 12

.include "ball_tables.inc"

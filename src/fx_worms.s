; Effect 4: Can of Worms. Six worms wander over whatever is on the screen
; and eat it: each step a worm's head clears a disc and draws a smaller one
; (which gives the body its segmented look), and its tail clears a disc to
; black, leaving an eaten path.

.include "config.inc"

.export fx_worms_init, fx_worms_step
.export wrm_count, wrm_xi, wrm_xh, wrm_yi, wrm_head

.import rng_next, rng_below, vbl_poll
.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi
.import wvx_lo, wvx_hi, wvy_lo, wvy_hi

NWORM = 6
RING  = 32                      ; positions remembered per worm (>= longest + 3)

; ---- state in FXRAM ----
wrm_xf   = FXRAM                ; head x: xh:xi.xf
wrm_xi   = wrm_xf + NWORM
wrm_xh   = wrm_xi + NWORM
wrm_yf   = wrm_xh + NWORM       ; head y: yi.yf
wrm_yi   = wrm_yf + NWORM
wrm_a    = wrm_yi + NWORM       ; heading, 256 = a full turn
wrm_len  = wrm_a + NWORM        ; 18-28 segments
wrm_head = wrm_len + NWORM      ; ring slot of the newest position
wrm_cnt  = wrm_head + NWORM     ; positions in the ring
ring_xl  = wrm_cnt + NWORM      ; NWORM x RING: x lo, x hi, y
ring_xh  = ring_xl + NWORM * RING
ring_y   = ring_xh + NWORM * RING
wb0      = ring_y + NWORM * RING ; per half-width 1-3: left byte, its mask,
wm0      = wb0 + 3              ; right byte, its mask (0 if the same byte)
wb1      = wm0 + 3
wm1      = wb1 + 3

; ---- zero page ----
W     = FXZ             ; current worm
WB    = FXZ+1           ; W * RING
NXF   = FXZ+2           ; candidate head position
NXI   = FXZ+3
NXH   = FXZ+4
NYF   = FXZ+5
NYI   = FXZ+6
DCX   = FXZ+7           ; 2: disc centre
DCY   = FXZ+9
DR    = FXZ+10          ; disc radius (2 or 3)
DDY   = FXZ+11          ; signed row offset
K     = FXZ+12
T0    = FXZ+13
RP    = FXZ+14          ; 2: row pointer

.segment "CODE"

wrm_count:
        .byte NWORM

; ================================================================ init
fx_worms_init:
        ldx #NWORM-1
@l:     lda #221                ; x 30-250
        jsr rng_below
        clc
        adc #30
        sta wrm_xi,x
        stz wrm_xh,x
        stz wrm_xf,x
        lda #153                ; y 20-172
        jsr rng_below
        clc
        adc #20
        sta wrm_yi,x
        stz wrm_yf,x
        jsr rng_next
        sta wrm_a,x
        lda #11                 ; 18-28 segments
        jsr rng_below
        clc
        adc #18
        sta wrm_len,x
        stz wrm_head,x
        stz wrm_cnt,x
        dex
        bpl @l
        rts

; ================================================================ step
fx_worms_step:
        lda #PAGE1
        sta PAGE
        stz W
@worm:  jsr vbl_poll            ; steps can take more than a frame
        ldx W
        lda W                   ; WB = W * 32
        asl a
        asl a
        asl a
        asl a
        asl a
        sta WB
        lda #25                 ; turn by -12..12 (about 0.3 radians)
        jsr rng_below
        sec
        sbc #12
        clc
        adc wrm_a,x
        sta wrm_a,x
        tay
        clc                     ; candidate x = x + 2 cos(a)
        lda wrm_xf,x
        adc wvx_lo,y
        sta NXF
        lda wrm_xi,x
        adc wvx_hi,y
        sta NXI
        lda wvx_hi,y            ; sign-extend the step
        and #$80
        beq :+
        lda #$FF
:       adc wrm_xh,x
        sta NXH
        clc                     ; candidate y = y + 1.7 sin(a)
        lda wrm_yf,x
        adc wvy_lo,y
        sta NYF
        lda wrm_yi,x
        adc wvy_hi,y
        sta NYI

        jsr in_bounds           ; within 4 dots of an edge? turn back instead
        bcs :+
        jmp @turn
:

        lda NXF                 ; move
        sta wrm_xf,x
        lda NXI
        sta wrm_xi,x
        lda NXH
        sta wrm_xh,x
        lda NYF
        sta wrm_yf,x
        lda NYI
        sta wrm_yi,x
        lda wrm_head,x          ; remember it in the ring
        inc a
        and #RING-1
        sta wrm_head,x
        clc
        adc WB
        tay
        lda NXI
        sta ring_xl,y
        sta DCX
        lda NXH
        sta ring_xh,y
        sta DCX+1
        lda NYI
        sta ring_y,y
        sta DCY
        inc wrm_cnt,x
        lda #3                  ; head: a dark ring around a lit disc
        stz PCOL
        jsr fdisc
        lda #1
        sta PCOL
        lda #2
        jsr fdisc

        ldx W                   ; tail: once longer than its length, eat
        lda wrm_cnt,x
        cmp wrm_len,x
        beq @next
        bcc @next
        dec wrm_cnt,x
        lda wrm_head,x          ; oldest = head - len
        sec
        sbc wrm_len,x
        jsr ring_pos
        stz PCOL
        lda #3
        jsr fdisc
        lda #3                  ; redraw the three oldest that remain
        sta K
@redo:  ldx W
        lda wrm_head,x
        sec
        sbc wrm_len,x
        clc
        adc K
        jsr ring_pos
        lda #1
        sta PCOL
        lda #2
        jsr fdisc
        dec K
        bne @redo
        bra @next

@turn:  lda #65                 ; turn back by 90-180 degrees
        jsr rng_below
        clc
        adc #64
        ldx W
        adc wrm_a,x
        sta wrm_a,x

@next:  inc W
        lda W
        cmp #NWORM
        beq :+
        jmp @worm
:       rts

; in_bounds: carry set if the candidate NXH:NXI, NYI is at least 4 dots
; from every edge (x 4-275, y 4-187)
in_bounds:
        lda NXH
        bne @hix
        lda NXI
        cmp #4
        bcc @no
        bra @y
@hix:   cmp #1
        bne @no
        lda NXI
        cmp #(276-256)
        bcs @no
@y:     lda NYI
        cmp #4
        bcc @no
        cmp #188
        bcs @no
        sec
        rts
@no:    clc
        rts

; ring_pos: DCX/DCY = worm W's ring slot A (wrapped)
ring_pos:
        and #RING-1
        clc
        adc WB
        tay
        lda ring_xl,y
        sta DCX
        lda ring_xh,y
        sta DCX+1
        lda ring_y,y
        sta DCY
        rts

; fdisc: a filled disc of radius A (2 or 3) at DCX/DCY in mode PCOL (0 or 1),
; the same dots as disc: dx*dx + dy*dy <= r*r + r. Worms stay at least 4
; dots from every edge, so nothing needs clipping: the bytes and masks for
; each half-width are worked out once, then each row is one or two bytes.
fdisc:  sta DR
        ldx #3                  ; for half-widths 3, 2, 1
@w:     stx K
        sec                     ; left end: cx - w
        lda DCX
        sbc K
        sta T0
        lda DCX+1
        sbc #0
        jsr x_byte              ; A = byte, Y = x mod 7
        sta wb0-1,x
        lda span_l,y
        sta wm0-1,x
        ldx K
        clc                     ; right end: cx + w
        lda DCX
        adc K
        sta T0
        lda DCX+1
        adc #0
        jsr x_byte
        sta wb1-1,x
        lda span_r,y
        sta wm1-1,x
        ldx K
        lda wb0-1,x             ; one byte: combine the masks
        cmp wb1-1,x
        bne :+
        lda wm0-1,x
        and wm1-1,x
        sta wm0-1,x
        stz wm1-1,x
:       dex
        bne @w

        lda DR
        eor #$FF
        inc a
        sta DDY                 ; dy from -r
@row:   lda DDY
        bpl :+
        eor #$FF
        inc a
:       ldx DR
        cpx #3
        beq :+
        tax
        lda half2,x
        bra :++
:       tax
        lda half3,x
:       tax                     ; X = half-width for this row
        lda DDY
        clc
        adc DCY
        tay
        lda row_lo,y
        sta RP
        lda row_hi,y
        sta RP+1
        ldy wb0-1,x
        lda wm0-1,x
        jsr dapply
        lda wm1-1,x
        beq :+
        ldy wb1-1,x
        jsr dapply
:       lda DDY
        inc DDY
        cmp DR
        bne @row
        rts

; x_byte: A:T0 = x (0-279); returns A = byte in row, Y = x mod 7. Keeps X.
x_byte: bne @hi
        ldy T0
        lda xmod_lo,y
        pha
        lda xbyte_lo,y
        bra @done
@hi:    ldy T0
        lda xmod_hi,y
        pha
        lda xbyte_hi,y
@done:  ply
        rts

; dapply: mask A into byte Y of (RP): set when PCOL = 1, clear when 0.
dapply: pha
        lda PCOL
        beq @clr
        pla
        ora (RP),y
        sta (RP),y
        rts
@clr:   pla
        eor #$7F
        and (RP),y
        sta (RP),y
        rts

span_l: .byte $7F, $7E, $7C, $78, $70, $60, $40   ; dots m..6
span_r: .byte $01, $03, $07, $0F, $1F, $3F, $7F   ; dots 0..m

half2:  .byte 2, 2, 1                 ; r = 2: rows 0, 1, 2
half3:  .byte 3, 3, 2, 1              ; r = 3: rows 0, 1, 2, 3

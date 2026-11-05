; Effect 4: Can of Worms. Six worms wander over whatever is on the screen
; and eat it. They crawl at the original's pace: each step a worm's head
; moves half a dot across (0.43 down), about 10 dots a second, turning up to
; 0.15 radians, and draws its disc there. Every fourth move (every 2 dots)
; the head first clears a bigger disc, which cuts a dark ring into the body
; behind it and gives the body its segmented look. A worm is 18-28 rings
; long. Its tail follows the rings smoothly, a quarter of the way to the
; next one each step, clearing a disc to black and leaving an eaten path;
; the ring three ahead of the tail is drawn whole again, a rounded tail end.

.include "config.inc"

.export fx_worms_init, fx_worms_step
.export wrm_count, wrm_xf, wrm_xi, wrm_xh, wrm_yf, wrm_yi, wrm_a, wrm_len, wrm_head
.export ring_xl, ring_xh, ring_y

.import rng_next, rng_below, vbl_poll
.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi
.import wvx_lo, wvx_hi, wvy_lo, wvy_hi

NWORM = 6
RING  = 32                      ; rings remembered per worm (>= longest + 3)
EVERY = 4                       ; moves between rings

; ---- state in FXRAM ----
wrm_xf   = FXRAM                ; head x: xh:xi.xf
wrm_xi   = wrm_xf + NWORM
wrm_xh   = wrm_xi + NWORM
wrm_yf   = wrm_xh + NWORM       ; head y: yi.yf
wrm_yi   = wrm_yf + NWORM
wrm_a    = wrm_yi + NWORM       ; heading, 256 = a full turn
wrm_len  = wrm_a + NWORM        ; 18-28 rings
wrm_head = wrm_len + NWORM      ; ring slot of the newest ring
wrm_m    = wrm_head + NWORM     ; moves since the newest ring, 0-3
ring_xl  = wrm_m + NWORM        ; NWORM x RING: x lo, x hi, y; every slot
ring_xh  = ring_xl + NWORM * RING ; starts at the worm's first position
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
SL    = FXZ+16          ; SH:SL this step's move on one axis, 8.8
SH    = FXZ+17
TDX   = FXZ+18          ; tail: the next ring's x (low byte) and y
TDY   = FXZ+19

.segment "FX4"
        jmp fx_worms_init        ; the overlay's entry points
        jmp fx_worms_step

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
        lda #11                 ; 18-28 rings
        jsr rng_below
        clc
        adc #18
        sta wrm_len,x
        stz wrm_head,x
        lda #EVERY-1            ; the first move cuts a ring
        sta wrm_m,x
        txa                     ; every ring slot: here, so the tail waits
        asl a                   ; here while the worm grows
        asl a
        asl a
        asl a
        asl a
        tay
        lda #RING
        sta K
:       lda wrm_xi,x
        sta ring_xl,y
        lda #0
        sta ring_xh,y
        lda wrm_yi,x
        sta ring_y,y
        iny
        dec K
        bne :-
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
        lda #13                 ; turn by -6..6 (about 0.15 radians)
        jsr rng_below
        sec
        sbc #6
        clc
        adc wrm_a,x
        sta wrm_a,x
        tay
        lda wvx_lo,y            ; candidate x = x + 0.5 cos(a): a quarter
        sta SL                  ; of the table's 2 cos(a)
        lda wvx_hi,y
        jsr quarter
        clc
        lda wrm_xf,x
        adc SL
        sta NXF
        lda wrm_xi,x
        adc SH
        sta NXI
        lda wrm_xh,x
        adc SH                  ; SH is the sign extension too
        sta NXH
        lda wvy_lo,y            ; candidate y = y + 0.43 sin(a), a quarter
        sta SL                  ; of 1.7 sin(a)
        lda wvy_hi,y
        jsr quarter
        clc
        lda wrm_yf,x
        adc SL
        sta NYF
        lda wrm_yi,x
        adc SH
        sta NYI

        jsr in_bounds           ; within 4 dots of an edge? turn back instead
        bcs :+
        jmp @turn
:
        lda NXF                 ; move
        sta wrm_xf,x
        lda NXI
        sta wrm_xi,x
        sta DCX
        lda NXH
        sta wrm_xh,x
        sta DCX+1
        lda NYF
        sta wrm_yf,x
        lda NYI
        sta wrm_yi,x
        sta DCY
        inc wrm_m,x             ; every fourth move, a ring: remember it,
        lda wrm_m,x             ; and clear a disc round the head first
        cmp #EVERY
        bcc @head
        stz wrm_m,x
        lda wrm_head,x
        inc a
        and #RING-1
        sta wrm_head,x
        clc
        adc WB
        tay
        lda NXI
        sta ring_xl,y
        lda NXH
        sta ring_xh,y
        lda NYI
        sta ring_y,y
        stz PCOL
        lda #3
        jsr fdisc
@head:  lda #1                  ; the head's disc
        sta PCOL
        lda #2
        jsr fdisc

        jsr tail_pos            ; tail: eat, then draw the ring three ahead
        stz PCOL                ; whole again
        lda #3
        jsr fdisc
        ldx W
        lda wrm_head,x
        sec
        sbc wrm_len,x
        clc
        adc #3
        jsr ring_pos
        lda #1
        sta PCOL
        lda #2
        jsr fdisc
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

; tail_pos: DCX/DCY = worm W's tail: wrm_m quarters of the way from its
; oldest ring (len rings behind the head) to the next one.
tail_pos:
        ldx W
        lda wrm_head,x          ; the next ring
        sec
        sbc wrm_len,x
        inc a
        jsr ring_pos
        lda DCX                 ; (rings are 1-3 dots apart, so the low
        sta TDX                 ; bytes' difference is enough)
        lda DCY
        sta TDY
        ldx W
        lda wrm_head,x          ; the oldest
        sec
        sbc wrm_len,x
        jsr ring_pos
        sec
        lda TDX
        sbc DCX
        jsr part
        pha
        clc
        adc DCX
        sta DCX
        pla
        bmi :+
        lda #0
        bra :++
:       lda #$FF
:       adc DCX+1
        sta DCX+1
        sec
        lda TDY
        sbc DCY
        jsr part
        clc
        adc DCY
        sta DCY
        rts

; part: A = A * wrm_m / 4, rounded; A signed, -4..4.
part:   sta T0
        ldx W
        ldy wrm_m,x
        lda #2                  ; rounding
        cpy #0
        beq @sh
:       clc
        adc T0
        dey
        bne :-
@sh:    cmp #$80                ; / 4, keeping the sign
        ror a
        cmp #$80
        ror a
        rts

; quarter: SH:SL = (A:SL) / 4, signed and rounded. A table step is at most
; 2 dots, so SH comes out 0 or $FF. Keeps X and Y.
quarter:
        pha
        clc
        lda SL
        adc #2
        sta SL
        pla
        adc #0
        cmp #$80                ; shift right twice, keeping the sign
        ror a
        ror SL
        cmp #$80
        ror a
        ror SL
        sta SH
        rts

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

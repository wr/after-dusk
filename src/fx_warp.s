; Effect 1: Warp. Stars stream out from the centre of the screen.
;
; Each star is an offset from the centre that grows by 1/16 or 1/32 of
; itself every step, so it starts slow near the middle and speeds up as it
; nears the edge, like flying through a starfield. Close stars (far from the
; centre) are drawn 2 x 2 dots. Off the screen, a star starts again near
; the centre. Drawn straight onto page 1.
;
; Offsets are signed 8.8 fixed point. x is stored halved (screen offset / 2)
; so both fit in a byte; the growth x >> 4 or x >> 5 comes from lookup
; tables, and the dots are set and cleared directly, which keeps 64 stars
; inside a 30-steps-a-second budget.

.include "config.inc"

.export fx_warp_init, fx_warp_step
.export wrp_count, wrp_xf, wrp_xi, wrp_yf, wrp_yi

.import rng_below, show_page1, vbl_poll
.import row_lo, row_hi, xbyte_lo, xbit_lo, xbyte_hi, xbit_hi
.import sar4, shl4, shr4, sar5, shl3, shr5

; 70 stars were planned; 64 keep every step inside 2 ticks (measured).
NSTARS = 64
CX     = 140
CY     = 96

; ---- state in FXRAM ----
wrp_xf  = FXRAM                 ; x offset / 2: xi.xf, signed
wrp_xi  = wrp_xf + NSTARS
wrp_yf  = wrp_xi + NSTARS       ; y offset: yi.yf, signed
wrp_yi  = wrp_yf + NSTARS
wrp_sh  = wrp_yi + NSTARS       ; 0: grows by 1/16 a step, 1: by 1/32
; where it was last drawn, as screen addresses, so erasing is cheap
wrp_ea  = wrp_sh + NSTARS       ; row address, low and high
wrp_eah = wrp_ea + NSTARS
wrp_eb  = wrp_eah + NSTARS      ; row below (big stars), low and high
wrp_ebh = wrp_eb + NSTARS
wrp_ey  = wrp_ebh + NSTARS      ; byte within the row
wrp_m0  = wrp_ey + NSTARS       ; dots in that byte (0: not drawn)
wrp_m1  = wrp_m0 + NSTARS       ; dots in the next byte
wrp_lb  = wrp_m1 + NSTARS       ; 1 one row, 2 two rows

I    = FXZ
T0   = FXZ+1
T1   = FXZ+2
BIG  = FXZ+3
PTR  = FXZ+5                    ; 2
MASK = FXZ+7

.segment "CODE"

wrp_count:
        .byte NSTARS

; ---------------------------------------------------------------- init
fx_warp_init:
        jsr show_page1
        ldx #NSTARS-1
@l:     jsr scatter
        dex
        bpl @l
        rts

; ---------------------------------------------------------------- step
fx_warp_step:
        ldx #NSTARS-1
@star:  stx I
        lda wrp_m0,x            ; erase where it was
        beq @grow
        lda wrp_ea,x
        sta PTR
        lda wrp_eah,x
        sta PTR+1
        jsr erase_row
        lda wrp_lb,x
        cmp #2
        bne @grow
        lda wrp_eb,x
        sta PTR
        lda wrp_ebh,x
        sta PTR+1
        jsr erase_row

@grow:  lda wrp_sh,x            ; T = x >> 4 or x >> 5, from the tables
        bne @x5
        ldy wrp_xi,x
        lda sar4,y
        sta T1
        lda shl4,y
        ldy wrp_xf,x
        ora shr4,y
        bra @xadd
@x5:    ldy wrp_xi,x
        lda sar5,y
        sta T1
        lda shl3,y
        ldy wrp_xf,x
        ora shr5,y
@xadd:  clc                     ; x += T
        adc wrp_xf,x
        sta wrp_xf,x
        lda wrp_xi,x
        adc T1
        sta wrp_xi,x

        lda wrp_sh,x            ; the same for y
        bne @y5
        ldy wrp_yi,x
        lda sar4,y
        sta T1
        lda shl4,y
        ldy wrp_yf,x
        ora shr4,y
        bra @yadd
@y5:    ldy wrp_yi,x
        lda sar5,y
        sta T1
        lda shl3,y
        ldy wrp_yf,x
        ora shr5,y
@yadd:  clc
        adc wrp_yf,x
        sta wrp_yf,x
        lda wrp_yi,x
        adc T1
        sta wrp_yi,x

        lda wrp_xf,x            ; screen x = 140 + 2 * offset, 0..278
        asl a
        lda wrp_xi,x
        rol a
        clc
        adc #CX
        sta PX
        lda wrp_xi,x
        bmi @xneg
        lda #0
        adc #0
        sta PX+1
        beq @yy
        lda PX                  ; 256..278 is still on screen
        cmp #(279-256)
        bcs @gone
        bra @yy
@xneg:  lda #$FF                ; negative offset: on screen if no borrow
        adc #0
        bne @gone
        sta PX+1

@yy:    lda wrp_yi,x            ; screen y = 96 + offset, 0..190
        bmi @yneg
        clc
        adc #CY
        cmp #191
        bcs @gone
        bra @yok
@yneg:  clc                     ; a negative offset >= -96 carries out
        adc #CY
        bcc @gone
@yok:   sta PY

        lda #1                  ; close stars (near the edges) are big
        sta BIG
        lda wrp_xi,x            ; |x offset| >= 80 (stored halved: 40)
        bpl :+
        eor #$FF
:       cmp #40
        bcs @big
        lda wrp_yi,x            ; |y offset| >= 58
        bpl :+
        eor #$FF
:       cmp #58
        bcc @draw
@big:   inc BIG
@draw:  lda BIG
        sta wrp_lb,x
        jsr draw
        bra @next

@gone:  ldx I
        jsr respawn
@next:  lda I                   ; halfway: count a blank if one has passed
        cmp #NSTARS/2
        bne :+
        jsr vbl_poll
:       ldx I
        dex
        bmi :+
        jmp @star
:       rts

; erase_row: clear star X's dots in the row at PTR. Keeps X.
erase_row:
        ldy wrp_ey,x
        lda wrp_m0,x
        eor #$7F
        and (PTR),y
        sta (PTR),y
        lda wrp_m1,x
        beq :+
        iny
        eor #$7F
        and (PTR),y
        sta (PTR),y
:       rts

; draw: star X at PX/PY (on screen: x <= 278, y <= 190) on page 1, one dot
; or 2 x 2 when BIG = 2, and remember where for erasing. Keeps X.
draw:   ldy PY
        lda row_lo,y
        sta wrp_ea,x
        sta PTR
        lda row_hi,y
        sta wrp_eah,x
        sta PTR+1
        lda BIG
        cmp #2
        bne :+
        iny                     ; the row below, for big stars
        lda row_lo,y
        sta wrp_eb,x
        lda row_hi,y
        sta wrp_ebh,x
:       ldy PX
        lda PX+1
        bne @hi
        lda xbit_lo,y
        sta MASK
        lda xbyte_lo,y
        bra @m
@hi:    lda xbit_hi,y
        sta MASK
        lda xbyte_hi,y
@m:     sta wrp_ey,x
        tay
        stz wrp_m1,x
        lda BIG
        cmp #2
        beq @wide
        lda MASK                ; one dot
        sta wrp_m0,x
        ora (PTR),y
        sta (PTR),y
        rts
@wide:  lda MASK                ; two dots across: this byte, maybe the next
        cmp #$40
        bne :+
        lda #$01
        sta wrp_m1,x
        lda #$40
        bra :++
:       asl a
        ora MASK
:       sta wrp_m0,x
        jsr set_row
        lda wrp_eb,x
        sta PTR
        lda wrp_ebh,x
        sta PTR+1
                                ; fall through: the row below
; set_row: set star X's dots in the row at PTR. Keeps X.
set_row:
        ldy wrp_ey,x
        lda wrp_m0,x
        ora (PTR),y
        sta (PTR),y
        lda wrp_m1,x
        beq :+
        iny
        ora (PTR),y
        sta (PTR),y
:       rts

; ---------------------------------------------------------------- spawning
; scatter: anywhere on the screen (first placement). X = star; keeps X.
scatter:
        lda #101                ; x offset -100..100 (stored halved)
        jsr rng_below
        sec
        sbc #50
        sta wrp_xi,x
        lda #153                ; y offset -76..76
        jsr rng_below
        sec
        sbc #76
        sta wrp_yi,x
        bra finish

; respawn: near the centre. X = star; keeps X.
respawn:
        lda #15                 ; x offset -14..14 (stored halved)
        jsr rng_below
        sec
        sbc #7
        sta wrp_xi,x
        lda #25                 ; y offset -12..12
        jsr rng_below
        sec
        sbc #12
        sta wrp_yi,x
        clc                     ; never right on the centre: it would never move
        adc #2
        cmp #5
        bcs finish
        lda wrp_xi,x
        clc
        adc #1
        cmp #3
        bcs finish
        lda #2
        sta wrp_xi,x
finish: stz wrp_xf,x
        stz wrp_yf,x
        stz wrp_m0,x            ; nothing drawn yet
        lda #2
        jsr rng_below
        sta wrp_sh,x
        rts

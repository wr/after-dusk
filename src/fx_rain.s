; Effect 13: Rainstorm, after the original (Storm Type hard, no lightning).
; Drops fall as thin streaks that lean left and speed up, so each streak grows
; longer on the way down, and fall right off the bottom of the screen before
; starting again a little above the top, anywhere from the left edge to 30
; dots past the right. No splashes. Each step every drop rubs out its streak,
; falls (y += v, x -= v/7, v += 1.2 up to 26, from 12-16) and draws its
; streak again: a line from (x, y) to (x - 0.9 v/7, y + 0.9 v), up to 24
; dots. Drawn straight onto page 1.
;
; As x falls v/7 for every v of y, a drop keeps to one line all its life, its
; lane: row r's dot is at x = (Q - r) div 7, where Q = 7 x0 + y0 + 3 for the
; whole-dot place (x0, y0) it started from (the 3 rounds to the nearest dot).
; Q is kept as a byte column and 49ths of one, so x's byte is (Q - r) div 49
; and its dot within the byte is ((Q - r) mod 49) div 7.
;
; Streaks are drawn by straight-line code built in FXRAM at init: a 10-byte
; slot for each screen row that flips one dot in byte Y of that row, from a
; mask table indexed by X, and counts X down a 49th, so every 7 rows the dot
; moves one left. A streak is one run of slots, or two where it crosses into
; the byte to the left; the slot after a run's last row is patched to rts
; while it runs. 15 cycles a dot. Flipping (rather than setting and clearing)
; leaves the screen exactly the drops' streaks; where two cross, the dots they
; share are dark.
;
; Rows are kept 64 up (k = row + 64), so the first rows of streaks above the
; top fit a byte, and y is kept as y + 64.5, so k = round(y) + 64 is its high
; byte, and a drop past the bottom carries out of it.

.include "config.inc"

.export fx_rain_init, fx_rain_step, rn_plan, rn_flip, rn_ndrops
.export rn_yf, rn_yk, rn_j, rn_qb, rn_qm, rn_r1s, rn_r1e, rn_m1, rn_b1, rn_r2s, rn_r2e
.export rn_vl, rn_vh, rn_ll, rn_lh

.import rng_next, show_page1, vbl_poll, row_lo, row_hi

NDROPS  = 45                    ; 55 don't fit 3 ticks at these lengths: a step
                                ; takes 47,400 cycles (median; worst 54,000) with
                                ; 55 drops and 43,100 (49,300) with 50, where 3
                                ; ticks allow 43,400 (50,800)
rn_ndrops = NDROPS
ACCEL   = 12                    ; v += 1.2 a step, in tenths
JMAX    = 140                   ; v at most 26: 12 + 140 tenths
JSTART  = 40                    ; v from 12.0-15.9
KB      = 64                    ; rows are kept 64 up

; ---- FXRAM ----
SLOT    = 10                    ; bytes of code a row
CODE    = FXRAM                 ; $0800: 193 slots, rows 0-192 (192: only ever rts)
MT      = FXRAM + $07C0         ; $0FC0: masks, 1 << (k div 7) for k 0-48
ENTLO   = FXRAM + $0800         ; $1000: each row's slot, by row + 64 (mod 256)
ENTHI   = ENTLO + $100
RDIV    = ENTLO + $200          ; (k - 64) div 49 for k = row + 64
RMOD    = ENTLO + $300          ; (k - 64) mod 49
rn_vl   = ENTLO + $400          ; speeds 12 + j/10, 8.8, j 0-140
rn_vh   = ENTLO + $500
rn_ll   = ENTLO + $600          ; streak lengths, 0.9 of those
rn_lh   = ENTLO + $700
DROPS   = FXRAM + $1000         ; $1800: the drops, one array of 64 each:
rn_yf   = DROPS                 ; y + 64.5: fraction,
rn_yk   = DROPS + $040          ; whole dots
rn_j    = DROPS + $080          ; speed index
rn_qb   = DROPS + $0C0          ; lane: byte column (signed)
rn_qm   = DROPS + $100          ; and 49ths, 0-48
rn_r1s  = DROPS + $140          ; the streak on screen: first run's row + 64 (0: none),
rn_r1e  = DROPS + $180          ; the row after its last, + 64,
rn_m1   = DROPS + $1C0          ; its first mask index,
rn_b1   = DROPS + $200          ; its byte column;
rn_r2s  = DROPS + $240          ; second run, in the byte to the left (0: none),
rn_r2e  = DROPS + $280

.assert CODE + 193 * SLOT < MT, error, "slots overrun the masks"
.assert rn_r2e + $40 <= FXRAM_END, error, "drops overrun FXRAM"
.assert NDROPS <= $40, error, "too many drops"

; ---- zero page ----
GP   = FXZ                      ; 2: where the next slot goes
RR   = FXZ+2                    ; its row
JV   = FXZ+3                    ; 2: a run's first slot
PV   = FXZ+5                    ; 2: the slot after its last
DI   = FXZ+7                    ; the drop being worked on
AK   = FXZ+8                    ; streak's first row + 64
BK   = FXZ+9                    ; and last
MM   = FXZ+10                   ; mask index at the first row
TT   = FXZ+11
ANY  = FXZ+12                   ; 1: a drop anywhere (at the start)
CC   = FXZ+13                   ; x0 = 7 CC + DD
DD   = FXZ+14
QH   = FXZ+15                   ; high byte while working out the lane
VA   = FXZ+16                   ; 3: speed, 1/65536 dot
LA   = FXZ+19                   ; 3: streak length

OP_RTS  = $60
OP_LDAY = $B9                   ; every slot's first byte

.segment "FX13"
        jmp fx_rain_init        ; the overlay's entry points
        jmp fx_rain_step

; ================================================================ init
fx_rain_init:
        jsr show_page1
        jsr build
        ldx #NDROPS - 1
:       lda #1
        jsr new_drop
        stz rn_r1s,x            ; nothing on screen yet
        stz rn_r2s,x
        dex
        bpl :-
        rts

; build: masks, row div and mod 49, the speeds, and the slots.
build:  ldx #0
        lda #1
        ldy #7
@mt:    sta MT,x
        inx
        dey
        bne :+
        asl a
        ldy #7
:       cpx #49
        bne @mt

        ldx #KB
        ldy #0
        stz TT
@rd:    lda TT
        sta RDIV,x
        tya
        sta RMOD,x
        iny
        cpy #49
        bne :+
        ldy #0
        inc TT
:       inx
        bne @rd

        ldx #5                  ; speeds: 12 and 10.8 (and a half for rounding),
:       lda acc0,x              ; up 0.1 and 0.09 at a time
        sta VA,x
        dex
        bpl :-
        ldx #0
@sp:    lda VA+1
        sta rn_vl,x
        lda VA+2
        sta rn_vh,x
        lda LA+1
        sta rn_ll,x
        lda LA+2
        sta rn_lh,x
        clc
        lda VA
        adc #<6554
        sta VA
        lda VA+1
        adc #>6554
        sta VA+1
        bcc :+
        inc VA+2
:       clc
        lda LA
        adc #<5898
        sta LA
        lda LA+1
        adc #>5898
        sta LA+1
        bcc :+
        inc LA+2
:       inx
        cpx #JMAX + 1
        bne @sp

        lda #<CODE
        sta GP
        lda #>CODE
        sta GP+1
        stz RR
@slot:  lda RR                  ; row 192 is k = 0
        clc
        adc #KB
        tay
        lda GP
        sta ENTLO,y
        lda GP+1
        sta ENTHI,y
        ldy #SLOT - 1
:       lda tpl,y
        sta (GP),y
        dey
        bpl :-
        ldx RR
        cpx #192
        bcc :+
        ldx #0                  ; row 192's slot only ever holds the rts
:       ldy #1                  ; the row's address, twice
        jsr @addr
        ldy #7
        jsr @addr
        lda GP
        clc
        adc #SLOT
        sta GP
        bcc :+
        inc GP+1
:       inc RR
        lda RR
        cmp #193
        bne @slot
        lda #OP_RTS             ; and an rts after the last, for safety
        sta (GP)
        rts
@addr:  lda row_lo,x
        sta (GP),y
        iny
        lda row_hi,x
        sta (GP),y
        rts

tpl:    .byte OP_LDAY, 0, 0, $5D, <MT, >MT, $99, 0, 0, $CA   ; lda row,y / eor MT,x / sta row,y / dex
acc0:   .byte $80, $00, 12, $4D, $CD, $0A                    ; 12, 10.8 (1/65536), + a half

; new_drop: drop X starts afresh: x0 0-310, y0 -60-0 (A = 0) or -64-191
; (A = 1, at the start), v 12.0-15.9, on a whole dot. Keeps X.
new_drop:
        sta ANY
@x:     jsr rng_next            ; x0 = 7 CC + DD: CC 0-44,
        and #63
        cmp #45
        bcs @x
        sta CC
@d:     jsr rng_next            ; DD 0-6,
        and #7
        cmp #7
        bcs @d
        sta DD
        ldy CC
        cpy #44
        bcc @xok
        cmp #3                  ; 44 * 7 + 2 = 310 at most
        bcs @x
@xok:   lda ANY
        beq @top
        jsr rng_next            ; y0 + 64.5 = n + 0.5
        bra @y
@top:   jsr rng_next            ; y0 = -(0-60)
        and #63
        cmp #61
        bcs @top
        sta TT
        lda #KB
        sec
        sbc TT
@y:     sta rn_yk,x
        lda #$80
        sta rn_yf,x
        lda CC                  ; Q = 49 CC + (7 DD + 3 + y0)
        sta rn_qb,x
        lda DD
        asl a
        asl a
        asl a
        sec
        sbc DD
        clc
        adc #3
        clc
        adc rn_yk,x             ; y0 + 64
        sta TT
        lda #0
        adc #0
        sta QH
        sec
        lda TT
        sbc #KB
        sta TT
        lda QH
        sbc #0
        sta QH
@norm:  lda QH                  ; into 0-48 49ths
        bpl @pos
        clc
        lda TT
        adc #49
        sta TT
        bcc :+
        inc QH
:       dec rn_qb,x
        bra @norm
@pos:   bne @sub
        lda TT
        cmp #49
        bcc @qok
@sub:   sec
        lda TT
        sbc #49
        sta TT
        bcs :+
        dec QH
:       inc rn_qb,x
        bra @norm
@qok:   sta rn_qm,x
@j:     jsr rng_next            ; speed 0-39 tenths over 12
        and #63
        cmp #JSTART
        bcs @j
        sta rn_j,x
        rts

; ================================================================ step
; PLAN: where drop X's streak goes on screen: rows round(y) to round(y + l),
; clipped, as up to two runs. Keeps X.
.macro PLAN
        .local nil, one, no2, done, r1off, r2
        lda rn_yk,x             ; first row: from row 0
        cmp #KB
        bcs :+
        lda #KB
:       sta AK
        ldy rn_j,x              ; last row: round(y + l), at most 191
        clc
        lda rn_yf,x
        adc rn_ll,y
        lda rn_yk,x
        adc rn_lh,y
        bcc :+
        lda #255
:       cmp AK
        bcc nil                 ; ends above the top
        sta BK
        ldy AK                  ; the lane at the first row: byte Y, mask MM
        lda rn_qm,x
        sec
        sbc RMOD,y
        sta MM
        lda rn_qb,x
        sbc RDIV,y
        tay
        lda MM
        cmp #49
        bcc :+
        adc #48                 ; borrowed: + 49 (carry is set)
        sta MM
:       sta rn_m1,x
        tya
        sta rn_b1,x
        lda MM                  ; the byte's last row
        clc
        adc AK
        bcs one                 ; past the bottom
        cmp BK
        bcs one
        inc a                   ; two runs: the second starts here
        sta TT
        cpy #40                 ; first run on screen? (byte 0-39)
        bcs r1off
        sta rn_r1e,x
        lda AK
        sta rn_r1s,x
        bra r2
r1off:  stz rn_r1s,x
r2:     dey                     ; second run's byte
        cpy #40
        bcs no2
        lda TT
        sta rn_r2s,x
        lda BK
        inc a
        sta rn_r2e,x
        bra done
one:    cpy #40                 ; one run, if on screen
        bcs nil
        lda AK
        sta rn_r1s,x
        lda BK
        inc a
        sta rn_r1e,x
no2:    stz rn_r2s,x
        bra done
nil:    stz rn_r1s,x
        stz rn_r2s,x
done:
.endmacro

; FLIP: flip drop X's streak, as planned (draws it, or rubs it out). Keeps X.
.macro FLIP
        .local two, done
        stx DI
        lda rn_r1s,x
        beq two
        tay
        lda ENTLO,y
        sta JV
        lda ENTHI,y
        sta JV+1
        ldy rn_r1e,x
        lda ENTLO,y
        sta PV
        lda ENTHI,y
        sta PV+1
        lda #OP_RTS             ; rts after the last row
        sta (PV)
        ldy rn_b1,x
        lda rn_m1,x
        tax
        jsr go
        lda #OP_LDAY            ; and the slot back as it was
        sta (PV)
        ldx DI
two:    lda rn_r2s,x
        beq done
        tay
        lda ENTLO,y
        sta JV
        lda ENTHI,y
        sta JV+1
        ldy rn_r2e,x
        lda ENTLO,y
        sta PV
        lda ENTHI,y
        sta PV+1
        lda #OP_RTS
        sta (PV)
        ldy rn_b1,x             ; from the right of the byte to the left
        dey
        ldx #48
        jsr go
        lda #OP_LDAY
        sta (PV)
        ldx DI
done:
.endmacro

fx_rain_step:
        ldx #NDROPS - 1
st_drop:  FLIP                    ; rub out its streak
        ldy rn_j,x              ; fall a step
        clc
        lda rn_yf,x
        adc rn_vl,y
        sta rn_yf,x
        lda rn_yk,x
        adc rn_vh,y
        sta rn_yk,x
        bcs st_again              ; y + 64.5 past 256: past the bottom
        cmp #255                ; y > 191: y + 64.5 > 255.5
        bne st_on
        lda rn_yf,x
        cmp #$81
        bcs st_again
st_on:    tya                     ; and speed up (carry is clear)
        adc #ACCEL
        cmp #JMAX + 1
        bcc st_fast
        lda #JMAX
st_fast:  sta rn_j,x
        bra st_plan
st_again: lda #0                  ; start again above the top
        jsr new_drop
st_plan:  PLAN
        FLIP                    ; and draw it where it is now
        txa
        and #3
        bne st_next
        jsr vbl_poll
st_next:  dex
        bmi st_done
        jmp st_drop
st_done:  rts

; rn_plan, rn_flip: the same, one drop at a time.
rn_plan:
        PLAN
        rts
rn_flip:
        FLIP
        rts
go:     jmp (JV)

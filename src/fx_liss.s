; Effect 5: Lissajous, after the original. Points jump about a quarter turn
; at a time round a tilted ellipse, x = 140 + 127 sin(t), y = 96 + 86 sin(t +
; phase), and each is joined to the last by a straight line. The last 100
; lines stay on screen, so they make slowly turning near-squares round an
; empty middle. The phase (the tilt) drifts, so the ellipse fattens, thins
; and turns over; every 400 steps the jump is picked again, now and then a
; third of a turn instead. Drawn straight onto page 1.

.include "config.inc"

.export fx_liss_init, fx_liss_step
.export lis_th, lis_dth, lis_ph, lis_n, lis_count, lis_head

.import rng_next, fline, show_page1, vbl_poll, lsx, lsy

CAP     = 101                   ; points kept: 100 lines
REPICK  = 400                   ; steps between new jumps
PH_STEP = $1A                   ; tilt drift a step, 8.8 (0.0025 radians)

; ---- state in FXRAM ----
lis_xl    = FXRAM               ; point ring: x lo, x hi, y
lis_xh    = lis_xl + 256
lis_y     = lis_xh + 256
lis_head  = lis_y + 256         ; newest point
lis_count = lis_head + 1        ; points kept
lis_th    = lis_count + 1       ; 2: t, 8.8, 256 = a full turn
lis_dth   = lis_th + 2          ; 2: the jump, 8.8
lis_ph    = lis_dth + 2         ; 2: phase, 8.8
lis_n     = lis_ph + 2          ; 2: steps since the jump was picked

; ---- zero page ----
NX   = FXZ                      ; 2: the new point
NY   = FXZ+2

.segment "CODE"

; ================================================================ init
fx_liss_init:
        jsr show_page1
        stz lis_count
        stz lis_head
        stz lis_th
        jsr rng_next            ; start anywhere round the ellipse
        sta lis_th+1
        stz lis_ph
        lda #32                 ; tilt 45 degrees
        sta lis_ph+1
        stz lis_n
        stz lis_n+1
        jmp quarter             ; the first jump is always about a quarter turn

; pick: a new jump, about a quarter turn 7 times in 10, else about a third.
pick:   jsr rng_next
        cmp #179
        bcc quarter
        jsr rng_next            ; $5100-$57FF: 81-87 of 256
        sta lis_dth
        jsr rng_next
        and #$07
        cmp #7
        bcc :+
        lda #6
:       clc
        adc #$51
        sta lis_dth+1
        rts
quarter:
        jsr rng_next            ; $3D00-$44FF: 61-68 of 256
        sta lis_dth
        jsr rng_next
        and #$07
        clc
        adc #$3D
        sta lis_dth+1
        rts

; ================================================================ step
fx_liss_step:
        lda #PAGE1
        sta PAGE
        lda lis_count           ; full: the oldest line goes first, so the
        cmp #CAP                ; newest is always drawn whole
        bcc :+
        jsr erase_oldest
        jsr vbl_poll            ; tall lines don't count blanks themselves
:       clc                     ; t += jump
        lda lis_th
        adc lis_dth
        sta lis_th
        lda lis_th+1
        adc lis_dth+1
        sta lis_th+1
        clc                     ; phase drifts
        lda lis_ph
        adc #PH_STEP
        sta lis_ph
        bcc :+
        inc lis_ph+1
:       inc lis_n               ; every 400 steps, a new jump
        bne :+
        inc lis_n+1
:       lda lis_n
        cmp #<REPICK
        bne @point
        lda lis_n+1
        cmp #>REPICK
        bne @point
        stz lis_n
        stz lis_n+1
        jsr pick

@point: ldx lis_th+1            ; x = 140 + 127 sin(t)
        lda lsx,x
        clc
        adc #140
        sta NX
        lda #0
        adc #0                  ; the carry is the high byte for sin >= 0;
        ldy lsx,x               ; for sin < 0 the add always carries, and
        bpl :+                  ; the high byte is 0
        lda #0
:       sta NX+1
        clc                     ; y = 96 + 86 sin(t + phase)
        lda lis_th
        adc lis_ph
        lda lis_th+1
        adc lis_ph+1
        tax
        lda lsy,x
        clc
        adc #96
        sta NY

        lda lis_count           ; join it to the last point
        beq @store
        ldx lis_head
        lda lis_xl,x
        sta PX
        lda lis_xh,x
        sta PX+1
        lda lis_y,x
        sta PY
        stz PY+1
        lda NX
        sta PX2
        lda NX+1
        sta PX2+1
        lda NY
        sta PY2
        stz PY2+1
        lda #1
        sta PCOL
        jsr fline
@store: inc lis_head            ; keep it
        ldx lis_head
        lda NX
        sta lis_xl,x
        lda NX+1
        sta lis_xh,x
        lda NY
        sta lis_y,x
        inc lis_count
        rts

; erase_oldest: clear the line between the two oldest points; one point goes.
erase_oldest:
        lda lis_head            ; oldest = head - count + 1
        sec
        sbc lis_count
        tax
        inx
        lda lis_xl,x
        sta PX
        lda lis_xh,x
        sta PX+1
        lda lis_y,x
        sta PY
        stz PY+1
        inx
        lda lis_xl,x
        sta PX2
        lda lis_xh,x
        sta PX2+1
        lda lis_y,x
        sta PY2
        stz PY2+1
        stz PCOL
        jsr fline
        dec lis_count
        rts

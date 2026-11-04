; Effect 5: Lissajous. One line traces x = 140 + 127 sin(a t + phase),
; y = 96 + 86 sin(b t), leaving a trail that is erased from its oldest end.
; The phase drifts, so the figure slowly twists. After 900 steps the line
; draws itself back in and a new figure starts. Drawn straight onto page 1.

.include "config.inc"

.export fx_liss_init, fx_liss_step
.export lis_a, lis_b, lis_n, lis_leaving, lis_count, lis_head, lis_t

.import rng_next, rng_below, line, show_page1, lsx, lsy

CAP   = 255                     ; points in the trail

; ---- state in FXRAM ----
lis_xl      = FXRAM             ; trail ring: x lo, x hi, y
lis_xh      = lis_xl + 256
lis_y       = lis_xh + 256
lis_head    = lis_y + 256       ; newest point
lis_count   = lis_head + 1      ; points in the trail
lis_t       = lis_count + 1     ; 2: t, 8.8, 256 = a full turn
lis_ph      = lis_t + 2         ; 2: phase, 8.8
lis_a       = lis_ph + 2        ; the figure: a and b
lis_b       = lis_a + 1
lis_n       = lis_b + 1         ; 2: steps into this figure
lis_leaving = lis_n + 2         ; 1 while the line draws itself back in

; ---- zero page ----
K    = FXZ
P0   = FXZ+1                    ; 2: product scratch
NX   = FXZ+3                    ; 2: the new point
NY   = FXZ+5

.segment "CODE"

; figures (a, b)
fig_a:  .byte 3, 5, 3, 1, 5, 2
fig_b:  .byte 2, 4, 4, 2, 6, 3

; ================================================================ init
fx_liss_init:
        jsr show_page1
fresh:  lda #6                  ; a new figure
        jsr rng_below
        tax
        lda fig_a,x
        sta lis_a
        lda fig_b,x
        sta lis_b
        stz lis_t
        stz lis_t+1
        stz lis_ph
        jsr rng_next
        sta lis_ph+1
        stz lis_count
        stz lis_head
        stz lis_n
        stz lis_n+1
        stz lis_leaving
        rts

; ================================================================ step
fx_liss_step:
        lda #PAGE1
        sta PAGE
        lda lis_leaving
        beq @draw
        lda #4                  ; drawing back in: 4 segments a step
        sta K
:       lda lis_count
        cmp #2
        bcc fresh               ; all gone: start a new figure
        jsr erase_oldest
        dec K
        bne :-
        rts

@draw:  lda #2                  ; two new points a step
        sta K
@pt:    clc                     ; t += 1.0156 (0.025 radians)
        lda lis_t
        adc #$04
        sta lis_t
        lda lis_t+1
        adc #$01
        sta lis_t+1
        clc                     ; phase += 0.0625 (0.0015 radians)
        lda lis_ph
        adc #$10
        sta lis_ph
        bcc :+
        inc lis_ph+1
:       lda lis_a               ; x = 140 + 127 sin(a t + phase)
        jsr times_t
        clc
        lda P0
        adc lis_ph
        lda P0+1
        adc lis_ph+1
        tax
        lda lsx,x
        clc
        adc #140
        sta NX
        lda lsx,x
        bmi :+
        lda #0
        adc #0
        bra :++
:       lda #$FF
        adc #0
:       sta NX+1
        lda lis_b               ; y = 96 + 86 sin(b t)
        jsr times_t
        ldx P0+1
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
        jsr line
@store: inc lis_head            ; add it to the trail
        ldx lis_head
        lda NX
        sta lis_xl,x
        lda NX+1
        sta lis_xh,x
        lda NY
        sta lis_y,x
        inc lis_count
        lda lis_count           ; full: the oldest segment goes
        cmp #CAP
        bcc :+
        jsr erase_oldest
:       dec K
        beq :+
        jmp @pt

:       inc lis_n               ; after 900 steps, draw back in
        bne :+
        inc lis_n+1
:       lda lis_n+1
        cmp #>900
        bcc @done
        lda lis_n
        cmp #<900
        bcc @done
        lda #1
        sta lis_leaving
@done:  rts

; erase_oldest: clear the segment between the two oldest points; the trail
; loses a point.
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
        jsr line
        dec lis_count
        rts

; times_t: P0 = A * lis_t (16-bit, wrapping), A = 1-6
times_t:
        tax
        stz P0
        stz P0+1
:       clc
        lda P0
        adc lis_t
        sta P0
        lda P0+1
        adc lis_t+1
        sta P0+1
        dex
        bne :-
        rts

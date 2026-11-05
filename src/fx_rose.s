; Effect 8: Rose. Big 2 x 2 dots trace loops round a ring:
;   x = 140 + 1.1 (36 cos(t + rot) + 18 cos(k t + rot))
;   y =  96 +      36 sin(t + rot) + 18 sin(k t + rot)
; with t moving on 0.03 radians and rot 0.0008 a point, four points a step.
; k is a whole number 5-11 plus 0.015-0.04, so there are k - 1 loops round
; the ring and they creep round a little each time; k is picked again every
; 900 steps. The last 900 dots stay: once there are 900, each new dot first
; rubs out the oldest, so the old figure fades as the new one comes. Drawn
; straight onto page 1.

.include "config.inc"

.export fx_rose_init, fx_rose_step
.export rose_x, rose_y, rose_head, rose_tail, rose_count
.export rose_t, rose_kt, rose_rot, rose_kdt, rose_n

.import rng_next, rng_below, show_page1
.import row_lo, row_hi, xbyte_lo, xbit_lo

CAP     = 900                   ; dots kept
REPICK  = 900                   ; steps between new loop counts
; Angles are 24 bits: the top byte is the table step (256 to a turn).
DT      = 80105                 ; 0.03 radians
DROT    = 2136                  ; 0.0008 radians
FMIN    = 1204                  ; k's fraction 0.015 (x DT), up to FMIN + 249 x 8:
                                ; 0.04

; ---- state in FXRAM ----
rose_x     = FXRAM              ; 1024: ring of dots, x (top-left of the dot)
rose_y     = FXRAM + $0400      ; 1024: ... and y
rose_head  = FXRAM + $0800      ; 2: next slot to fill, 0-1023
rose_tail  = rose_head + 2      ; 2: oldest dot kept
rose_count = rose_tail + 2      ; 2: dots kept, 0-900
rose_t     = rose_count + 2     ; 3: t
rose_kt    = rose_t + 3         ; 3: k t
rose_rot   = rose_kt + 3        ; 3: rot
rose_kdt   = rose_rot + 3       ; 3: k x DT
rose_n     = rose_kdt + 3       ; 2: steps since k was picked

; ---- zero page ----
ROW0 = FXZ                      ; 2: the dot's top row
ROW1 = FXZ+2                    ; 2: its bottom row
MASK = FXZ+4
RP   = FXZ+5                    ; 2: a slot in the ring
NX   = FXZ+7                    ; the new dot
NY   = FXZ+8
LEFT = FXZ+9                    ; points still to add this step
FHI  = FXZ+10                   ; while picking k: its fraction's high byte
WHOLE = FXZ+11                  ; ... and its whole number

.segment "FX8"
        jmp fx_rose_init        ; the overlay's entry points
        jmp fx_rose_step

; ================================================================ init
fx_rose_init:
        jsr show_page1
        ldx #rose_n + 2 - rose_head - 1
:       stz rose_head,x         ; empty ring, t = k t = 0
        dex
        bpl :-
        jsr rng_next            ; rot starts anywhere
        sta rose_rot+2
        ; fall through

; pick: k = 5-11 plus 0.015-0.04, as k x DT. The step count starts again.
pick:   stz rose_n
        stz rose_n+1
        lda #7                  ; the whole number
        jsr rng_below
        clc
        adc #5
        sta WHOLE
        lda #250                ; the fraction: FMIN + 8 r
        jsr rng_below
        stz FHI
        asl a
        rol FHI
        asl a
        rol FHI
        asl a
        rol FHI
        clc
        adc #<FMIN
        sta rose_kdt
        lda FHI
        adc #>FMIN
        sta rose_kdt+1
        stz rose_kdt+2
:       clc                     ; plus the whole number x DT
        lda rose_kdt
        adc #<DT
        sta rose_kdt
        lda rose_kdt+1
        adc #>DT
        sta rose_kdt+1
        lda rose_kdt+2
        adc #^DT
        sta rose_kdt+2
        dec WHOLE
        bne :-
        rts

; ================================================================ step
fx_rose_step:
        lda #4
        sta LEFT
@point: lda rose_count          ; full: the oldest dot goes first
        cmp #<CAP
        bne @grow
        lda rose_count+1
        cmp #>CAP
        bne @grow
        jsr erase_oldest
        bra @move
@grow:  inc rose_count
        bne @move
        inc rose_count+1

@move:  clc                     ; t += DT
        lda rose_t
        adc #<DT
        sta rose_t
        lda rose_t+1
        adc #>DT
        sta rose_t+1
        lda rose_t+2
        adc #^DT
        sta rose_t+2
        clc                     ; k t += k DT
        lda rose_kt
        adc rose_kdt
        sta rose_kt
        lda rose_kt+1
        adc rose_kdt+1
        sta rose_kt+1
        lda rose_kt+2
        adc rose_kdt+2
        sta rose_kt+2
        clc                     ; rot += DROT
        lda rose_rot
        adc #<DROT
        sta rose_rot
        lda rose_rot+1
        adc #>DROT
        sta rose_rot+1
        lda rose_rot+2
        adc #^DROT
        sta rose_rot+2

        clc                     ; X = step of t + rot
        lda rose_t
        adc rose_rot
        lda rose_t+1
        adc rose_rot+1
        lda rose_t+2
        adc rose_rot+2
        tax
        clc                     ; Y = step of k t + rot
        lda rose_kt
        adc rose_rot
        lda rose_kt+1
        adc rose_rot+1
        lda rose_kt+2
        adc rose_rot+2
        tay
        lda rose_cx,y           ; x: the loop, half the ring's size...
        cmp #$80                ; (signed halving, rounded)
        ror a
        adc #0
        clc                     ; ...plus the ring. The offsets are signed
        adc rose_cx,x           ; and the dot is always on screen, so
        clc                     ; plain byte sums work.
        adc #140
        sta NX
        lda rose_sy,y           ; y likewise
        cmp #$80
        ror a
        adc #0
        clc
        adc rose_sy,x
        clc
        adc #96
        sta NY

        lda rose_head           ; keep it
        sta RP
        lda rose_head+1
        clc
        adc #>rose_x
        sta RP+1
        lda NX
        sta (RP)
        lda RP+1
        adc #>(rose_y - rose_x) ; (carry clear)
        sta RP+1
        lda NY
        sta (RP)
        inc rose_head
        bne :+
        lda rose_head+1
        inc a
        and #$03
        sta rose_head+1
:       ldx NX                  ; and draw it
        ldy NY
        jsr dot_set
        dec LEFT
        beq :+
        jmp @point

:       inc rose_n              ; every 900 steps, a new k
        bne :+
        inc rose_n+1
:       lda rose_n
        cmp #<REPICK
        bne :+
        lda rose_n+1
        cmp #>REPICK
        bne :+
        jmp pick
:       rts

; erase_oldest: rub out the oldest dot; it leaves the ring.
erase_oldest:
        lda rose_tail
        sta RP
        lda rose_tail+1
        clc
        adc #>rose_x
        sta RP+1
        lda (RP)
        tax
        lda RP+1
        adc #>(rose_y - rose_x) ; (carry clear)
        sta RP+1
        lda (RP)
        tay
        jsr dot_clear
        inc rose_tail
        bne :+
        lda rose_tail+1
        inc a
        and #$03
        sta rose_tail+1
:       rts

; ================================================================ dots
; dot_set / dot_clear: the 2 x 2 dot with its top-left at x = X (0-254),
; y = Y (0-190), on page 1.
.macro DOT apply
        .local split
        lda row_lo,y
        sta ROW0
        lda row_hi,y
        sta ROW0+1
        lda row_lo+1,y
        sta ROW1
        lda row_hi+1,y
        sta ROW1+1
        ldy xbyte_lo,x
        lda xbit_lo,x
        cmp #$40
        beq split
        sta MASK                ; x and x + 1 in the same byte
        asl a
        ora MASK
        jmp apply
split:  lda #$40                ; x is the byte's last dot, x + 1 the next's first
        jsr apply
        iny
        lda #$01
        jmp apply
.endmacro

dot_set:   DOT apply1
dot_clear: DOT apply0

; apply1 / apply0: set / clear the dots A in byte Y of both rows.
apply1: sta MASK
        lda (ROW0),y
        ora MASK
        sta (ROW0),y
        lda (ROW1),y
        ora MASK
        sta (ROW1),y
        rts
apply0: eor #$7F
        sta MASK
        lda (ROW0),y
        and MASK
        sta (ROW0),y
        lda (ROW1),y
        and MASK
        sta (ROW1),y
        rts

.include "rose_tables.inc"

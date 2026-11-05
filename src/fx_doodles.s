; Effect 9: Doodles. The screen is split into a grid of cells, 4-8 across and
; 3-6 down (picked afresh for each grid), and a pen fills them one at a time,
; left to right, top to bottom. Each doodle is one smooth looping stroke: 41
; points joined by 40 straight lines, two lines a step, so a doodle takes 20
; steps. Point i is at t = end * i / 40, end 0.75-1 of a turn:
;   x = cx + ax (0.63 sin(f0 t + q0) + 0.37 sin(f1 t + q1))
;   y = cy + ay (0.63 sin(f2 t + q2) + 0.37 sin(f3 t + q3))
; f0, f2 1-3, f1, f3 2-5, q random, (cx, cy) the cell's centre, ax 0.34 of the
; cell's width, ay 0.38 of its height. A full grid stays up for 75 steps; then
; the screen is cleared 16 rows a step from the top, and a new grid starts.
; Drawn straight onto page 1.

.include "config.inc"

.export fx_doodles_init, fx_doodles_step
.export dd_mode, dd_cols, dd_rows, dd_ncell, dd_cell, dd_col, dd_row, dd_k
.export dd_hold, dd_crow, dd_f, dd_q, dd_dt, dd_nx, dd_ny

.import rng_next, rng_below, fline, show_page1, row_lo, row_hi

PTS      = 41                   ; points in a doodle
HOLD     = 75                   ; steps a full grid stays up
BAND     = 16                   ; rows cleared a step (192 / 16 = 12 steps)
DT_MIN   = 1229                 ; t's step a point, 1/65536 of a turn: 40 of
DT_SPAN  = 205                  ; them make 0.75 of a turn, plus 2 * (0-204) + 0-1
                                ; (up to 1638: 0.9998 of a turn)

DRAW     = 0                    ; dd_mode
HOLDING  = 1
CLEARING = 2

; ---- state in FXRAM ----
dd_mode  = FXRAM
dd_cols  = FXRAM+1              ; grid: 4-8 across
dd_rows  = FXRAM+2              ; 3-6 down
dd_ncell = FXRAM+3              ; cols * rows
dd_cell  = FXRAM+4              ; the cell being drawn, 0 top left
dd_col   = FXRAM+5              ; ...its column
dd_row   = FXRAM+6              ; ...and row
dd_k     = FXRAM+7              ; the doodle's next point, 1-41
dd_hold  = FXRAM+8              ; steps the full grid has been up
dd_crow  = FXRAM+9              ; next row to clear
dd_f     = FXRAM+10             ; 4: the wobbles' frequencies
dd_q     = FXRAM+14             ; 4 x 2: their phases, 1/65536 of a turn
dd_dt    = FXRAM+22             ; 2: t's step a point, 1/65536 of a turn

; ---- zero page ----
PH    = FXZ                     ; 4 x 2: each wobble's angle now, 8.8 of 1/256 turn
DP    = FXZ+8                   ; 4 x 2: how far each turns a point (f * dt)
NX    = FXZ+16                  ; 2: the newest point
NY    = FXZ+18
CX    = FXZ+19                  ; 2: the cell's centre
CY    = FXZ+21
AMPX  = FXZ+22                  ; the doodle's reach, offset = wobble * amp / 256
AMPY  = FXZ+23
XBASE = FXZ+24                  ; (cols - 4) * 8: the grid's row of dd_cxl/dd_cxh
YBASE = FXZ+25                  ; (rows - 3) * 8: its row of dd_cyt
MA    = FXZ+26                  ; scale: multiplicand
MB    = FXZ+27                  ; scale: multiplier, then the product's low byte
SG    = FXZ+28                  ; scale: the wobble's sign
CPTR  = FXZ+29                  ; 2: row being cleared
TMP   = FXZ+31

dd_nx = NX
dd_ny = NY

.segment "FX9"
        jmp fx_doodles_init     ; the overlay's entry points
        jmp fx_doodles_step

; ================================================================ init
fx_doodles_init:
        jsr show_page1
        jmp new_grid

; ================================================================ step
fx_doodles_step:
        lda #PAGE1
        sta PAGE
        lda dd_mode
        beq @draw
        cmp #HOLDING
        beq @hold
        jmp clear_band
@hold:  inc dd_hold             ; the 76th step starts clearing
        lda dd_hold
        cmp #HOLD+1
        bcc @done
        lda #CLEARING
        sta dd_mode
        stz dd_crow
        jmp clear_band
@draw:  jsr segment
        jsr segment
        lda dd_k
        cmp #PTS
        bcc @done
        inc dd_cell             ; doodle done: the next cell
        inc dd_col
        lda dd_col
        cmp dd_cols
        bcc :+
        stz dd_col
        inc dd_row
:       lda dd_cell
        cmp dd_ncell
        bcs @full
        jmp new_doodle
@full:  lda #HOLDING            ; grid full: hold it
        sta dd_mode
        stz dd_hold
@done:  rts

; segment: a line from the newest point to the next one.
segment:
        lda NX
        sta PX
        lda NX+1
        sta PX+1
        lda NY
        sta PY
        stz PY+1
        jsr next_point
        lda NX
        sta PX2
        lda NX+1
        sta PX2+1
        lda NY
        sta PY2
        stz PY2+1
        lda #1
        sta PCOL
        inc dd_k
        jmp fline               ; short, and wholly inside the cell

; clear_band: clear the next 16 rows; after the last, a new grid.
clear_band:
        ldx dd_crow
        lda #BAND
        sta TMP
@row:   lda row_lo,x
        sta CPTR
        lda row_hi,x
        sta CPTR+1
        lda #0
        ldy #39
:       sta (CPTR),y
        dey
        bpl :-
        inx
        dec TMP
        bne @row
        stx dd_crow
        cpx #192
        bcs new_grid
        rts

; ================================================================ grid
; new_grid: pick the grid's size and start its first doodle.
new_grid:
        lda #5                  ; 4-8 across
        jsr rng_below
        tax
        lda dd_ampx,x
        sta AMPX
        txa
        asl a
        asl a
        asl a
        sta XBASE
        txa
        clc
        adc #4
        sta dd_cols
        lda #4                  ; 3-6 down
        jsr rng_below
        tax
        lda dd_ampy,x
        sta AMPY
        txa
        asl a
        asl a
        asl a
        sta YBASE
        txa
        clc
        adc #3
        sta dd_rows
        tax                     ; cells = cols * rows
        lda #0
:       clc
        adc dd_cols
        dex
        bne :-
        sta dd_ncell
        stz dd_cell
        stz dd_col
        stz dd_row
        stz dd_mode
        ; fall through

; new_doodle: the cell's centre, a new stroke's wobbles, and its point 0.
new_doodle:
        lda XBASE
        clc
        adc dd_col
        tax
        lda dd_cxl,x
        sta CX
        lda dd_cxh,x
        sta CX+1
        lda YBASE
        clc
        adc dd_row
        tax
        lda dd_cyt,x
        sta CY
        lda #DT_SPAN            ; dt = 1229 + 0-409
        jsr rng_below
        asl a
        sta dd_dt
        lda #0
        rol a
        sta dd_dt+1
        jsr rng_next
        and #1
        ora dd_dt
        clc
        adc #<DT_MIN
        sta dd_dt
        lda dd_dt+1
        adc #>DT_MIN
        sta dd_dt+1
        ldy #0                  ; frequencies: f0 1-3, f1 2-5, f2 1-3, f3 2-5
@f:     tya
        lsr a
        bcs @fast
        lda #3
        jsr rng_below
        inc a
        bra :+
@fast:  lda #4
        jsr rng_below
        clc
        adc #2
:       sta dd_f,y
        iny
        cpy #4
        bne @f
        ldx #0                  ; each wobble starts at a random phase and
        ldy #0                  ; turns f * dt a point
@q:     jsr rng_next
        sta dd_q,x
        jsr rng_next
        sta dd_q+1,x
        clc                     ; rounded, as the tables use the high byte
        lda dd_q,x
        adc #$80
        sta PH,x
        lda dd_q+1,x
        adc #0
        sta PH+1,x
        stz DP,x
        stz DP+1,x
        lda dd_f,y
        sta TMP
:       clc
        lda DP,x
        adc dd_dt
        sta DP,x
        lda DP+1,x
        adc dd_dt+1
        sta DP+1,x
        dec TMP
        bne :-
        inx
        inx
        iny
        cpy #4
        bne @q
        lda #1
        sta dd_k
        bra point               ; point 0

; ================================================================ points
; next_point: every wobble turns on by its step; NX/NY = the point there.
next_point:
        ldx #6
:       clc
        lda PH,x
        adc DP,x
        sta PH,x
        lda PH+1,x
        adc DP+1,x
        sta PH+1,x
        dex
        dex
        bpl :-
point:  ldx PH+1                ; x = cx + (80 sin ph0 + 47 sin ph1) * amp / 256
        lda dd_sa,x
        ldx PH+3
        clc
        adc dd_sb,x
        ldx AMPX
        jsr scale
        ldx #0
        cmp #$80
        bcc :+
        dex
:       clc
        adc CX
        sta NX
        txa
        adc CX+1
        sta NX+1
        ldx PH+5                ; y likewise, from ph2 and ph3
        lda dd_sa,x
        ldx PH+7
        clc
        adc dd_sb,x
        ldx AMPY
        jsr scale
        clc
        adc CY
        sta NY                  ; y last (the tests watch for it)
        rts

; scale: A = wobble (signed, -127 to 127), X = amp. Returns
; round(wobble * amp / 256), signed, in A.
scale:  stx MB
        sta SG
        bit SG
        bpl :+
        eor #$FF
        inc a
:       sta MA
        lda #0                  ; MA * MB: A high byte, MB low
        ldx #8
        lsr MB
@mul:   bcc :+
        clc
        adc MA
:       ror a
        ror MB
        dex
        bne @mul
        ldx MB                  ; round
        bpl :+
        inc a
:       bit SG
        bpl :+
        eor #$FF
        inc a
:       rts

.include "doodles_tables.inc"

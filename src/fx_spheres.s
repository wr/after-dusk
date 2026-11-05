; Effect 11: Spheres, after the original (Offset 3, Clear Every 10). A sphere
; is 34 filled circles, one a step, each smaller and brighter than the last
; and nudged up and to the right, towards the highlight, so it glows up out
; of a dark disc. For a sphere of radius r centred anywhere on screen,
; circle k = 0..33 has radius r sqrt(1 - k/33), its centre moved
; r 3/20 sqrt(k/33) up and 1.1 times that right, and grey level
; round((24 + 7k) / 255 x 16), drawn opaque (every dot set or cleared by the
; dither). After 10 spheres the picture holds, the screen clears (top half,
; then bottom half: the last two of the 16 steps), and it starts again.
; Drawn straight onto page 1.
;
; r is 12-44, not the original's 12-58 (Maximum Size 60%): at 15 circles a
; second the biggest circle must be drawn in 4 ticks, and a 44 takes about
; 59,000 of the 67,820 cycles.
;
; Sizes are in quarter dots, and the centre's height is kept to the nearest
; half dot so the rows pair up round it: each pair, from the middle out, is
; two pspan runs of the same width. The runs' half-width h (y scale) is kept
; from pair to pair with T = R^2 - D^2 (R the radius, D the rows' distance
; from the centre): h^2 <= T < (h + 1)^2, as delta = T - h^2 and k = 2h + 1,
; so each step of h costs an add.

.include "config.inc"

.export fx_spheres_init, fx_spheres_step, sp_fresh
.export sp_r, sp_cx, sp_cy, sp_k, sp_count, sp_hold, sp_rr, sp_ccx, sp_ccy, sp_lev

.import rng_next, rng_below, pspan, show_page1, vbl_poll, row_lo, row_hi

NCIRC   = 34                    ; circles a sphere
NSPH    = 10                    ; spheres before the screen clears
HOLD    = 16                    ; steps the last one stays, clear included
RMAX    = 44                    ; the biggest sphere (see above; and gen_spheres.py)

; ---- state in FXRAM ----
sp_r     = FXRAM                ; the sphere: radius 12-44
sp_cx    = sp_r + 1             ; 2: centre x 0-279
sp_cy    = sp_cx + 2            ; centre y 0-191
sp_k     = sp_cy + 1            ; the next circle, 0-33 (34: done)
sp_count = sp_k + 1             ; spheres finished since the last clear
sp_hold  = sp_count + 1         ; steps left before the clear, 0 when drawing
sp_rr    = sp_hold + 1          ; the last circle: radius, quarter dots
sp_ccx   = sp_rr + 1            ; 2: its centre, quarter dots
sp_ccy   = sp_ccx + 2           ; 2: signed
sp_lev   = sp_ccy + 2           ; its grey

; ---- zero page ----
R4    = FXZ                     ; radius, quarter dots
CX4   = FXZ+1                   ; 2: centre, quarter dots
CY4   = FXZ+3                   ; 2: signed
DLT   = FXZ+5                   ; 2: T - h^2, signed
EE    = FXZ+7                   ; 2: what T loses to the next pair out, 8D + 16
KK    = FXZ+9                   ; 2: 2h + 1
CL    = FXZ+11                  ; 2: centre x + 3
DD    = FXZ+13                  ; D: the pair's distance from the centre
TMP   = FXZ+14                  ; 2
MCAND = FXZ+16                  ; mul8r
MPLR  = FXZ+17
MLO   = FXZ+18
CPTR  = FXZ+19                  ; 2: clear's row pointer
PYT   = FXZ+21                  ; 2: the pair's top row
PYB   = FXZ+23                  ; 2: and bottom row

.segment "FX11"
        jmp fx_spheres_init     ; the overlay's entry points
        jmp fx_spheres_step

; ================================================================ init
fx_spheres_init:
        jsr show_page1
        stz sp_count
        stz sp_hold
        ; fall through

; sp_fresh: a new sphere, anywhere on screen, at any size.
sp_fresh:
        lda #RMAX - 11          ; r = 12-44
        jsr rng_below
        clc
        adc #12
        sta sp_r
@x:     jsr rng_next            ; x = 0-279
        and #1
        sta sp_cx+1
        jsr rng_next
        sta sp_cx
        ldx sp_cx+1
        beq :+
        cmp #24
        bcs @x
:       lda #192                ; y = 0-191
        jsr rng_below
        sta sp_cy
        stz sp_k
        rts

; ================================================================ step
fx_spheres_step:
        lda sp_hold
        beq @draw
        dec sp_hold             ; the finished picture stays...
        beq @bottom
        lda sp_hold
        cmp #1
        bne @rts
        ldx #0                  ; ...then the top half goes...
        jmp clear
@bottom:
        ldx #96                 ; ...and the bottom, and a new one starts
        jsr clear
        jmp sp_fresh
@draw:  jsr circle
        inc sp_k
        lda sp_k
        cmp #NCIRC
        bcc @rts
        inc sp_count            ; a sphere done
        lda sp_count
        cmp #NSPH
        bcc sp_fresh
        stz sp_count
        lda #HOLD
        sta sp_hold
@rts:   rts

; clear: rows X to X + 95 of page 1 to black, counting vertical blanks.
clear:  stx TMP
        lda #96
        sta TMP+1
@row:   ldx TMP
        lda row_lo,x
        sta CPTR
        lda row_hi,x
        sta CPTR+1
        lda #0
        ldy #39
:       sta (CPTR),y
        dey
        bpl :-
        jsr vbl_poll
        inc TMP
        dec TMP+1
        bne @row
        rts

; mul8r: A x Y / 256, rounded. Keeps X.
mul8r:  sta MCAND
        sty MPLR
        lda #0
        ldy #8
@l:     lsr MPLR
        bcc :+
        clc
        adc MCAND
:       ror a
        ror MLO
        dey
        bne @l
        asl MLO
        adc #0
        rts

; ================================================================ circle
; circle: draw circle sp_k of the sphere.
circle:
        ldx sp_k
        lda sp_tl,x             ; its grey
        sta sp_lev
        lda sp_r                ; radius: 4r sqrt(1 - k/33)
        asl a
        asl a
        cpx #0
        beq :+
        ldy sp_tr,x
        jsr mul8r
:       sta R4
        sta sp_rr
        lda sp_cx               ; centre x: 4 cx + 1.1 offset
        sta CX4
        lda sp_cx+1
        asl CX4
        rol a
        asl CX4
        rol a
        sta CX4+1
        lda sp_r
        ldy sp_tox,x
        jsr mul8r
        clc
        adc CX4
        sta CX4
        sta sp_ccx
        bcc :+
        inc CX4+1
:       lda CX4+1
        sta sp_ccx+1
        lda sp_cy               ; centre y: 4 cy - offset, to the nearest
        stz CY4+1               ; half dot, so the rows pair up round it
        asl a
        rol CY4+1
        asl a
        rol CY4+1
        sta CY4
        lda sp_r
        ldy sp_to,x
        jsr mul8r
        sta TMP
        sec
        lda CY4
        sbc TMP
        tax
        lda CY4+1
        sbc #0
        tay
        txa
        clc
        adc #1
        and #$FE
        sta CY4
        sta sp_ccy
        tya
        adc #0
        sta CY4+1
        sta sp_ccy+1

        ; rows in pairs, top and bottom, from the middle out: on a whole dot
        ; c, rows c - d and c + d (D = 4d); on a half dot c + 1/2, rows c - d
        ; and c + 1 + d (D = 4d + 2)
        lda CY4
        and #2
        sta DD                  ; D for the first pair: 0 or 2
        lda CY4+1               ; c = cy >> 2, signed
        sta PYB+1
        cmp #$80
        ror PYB+1
        lda CY4
        ror a
        sta PYB
        lda PYB+1
        cmp #$80
        ror PYB+1
        lda PYB
        ror a
        sta PYB
        sta PYT
        lda PYB+1
        sta PYT+1
        lda DD                  ; the bottom row is one lower on a half dot
        beq :+
        inc PYB
        bne :+
        inc PYB+1
:       lda R4
        cmp DD
        bcs :+
        rts                     ; no rows at all (the last, smallest circles)
:       stz DLT                 ; h = R, delta = T - h^2 = -D^2, k = 2h + 1
        stz DLT+1
        lda DD
        beq :+
        lda #<-4
        sta DLT
        dec DLT+1
:       lda R4
        asl a
        ora #1
        sta KK
        lda #0
        rol a
        sta KK+1
        lda DD                  ; E = 8 D + 16
        asl a
        asl a
        asl a
        adc #16
        sta EE
        stz EE+1
        clc                     ; CL = cx + 3, for the left ends
        lda CX4
        adc #3
        sta CL
        lda CX4+1
        adc #0
        sta CL+1
        stz PCOL                ; opaque, on page 1
        lda #PAGE1
        sta PAGE

@pair:  lda DLT+1               ; h down to fit this pair's T
        bpl @span
@down:  lda KK                  ; h one smaller: k -= 2, delta += k
        sec
        sbc #2
        sta KK
        bcs :+
        dec KK+1
:       clc
        lda DLT
        adc KK
        sta DLT
        lda DLT+1
        adc KK+1
        sta DLT+1
        bmi @down

@span:  lda KK+1                ; h = k >> 1; the run is cx -/+ 1.1 (h + 1/2)
        lsr a
        lda KK
        ror a
        tax
        lda sp_hx,x
        sta TMP
        sec                     ; left: ceil((cx - w) / 4)
        lda CL
        sbc TMP
        sta PX
        lda CL+1
        sbc #0
        cmp #$80
        ror a
        ror PX
        cmp #$80
        ror a
        ror PX
        sta PX+1
        clc                     ; right: floor((cx + w) / 4)
        lda CX4
        adc TMP
        sta PX2
        lda CX4+1
        adc #0
        lsr a                   ; cx + w is never negative
        ror PX2
        lsr a
        ror PX2
        sta PX2+1
        lda PYT                 ; the top row...
        sta PY
        lda PYT+1
        sta PY+1
        lda sp_lev
        jsr pspan
        lda PYB                 ; ...and the bottom one, unless it is the same
        cmp PYT
        beq @next
        sta PY
        lda PYB+1
        sta PY+1
        lda sp_lev
        jsr pspan
@next:  lda DD                  ; count blanks every other pair (a pair is
        and #4                  ; under 1,300 cycles)
        bne :+
        jsr vbl_poll
:       clc                     ; the next pair out, while D <= R
        lda DD
        adc #4
        sta DD
        cmp R4
        beq :+
        bcs @done
:       sec                     ; T -= E, E += 32
        lda DLT
        sbc EE
        sta DLT
        lda DLT+1
        sbc EE+1
        sta DLT+1
        clc
        lda EE
        adc #32
        sta EE
        bcc :+
        inc EE+1
:       lda PYT                 ; rows one further out
        bne :+
        dec PYT+1
:       dec PYT
        inc PYB
        bne :+
        inc PYB+1
:       jmp @pair
@done:  rts

.include "spheres_tables.inc"

.assert sp_hx_end - sp_hx = 4 * RMAX + 1, error, "sp_hx must reach radius RMAX"

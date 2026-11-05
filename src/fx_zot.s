; Effect 3: Zot! Lightning strikes on a cleared screen (the randomizer wipes first).
;
; A bolt is a jagged trunk from the top of the screen, two dots wide, with
; branches up to two levels deep. It is drawn by inverting dots, so drawing
; it a second time puts the screen back exactly. As in the original, a bolt
; strikes every 2.5-4 seconds and holds 14-24 steps (about a second); some
; flicker off and on once; one in four flashes the whole screen.
;
; Segments are drawn row by row from just below their start: each row
; inverts the run of dots from the previous row's x to this row's, so every
; dot of a segment is inverted once and joints aren't inverted twice. The
; bolt is worked out one step before it appears, so the drawing step only
; draws.
;
; The flash shows page 2, which init fills with an inverted copy of the
; screen, for one tick inside the step, then goes back to page 1, so the
; randomizer never sees page 2 showing.

.include "config.inc"

.export fx_zot_init, fx_zot_step
.export zot_seg, zot_nseg, zot_phase, zot_nbolt, zot_nflash, zot_nflick

.import rng_next, rng_below, show_page1, show_page2, wait_ticks, vbl_poll
.import timing_restart
.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi

MAXSEG = 64

; ---- state in FXRAM ----
zot_seg    = FXRAM                      ; MAXSEG x 7: x0 lo, x0 hi, y0, x1 lo, x1 hi, y1, flags
                                        ; flags bit 0: trunk (2 dots wide)
zot_nseg   = zot_seg + MAXSEG * 7
zot_phase  = zot_nseg + 1               ; 0 waiting, 1 bolt showing, 2 flickered off
zot_wait   = zot_phase + 1
zot_hold   = zot_wait + 1
zot_flick  = zot_hold + 1               ; this bolt still has a flicker to do
zot_nbolt  = zot_flick + 1              ; counters for the tests (wrap)
zot_nflash = zot_nbolt + 1
zot_nflick = zot_nflash + 1

; ---- zero page ----
GX    = FXZ             ; 2: generator position
GY    = FXZ+2
GN    = FXZ+3           ; segments left in this branch
GDIR  = FXZ+4           ; branch drift: 0 none, 1 right, $FF left
GDEP  = FXZ+5           ; branch depth
GYMAX = FXZ+6           ; trunk ends below this
GFLG  = FXZ+7           ; flags for the next segment
NX    = FXZ+8           ; 2
NY    = FXZ+10
T0    = FXZ+11
SPTR  = FXZ+12          ; 2
I     = FXZ+14
SRC   = FXZ+15          ; 2 (init's copy)
DST   = FXZ+17          ; 2
WIDE  = FXZ+19
XA    = FXZ+20          ; 3: x along the segment, 8.8 with a 16-bit whole part
XP    = FXZ+23          ; 2: previous row's x
XC    = FXZ+25          ; 2: this row's x
YR    = FXZ+27
DY    = FXZ+28
DX    = FXZ+29
ST    = FXZ+30          ; 3: x step per row
RLO   = FXZ+33          ; 2: run to invert
RHI   = FXZ+35          ; 2
RP    = FXZ+37          ; 2: row pointer
B0    = FXZ+39
B1    = FXZ+40
M0    = FXZ+41
M1    = FXZ+42
QL    = FXZ+43
QH    = FXZ+44
REM   = FXZ+45

.segment "FX3"
        jmp fx_zot_init        ; the overlay's entry points
        jmp fx_zot_step

; ================================================================ init
fx_zot_init:
        jsr show_page1
        lda #PAGE1
        sta PAGE
        stz SRC                 ; page 2 = page 1 inverted, for the flash
        stz DST
        lda #PAGE1
        sta SRC+1
        lda #PAGE2
        sta DST+1
        ldx #$20
        ldy #0
:       lda (SRC),y
        eor #$7F
        sta (DST),y
        iny
        bne :-
        inc SRC+1
        inc DST+1
        dex
        bne :-
        stz zot_phase
        stz zot_nseg
        lda #6
        sta zot_wait
        rts

; ================================================================ step
fx_zot_step:
        lda #PAGE1
        sta PAGE
        lda zot_phase
        beq @idle
        cmp #1
        beq @shown

        dec zot_hold            ; 2: flickered off; back on when the hold ends
        bne @out
        jsr draw_bolt
        lda #1
        sta zot_phase
        lda #3
        jsr rng_below
        inc a
        sta zot_hold
@out:   rts

@shown: dec zot_hold            ; 1: bolt showing
        bne @out
        jsr draw_bolt           ; take it away
        lda zot_flick
        beq :+
        stz zot_flick           ; flicker: off for 2 steps, then on again
        inc zot_nflick
        lda #2
        sta zot_phase
        lda #2
        sta zot_hold
        rts
:       stz zot_phase           ; done; pause 30-60 steps, so a bolt starts
        lda #31                 ; every 2.2-4.2 seconds, as in the original
        jsr rng_below
        clc
        adc #30
        sta zot_wait
        rts

@idle:  dec zot_wait
        beq @strike
        lda zot_wait
        cmp #1
        bne @out
        jmp make_bolt           ; work out the next bolt a step early
@strike:
        jsr draw_bolt
        inc zot_nbolt
        lda #1
        sta zot_phase
        lda #11                 ; hold 14-24 steps
        jsr rng_below
        clc
        adc #14
        sta zot_hold
        stz zot_flick           ; 40% flicker
        jsr rng_next
        cmp #102
        bcs :+
        inc zot_flick
:       jsr rng_next            ; 25% flash
        cmp #64
        bcs @out
        inc zot_nflash
        jsr timing_restart      ; wait for the next blank, so the flash fills
        lda #1                  ; one whole frame, however long the bolt took
        jsr wait_ticks
        jsr show_page2
        lda #1
        jsr wait_ticks
        jmp show_page1

; ================================================================ drawing
; draw_bolt: invert every segment on page 1 (a second call undoes it all).
draw_bolt:
        stz I
@seg:   jsr vbl_poll            ; a bolt takes several frames to draw
        lda I
        cmp zot_nseg
        bcs @done
        jsr seg_ptr
        jsr zline
        inc I
        bra @seg
@done:  rts

; zline: invert the segment at SPTR, rows y0+1 .. y1. Each row inverts the
; dots from just past the previous row's x up to this row's x (one more to
; the right for trunks), so the rows join up and no dot is inverted twice.
zline:
        ldy #6
        lda (SPTR),y
        and #1
        sta WIDE
        ldy #0                  ; XA = x0 + 0.5 (8.8, 16-bit whole part)
        lda (SPTR),y
        sta XA+1
        sta XP
        iny
        lda (SPTR),y
        sta XA+2
        sta XP+1
        lda #$80
        sta XA
        iny
        lda (SPTR),y
        sta YR                  ; current row
        ldy #5                  ; DY = y1 - y0
        lda (SPTR),y
        sec
        sbc YR
        bne :+
        rts                     ; flat: nothing to draw
:       sta DY
        ldy #3                  ; DX = x1 - x0 (small, signed)
        lda (SPTR),y
        sec
        ldy #0
        sbc (SPTR),y
        sta DX
        jsr step_size           ; ST = DX * 256 / DY, signed 8.8

@row:   inc YR                  ; next row
        clc                     ; XA += ST
        lda XA
        adc ST
        sta XA
        lda XA+1
        adc ST+1
        sta XA+1
        lda XA+2
        adc ST+2
        sta XA+2
        lda XA+1                ; run from the previous x to this one
        sta XC
        lda XA+2
        sta XC+1
        sec                     ; compare XC with XP (signed)
        lda XC
        sbc XP
        lda XC+1
        sbc XP+1
        bvc :+
        eor #$80
:       bmi @left
        lda XC                  ; XC >= XP: run XP+1 .. XC (or just XC)
        cmp XP
        bne :+
        lda XC+1
        cmp XP+1
        beq @same
:       clc
        lda XP
        adc #1
        sta RLO
        lda XP+1
        adc #0
        sta RLO+1
        bra @rhi
@same:  lda XC
        sta RLO
        lda XC+1
        sta RLO+1
@rhi:   lda XC
        sta RHI
        lda XC+1
        sta RHI+1
        bra @draw
@left:  lda XC                  ; XC < XP: run XC .. XP-1
        sta RLO
        lda XC+1
        sta RLO+1
        sec
        lda XP
        sbc #1
        sta RHI
        lda XP+1
        sbc #0
        sta RHI+1
@draw:  lda WIDE                ; trunks are one dot wider
        beq :+
        inc RHI
        bne :+
        inc RHI+1
:       jsr invert_run
        lda XC
        sta XP
        lda XC+1
        sta XP+1
        dec DY
        beq :+
        jmp @row
:       rts

; step_size: ST (3 bytes: fraction, whole lo, whole hi) = DX * 256 / DY,
; DX signed (-128..127), DY 1-191. Shift-and-subtract division.
step_size:
        lda DX
        php                     ; remember the sign
        bpl :+
        eor #$FF
        inc a
:       sta QH                  ; dividend = |DX| * 256: QH:QL
        stz QL
        stz REM
        ldx #16
@div:   asl QL
        rol QH
        rol REM
        lda REM
        cmp DY
        bcc :+
        sbc DY
        sta REM
        inc QL
:       dex
        bne @div
        lda QL                  ; quotient QH:QL is |step| in 8.8
        sta ST
        lda QH
        sta ST+1
        stz ST+2
        plp
        bpl @done
        sec                     ; negate
        lda #0
        sbc ST
        sta ST
        lda #0
        sbc ST+1
        sta ST+1
        lda #0
        sbc ST+2
        sta ST+2
@done:  rts

; invert_run: invert dots RLO..RHI (signed 16-bit, clipped to 0..279) on
; row YR of page 1.
invert_run:
        lda RLO+1               ; clip the left end to 0
        bpl :+
        stz RLO
        stz RLO+1
:       lda RHI+1               ; and the right end to 279
        bmi @none
        beq @ok
        cmp #1
        bne @clipr
        lda RHI
        cmp #24
        bcc @ok
@clipr: lda #<279
        sta RHI
        lda #>279
        sta RHI+1
@ok:    lda RLO+1               ; anything left?
        cmp RHI+1
        bcc @go
        bne @none
        lda RHI
        cmp RLO
        bcs @go
@none:  rts
@go:    ldx YR
        lda row_lo,x
        sta RP
        lda row_hi,x
        sta RP+1
        ldx RLO                 ; first byte and mask
        lda RLO+1
        bne :+
        lda xbyte_lo,x
        sta B0
        ldy xmod_lo,x
        bra :++
:       lda xbyte_hi,x
        sta B0
        ldy xmod_hi,x
:       lda lmask,y
        sta M0
        ldx RHI                 ; last byte and mask
        lda RHI+1
        bne :+
        lda xbyte_lo,x
        sta B1
        ldy xmod_lo,x
        bra :++
:       lda xbyte_hi,x
        sta B1
        ldy xmod_hi,x
:       lda rmask,y
        sta M1
        ldy B0
        cpy B1
        bne @span
        lda M0                  ; all in one byte
        and M1
        eor (RP),y
        sta (RP),y
        rts
@span:  lda M0                  ; first byte, any whole bytes, last byte
        eor (RP),y
        sta (RP),y
:       iny
        cpy B1
        beq :+
        lda #$7F
        eor (RP),y
        sta (RP),y
        bra :-
:       lda M1
        eor (RP),y
        sta (RP),y
        rts

lmask:  .byte $7F, $7E, $7C, $78, $70, $60, $40   ; dots m..6
rmask:  .byte $01, $03, $07, $0F, $1F, $3F, $7F   ; dots 0..m

; SPTR = segment I (I * 7 can pass 255, so the sum is 16-bit)
seg_ptr:
        stz SPTR+1
        lda I                   ; SPTR = I * 8
        asl a
        rol SPTR+1
        asl a
        rol SPTR+1
        asl a
        rol SPTR+1
        sec                     ; - I
        sbc I
        bcs :+
        dec SPTR+1
:       clc                     ; + zot_seg
        adc #<zot_seg
        sta SPTR
        lda SPTR+1
        adc #>zot_seg
        sta SPTR+1
        rts

; ================================================================ shape
; make_bolt: a trunk from x 30-250 at the top down to y 120-191, with branches.
make_bolt:
        stz zot_nseg
        lda #221
        jsr rng_below
        clc
        adc #30
        sta GX
        stz GX+1
        stz GY
        lda #72
        jsr rng_below
        clc
        adc #120
        sta GYMAX
        lda #1                  ; trunk segments are 2 dots wide
        sta GFLG
@trunk: lda GY
        cmp GYMAX
        bcs @done
        lda #0
        jsr next_point
        jsr add_segment
        bcs @done               ; full
        lda zot_nseg            ; leave room for the rest of the trunk
        cmp #40
        bcs @trunk
        jsr rng_next            ; 13% chance of a branch here
        cmp #33
        bcs @trunk
        lda #1
        sta GDEP
        jsr branch
        lda #1
        sta GFLG
        bra @trunk
@done:  rts

; branch: from GX/GY, 3-7 segments drifting to one side. GDEP = 1 or 2.
; Saves the caller's position, so the trunk carries on where it was.
branch:
        lda GX                  ; save where we came from
        pha
        lda GX+1
        pha
        lda GY
        pha
        lda GN
        pha
        lda GDIR
        pha
        lda #5
        jsr rng_below
        clc
        adc #3
        sta GN
        jsr rng_next
        and #1
        bne :+
        lda #$FF
:       sta GDIR
@seg:   lda GY
        cmp #188
        bcs @done
        lda GDIR
        jsr next_point
        stz GFLG                ; branches are 1 dot wide
        jsr add_segment
        bcs @done
        lda GDEP                ; a branch off the branch: 13%, one level only
        cmp #1
        bne :+
        jsr rng_next
        cmp #33
        bcs :+
        inc GDEP
        jsr branch
        dec GDEP
:       dec GN
        bne @seg
@done:  pla
        sta GDIR
        pla
        sta GN
        pla
        sta GY
        pla
        sta GX+1
        pla
        sta GX
        rts

; next_point: NX/NY = GX/GY moved down 4-9 and sideways -5..5, plus a drift
; of 0-4 in direction A (0 none, 1 right, $FF left).
next_point:
        sta T0
        lda #11
        jsr rng_below
        sec
        sbc #5
        sta NY                  ; NY used as scratch: sideways step
        lda T0
        beq @add
        lda #5
        jsr rng_below
        bit T0
        bpl :+
        eor #$FF
        inc a
:       clc
        adc NY
        sta NY
@add:   lda NY                  ; NX = GX + step (signed)
        clc
        adc GX
        sta NX
        lda NY
        bpl :+
        lda #$FF
        bra :++
:       lda #0
:       adc GX+1
        sta NX+1
        lda #6                  ; NY = GY + 4..9
        jsr rng_below
        clc
        adc #4
        adc GY
        cmp #191
        bcc :+
        lda #191
:       sta NY
        rts

; add_segment: (GX,GY)-(NX,NY) with flags GFLG, then GX/GY = NX/NY.
; Carry set if the list is full.
add_segment:
        jsr vbl_poll
        lda zot_nseg
        cmp #MAXSEG
        bcc :+
        rts
:       sta I
        jsr seg_ptr
        ldy #0
        lda GX
        sta (SPTR),y
        iny
        lda GX+1
        sta (SPTR),y
        iny
        lda GY
        sta (SPTR),y
        iny
        lda NX
        sta (SPTR),y
        iny
        lda NX+1
        sta (SPTR),y
        iny
        lda NY
        sta (SPTR),y
        iny
        lda GFLG
        sta (SPTR),y
        inc zot_nseg
        lda NX
        sta GX
        lda NX+1
        sta GX+1
        lda NY
        sta GY
        clc
        rts

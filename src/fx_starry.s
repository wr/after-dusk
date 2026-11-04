; Effect 2: Starry Night. A new city skyline each time; windows switch on
; and off, stars twinkle, antenna lights blink, and now and then a shooting
; star crosses the sky. Drawn straight onto page 1.

.include "config.inc"

.export fx_starry_init, fx_starry_step
.export str_top, str_win, str_nwin, str_star, str_nstar, str_ant, str_nant
.export str_tick, str_slife, str_sx, str_sy, str_sfy, str_sdir, str_nseg

.import rng_next, rng_below, plot, line, show_page1
.import row_lo, row_hi, xbyte_lo, xbit_lo, xbyte_hi, xbit_hi

MAXWIN  = 800
NSTARS  = 85                    ; x 3 bytes must stay under 256 (one Y index)
MAXANT  = 12

; ---- state in FXRAM ----
str_top   = FXRAM                       ; 280: roofline y of each column (192 = none)
str_win   = str_top + 280               ; MAXWIN x 4: x lo, x hi, y, lit
str_star  = str_win + MAXWIN * 4        ; NSTARS x 3: x lo, x hi, y
str_ant   = str_star + NSTARS * 3       ; MAXANT x 3: light x lo, x hi, y
str_seg   = str_ant + MAXANT * 3        ; 4 trail segments x 17: count, 4 x (x lo, x hi, y, old)
str_nwin  = str_seg + 4 * 17            ; 2
str_nstar = str_nwin + 2
str_nant  = str_nstar + 1
str_tick  = str_nant + 1
str_acnt  = str_tick + 1                ; steps until the antenna lights blink
str_slife = str_acnt + 1                ; shooting star: steps left, 0 = none
str_sx    = str_slife + 1               ; 2
str_sy    = str_sx + 2
str_sfy   = str_sy + 1                  ; y fraction
str_sdir  = str_sfy + 1                 ; 0 left, 1 right
str_nseg  = str_sdir + 1                ; trail segments still drawn
str_shead = str_nseg + 1                ; next segment slot 0-3

; ---- zero page ----
BX    = FXZ             ; 2: building left x (signed)
BX1   = FXZ+2           ; 2: building right x
BW    = FXZ+4
BH    = FXZ+5
BY0   = FXZ+6           ; roofline y
YY    = FXZ+7
XX    = FXZ+8           ; 2
WY    = FXZ+10
WX    = FXZ+11          ; 2
PTR   = FXZ+13          ; 2
CNT   = FXZ+15          ; 2
T0    = FXZ+17
T1    = FXZ+18
SPTR  = FXZ+19          ; 2: segment being written
NPT   = FXZ+21
OK    = FXZ+22
DPTR  = FXZ+23          ; 2: for getdot
DMSK  = FXZ+25

.segment "CODE"

; ================================================================ init
fx_starry_init:
        jsr show_page1
        lda #PAGE1
        sta PAGE
        ldx #0                  ; no buildings yet
        lda #192
:       sta str_top,x
        inx
        bne :-
        ldx #23
:       sta str_top+256,x
        dex
        bpl :-
        stz str_nwin
        stz str_nwin+1
        stz str_nstar
        stz str_nant
        stz str_tick
        stz str_slife
        stz str_nseg
        stz str_shead
        lda #10
        sta str_acnt

        lda #9                  ; first building starts at x -8..0
        jsr rng_below
        sec
        sbc #8
        sta BX
        lda #0
        sbc #0
        sta BX+1

@bld:   lda BX+1                ; while BX < 280
        bmi @one
        beq @one
        cmp #1
        bne @city
        lda BX
        cmp #24
        bcs @city
@one:   lda #23                 ; width 16-38, height 28-100
        jsr rng_below
        clc
        adc #16
        sta BW
        lda #73
        jsr rng_below
        clc
        adc #28
        sta BH
        clc                     ; BX1 = BX + width - 2
        lda BX
        adc BW
        sta BX1
        lda BX+1
        adc #0
        sta BX1+1
        sec
        lda BX1
        sbc #2
        sta BX1
        lda BX1+1
        sbc #0
        sta BX1+1
        lda #192                ; roofline
        sec
        sbc BH
        sta BY0
        jsr set_tops
        jsr draw_building
        jsr add_windows
        jsr maybe_antenna
        clc                     ; next building after a one-dot gap
        lda BX1
        adc #2
        sta BX
        lda BX1+1
        adc #0
        sta BX+1
        bra @bld

@city:  jsr add_stars
        jmp light_some

; set_tops: str_top[x] = BY0 for the building's on-screen columns
set_tops:
        lda BX                  ; XX = max(0, BX)
        sta XX
        lda BX+1
        sta XX+1
        bpl :+
        stz XX
        stz XX+1
:
@l:     lda XX+1                ; stop past BX1 or 279
        cmp BX1+1
        bcc :+
        bne @done
        lda XX
        cmp BX1
        beq :+
        bcs @done
:       lda XX+1
        beq :+
        lda XX
        cmp #24
        bcs @done
:       clc
        lda #<str_top
        adc XX
        sta PTR
        lda #>str_top
        adc XX+1
        sta PTR+1
        lda BY0
        sta (PTR)
        inc XX
        bne @l
        inc XX+1
        bra @l
@done:  rts

; draw_building: solid roofline, then a 1-in-8 dot pattern below it:
; lit where x mod 4 = 0 on rows y mod 4 = 0, and x mod 4 = 2 on rows y mod 4 = 2.
draw_building:
        lda #1
        sta PCOL
        lda BX
        sta PX
        lda BX+1
        sta PX+1
        lda BY0
        sta PY
        sta PY2
        stz PY+1
        stz PY2+1
        lda BX1
        sta PX2
        lda BX1+1
        sta PX2+1
        jsr line
        ldy BY0
        iny
@row:   sty YY
        tya
        and #3
        beq @r0
        cmp #2
        bne @next
@r0:    sta T0                  ; T0 = the x residue for this row
        lda T0                  ; XX = BX + ((T0 - BX) & 3)
        sec
        sbc BX
        and #3
        clc
        adc BX
        sta XX
        lda BX+1
        adc #0
        sta XX+1
        lda YY
        sta PY
        stz PY+1
@dot:   lda XX+1                ; while XX <= BX1
        cmp BX1+1
        beq :+
        bpl @next
        bra @go
:       lda XX
        cmp BX1
        beq @go
        bcs @next
@go:    lda XX
        sta PX
        lda XX+1
        sta PX+1
        jsr plot
        clc
        lda XX
        adc #4
        sta XX
        bcc @dot
        inc XX+1
        bra @dot
@next:  ldy YY
        iny
        cpy #192
        bne @row
        rts

; add_windows: a 2 x 2 window every 4 dots across and 5 down, each in a
; dark 4 x 4 frame (clearing the two pattern dots that fall inside it).
add_windows:
        lda BY0
        clc
        adc #4
        sta WY
@wrow:  lda WY
        cmp #188
        bcc :+
        rts
:       clc                     ; WX = BX + 3
        lda BX
        adc #3
        sta WX
        lda BX+1
        adc #0
        sta WX+1
@wcol:  sec                     ; while WX <= BX1 - 3
        lda BX1
        sbc #3
        sta T0
        lda BX1+1
        sbc #0
        sta T1
        lda WX+1
        cmp T1
        beq :+
        bpl @wnext
        bra @in
:       lda WX
        cmp T0
        beq @in
        bcs @wnext
@in:    lda WX+1                ; on screen: 0 <= WX <= 277
        bmi @wstep
        beq :+
        lda WX
        cmp #22
        bcs @wstep
:       jsr add_window
@wstep: clc
        lda WX
        adc #4
        sta WX
        bcc @wcol
        inc WX+1
        bra @wcol
@wnext: lda WY
        clc
        adc #5
        sta WY
        bra @wrow

add_window:
        lda str_nwin+1          ; room left?
        cmp #>MAXWIN
        bcc :+
        lda str_nwin
        cmp #<MAXWIN
        bcc :+
        rts
:       lda str_nwin            ; PTR = record
        ldx str_nwin+1
        jsr win_addr
        ldy #0
        lda WX
        sta (PTR),y
        iny
        lda WX+1
        sta (PTR),y
        iny
        lda WY
        sta (PTR),y
        iny
        lda #0
        sta (PTR),y
        inc str_nwin
        bne :+
        inc str_nwin+1
:       stz PCOL                ; dark frame: clear its two pattern dots
        lda WX                  ; (c0, r0): c0 = (WX+2) & ~3, r0 = (WY+2) & ~3
        clc
        adc #2
        and #$FC
        sta PX
        lda WX+1
        adc #0
        sta PX+1
        lda WY
        clc
        adc #2
        and #$FC
        sta PY
        stz PY+1
        jsr plot
        lda WX                  ; (c2, r2): c2 = (WX & ~3) + 2, r2 = (WY & ~3) + 2
        and #$FC
        clc
        adc #2
        sta PX
        lda WX+1
        adc #0
        sta PX+1
        lda WY
        and #$FC
        clc
        adc #2
        sta PY
        jmp plot

; maybe_antenna: tall buildings get an antenna 70% of the time
maybe_antenna:
        lda BH
        cmp #79
        bcc @no
        lda #10
        jsr rng_below
        cmp #7
        bcs @no
        lda str_nant
        cmp #MAXANT
        bcs @no
        lda BW                  ; cx = BX + width / 2
        lsr a
        clc
        adc BX
        sta PX
        sta PX2
        lda BX+1
        adc #0
        sta PX+1
        sta PX2+1
        bmi @no                 ; off the left
        beq :+
        lda PX
        cmp #24
        bcs @no                 ; off the right
:       lda BY0
        sec
        sbc #1
        sta PY
        sec
        sbc #9
        sta PY2
        stz PY+1
        stz PY2+1
        lda #1
        sta PCOL
        jsr line                ; leaves PX at the antenna's x
        lda str_nant            ; its light sits 2 dots above the tip
        asl a
        clc
        adc str_nant
        tay
        lda PX
        sta str_ant,y
        lda PX+1
        sta str_ant+1,y
        lda BY0
        sec
        sbc #12
        sta str_ant+2,y
        inc str_nant
@no:    rts

; add_stars: up to 85 stars, at least 8 dots above the skyline
add_stars:
        lda #NSTARS
        sta CNT
@s:     jsr rnd_x
        jsr top_at              ; A = roofline at XX
        cmp #192
        beq @skip               ; a gap between buildings
        cmp #10
        bcc @skip
        sec                     ; y = 2 .. top - 8
        sbc #9
        jsr rng_below
        clc
        adc #2
        sta PY
        stz PY+1
        lda XX
        sta PX
        lda XX+1
        sta PX+1
        lda #1
        sta PCOL
        jsr plot
        lda str_nstar
        asl a
        clc
        adc str_nstar
        tay
        lda XX
        sta str_star,y
        lda XX+1
        sta str_star+1,y
        lda PY
        sta str_star+2,y
        inc str_nstar
@skip:  dec CNT
        bne @s
        rts

; light_some: about 12% of windows start lit
light_some:
        stz CNT
        stz CNT+1
@l:     lda CNT
        cmp str_nwin
        bne :+
        lda CNT+1
        cmp str_nwin+1
        beq @done
:       jsr rng_next
        cmp #31
        bcs @n
        lda CNT
        ldx CNT+1
        jsr win_addr
        ldy #3
        lda #1
        sta (PTR),y
        jsr win_cell
@n:     inc CNT
        bne @l
        inc CNT+1
        bra @l
@done:  rts

; ================================================================ step
fx_starry_step:
        lda #PAGE1
        sta PAGE
        inc str_tick
        lda str_nwin
        ora str_nwin+1
        beq @stars
        jsr rnd_win             ; switch a window on...
        ldy #3
        lda (PTR),y
        bne :+
        lda #1
        sta (PTR),y
        jsr win_cell
:       jsr rng_next            ; ...and half the time one off
        bmi @stars
        jsr rnd_win
        ldy #3
        lda (PTR),y
        beq @stars
        lda #0
        sta (PTR),y
        jsr win_cell

@stars: lda str_nstar           ; two stars twinkle
        beq @ant
        jsr twinkle
        jsr twinkle

@ant:   dec str_acnt            ; antenna lights blink every 10 steps
        bne @shoot
        lda #10
        sta str_acnt
        lda #2
        sta PCOL
        ldx #0
@al:    cpx str_nant
        beq @shoot
        txa
        asl a
        clc
        adc #0
        stx T0
        clc
        adc T0
        tay
        lda str_ant,y
        sta PX
        lda str_ant+1,y
        sta PX+1
        lda str_ant+2,y
        sta PY
        stz PY+1
        jsr plot
        ldx T0
        inx
        bra @al

@shoot: jmp shoot

twinkle:
        lda str_nstar
        jsr rng_below
        sta T0
        asl a
        clc
        adc T0
        tay
        lda str_star,y
        sta PX
        lda str_star+1,y
        sta PX+1
        lda str_star+2,y
        sta PY
        stz PY+1
        lda #2
        sta PCOL
        jmp plot

; ================================================================ shooting star
shoot:
        lda str_slife
        bne @fly
        lda str_nseg            ; finished: take the rest of the trail away
        beq :+
        jmp restore_oldest
:       jsr rng_next            ; 1.2% of steps start a new one
        cmp #3
        bcs @out
        lda #221                ; x 30-250
        jsr rng_below
        clc
        adc #30
        sta str_sx
        stz str_sx+1
        lda #23                 ; y 4-26
        jsr rng_below
        clc
        adc #4
        sta str_sy
        stz str_sfy
        jsr rng_next
        and #1
        sta str_sdir
        lda #9                  ; 10-18 steps
        jsr rng_below
        clc
        adc #10
        sta str_slife
@out:   rts

@fly:   dec str_slife
        lda str_shead           ; SPTR = segment slot
        jsr seg_addr
        stz NPT
        lda #1
        sta OK
@pt:    lda str_sdir            ; 4 dots: x by 1, y by 0.35 each
        beq @left
        inc str_sx
        bne @ystep
        inc str_sx+1
        bra @ystep
@left:  lda str_sx
        bne :+
        dec str_sx+1
:       dec str_sx
@ystep: clc
        lda str_sfy
        adc #$5A
        sta str_sfy
        bcc :+
        inc str_sy
:       lda str_sx+1            ; still in the sky?
        bmi @stop
        beq :+
        lda str_sx
        cmp #24
        bcs @stop
:       lda str_sx
        sta XX
        lda str_sx+1
        sta XX+1
        jsr top_at
        sec
        sbc #3
        bcc @stop
        cmp str_sy
        bcc @stop
        beq @stop
        lda str_sx              ; record the dot and what was under it
        sta PX
        lda str_sx+1
        sta PX+1
        lda str_sy
        sta PY
        stz PY+1
        jsr getdot
        pha
        lda NPT
        asl a
        asl a
        tay
        iny
        lda PX
        sta (SPTR),y
        iny
        lda PX+1
        sta (SPTR),y
        iny
        lda PY
        sta (SPTR),y
        iny
        pla
        sta (SPTR),y
        lda #1
        sta PCOL
        jsr plot
        inc NPT
        lda NPT
        cmp #4
        beq @keep
        jmp @pt
@stop:  stz OK
        stz str_slife
@keep:  lda NPT                 ; this segment's dot count
        sta (SPTR)
        beq @full
        lda str_shead
        inc a
        and #3
        sta str_shead
        inc str_nseg
@full:  lda str_nseg            ; trail of 3: take the oldest away
        cmp #4
        bcs restore_oldest
        lda OK
        bne :+
        lda str_nseg
        bne restore_oldest
:       rts

; restore_oldest: put back what the oldest trail segment covered
restore_oldest:
        lda str_shead
        sec
        sbc str_nseg
        and #3
        jsr seg_addr
        lda (SPTR)
        sta NPT
@l:     lda NPT
        beq @done
        dec NPT                 ; newest dot first
        lda NPT
        asl a
        asl a
        tay
        iny
        lda (SPTR),y
        sta PX
        iny
        lda (SPTR),y
        sta PX+1
        iny
        lda (SPTR),y
        sta PY
        stz PY+1
        iny
        lda (SPTR),y
        sta PCOL
        jsr plot
        bra @l
@done:  dec str_nseg
        rts

; SPTR = segment A (0-3)
seg_addr:
        sta T0
        asl a                   ; * 17 = * 16 + 1
        asl a
        asl a
        asl a
        clc
        adc T0
        clc
        adc #<str_seg
        sta SPTR
        lda #>str_seg
        adc #0
        sta SPTR+1
        rts

; ================================================================ helpers
; rnd_x: XX = random x 0-279
rnd_x:  lda #140
        jsr rng_below
        asl a
        sta XX
        lda #0
        rol a
        sta XX+1
        jsr rng_next
        and #1
        ora XX
        sta XX
        rts

; top_at: A = str_top[XX]
top_at: clc
        lda #<str_top
        adc XX
        sta PTR
        lda #>str_top
        adc XX+1
        sta PTR+1
        lda (PTR)
        rts

; rnd_win: PTR = a random window record
rnd_win:
:       jsr rng_next
        sta T0
        lda RNG+1
        and #3
        sta T1
        cmp str_nwin+1
        bcc @ok
        bne :-
        lda T0
        cmp str_nwin
        bcs :-
@ok:    lda T0
        ldx T1
        ; fall through

; win_addr: PTR = str_win + (X:A) * 4
win_addr:
        sta PTR
        stx PTR+1
        asl PTR
        rol PTR+1
        asl PTR
        rol PTR+1
        clc
        lda PTR
        adc #<str_win
        sta PTR
        lda PTR+1
        adc #>str_win
        sta PTR+1
        rts

; win_cell: draw the window at PTR, lit if its record says so
win_cell:
        ldy #3
        lda (PTR),y
        sta PCOL
        ldy #0
        lda (PTR),y
        sta PX
        iny
        lda (PTR),y
        sta PX+1
        iny
        lda (PTR),y
        sta PY
        stz PY+1
        jsr plot
        inc PY
        jsr plot
        inc PX
        bne :+
        inc PX+1
:       jsr plot
        dec PY
        jmp plot

; getdot: A = 1 if the dot at PX/PY (on screen, page 1) is lit, else 0
getdot: ldy PY
        lda row_lo,y
        sta DPTR
        lda row_hi,y
        sta DPTR+1
        ldx PX
        lda PX+1
        bne @hi
        lda xbit_lo,x
        sta DMSK
        ldy xbyte_lo,x
        bra @t
@hi:    lda xbit_hi,x
        sta DMSK
        ldy xbyte_hi,x
@t:     lda (DPTR),y
        and DMSK
        beq :+
        lda #1
:       rts

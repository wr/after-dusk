; Hi-res drawing primitives. All take their inputs in zero page (see
; config.inc): PX/PY (signed 16-bit), PX2/PY2, PCOL (0 clear, 1 set,
; 2 invert), PAGE ($20 or $40), RAD. Off-screen dots are skipped. Every
; routine clobbers A, X and Y. Screen bytes never get bit 7 set.

.include "config.inc"

.export plot, line, fline, disc, clear_page, fill_page, invert_page, copy_page
.export show_page1, show_page2, wipe_to_black, hspan, pspan
.import wait_ticks, vbl_poll
.export row_lo, row_hi, xbyte_lo, xbit_lo, xbyte_hi, xbit_hi, xmod_lo, xmod_hi
.export wvx_lo, wvx_hi, wvy_lo, wvy_hi, lsx, lsy, make_tables

; scratch
PTR   = DSCR          ; 2 bytes: row pointer
MASK  = DSCR+2
SRC   = DSCR+3        ; 2 bytes: copy_page source

; line
LDX_  = DSX           ; 2: |dx|
LDY_  = DSX+2         ; 2: -|dy|
ERR   = DSX+4         ; 2
E2    = DSX+6         ; 2
SX    = DSX+8         ; 1 or $FF
SY    = DSX+9

; fline
FDX   = DSX           ; 2: dx, 0-279
FDY   = DSX+2         ; |dy|
FSY   = DSX+3         ; 1 or $FF: row direction
FERR  = DSX+4         ; 2
FCNT  = DSX+6         ; 2: dots left
FPG   = DSX+8         ; $00 for page 1, $60 for page 2

; hspan, pspan
HB0   = DSX           ; first byte
HB1   = DSX+1         ; last byte
HM0   = DSX+2         ; its dots
HM1   = DSX+3

; pspan
GL    = DSX+8         ; grey level
GP    = DSX+9         ; 4: the row's pattern bytes, by the first dot's x & 3
GM    = DSX+13        ; 4 x the grey level

; disc
CX    = DSX           ; 2: centre
CY    = DSX+2         ; 2
DXI   = DSX+4         ; signed dx
DYI   = DSX+5         ; signed dy
DYS   = DSX+6         ; dy squared
RR    = DSX+7         ; r*r + r

.segment "CODE"

; ---------------------------------------------------------------- plot
; One dot at (PX, PY) on PAGE, in mode PCOL.
plot:
        ldy PY+1
        bne @out                ; y < 0 or y > 255
        ldy PY
        cpy #192
        bcs @out
        lda row_lo,y
        sta PTR
        lda PAGE
        eor #$20                ; $00 for page 1, $60 for page 2
        eor row_hi,y
        sta PTR+1
        ldx PX
        lda PX+1
        beq @xlo
        cmp #1
        bne @out                ; x < 0 or x > 511
        cpx #24
        bcs @out                ; x > 279
        lda xbit_hi,x
        sta MASK
        ldy xbyte_hi,x
        bra @draw
@xlo:   lda xbit_lo,x
        sta MASK
        ldy xbyte_lo,x
@draw:  lda PCOL
        beq @clear
        cmp #1
        beq @set
        lda (PTR),y
        eor MASK
        sta (PTR),y
@out:   rts
@set:   lda (PTR),y
        ora MASK
        sta (PTR),y
        rts
@clear: lda MASK
        eor #$7F
        and (PTR),y
        sta (PTR),y
        rts

; ---------------------------------------------------------------- line
; Bresenham line from (PX, PY) to (PX2, PY2), both ends included.
; Leaves PX/PY equal to PX2/PY2.
line:
        sec                     ; LDX_ = |PX2 - PX|, SX = direction
        lda PX2
        sbc PX
        sta LDX_
        lda PX2+1
        sbc PX+1
        sta LDX_+1
        ldx #1
        bit LDX_+1
        bpl @dxok
        sec
        lda #0
        sbc LDX_
        sta LDX_
        lda #0
        sbc LDX_+1
        sta LDX_+1
        ldx #$FF
@dxok:  stx SX

        sec                     ; LDY_ = -|PY2 - PY|, SY = direction
        lda PY2
        sbc PY
        sta LDY_
        lda PY2+1
        sbc PY+1
        sta LDY_+1
        bmi @dyneg
        sec
        lda #0
        sbc LDY_
        sta LDY_
        lda #0
        sbc LDY_+1
        sta LDY_+1
        ldx #1
        bra @dyok
@dyneg: ldx #$FF
@dyok:  stx SY

        clc                     ; ERR = dx + dy
        lda LDX_
        adc LDY_
        sta ERR
        lda LDX_+1
        adc LDY_+1
        sta ERR+1

@loop:  jsr plot
        lda PX
        cmp PX2
        bne @step
        lda PX+1
        cmp PX2+1
        bne @step
        lda PY
        cmp PY2
        bne @step
        lda PY+1
        cmp PY2+1
        bne @step
        rts

@step:  lda ERR                 ; E2 = 2 * ERR
        asl a
        sta E2
        lda ERR+1
        rol a
        sta E2+1

        sec                     ; if E2 >= LDY_: step x
        lda E2
        sbc LDY_
        lda E2+1
        sbc LDY_+1
        bvc :+
        eor #$80
:       bmi @noxs
        clc
        lda ERR
        adc LDY_
        sta ERR
        lda ERR+1
        adc LDY_+1
        sta ERR+1
        lda SX
        bmi @decx
        inc PX
        bne @noxs
        inc PX+1
        bra @noxs
@decx:  lda PX
        bne :+
        dec PX+1
:       dec PX

@noxs:  sec                     ; if E2 <= LDX_: step y
        lda LDX_
        sbc E2
        lda LDX_+1
        sbc E2+1
        bvc :+
        eor #$80
:       bmi @again
        clc
        lda ERR
        adc LDX_
        sta ERR
        lda ERR+1
        adc LDX_+1
        sta ERR+1
        lda SY
        bmi @decy
        inc PY
        bne @again
        inc PY+1
        bra @again
@decy:  lda PY
        bne :+
        dec PY+1
:       dec PY
@again: jmp @loop

; ---------------------------------------------------------------- fline
; Fast line for lines wholly on screen: (PX, PY) to (PX2, PY2), x 0-279 and
; y 0-191 (not checked), both ends included, in mode PCOL (0 clear, 1 set).
; Always drawn left to right, so a line and its reverse cover the same dots
; (the two ends may be swapped on return). About 45 cycles a dot, plus 35
; each time the row changes. Lines wider than they are tall count vertical
; blanks as they go, so any length is safe; taller ones take under a frame.
; The row being drawn is kept in X throughout.

.macro PLOTOP mode
  .if mode
        lda (PTR),y
        ora MASK
  .else
        lda MASK
        eor #$7F
        and (PTR),y
  .endif
        sta (PTR),y
.endmacro

.macro NEXTROW
        txa
        clc
        adc FSY
        tax
        lda row_lo,x
        sta PTR
        lda row_hi,x
        eor FPG
        sta PTR+1
.endmacro

; wider than tall: a dot right every time, a row up or down when the error
; says. wide = 1 for lines more than 255 dots across (16-bit error).
.macro FLINE_X mode, wide
        .local dot, step, right, done
dot:    PLOTOP mode
        dec FCNT
        bne step
        dec FCNT+1
        beq done
step:   asl MASK                ; one dot right
        bpl right
        lda #1
        sta MASK
        iny
        jsr vbl_poll            ; a byte done: keep the frame count right
right:
  .if wide
        sec                     ; err -= dy; below zero: err += dx, next row
        lda FERR
        sbc FDY
        sta FERR
        lda FERR+1
        sbc #0
        sta FERR+1
        bpl dot
        clc
        lda FERR
        adc FDX
        sta FERR
        lda FERR+1
        adc FDX+1
        sta FERR+1
  .else
        sec                     ; err -= dy; below zero (carry clear):
        lda FERR                ; err += dx, next row
        sbc FDY
        sta FERR
        bcs dot
        adc FDX
        sta FERR
  .endif
        NEXTROW
        bra dot
done:   rts
.endmacro

; taller than wide: a row every time, a dot right when the error says
.macro FLINE_Y mode
        .local dot, done
dot:    PLOTOP mode
        dec FCNT
        beq done
        NEXTROW
        sec                     ; err -= dx; below zero (carry clear):
        lda FERR                ; err += dy, one dot right
        sbc FDX
        sta FERR
        bcs dot
        adc FDY
        sta FERR
        asl MASK
        bpl dot
        lda #1
        sta MASK
        iny
        bra dot
done:   rts
.endmacro

fline:
        lda PX2                 ; left to right: swap the ends if needed
        cmp PX
        lda PX2+1
        sbc PX+1
        bcs @ordered
        lda PX
        ldx PX2
        sta PX2
        stx PX
        lda PX+1
        ldx PX2+1
        sta PX2+1
        stx PX+1
        lda PY
        ldx PY2
        sta PY2
        stx PY
@ordered:
        sec                     ; FDX = PX2 - PX
        lda PX2
        sbc PX
        sta FDX
        lda PX2+1
        sbc PX+1
        sta FDX+1
        ldx #1                  ; FDY = |PY2 - PY|, FSY = its direction
        sec
        lda PY2
        sbc PY
        bcs :+
        eor #$FF
        inc a
        ldx #$FF
:       sta FDY
        stx FSY
        lda PAGE
        eor #$20
        sta FPG
        ldx PX                  ; the first dot: byte and mask...
        lda PX+1
        bne :+
        lda xbit_lo,x
        sta MASK
        ldy xbyte_lo,x
        bra :++
:       lda xbit_hi,x
        sta MASK
        ldy xbyte_hi,x
:       ldx PY                  ; ...and row
        lda row_lo,x
        sta PTR
        lda row_hi,x
        eor FPG
        sta PTR+1
        lda FDX+1               ; wider than tall, or taller?
        bne @wide
        lda FDX
        cmp FDY
        bcc @tall
        inc a                   ; dx + 1 dots (1-256): FCNT, then one round
        sta FCNT
        lda #1
        sta FCNT+1
        lda FDX                 ; err = dx / 2
        lsr a
        sta FERR
        lda PCOL
        beq :+
        jmp fline_xs
:       jmp fline_xc
@wide:  clc                     ; dx + 1 dots (257-280)
        lda FDX
        adc #1
        sta FCNT
        lda #2
        sta FCNT+1
        lda FDX+1               ; err = dx / 2
        lsr a
        sta FERR+1
        lda FDX
        ror a
        sta FERR
        lda PCOL
        beq :+
        jmp fline_xws
:       jmp fline_xwc
@tall:  lda FDY                 ; dy + 1 dots
        inc a
        sta FCNT
        lda FDY                 ; err = dy / 2
        lsr a
        sta FERR
        lda PCOL
        beq :+
        jmp fline_ys
:       jmp fline_yc

fline_xs:  FLINE_X 1, 0
fline_xc:  FLINE_X 0, 0
fline_xws: FLINE_X 1, 1
fline_xwc: FLINE_X 0, 1
fline_ys:  FLINE_Y 1
fline_yc:  FLINE_Y 0

; ---------------------------------------------------------------- disc
; Filled disc centred on (PX, PY): every dot with dx*dx + dy*dy <= r*r + r,
; r = RAD (0-10). PX/PY are left unchanged.
disc:
        lda PX
        sta CX
        lda PX+1
        sta CX+1
        lda PY
        sta CY
        lda PY+1
        sta CY+1
        ldx RAD
        lda squares,x
        clc
        adc RAD
        sta RR
        lda RAD
        eor #$FF
        inc a
        sta DYI                 ; dy from -r

@row:   lda DYI                 ; DYS = dy * dy
        bpl :+
        eor #$FF
        inc a
:       tax
        lda squares,x
        sta DYS
        ldx #0                  ; PY = CY + dy
        lda DYI
        bpl :+
        dex
:       clc
        adc CY
        sta PY
        txa
        adc CY+1
        sta PY+1
        lda RAD
        eor #$FF
        inc a
        sta DXI                 ; dx from -r

@col:   lda DXI
        bpl :+
        eor #$FF
        inc a
:       tax
        lda squares,x
        clc
        adc DYS
        cmp RR
        beq @in
        bcs @next
@in:    ldx #0                  ; PX = CX + dx
        lda DXI
        bpl :+
        dex
:       clc
        adc CX
        sta PX
        txa
        adc CX+1
        sta PX+1
        jsr plot
@next:  lda DXI
        inc DXI
        cmp RAD
        bne @col
        lda DYI
        inc DYI
        cmp RAD
        beq :+
        jmp @row

:       lda CX                  ; restore the centre
        sta PX
        lda CX+1
        sta PX+1
        lda CY
        sta PY
        lda CY+1
        sta PY+1
        rts

squares:
        .byte 0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100

; ---------------------------------------------------------------- hspan
; A horizontal run of dots from (PX, PY) to (PX2, PY) on PAGE in mode PCOL,
; clipped to the screen; nothing when PX2 < PX. A byte at a time, so a run
; costs about as much as two or three dots. PX/PX2/PY are left unchanged.
hspan:
        jsr span_setup
        bcs span_out
        cpy HB1
        bne @wide
        lda HM0
        and HM1
        bra span_apply
@wide:  lda HM0
        jsr span_apply
:       iny
        cpy HB1
        beq :+
        lda #$7F
        jsr span_apply
        bra :-
:       lda HM1
        ; fall through

; span_apply: dots A in byte Y of (PTR), in mode PCOL. Keeps Y.
span_apply:
        ldx PCOL
        beq @clr
        cpx #1
        beq @set
        eor (PTR),y
        sta (PTR),y
        rts
@set:   ora (PTR),y
        sta (PTR),y
        rts
@clr:   eor #$7F
        and (PTR),y
        sta (PTR),y
span_out:
        rts

; span_setup: clip the run PX..PX2 on row PY to the screen. Carry set when
; nothing is left; otherwise PTR is the row on PAGE, HB0 (also in Y) and HB1
; the first and last bytes, HM0 and HM1 the run's dots in each.
span_setup:
        ldy PY
        lda PY+1
        bne @out
        cpy #192
        bcs @out
        lda row_lo,y
        sta PTR
        lda PAGE
        eor #$20
        eor row_hi,y
        sta PTR+1
        lda PX2+1               ; right end: left of the screen, on it, or
        bmi @out                ; past it (279)
        bne @rhi
        ldx PX2
        lda xbyte_lo,x
        ldy xmod_lo,x
        bra @r
@rhi:   ldx PX2
        cmp #1
        bne @rclip
        cpx #24
        bcs @rclip
        lda xbyte_hi,x
        ldy xmod_hi,x
        bra @r
@rclip: lda #39
        ldy #6
@r:     sta HB1
        lda span_r,y
        sta HM1
        lda PX+1                ; left end: before the screen (0), on it, or
        bmi @lclip              ; past it
        bne @lhi
        ldx PX
        ldy xbyte_lo,x
        lda xmod_lo,x
        bra @l
@lhi:   cmp #1
        bne @out
        ldx PX
        cpx #24
        bcs @out
        ldy xbyte_hi,x
        lda xmod_hi,x
        bra @l
@lclip: ldy #0
        tya
@l:     sty HB0
        tax
        lda span_l,x
        sta HM0
        cpy HB1                 ; first byte after the last: nothing (in one
        beq :+                  ; byte, the two ends' dots have none in common)
        rts                     ; (carry: set if after)
:       clc
        rts
@out:   sec
        rts

span_l: .byte $7F, $7E, $7C, $78, $70, $60, $40   ; dots m..6
span_r: .byte $01, $03, $07, $0F, $1F, $3F, $7F   ; dots 0..m

; ---------------------------------------------------------------- pspan
; A run like hspan's filled with grey level A (0-16), a 4 x 4 ordered
; dither: dot (x, y) is lit when BAYER[(y & 3) * 4 + (x & 3)] < A, so a
; level lights that many of every 16 dots. PCOL 1: only the lit dots are set
; (see-through); otherwise every dot is set or cleared (opaque). About 250
; cycles a run, plus 17 a byte (opaque) or 21 (see-through). PX/PX2/PY are
; left unchanged.
;
; Bytes hold 7 dots and the pattern repeats every 4, so a byte whose first
; dot is x has the pattern's 7 dots from x & 3 on; one byte to the right,
; x & 3 is one less (7 = -1 mod 4). GP holds the row's four such bytes.
pspan:
        sta GL
        jsr span_setup
        bcc :+
        rts
:       lda GL                  ; the row's four dots, twice over
        asl a
        asl a
        sta GM
        lda PY
        and #3
        ora GM
        tax
        ldy greys,x             ; and its four pattern bytes
        lda gexp,y
        sta GP
        lda gexp+1,y
        sta GP+1
        lda gexp+2,y
        sta GP+2
        lda gexp+3,y
        sta GP+3
        ldy HB0                 ; X = the first byte's x & 3 = -byte & 3
        tya
        eor #$FF
        inc a
        and #3
        tax
        lda HM0                 ; its dots (if it is also the last, the dots
        cpy HB1                 ; of both ends)
        bne :+
        and HM1
:       sta MASK
        lda PCOL
        cmp #1
        bne :+
        jmp pspan_see

:       lda (PTR),y             ; opaque: old ^ ((old ^ pattern) & dots)
        eor GP,x
        and MASK
        eor (PTR),y
        sta (PTR),y
        cpy HB1
        beq @rts
        iny                     ; whole bytes are the pattern, four at a
        dex                     ; time from the next byte's phase
        bpl :+
        ldx #3
:       cpy HB1
        beq @last
        txa
        asl a
        tax
        jmp (@at,x)
@at:    .word @p0, @p1, @p2, @p3
@p3:    lda GP+3
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p2:    lda GP+2
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p1:    lda GP+1
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p0:    lda GP
        sta (PTR),y
        iny
        cpy HB1
        bne @p3
@last:  jsr pspan_last
        lda (PTR),y
        eor GP,x
        and MASK
        eor (PTR),y
        sta (PTR),y
@rts:   rts

pspan_see:
        lda GP,x                ; see-through: old | (pattern & dots)
        and MASK
        ora (PTR),y
        sta (PTR),y
        cpy HB1
        beq @rts
        iny
        dex
        bpl :+
        ldx #3
:       cpy HB1
        beq @last
        txa
        asl a
        tax
        jmp (@at,x)
@at:    .word @p0, @p1, @p2, @p3
@p3:    lda GP+3
        ora (PTR),y
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p2:    lda GP+2
        ora (PTR),y
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p1:    lda GP+1
        ora (PTR),y
        sta (PTR),y
        iny
        cpy HB1
        beq @last
@p0:    lda GP
        ora (PTR),y
        sta (PTR),y
        iny
        cpy HB1
        bne @p3
@last:  jsr pspan_last
        lda GP,x
        and MASK
        ora (PTR),y
        sta (PTR),y
@rts:   rts

; pspan_last: X = the phase of the last byte (Y), MASK = its dots.
pspan_last:
        tya
        eor #$FF
        inc a
        and #3
        tax
        lda HM1
        sta MASK
        rts

; greys: for each level 0-16 and row r = y & 3, 4 x the row's four dots m,
; dot i of 4 in bit i: lit when BAYER[4r + i] < level, with
; BAYER = 0 8 2 10 / 12 4 14 6 / 3 11 1 9 / 15 7 13 5.
greys:
        .byte $00, $00, $00, $00   ; 0
        .byte $04, $00, $00, $00   ; 1
        .byte $04, $00, $10, $00   ; 2
        .byte $14, $00, $10, $00   ; 3
        .byte $14, $00, $14, $00   ; 4
        .byte $14, $08, $14, $00   ; 5
        .byte $14, $08, $14, $20   ; 6
        .byte $14, $28, $14, $20   ; 7
        .byte $14, $28, $14, $28   ; 8
        .byte $1C, $28, $14, $28   ; 9
        .byte $1C, $28, $34, $28   ; 10
        .byte $3C, $28, $34, $28   ; 11
        .byte $3C, $28, $3C, $28   ; 12
        .byte $3C, $2C, $3C, $28   ; 13
        .byte $3C, $2C, $3C, $38   ; 14
        .byte $3C, $3C, $3C, $38   ; 15
        .byte $3C, $3C, $3C, $3C   ; 16
; gexp: for each m, the four pattern bytes: byte p is the dots of m
; repeated, from dot p on (bits p to p + 6 of m + 16 m + 256 m).
gexp:
        .byte $00, $00, $00, $00
        .byte $11, $08, $44, $22
        .byte $22, $11, $08, $44
        .byte $33, $19, $4C, $66
        .byte $44, $22, $11, $08
        .byte $55, $2A, $55, $2A
        .byte $66, $33, $19, $4C
        .byte $77, $3B, $5D, $6E
        .byte $08, $44, $22, $11
        .byte $19, $4C, $66, $33
        .byte $2A, $55, $2A, $55
        .byte $3B, $5D, $6E, $77
        .byte $4C, $66, $33, $19
        .byte $5D, $6E, $77, $3B
        .byte $6E, $77, $3B, $5D
        .byte $7F, $7F, $7F, $7F

; ---------------------------------------------------------------- pages
; clear_page: zero the 8K page at PAGE. fill_page: fill it with A.
clear_page:
        lda #0
fill_page:
        ldx PAGE
        stx PTR+1
        ldy #0
        sty PTR
        ldx #$20
@l:     sta (PTR),y
        iny
        bne @l
        inc PTR+1
        dex
        bne @l
        rts

; invert_page: flip every dot on PAGE (bits 0-6 of each byte).
invert_page:
        ldx PAGE
        stx PTR+1
        ldy #0
        sty PTR
        ldx #$20
@l:     lda (PTR),y
        eor #$7F
        sta (PTR),y
        iny
        bne @l
        inc PTR+1
        dex
        bne @l
        rts

; copy_page: copy the 8K page whose high byte is in A to PAGE.
copy_page:
        sta SRC+1
        lda PAGE
        sta PTR+1
        ldy #0
        sty PTR
        sty SRC
        ldx #$20
@l:     lda (SRC),y
        sta (PTR),y
        iny
        bne @l
        inc SRC+1
        inc PTR+1
        dex
        bne @l
        rts

; wipe_to_black: clear page 1 from top to bottom, 8 rows per tick
; (24 ticks, about 0.4 s).
wipe_to_black:
        stz SRC                 ; SRC = first row of this band
@band:  ldx #8
@row:   phx
        ldx SRC
        lda row_lo,x
        sta PTR
        lda row_hi,x
        sta PTR+1
        ldy #39
        lda #0
:       sta (PTR),y
        dey
        bpl :-
        inc SRC
        plx
        dex
        bne @row
        lda #1
        jsr wait_ticks
        lda SRC
        cmp #192
        bne @band
        rts

show_page1:
        sta LOWSCR
        stz DISP
        rts

show_page2:
        sta HISCR
        lda #1
        sta DISP
        rts

; ---------------------------------------------------------------- tables
; make_tables: build Warp's shift tables in the language card (call after
; sprite_setup has switched its RAM in). For a signed 8.8 value hi:lo,
;   (hi:lo) >> n = sarN[hi] : (shlM[hi] | shrN[lo]), M = 8 - n.
make_tables:
        ldx #0
@l:     txa                     ; sar4/sar5: arithmetic shifts of x
        cmp #$80
        ror a
        cmp #$80
        ror a
        cmp #$80
        ror a
        cmp #$80
        ror a
        sta sar4,x
        cmp #$80
        ror a
        sta sar5,x
        txa                     ; shl4, shl3
        asl a
        asl a
        asl a
        sta shl3,x
        asl a
        sta shl4,x
        txa                     ; shr4, shr5
        lsr a
        lsr a
        lsr a
        lsr a
        sta shr4,x
        lsr a
        sta shr5,x
        inx
        bne @l
        rts

.include "tables.inc"

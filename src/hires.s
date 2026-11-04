; Hi-res drawing primitives. All take their inputs in zero page (see
; config.inc): PX/PY (signed 16-bit), PX2/PY2, PCOL (0 clear, 1 set,
; 2 invert), PAGE ($20 or $40), RAD. Off-screen dots are skipped. Every
; routine clobbers A, X and Y. Screen bytes never get bit 7 set.

.include "config.inc"

.export plot, line, disc, clear_page, fill_page, invert_page, copy_page
.export show_page1, show_page2, wipe_to_black
.import wait_ticks
.export row_lo, row_hi, xbyte_lo, xbit_lo, xbyte_hi, xbit_hi, xmod_lo, xmod_hi
.export sar4, shl4, shr4, sar5, shl3, shr5

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
.include "tables.inc"

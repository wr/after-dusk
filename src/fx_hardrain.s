; Effect 15: Hard Rain, after the original. Rain seen from above: each drop
; lands as a single dot and spreads into a thin ring, one dot wider every
; step, until it vanishes 3-9 steps later. Up to NDROPS drops at once; while
; a slot is free, a new drop starts on about 45% of steps (115/256), anywhere
; a ring of radius 9 still fits on the screen. 20 steps a second (3 ticks).
;
; Rings are XORed on and off: each step a drop XORs off the ring it showed,
; grows, and XORs on the next one, so the screen is always exactly the XOR
; of the live rings and nothing need be clipped or remembered. A ring is
; drawn a row at a time as 4 screen bytes, from tables init builds in FXRAM:
; for every ring (the midpoint circle of radius 0-9), every row and every
; bit position s of the centre within its byte, the row's 5 bytes covering
; byte columns -2 to +2 of the centre's (hardrain_tables.inc holds the s = 0
; rows; each further s is the previous shifted one dot right). A drop reads
; 4 of the 5: columns -2 to +1 when s <= 4, -1 to +2 when s >= 5 (or the
; centre is in byte 1, where column -2 is off the screen; a ring there never
; reaches column 2). Drawn straight onto page 1.

.include "config.inc"

.export hr_on, hr_x_lo, hr_x_hi, hr_y, hr_r, hr_life, hr_s, hr_off, hr_cbw

.import rng_next, rng_below, vbl_poll, show_page1, row_lo, row_hi
.import xbyte_lo, xbyte_hi, xmod_lo, xmod_hi

NDROPS  = 10
MAXR    = 9
SPAWN   = 115                   ; a new drop when rng_next < this: 115/256
XMIN    = 9                     ; centres: x 9-270, y 9-182
XSPAN   = 262
YMIN    = 9
YSPAN   = 174
LIFEMIN = 3
LIFESPAN = 7                    ; life 3-9

; ---- FXRAM ----
HR_TBL  = FXRAM                 ; $0800-$15AB: the ring tables, 5 bytes a row
hr_on   = FXRAM + $0E00         ; $1600: the drops, NDROPS each, 16 apart
hr_x_lo = hr_on + $10           ; centre x
hr_x_hi = hr_on + $20
hr_y    = hr_on + $30           ; centre y
hr_r    = hr_on + $40           ; the ring showing
hr_life = hr_on + $50           ; the last ring it shows
hr_s    = hr_on + $60           ; centre x mod 7: which table
hr_off  = hr_on + $70           ; 0 or 1: the first of the 5 bytes a row drawn
hr_cbw  = hr_on + $80           ; the byte column that first byte lands on

.assert hr_cbw + NDROPS <= FXRAM_END, error, "drops overrun FXRAM"

; ---- zero page ----
PTR   = FXZ                     ; 2: the screen row being drawn
TP    = FXZ+2                   ; 2: the table row being drawn
CBW   = FXZ+4                   ; byte column its first byte lands on
ENDR  = FXZ+5                   ; the row after the ring's last
SLOT  = FXZ+6                   ; the drop being stepped
XL    = FXZ+7                   ; 2: a new drop's x
SRC   = FXZ+9                   ; 2: init: the s = 0 row to copy
DST   = FXZ+11                  ; 2: init: where the next table row goes
RP    = FXZ+13                  ; 2: init: the row being shifted
NR    = FXZ+15                  ; init: rows in the ring, 2r + 1
CNT   = FXZ+16                  ; init: rows left

.segment "FX15"
        jmp init                ; the overlay's entry points
        jmp step

; ================================================================ init
init:   jsr show_page1
        ldx #NDROPS-1
:       stz hr_on,x
        dex
        bpl :-
        lda #<hr_rows           ; build the ring tables: ring by ring, the
        sta SRC                 ; s = 0 rows copied in, then each further s
        lda #>hr_rows           ; made from the one before it
        sta SRC+1
        lda #<HR_TBL
        sta DST
        lda #>HR_TBL
        sta DST+1
        lda #1
        sta NR
@ring:  lda DST                 ; RP: the s = 0 block, the first to shift
        sta RP
        lda DST+1
        sta RP+1
        lda NR
        sta CNT
@copy:  ldy #3                  ; a row: 4 bytes and a clear fifth
:       lda (SRC),y
        sta (DST),y
        dey
        bpl :-
        ldy #4
        lda #0
        sta (DST),y
        lda SRC
        clc
        adc #4
        sta SRC
        bcc :+
        inc SRC+1
:       jsr dst5
        dec CNT
        bne @copy
        lda NR                  ; 6 more blocks of NR rows: each row the one
        asl a                   ; NR rows back, shifted one dot right
        adc NR
        asl a
        sta CNT
@shift: clc
        ldy #0
        .repeat 5               ; bit 6 of each byte carries into the next
        lda (RP),y
        rol a
        cmp #$80
        and #$7F
        sta (DST),y
        iny
        .endrepeat
        lda RP
        clc
        adc #5
        sta RP
        bcc :+
        inc RP+1
:       jsr dst5
        dec CNT
        bne @shift
        inc NR
        inc NR
        lda NR
        cmp #2*MAXR+3
        beq :+
        jmp @ring
:       rts

; dst5: DST += 5
dst5:   lda DST
        clc
        adc #5
        sta DST
        bcc :+
        inc DST+1
:       rts

; ================================================================ step
step:   ldx #NDROPS-1
@drop:  lda hr_on,x
        beq @next
        stx SLOT
        jsr ring                ; off with the ring it shows
        ldx SLOT
        inc hr_r,x              ; one wider; past its life, it's gone
        lda hr_r,x
        cmp hr_life,x
        beq :+
        bcs @gone
:       jsr ring                ; on with the next
        ldx SLOT
@next:  jsr vbl_poll
        dex
        bpl @drop
        ldx #NDROPS-1           ; a slot free?
@free:  lda hr_on,x
        beq @found
        dex
        bpl @free
        rts
@gone:  stz hr_on,x
        jmp @next
@found: stx SLOT
        jsr rng_next            ; a new drop on 115 steps in 256
        cmp #SPAWN
        bcc :+
        rts
:       lda #XSPAN/2            ; x = XMIN + 2 * (0-130) + 0-1: XMIN to XMIN + 261
        jsr rng_below
        asl a
        sta XL
        lda #0
        rol a
        sta XL+1
        jsr rng_next
        and #1
        clc
        adc #XMIN
        adc XL
        sta XL
        sta hr_x_lo,x
        bcc :+
        inc XL+1
:       lda XL+1
        sta hr_x_hi,x
        ldy XL                  ; its byte column (Y) and bit (hr_s)
        lda XL+1
        beq @lo
        lda xmod_hi,y
        sta hr_s,x
        lda xbyte_hi,y
        bra @cb
@lo:    lda xmod_lo,y
        sta hr_s,x
        lda xbyte_lo,y
@cb:    tay
        lda #1                  ; the 4 bytes drawn start a column later
        cpy #1                  ; when the centre is in byte 1 or its bit
        beq @off                ; is 5 or 6
        lda hr_s,x
        cmp #5
        lda #1
        bcs @off
        lda #0
@off:   sta hr_off,x
        sty CBW
        clc
        adc CBW
        sec
        sbc #2
        sta hr_cbw,x
        stz hr_r,x
        lda #LIFESPAN
        jsr rng_below
        clc
        adc #LIFEMIN
        sta hr_life,x
        lda #YSPAN
        jsr rng_below
        clc
        adc #YMIN
        sta hr_y,x
        lda #1
        sta hr_on,x
        jsr ring                ; on with its first dot
@out:   rts

; ring: XOR ring hr_r of drop X onto page 1, a row at a time: 4 bytes from
; its table row onto byte columns CBW to CBW + 3 of each screen row. Clobbers X.
ring:   ldy hr_r,x
        lda r7,y
        clc
        adc hr_s,x
        tay
        lda hr_tlo,y
        clc
        adc hr_off,x
        sta TP
        lda hr_thi,y
        adc #0
        sta TP+1
        lda hr_cbw,x
        sta CBW
        lda hr_y,x
        clc
        adc hr_r,x
        inc a
        sta ENDR
        lda hr_y,x
        sec
        sbc hr_r,x
        tax
@row:   lda row_lo,x            ; the row's base plus a column up to 37 never
        clc                     ; carries
        adc CBW
        sta PTR
        lda row_hi,x
        sta PTR+1
        ldy #0
        lda (TP),y
        eor (PTR),y
        sta (PTR),y
        iny
        lda (TP),y
        eor (PTR),y
        sta (PTR),y
        iny
        lda (TP),y
        eor (PTR),y
        sta (PTR),y
        iny
        lda (TP),y
        eor (PTR),y
        sta (PTR),y
        lda TP
        clc
        adc #5
        sta TP
        bcc :+
        inc TP+1
:       inx
        cpx ENDR
        bne @row
        rts

r7:     .byte 0, 7, 14, 21, 28, 35, 42, 49, 56, 63

.include "hardrain_tables.inc"

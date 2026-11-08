; Sprite engine: the toaster's four wing positions (ids 0-3) and the slice
; of toast (id 4), drawn masked at any dot position with clipping at every
; edge.
;
; sprite_setup switches the language card's RAM in (bank 1, read and write)
; and builds, for every sprite and each of the 7 shifts, a packed block
; there at the address tools/gen_art.py fixed in art.inc. A block holds the
; sprite's rows top to bottom with no gaps; a row holds its byte columns
; c0..c1 left to right, one byte (the lit dots) where every dot of the
; column is covered by the mask, else two (lit, then the AND-mask). Drawing
; is screen AND mask OR lit, or just lit on the solid columns; erasing
; clears the row's bytes c0..c1. The ROM's vectors at $FFFA-$FFFF are copied into
; the language card first, so a reset still finds them.
;
; Which columns a row has at a shift comes from the row descriptors in
; art.inc (a, e-1, fa+6, fe: the row's covered dots [a, e) and its longest
; covered run [fa, fe), in dots from the box's left edge) through the div-7
; tables: c0 = (a+k)/7, c1 = (e-1+k)/7, s0 = (fa+6+k)/7, s1 = (fe+k)/7;
; the solid columns are [s0, s1), none when s0 >= s1. sprite_tables works
; them out once for every row, sprite and shift into the row tables in FXRAM
; (SPR_ROWTAB, 4 arrays of h bytes per block: c0, s0, s1, c1+1, with
; s0 = s1 = c1+1 when there is no solid column), so drawing only looks them
; up. The effect that draws sprites calls it from its init.

.include "config.inc"

.export sprite_setup, sprite_tables, sprite_draw, sprite_erase

.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi
.import vbl_poll

LCBANK1 = $C08B         ; read twice: RAM bank 1, read and write
SCR_LIT = $0800         ; start-up scratch: the shifted lit rows, 7 bytes each
SCR_MSK = $0A00         ; the shifted mask rows, 7 bytes each

; draw/erase
SCR   = SPZ             ; 2: screen row pointer (row start + SCOL)
LIM1  = SPZ+2           ; this row's first solid column (s0)
LIM2  = SPZ+3           ; one past its last solid column (s1)
LIM3  = SPZ+4           ; one past its last column (c1 + 1)
YROW  = SPZ+5           ; screen row being drawn
SH    = SPZ+6           ; rows left
SCOL  = SPZ+7           ; screen byte column of the box's byte 0, signed
SCOLH = SPZ+8           ; $FF when SCOL is negative, else 0
SK    = SPZ+9           ; shift 0-6
SID   = SPZ+10
SMODE = SPZ+11          ; 0 draw, 1 erase
PAGEX = SPZ+12          ; PAGE eor $20: $00 page 1, $60 page 2
XEND  = SPZ+13          ; block index at the end of the clipped row
BLK   = SPZ+14          ; 2: the packed block, at the current row
C0P   = SPX             ; 2: row table c0, indexed by screen row
S0P   = SPX+2           ; 2: s0
S1P   = SPX+4           ; 2: s1
CEP   = SPX+6           ; 2: c1 + 1
T0    = SPX+8
T1    = SPX+9
ROWVEC = SPX+10         ; 2: the row setup in use (fast or clipped)
RIX   = SPX+12          ; first row of the sprite to draw
VL    = SPX+13          ; first visible box column (clipped path)
VR    = SPX+14          ; one past the last visible box column
LEN   = SPX+15

; setup (same zero page, never at the same time as drawing)
SRCP  = SPZ             ; 2
DSTP  = SPZ+2           ; 2
LITP  = SPZ+4           ; 2: scratch row of lit dots
MSKP  = SPZ+6           ; 2: scratch row of mask
ROWS  = SPZ+8
H     = SPZ+11
WB    = SPZ+12
CIN   = SPZ+13          ; bit carried into the next byte while shifting
DA    = SPX             ; 2: row descriptors a
DE    = SPX+2           ; 2: e - 1
DFA   = SPX+4           ; 2: fa + 6
DFE   = SPX+6           ; 2: fe
C0    = SPX+8
C1    = SPX+9
S0    = SPX+10
S1    = SPX+11
COL   = SPX+12

.segment "CODE"

; ---------------------------------------------------------------- setup
sprite_setup:
        ldx #5                  ; carry the ROM's vectors over
:       lda $FFFA,x
        sta vecsave,x
        dex
        bpl :-
        lda LCBANK1
        lda LCBANK1
        ldx #5
:       lda vecsave,x
        sta $FFFA,x
        dex
        bpl :-

        stz SID
@sprite:
        ldx SID
        lda spr_h,x
        sta H
        lda spr_wb,x
        sta WB
        lda spr_src_lo,x
        sta SRCP
        lda spr_src_hi,x
        sta SRCP+1
        jsr desc_pointers

        lda #<SCR_LIT           ; clear both scratch rectangles
        sta DSTP
        lda #>SCR_LIT
        sta DSTP+1
        ldx #4
        ldy #0
:       lda #0
        sta (DSTP),y
        iny
        bne :-
        inc DSTP+1
        dex
        bne :-

        lda #<SCR_LIT           ; copy the source rows in, 7 bytes apart
        sta LITP
        lda #>SCR_LIT
        sta LITP+1
        jsr copy_rows
        lda #<SCR_MSK
        sta LITP
        lda #>SCR_MSK
        sta LITP+1
        jsr copy_rows

        stz SK
@shift: lda SK
        beq :+
        jsr shift_scratch       ; shift k = shift k-1 moved right one dot
:       jsr emit_block
        inc SK
        lda SK
        cmp #7
        bne @shift
        inc SID
        lda SID
        cmp #SPR_COUNT
        bne @sprite
        rts

; DA..DFE = this sprite's row descriptor tables
desc_pointers:
        ldx SID
        lda spr_a_lo,x
        sta DA
        lda spr_a_hi,x
        sta DA+1
        lda spr_e1_lo,x
        sta DE
        lda spr_e1_hi,x
        sta DE+1
        lda spr_fa6_lo,x
        sta DFA
        lda spr_fa6_hi,x
        sta DFA+1
        lda spr_fe_lo,x
        sta DFE
        lda spr_fe_hi,x
        sta DFE+1
        rts

; copy H rows of WB bytes from SRCP to LITP, 7 bytes apart; SRCP moves on
copy_rows:
        lda H
        sta ROWS
@row:   ldy #0
:       lda (SRCP),y
        sta (LITP),y
        iny
        cpy WB
        bne :-
        clc
        lda SRCP
        adc WB
        sta SRCP
        bcc :+
        inc SRCP+1
:       clc
        lda LITP
        adc #7
        sta LITP
        bcc :+
        inc LITP+1
:       dec ROWS
        bne @row
        rts

; move every row of both scratch rectangles right by one dot
shift_scratch:
        lda #<SCR_LIT
        sta LITP
        lda #>SCR_LIT
        sta LITP+1
        jsr shift_rows
        lda #<SCR_MSK
        sta LITP
        lda #>SCR_MSK
        sta LITP+1
shift_rows:
        lda H
        sta ROWS
@row:   ldy #0
        stz CIN
@b:     lda (LITP),y
        asl a                   ; bit 6 moves to bit 7...
        ora CIN
        cmp #$80                ; ...and from there into the carry
        and #$7F
        sta (LITP),y
        lda #0
        rol a
        sta CIN
        iny
        cpy #7
        bne @b
        clc
        lda LITP
        adc #7
        sta LITP
        bcc :+
        inc LITP+1
:       dec ROWS
        bne @row
        rts

; write the packed block of sprite SID at shift SK
emit_block:
        lda SID                 ; X = SID * 7 + SK
        asl a
        asl a
        asl a
        sec
        sbc SID
        clc
        adc SK
        tax
        lda spr_blk_lo,x
        sta DSTP
        lda spr_blk_hi,x
        sta DSTP+1
        lda #<SCR_LIT
        sta LITP
        lda #>SCR_LIT
        sta LITP+1
        lda #<SCR_MSK
        sta MSKP
        lda #>SCR_MSK
        sta MSKP+1
        stz ROWS
@row:   ldy ROWS
        lda (DA),y
        clc
        adc SK
        tax
        lda div7,x
        sta C0
        lda (DE),y
        clc
        adc SK
        tax
        lda div7,x
        sta C1
        lda (DFA),y
        clc
        adc SK
        tax
        lda div7,x
        sta S0
        lda (DFE),y
        clc
        adc SK
        tax
        lda div7,x
        sta S1
        ldy C0
@col:   lda (LITP),y
        sta (DSTP)
        inc DSTP
        bne :+
        inc DSTP+1
:       cpy S0
        bcc @masked
        cpy S1
        bcc @next               ; solid: the lit byte alone
@masked:
        lda (MSKP),y
        eor #$7F
        sta (DSTP)
        inc DSTP
        bne @next
        inc DSTP+1
@next:  iny
        cpy C1
        bcc @col
        beq @col
        clc
        lda LITP
        adc #7
        sta LITP
        bcc :+
        inc LITP+1
:       clc
        lda MSKP
        adc #7
        sta MSKP
        bcc :+
        inc MSKP+1
:       inc ROWS
        lda ROWS
        cmp H
        bne @row
        rts


; ---------------------------------------------------------------- row tables
; sprite_tables: fill the row tables in FXRAM from the descriptors.
sprite_tables:
        stz SID
@sprite:
        ldx SID
        lda spr_h,x
        sta H
        jsr desc_pointers
        stz SK
@shift: lda SID                 ; X = SID * 7 + SK
        asl a
        asl a
        asl a
        sec
        sbc SID
        clc
        adc SK
        tax
        lda spr_row_lo,x        ; the four arrays, H bytes apart
        sta SRCP
        lda spr_row_hi,x
        sta SRCP+1
        lda SRCP
        clc
        adc H
        sta DSTP
        lda SRCP+1
        adc #0
        sta DSTP+1
        clc
        lda DSTP
        adc H
        sta LITP
        lda DSTP+1
        adc #0
        sta LITP+1
        clc
        lda LITP
        adc H
        sta MSKP
        lda LITP+1
        adc #0
        sta MSKP+1
        ldy #0
@row:   lda (DA),y
        clc
        adc SK
        tax
        lda div7,x
        sta (SRCP),y            ; c0
        lda (DE),y
        clc
        adc SK
        tax
        lda div7p1,x
        sta (MSKP),y            ; c1 + 1
        sta C1
        lda (DFE),y
        clc
        adc SK
        tax
        lda div7,x
        sta S1
        lda (DFA),y
        clc
        adc SK
        tax
        lda div7,x
        cmp S1
        bcc :+
        lda C1                  ; no solid column: s0 = s1 = c1 + 1
        sta S1
:       sta (DSTP),y            ; s0
        lda S1
        sta (LITP),y            ; s1
        iny
        cpy H
        bne @row
        inc SK
        lda SK
        cmp #7
        beq :+
        jmp @shift
:       inc SID
        lda SID
        cmp #SPR_COUNT
        beq :+
        jmp @sprite
:       rts

; ---------------------------------------------------------------- draw
; sprite_draw: A = sprite id, PX/PY = top-left of its cell (signed), PAGE.
; Masked columns: screen AND mask OR lit; solid columns: lit. Clipped at
; all four edges.
; sprite_erase: the same parameters; clears every byte of each row that
; holds any of the sprite's mask (columns c0..c1) to 0. Dots of a neighbour
; in those bytes go too, so an effect erases everything on a page before it
; redraws any of it.
sprite_erase:
        ldx #1
        bra sprite_go
sprite_draw:
        ldx #0
sprite_go:
        jsr vbl_poll            ; keep the frame count right during long steps
        stx SMODE
        sta SID
        tay
        clc                     ; SCR = x of the box + 42
        lda PX
        adc spr_x0,y
        sta SCR
        lda PX+1
        adc #0
        sta SCR+1
        clc
        lda SCR
        adc #42
        sta SCR
        lda SCR+1
        adc #0
        bmi @out                ; x < -42: off the left
        beq @xlo
        cmp #1
        bne @out
        ldx SCR
        cpx #80
        bcs @out                ; x >= 294: off the right
        lda xbyte_hi,x
        sec
        sbc #6
        sta SCOL
        lda xmod_hi,x
        bra @shift
@out:   rts
@xlo:   ldx SCR
        lda xbyte_lo,x
        sec
        sbc #6
        sta SCOL
        lda xmod_lo,x
@shift: sta SK
        lda SCOL
        bmi @neg
        cmp #40
        bcs @out                ; x >= 280: off the right
        stz SCOLH
        bra @vert
@neg:   lda #$FF
        sta SCOLH

@vert:  ldy SID
        lda spr_h,y
        sta SH
        clc                     ; YROW = y of the box
        lda PY
        adc spr_y0,y
        sta YROW
        lda PY+1
        adc #0
        bmi @above
        bne @out                ; y >= 256
        lda YROW
        cmp #192
        bcs @out
        stz RIX
        bra @vis
@above: lda YROW                ; y < 0: skip -y rows
        eor #$FF
        inc a
        cmp SH
        bcs @out                ; entirely above the top
        sta RIX
        stz YROW
@vis:   lda SH                  ; rows to draw: min(H - RIX, 192 - YROW)
        sec
        sbc RIX
        sta SH
        lda #192
        sec
        sbc YROW
        cmp SH
        bcs :+
        sta SH
:       lda PAGE
        eor #$20
        sta PAGEX
        lda SID                 ; X = SID * 7 + SK: the block and row tables
        asl a
        asl a
        asl a
        sec
        sbc SID
        clc
        adc SK
        tax
        lda spr_blk_lo,x
        sta BLK
        lda spr_blk_hi,x
        sta BLK+1
        lda spr_row_lo,x        ; the four row arrays, H bytes apart
        sta C0P
        lda spr_row_hi,x
        sta C0P+1
        ldy SID
        clc
        lda C0P
        adc spr_h,y
        sta S0P
        lda C0P+1
        adc #0
        sta S0P+1
        clc
        lda S0P
        adc spr_h,y
        sta S1P
        lda S0P+1
        adc #0
        sta S1P+1
        clc
        lda S1P
        adc spr_h,y
        sta CEP
        lda S1P+1
        adc #0
        sta CEP+1

        ldy #0                  ; step the block past the rows above the top
@skip:  cpy RIX
        beq @skipped
        lda (CEP),y
        sec
        sbc (C0P),y
        asl a
        sta LEN                 ; 2 * (c1 + 1 - c0), less one per solid column
        lda (S1P),y
        sec
        sbc (S0P),y
        sta T0
        lda LEN
        sec
        sbc T0
        clc
        adc BLK
        sta BLK
        bcc :+
        inc BLK+1
:       iny
        bra @skip

@skipped:
        lda RIX                 ; index the row tables by screen row:
        sec                     ; pointers += RIX - YROW
        sbc YROW
        sta T0
        lda #0
        sbc #0
        sta T1
        clc
        lda C0P
        adc T0
        sta C0P
        lda C0P+1
        adc T1
        sta C0P+1
        clc
        lda S0P
        adc T0
        sta S0P
        lda S0P+1
        adc T1
        sta S0P+1
        clc
        lda S1P
        adc T0
        sta S1P
        lda S1P+1
        adc T1
        sta S1P+1
        clc
        lda CEP
        adc T0
        sta CEP
        lda CEP+1
        adc T1
        sta CEP+1
        ldx #0
        jsr blk_patch

        lda SCOL                ; every column on screen? then the fast rows
        bmi @toclip
        ldy SID
        clc
        adc spr_wb,y
        cmp #40
        bcs @toclip
        lda SMODE
        bne @toerase
        lda #<fd_row
        sta ROWVEC
        lda #>fd_row
        sta ROWVEC+1
        jmp fd_row
@toerase:
        lda #<fe_row
        sta ROWVEC
        lda #>fe_row
        sta ROWVEC+1
        jmp fe_row
@toclip:
        lda #<clip_row
        sta ROWVEC
        lda #>clip_row
        sta ROWVEC+1
        lda #0                  ; VL = max(0, -SCOL); VR = min(7, 40 - SCOL)
        sec
        sbc SCOL
        bpl :+
        lda #0
:       sta VL
        lda #40
        sec
        sbc SCOL
        cmp #7
        bcc :+
        lda #7
:       sta VR
        stz XEND
        jmp clip_row

; The loops read the block through patched absolute addresses: X runs
; through the block, Y is the box column, and the screen pointer is the row
; start plus SCOL so (SCR),y is the column's byte. A row is its masked
; columns up to LIM1, solid ones up to LIM2, masked ones up to LIM3.
fd_row: cpx #$80
        bcc :+
        jsr rebase
:       ldy YROW
        lda row_lo,y
        clc
        adc SCOL
        sta SCR
        lda row_hi,y
        eor PAGEX
        adc SCOLH
        sta SCR+1
        lda (S0P),y
        sta LIM1
        lda (S1P),y
        sta LIM2
        lda (CEP),y
        sta LIM3
        lda (C0P),y
        inc YROW
        tay
fd_segs:
        cpy LIM1
        bcs fd_s2
fd_mk1: lda (SCR),y
fd_m1:  and $FFFF,x
fd_l1:  ora $FFFF,x
        sta (SCR),y
        inx
        inx
        iny
        cpy LIM1
        bcc fd_mk1
fd_s2:  cpy LIM2
        bcs fd_s3
fd_l2:  lda $FFFF,x
        sta (SCR),y
        inx
        iny
        cpy LIM2
        bcc fd_l2
fd_s3:  cpy LIM3
        bcs fd_next
fd_mk2: lda (SCR),y
fd_m2:  and $FFFF,x
fd_l3:  ora $FFFF,x
        sta (SCR),y
        inx
        inx
        iny
        cpy LIM3
        bcc fd_mk2
fd_next:
        dec SH
        beq :+
        jmp (ROWVEC)
:       rts

fe_row: ldy YROW
        lda row_lo,y
        clc
        adc SCOL
        sta SCR
        lda row_hi,y
        eor PAGEX
        adc SCOLH
        sta SCR+1
        lda (CEP),y
        sta LIM3
        lda (C0P),y
        inc YROW
        tay
fe_segs:
        cpy LIM3
        bcs fe_next
        lda #0
fe_l:   sta (SCR),y
        iny
        cpy LIM3
        bcc fe_l
fe_next:
        dec SH
        beq :+
        jmp (ROWVEC)
:       rts

; A clipped row: the same loops over the visible columns [VL, VR) only,
; with X stepped past the bytes of the columns clipped at the left and,
; through XEND, those clipped at the right.
clip_row:
        ldx XEND
        cpx #$80
        bcc :+
        jsr rebase
:       ldy YROW
        lda row_lo,y
        clc
        adc SCOL
        sta SCR
        lda row_hi,y
        eor PAGEX
        adc SCOLH
        sta SCR+1
        lda (S0P),y
        sta LIM1
        lda (S1P),y
        sta LIM2
        lda (CEP),y
        sta LIM3
        lda (C0P),y
        sta T0
        inc YROW
        lda LIM3                ; XEND = X + 2 * (ce - c0) - (s1 - s0)
        sec
        sbc T0
        asl a
        sta LEN
        lda LIM2
        sec
        sbc LIM1
        sta T1
        lda LEN
        sec
        sbc T1
        sta LEN
        txa
        clc
        adc LEN
        sta XEND
        lda T0                  ; columns left of VL: step X past their bytes
        cmp VL
        bcs @left
        lda VL
        sec
        sbc T0
        asl a
        sta LEN                 ; 2 per column...
        lda VL
        cmp LIM2
        bcc :+
        lda LIM2
:       sec                     ; ...less one per solid column among them
        sbc LIM1
        bcc :+
        sta T1
        lda LEN
        sec
        sbc T1
        sta LEN
:       txa
        clc
        adc LEN
        tax
        lda VL
        sta T0
@left:  lda LIM1                ; clamp the limits to [VL, VR]
        cmp VL
        bcs :+
        lda VL
:       cmp VR
        bcc :+
        lda VR
:       sta LIM1
        lda LIM2
        cmp VL
        bcs :+
        lda VL
:       cmp VR
        bcc :+
        lda VR
:       sta LIM2
        lda LIM3
        cmp VR
        bcc :+
        lda VR
:       sta LIM3
        ldy T0
        lda SMODE
        bne :+
        jmp fd_segs
:       jmp fe_segs

; BLK += X, X = 0, so X never passes 255; then point the loops at BLK
rebase: txa
        clc
        adc BLK
        sta BLK
        bcc :+
        inc BLK+1
:       ldx #0
blk_patch:
        lda BLK
        sta fd_l1+1
        sta fd_l2+1
        sta fd_l3+1
        lda BLK+1
        sta fd_l1+2
        sta fd_l2+2
        sta fd_l3+2
        clc
        lda BLK
        adc #1
        sta fd_m1+1
        sta fd_m2+1
        lda BLK+1
        adc #0
        sta fd_m1+2
        sta fd_m2+2
        rts

vecsave:
        .res 6

; n div 7 for n = 0..63, and the same plus one
div7:
        .repeat 64, n
        .byte n / 7
        .endrepeat
div7p1:
        .repeat 64, n
        .byte n / 7 + 1
        .endrepeat

.include "art.inc"

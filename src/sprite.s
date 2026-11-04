; Sprite engine: the toaster's three wing positions (ids 0-2) and the toast
; (id 3), drawn masked at any dot position with clipping at every edge.
;
; sprite_setup switches the language card's RAM in (bank 1, read and write)
; and builds 7 pre-shifted copies of every sprite's pixels and mask there,
; at the addresses tools/gen_art.py fixed in art.inc. Masks are stored
; inverted (AND-masks), so drawing is screen AND mask OR pixels, and
; erasing is screen AND mask. The ROM's vectors at $FFFA-$FFFF are copied
; into the language card first, so a reset still finds them.

.include "config.inc"

.export sprite_setup, sprite_draw, sprite_erase

.import row_lo, row_hi, xbyte_lo, xmod_lo, xbyte_hi, xmod_hi

LCBANK1 = $C08B         ; read twice: RAM bank 1, read and write

; draw/erase
SCR   = SPZ             ; 2: screen row pointer
PIXP  = SPZ+2           ; 2: pixel rows
MSKP  = SPZ+4           ; 2: AND-mask rows
SYY   = SPZ+6           ; 2: y of the current row, signed
SH    = SPZ+8           ; rows left
SBPR  = SPZ+9           ; bytes per row
JS    = SPZ+10          ; first byte to draw in a row
JE    = SPZ+11          ; one past the last
SCOL  = SPZ+12          ; screen byte column of the row's byte 0, signed
SID   = SPZ+13
SMODE = SPZ+14          ; 0 draw, 1 erase
SK    = SPZ+15          ; shift 0-6

; setup (same zero page, never at the same time as drawing)
SRCP  = SPZ             ; 2
DSTP  = SPZ+2           ; 2
CNT   = SPZ+4           ; 2
SIZE  = SPZ+6           ; 2: bytes in one block (bpr * h)
ROWS  = SPZ+8
CIN   = SPZ+10          ; bit carried into the next byte while shifting

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
        ldx SID                 ; SIZE = bpr * h
        stz SIZE
        stz SIZE+1
        ldy spr_h,x
:       clc
        lda SIZE
        adc spr_bpr,x
        sta SIZE
        bcc :+
        inc SIZE+1
:       dey
        bne :--

        lda spr_src_lo,x        ; shift 0: copy the pixels...
        sta SRCP
        lda spr_src_hi,x
        sta SRCP+1
        stz SK
        jsr pix_dst
        jsr copy_block
        jsr msk_dst             ; ...then the mask, which follows them
        jsr copy_block

@shift: lda SK                  ; shift k = shift k-1 moved right one dot
        cmp #6
        beq @next
        jsr pix_dst
        jsr dst_to_src
        inc SK
        jsr pix_dst
        jsr copy_block
        jsr pix_dst
        jsr shift_block
        dec SK
        jsr msk_dst
        jsr dst_to_src
        inc SK
        jsr msk_dst
        jsr copy_block
        jsr msk_dst
        jsr shift_block
        bra @shift

@next:  stz SK                  ; finally turn the masks into AND-masks
:       jsr msk_dst
        jsr invert_block
        inc SK
        lda SK
        cmp #7
        bne :-
        inc SID
        lda SID
        cmp #SPR_COUNT
        beq :+
        jmp @sprite
:       rts

; DSTP = pixel block / mask block of sprite SID at shift SK
pix_dst:
        jsr block_index
        lda spr_pix_lo,x
        sta DSTP
        lda spr_pix_hi,x
        sta DSTP+1
        rts
msk_dst:
        jsr block_index
        lda spr_msk_lo,x
        sta DSTP
        lda spr_msk_hi,x
        sta DSTP+1
        rts
block_index:                    ; X = SID * 7 + SK
        lda SID
        asl a
        asl a
        asl a
        sec
        sbc SID
        clc
        adc SK
        tax
        rts
dst_to_src:
        lda DSTP
        sta SRCP
        lda DSTP+1
        sta SRCP+1
        rts

; copy SIZE bytes from SRCP to DSTP; SRCP ends just past the source
copy_block:
        lda SIZE
        sta CNT
        lda SIZE+1
        sta CNT+1
        ldy #0
@l:     lda (SRCP),y
        sta (DSTP),y
        inc SRCP
        bne :+
        inc SRCP+1
:       inc DSTP
        bne :+
        inc DSTP+1
:       lda CNT
        bne :+
        dec CNT+1
:       dec CNT
        lda CNT
        ora CNT+1
        bne @l
        rts

; flip bits 0-6 of SIZE bytes at DSTP
invert_block:
        lda SIZE
        sta CNT
        lda SIZE+1
        sta CNT+1
        ldy #0
@l:     lda (DSTP),y
        eor #$7F
        sta (DSTP),y
        inc DSTP
        bne :+
        inc DSTP+1
:       lda CNT
        bne :+
        dec CNT+1
:       dec CNT
        lda CNT
        ora CNT+1
        bne @l
        rts

; move every row of the block at DSTP right by one dot
shift_block:
        ldx SID
        lda spr_h,x
        sta ROWS
@row:   ldy #0
        stz CIN
@b:     lda (DSTP),y
        asl a                   ; bit 6 moves to bit 7...
        ora CIN
        cmp #$80                ; ...and from there into the carry
        and #$7F
        sta (DSTP),y
        lda #0
        rol a
        sta CIN
        iny
        tya
        ldx SID
        cmp spr_bpr,x
        bne @b
        clc
        lda DSTP
        adc spr_bpr,x
        sta DSTP
        bcc :+
        inc DSTP+1
:       dec ROWS
        bne @row
        rts

; ---------------------------------------------------------------- draw
; sprite_draw / sprite_erase: A = sprite id, PX/PY = top-left of its cell
; (signed), PAGE. Clipped at all four edges.
sprite_erase:
        ldx #1
        bra sprite_go
sprite_draw:
        ldx #0
sprite_go:
        stx SMODE
        sta SID
        tay
        clc                     ; SCR = x of the trimmed box + 42
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
@out:   rts                     ; (a near target for the early exits)
@xlo:   ldx SCR
        lda xbyte_lo,x
        sec
        sbc #6
        sta SCOL
        lda xmod_lo,x
@shift: sta SK
        lda SID                 ; X = SID * 7 + shift
        asl a
        asl a
        asl a
        sec
        sbc SID
        clc
        adc SK
        tax
        lda spr_pix_lo,x
        sta PIXP
        lda spr_pix_hi,x
        sta PIXP+1
        lda spr_msk_lo,x
        sta MSKP
        lda spr_msk_hi,x
        sta MSKP+1
        lda spr_bpr,y
        sta SBPR
        lda spr_h,y
        sta SH

        lda SCOL                ; JS = max(0, -col)
        bpl :+
        eor #$FF
        inc a
        bra :++
:       lda #0
:       sta JS
        lda #40                 ; JE = min(bpr, 40 - col)
        sec
        sbc SCOL
        bmi @out
        beq @out
        cmp SBPR
        bcc :+
        lda SBPR
:       sta JE
        lda JS
        cmp JE
        bcs @off

        clc                     ; SYY = y of the trimmed box
        lda PY
        adc spr_y0,y
        sta SYY
        lda PY+1
        adc #0
        sta SYY+1

@row:   lda SYY+1
        bmi @next               ; above the top: skip the row
        bne @off                ; below the bottom: done
        ldx SYY
        cpx #192
        bcs @off
        lda PAGE                ; SCR = row start + col (col may be negative)
        eor #$20
        eor row_hi,x
        sta SCR+1
        lda row_lo,x
        clc
        adc SCOL
        sta SCR
        lda SCOL
        bmi :+
        bcc @go
        inc SCR+1
        bra @go
:       bcs @go
        dec SCR+1
@go:    ldy JS
        lda SMODE
        bne @erase
@d:     lda (SCR),y
        and (MSKP),y
        ora (PIXP),y
        sta (SCR),y
        iny
        cpy JE
        bne @d
        bra @next
@erase: lda (SCR),y
        and (MSKP),y
        sta (SCR),y
        iny
        cpy JE
        bne @erase

@next:  clc
        lda PIXP
        adc SBPR
        sta PIXP
        bcc :+
        inc PIXP+1
:       clc
        lda MSKP
        adc SBPR
        sta MSKP
        bcc :+
        inc MSKP+1
:       inc SYY
        bne :+
        inc SYY+1
:       dec SH
        bne @row
@off:   rts

vecsave:
        .res 6

.include "art.inc"

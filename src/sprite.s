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
.import vbl_poll

LCBANK1 = $C08B         ; read twice: RAM bank 1, read and write

; draw/erase
SCR   = SPZ             ; 2: screen row pointer
PIXP  = SPZ+2           ; 2: pixel rows
MSKP  = SPZ+4           ; 2: AND-mask rows
SH    = SPZ+8           ; rows left
SBPR  = SPZ+9           ; bytes per row
JS    = SPZ+10          ; first byte to draw in a row
JE    = SPZ+11          ; one past the last
SCOL  = SPZ+12          ; screen byte column of the row's byte 0, signed
SID   = SPZ+13
SMODE = SPZ+14          ; 0 draw, 1 erase
SK    = SPZ+15          ; shift 0-6
SSP   = SPX             ; 2: span starts for this sprite and shift
SEP   = SPX+2           ; 2: span ends
YROW  = SPX+4           ; screen row being drawn
RIX   = SPX+5           ; sprite row being drawn
T0    = SPX+6           ; this row's first byte
T1    = SPX+7           ; one past its last
PAGEX = SPX+8           ; PAGE eor $20: $00 page 1, $60 page 2
SCOLH = SPX+9           ; $FF when SCOL is negative, else 0
OFFL  = SPX+10          ; 2: col - row * bpr
OFFH  = SPX+11
RBJS  = SPX+12          ; side clip limits as block offsets
RBJE  = SPX+13

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
; sprite_draw: A = sprite id, PX/PY = top-left of its cell (signed), PAGE.
; Masked: screen AND mask OR pixels. Clipped at all four edges.
; sprite_erase: the same parameters; clears to black every byte of each row
; that holds any of the sprite's mask. (Only for sprites on a black
; background: neighbouring dots in those bytes are cleared too.)
; Both draw only each row's span, so the empty corners cost nothing.
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
@out:   rts
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
        lda spr_spn_lo,x        ; span starts, then ends H bytes later
        sta SSP
        lda spr_spn_hi,x
        sta SSP+1
        lda spr_h,y
        sta SH
        clc
        adc SSP
        sta SEP
        lda SSP+1
        adc #0
        sta SEP+1
        lda spr_bpr,y
        sta SBPR

        lda SCOL                ; JS = max(0, -col), SCOLH = sign of col
        bpl :+
        eor #$FF
        inc a
        sta JS
        lda #$FF
        bra :++
:       stz JS
        lda #0
:       sta SCOLH
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
        bcs @out
        lda PAGE
        eor #$20
        sta PAGEX

        lda SCOL                ; OFF = col - RIX * bpr: screen pointers are
        sta OFFL                ; offset so one Y indexes data and screen
        lda SCOLH
        sta OFFH
        lda JS                  ; RBJS/RBJE: the clip limits as block offsets
        sta RBJS
        lda JE
        sta RBJE
        stz RIX                 ; first row of the sprite to draw
        clc                     ; YROW = y of the trimmed box
        lda PY
        adc spr_y0,y
        sta YROW
        lda PY+1
        adc #0
        bmi @above
        bne @out2               ; y >= 256
        lda YROW
        cmp #192
        bcs @out2
        bra @rows
@out2:  rts
@above: lda YROW                ; y < 0: skip -y rows
        eor #$FF
        inc a
        cmp SH
        bcs @out2               ; entirely above the top
        tax                     ; step past them: RIX counts up from 0 and
:       jsr next_row_offsets    ; YROW from the negative y to 0
        dex
        bne :-

@rows:  lda #192                ; rows to draw: min(H - RIX, 192 - YROW)
        sec
        sbc YROW
        sta T1
        lda SH
        sec
        sbc RIX
        cmp T1
        bcc :+
        lda T1
:       sta SH
        lda JS                  ; no clipping at the sides: the fast loops
        bne @toclip
        lda JE
        cmp SBPR
        bne @toclip
        lda SMODE
        bne @toerase
        bra @fdraw0
@toclip: jmp @clip
@toerase: ldx YROW
        jmp @ferase
@fdraw0:

; The fast loops are written out in full: this is where the time goes.
        ldx YROW                ; X stays the screen row
@fdraw: lda row_lo,x
        clc
        adc OFFL
        sta SCR
        lda row_hi,x
        eor PAGEX
        adc OFFH
        sta SCR+1
        ldy RIX                 ; this row's span
        lda (SEP),y
        sta T1
        lda (SSP),y
        tay
:       lda (SCR),y
        and (MSKP),y
        ora (PIXP),y
        sta (SCR),y
        iny
        cpy T1
        bne :-
        sec                     ; next row
        lda OFFL
        sbc SBPR
        sta OFFL
        bcs :+
        dec OFFH
:       inx
        inc RIX
        dec SH
        bne @fdraw
        rts

@ferase: lda row_lo,x
        clc
        adc OFFL
        sta SCR
        lda row_hi,x
        eor PAGEX
        adc OFFH
        sta SCR+1
        ldy RIX
        lda (SEP),y
        sta T1
        lda (SSP),y
        tay
        lda #0
:       sta (SCR),y
        iny
        cpy T1
        bne :-
        sec
        lda OFFL
        sbc SBPR
        sta OFFL
        bcs :+
        dec OFFH
:       inx
        inc RIX
        dec SH
        bne @ferase
        rts

@clip:  ldy RIX                 ; this row's span, clipped to the sides
        lda (SSP),y
        cmp RBJS
        bcs :+
        lda RBJS
:       sta T0
        lda (SEP),y
        cmp RBJE
        bcc :+
        lda RBJE
:       sta T1
        lda T0
        cmp T1
        bcs @cnext              ; nothing left in this row
        jsr row_pointer
        ldy T0
        lda SMODE
        bne @cer
:       lda (SCR),y
        and (MSKP),y
        ora (PIXP),y
        sta (SCR),y
        iny
        cpy T1
        bne :-
        bra @cnext
@cer:   lda #0
:       sta (SCR),y
        iny
        cpy T1
        bne :-
@cnext: jsr next_row_offsets
        dec SH
        bne @clip
        rts

; SCR = start of screen row YROW + OFF
row_pointer:
        ldx YROW
        lda row_lo,x
        clc
        adc OFFL
        sta SCR
        lda row_hi,x
        eor PAGEX
        adc OFFH
        sta SCR+1
        rts

; step to the next sprite row and screen row. Keeps X.
next_row_offsets:
        sec
        lda OFFL
        sbc SBPR
        sta OFFL
        bcs :+
        dec OFFH
:       clc
        lda RBJS
        adc SBPR
        sta RBJS
        clc
        lda RBJE
        adc SBPR
        sta RBJE
        inc YROW
        inc RIX
        rts

vecsave:
        .res 6

.include "art.inc"

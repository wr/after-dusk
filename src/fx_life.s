; Effect 17: Life II. Conway's Life on a 40 x 32 torus, 10 generations a
; second. A cell is one screen byte wide and six rows tall: a rounded blob
; ($1C $3E $3E $3E $1C) over five rows and a blank sixth. The board starts as
; a scatter in which each cell is alive on two random bits both set (a
; quarter of them), and when the population has moved by 2 or less for more
; than 40 generations running, or falls under 6, a new scatter replaces it,
; drawn within one step with only the changed cells redrawn. The scatter is a
; step of its own, taken when the condition is seen at the start of a step,
; so it never comes on top of a generation's work. Page 1 shows; page 2 is
; the board.
;
; The board: row r lives in page $40 + r, cell c at offset c + 1, so offsets
; 0 and 41 are margins that catch the counts spilling over the left and
; right edges. Each byte is the cell's live-neighbour count in the low nibble
; and bit 4 for alive. A generation is two passes. The first runs a 32-entry
; rule table over every cell (count and alive in, alive out, count cleared),
; draws the cells that changed and lists the live cells of each row (their
; offsets, 1-40, from offset 64 in the row's page, 0 at the end: nothing on
; page 2 ever has bit 7 set). The second walks each row's list and adds one
; to the eight neighbours of every live cell with inc abs,x; then the margins
; are folded onto columns 40 and 1. Rows 0 and 31 are neighbours. The X
; register holds a cell's offset throughout, so the drawing kernels' store
; addresses start one byte before each screen row.
;
; The overlay is never written, so the code that is patched for each row
; lives in FXRAM: the first pass's row loop and the scatter's (their board
; page bytes and the draw calls), and for each of the 32 rows a drawing
; kernel pair (draw a cell, rub one out: five stores to that row's five
; screen rows) and a counting kernel (the eight incs with that row's pages),
; all built at init.
;
; Cost: a generation is about 26 cycles a cell plus 67 a live cell and
; 45 a changed cell. The first generations after a scatter, with 370-390
; live and 360 changed cells, take 87,000 of the 6 ticks' 102,180; a scatter
; from the densest still life the stillness rule can meet (blocks everywhere,
; 520 cells) takes 97,400.

.include "config.inc"

.export lf_pop, lf_prev, lf_still, lf_board

.import vbl_poll, show_page1, row_lo, row_hi

COLS    = 40
ROWS    = 32
ALIVE   = $10                   ; bit 4 of a board byte
STILL_LIMIT = 40                ; steady for more generations than this: scatter
MIN_POP = 6                     ; fewer cells than this: scatter
LIST    = 64                    ; a row's live list (columns + 1, 0 at the end) at this offset in its page
SCELL_SIZE = 36                 ; bytes of scatter code a cell (checked below)

lf_board = $4000                ; the board: row r in page $40 + r
BOARD_PG = $40
BOARD_END = BOARD_PG + ROWS

; ---- FXRAM ----
BLK     = FXRAM                 ; $0800: code patched per row (copied from the overlay)
BLK_END = FXRAM + $0400
lf_pop  = FXRAM + $0400         ; 2: cells alive after the last generation or scatter
lf_prev = lf_pop + 2            ; 2: the population before that ($FFFF after a scatter)
lf_still = lf_prev + 2          ; 1: generations running that moved the population by 2 or less
DRAWK   = FXRAM + $0800         ; $1000: a row's drawing kernels, 64 bytes a row:
KON_OFS = 0                     ;   draw a cell at +0 (22 bytes),
KOFF_OFS = 32                   ;   rub one out at +32 (16 bytes)
P2K     = FXRAM + $1000         ; $1800: a row's counting kernel, P2K_STRIDE bytes a row
P2K_STRIDE = 40

.assert DRAWK + 64 * ROWS <= P2K, error, "drawing kernels overrun the counting kernels"
.assert P2K + P2K_STRIDE * ROWS <= FXRAM_END, error, "counting kernels overrun FXRAM"

; ---- zero page ----
LP      = FXZ                   ; 2: where the next live cell's column goes
FP      = FXZ+2                 ; 2: a board row, for the fold and the clear
ROW     = FXZ+4                 ; the row being worked on
PG      = FXZ+5                 ; its page
D       = FXZ+6                 ; 2: population difference
KP      = FXZ+8                 ; 2: where a kernel is being built
P2P     = FXZ+10                ; 2
T       = FXZ+12
T2      = FXZ+13
T3      = FXZ+14
CNT     = FXZ+15

.segment "FX17"
        jmp init                ; the overlay's entry points
        jmp step

; ================================================================ init
init:   jsr show_page1
        lda #PAGE1
        sta PAGE
        jsr copy_block
        jsr build_kernels
        ; the board: all dead, counts and lists clear
        stz FP
        lda #BOARD_PG
        sta FP+1
        ldy #0
        tya
@clr:   sta (FP),y
        iny
        bne @clr
        inc FP+1
        ldx FP+1
        cpx #BOARD_END
        bne @clr
        jmp scatter

; copy_block: the row code to FXRAM.
copy_block:
        lda #<blk_src
        sta FP
        lda #>blk_src
        sta FP+1
        lda #<BLK
        sta KP
        lda #>BLK
        sta KP+1
        ldx #(blk_end - blk_start + 255) / 256
        ldy #0
@c:     lda (FP),y
        sta (KP),y
        iny
        bne @c
        inc FP+1
        inc KP+1
        dex
        bne @c
        rts

; build_kernels: for each row, its drawing kernels (the templates with that
; row's five screen row addresses) and its counting kernel (the template with
; the pages of the row and its neighbours).
build_kernels:
        lda #<DRAWK
        sta KP
        lda #>DRAWK
        sta KP+1
        lda #<P2K
        sta P2P
        lda #>P2K
        sta P2P+1
        stz ROW
@row:   ldy #47                 ; the drawing templates, 48 bytes
:       lda draw_tmpl,y
        sta (KP),y
        dey
        bpl :-
        lda ROW                 ; screen row 6 * ROW
        asl a
        adc ROW
        asl a
        sta T
        ldx #0
@k:     ldy T
        lda row_lo,y            ; the row's base less one: X is the column + 1
        sec
        sbc #1
        sta T2
        lda row_hi,y
        sbc #0
        sta T3
        ldy kon_ofs,x
        lda T2
        sta (KP),y
        iny
        lda T3
        sta (KP),y
        ldy koff_ofs,x
        lda T2
        sta (KP),y
        iny
        lda T3
        sta (KP),y
        inc T
        inx
        cpx #5
        bne @k
        lda KP
        clc
        adc #64
        sta KP
        bcc :+
        inc KP+1
:
        ldy #p2_tmpl_end - p2_tmpl - 1  ; the counting template
:       lda p2_tmpl,y
        sta (P2P),y
        dey
        bpl :-
        lda ROW                 ; its pages: the row's, the one above, the one
        clc                     ; below (the left neighbour's inc, indexed by
        adc #BOARD_PG           ; column + 1 from $xxFF, names the page before)
        ldy #4
        sta (P2P),y
        ldy #21
        sta (P2P),y
        dec a
        ldy #18
        sta (P2P),y
        lda ROW
        dec a
        and #ROWS - 1
        clc
        adc #BOARD_PG
        ldy #12
        sta (P2P),y
        ldy #15
        sta (P2P),y
        dec a
        ldy #9
        sta (P2P),y
        lda ROW
        inc a
        and #ROWS - 1
        clc
        adc #BOARD_PG
        ldy #27
        sta (P2P),y
        ldy #30
        sta (P2P),y
        dec a
        ldy #24
        sta (P2P),y
        lda P2P
        clc
        adc #P2K_STRIDE
        sta P2P
        bcc :+
        inc P2P+1
:       inc ROW
        lda ROW
        cmp #ROWS
        beq :+
        jmp @row
:       rts

; The drawing kernels, as built for every row: the five store addresses are
; filled in. Draw at +0, rub out at +32.
draw_tmpl:
        lda #$1C
        sta $2000,x
        lda #$3E
        sta $2000,x
        sta $2000,x
        sta $2000,x
        lda #$1C
        sta $2000,x
        rts
        .res KOFF_OFS - (* - draw_tmpl)
        stz $2000,x
        stz $2000,x
        stz $2000,x
        stz $2000,x
        stz $2000,x
        rts
        .res 48 - (* - draw_tmpl)
kon_ofs:  .byte 3, 8, 11, 14, 19               ; the operands' offsets
koff_ofs: .byte KOFF_OFS + 1, KOFF_OFS + 4, KOFF_OFS + 7, KOFF_OFS + 10, KOFF_OFS + 13

; The counting kernel, as built for every row: walk the row's list (columns
; + 1, so 1-40, 0 at the end) and add one to each live cell's eight
; neighbours. The page bytes are filled in: offsets 4, 21 the row's and 18
; the one before it, 12, 15 the row above's and 9 the one before, 24, 27, 30
; the same for the row below.
p2_tmpl:
        ldy #0
@l:     ldx $4000 + LIST,y
        beq @done
        inc $3FFF,x
        inc $4000,x
        inc $4001,x
        inc $3FFF,x
        inc $4001,x
        inc $3FFF,x
        inc $4000,x
        inc $4001,x
        iny
        bra @l
@done:  rts
p2_tmpl_end:
.assert p2_tmpl_end - p2_tmpl <= P2K_STRIDE, error, "counting kernel too long"

; ================================================================ step
step:   lda #PAGE1
        sta PAGE
        lda lf_still            ; steady too long, or nearly empty: scatter
        cmp #STILL_LIMIT + 1
        bcs @scatter
        lda lf_pop+1
        bne gen
        lda lf_pop
        cmp #MIN_POP
        bcs gen
@scatter:
        jmp scatter

; gen: one generation.
gen:    stz lf_pop
        stz lf_pop+1
        stz ROW
        lda #BOARD_PG
        sta PG
@row:   lda PG
        sta p1a+2
        sta p1b+2
        sta p1c+2
        sta p1d+2
        sta LP+1
        lda #LIST
        sta LP
        lda ROW                 ; the row's drawing kernels: DRAWK + 64 * ROW
        and #3
        tay
        lda shl6,y
        sta p1on+1
        sta p1on2+1
        ora #KOFF_OFS
        sta p1off+1
        sta p1off2+1
        lda ROW
        lsr a
        lsr a
        clc
        adc #>DRAWK
        sta p1on+2
        sta p1off+2
        sta p1on2+2
        sta p1off2+2
        jsr p1row
        jsr end_row
        inc PG
        inc ROW
        lda ROW
        cmp #ROWS
        bne @row
        jsr count
        ; still: one more if the population moved by 2 or less, else 0
        lda lf_pop
        sec
        sbc lf_prev
        sta D
        lda lf_pop+1
        sbc lf_prev+1
        sta D+1
        lda D                   ; -2 <= D <= 2, as 0 <= D + 2 <= 4
        clc
        adc #2
        sta D
        lda D+1
        adc #0
        bne @moved
        lda D
        cmp #5
        bcs @moved
        inc lf_still
        bra :+
@moved: stz lf_still
:       lda lf_pop
        sta lf_prev
        lda lf_pop+1
        sta lf_prev+1
        rts

shl6:   .byte $00, $40, $80, $C0

; end_row: close the row's list, count its live cells into lf_pop and poll
; the vertical blank.
end_row:
        lda #0
        sta (LP)
        lda LP
        sec
        sbc #LIST
        clc
        adc lf_pop
        sta lf_pop
        bcc :+
        inc lf_pop+1
:       jmp vbl_poll

; count: the second pass over every row, then the margins folded in.
count:  lda #<P2K
        sta p2call+1
        lda #>P2K
        sta p2call+2
        lda #ROWS
        sta CNT
@row:   jsr p2call
        jsr vbl_poll
        lda p2call+1
        clc
        adc #P2K_STRIDE
        sta p2call+1
        bcc :+
        inc p2call+2
:       dec CNT
        bne @row
        ; fold: what spilled left of column 0 belongs to column 39, and
        ; right of column 39 to column 0
        stz FP
        lda #BOARD_PG
        sta FP+1
@fold:  ldy #0
        lda (FP),y
        beq :+
        ldy #COLS
        clc
        adc (FP),y
        sta (FP),y
        lda #0
        ldy #0
        sta (FP),y
:       ldy #COLS + 1
        lda (FP),y
        beq :+
        ldy #1
        clc
        adc (FP),y
        sta (FP),y
        lda #0
        ldy #COLS + 1
        sta (FP),y
:       inc FP+1
        lda FP+1
        cmp #BOARD_END
        bne @fold
        rts

; scatter: a new board, a quarter of the cells alive, drawn where it differs
; from the old one; then its counts.
scatter:
        stz lf_pop
        stz lf_pop+1
        stz ROW
        lda #BOARD_PG
        sta PG
@row:   lda PG
        .repeat 8, i
        sta scells + i * SCELL_SIZE + 2
        sta scells + i * SCELL_SIZE + 19
        sta scells + i * SCELL_SIZE + 34
        .endrepeat
        sta LP+1
        lda #LIST
        sta LP
        lda ROW                 ; the row's drawing kernels, through the stubs
        and #3
        tay
        lda shl6,y
        sta on_stub+1
        ora #KOFF_OFS
        sta off_stub+1
        lda ROW
        lsr a
        lsr a
        clc
        adc #>DRAWK
        sta on_stub+2
        sta off_stub+2
        jsr scrow
        jsr end_row
        inc PG
        inc ROW
        lda ROW
        cmp #ROWS
        bne @row
        jsr count
        stz lf_still
        lda #$FF
        sta lf_prev
        sta lf_prev+1
        rts

; rule: the new state from a board byte (count 0-8, bit 4 alive): alive on 3
; neighbours, or 2 when already alive.
rule:   .byte 0, 0, 0, ALIVE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte 0, 0, ALIVE, ALIVE, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
.assert <rule <= $E0, lderror, "rule table crosses a page"

; ================================================================ FXRAM code
; Copied to BLK at init. Assembled for its home there: the rest of the
; overlay reaches it by the labels below.
blk_src:
        .org BLK
blk_start:

; p1row: the first pass over row PG, two cells a turn (page bytes patched
; at p1a-p1d): rule, draw the changes with the row's kernels (p1on, p1off,
; p1on2, p1off2), list the live cells at LP.
p1row:  ldx #1
p1_cell:
p1a:    ldy lf_board,x
        lda rule,y
p1b:    sta lf_board,x
        bne p1_live
        cpy #ALIVE
        bcs p1_died
p1_mid: inx
p1c:    ldy lf_board,x
        lda rule,y
p1d:    sta lf_board,x
        bne p1_live2
        cpy #ALIVE
        bcs p1_died2
p1_next:  inx
        cpx #COLS + 1
        bne p1_cell
        rts
p1_died:
p1off:  jsr DRAWK + KOFF_OFS
        bra p1_mid
p1_live:  txa
        sta (LP)
        inc LP
        cpy #ALIVE
        bcs p1_mid
p1on:   jsr DRAWK + KON_OFS
        bra p1_mid
p1_died2:
p1off2: jsr DRAWK + KOFF_OFS
        bra p1_next
p1_live2: txa
        sta (LP)
        inc LP
        cpy #ALIVE
        bcs p1_next
p1on2:  jsr DRAWK + KON_OFS
        bra p1_next

; on_stub, off_stub: the scatter's way to the row's drawing kernels.
on_stub:
        jmp DRAWK + KON_OFS
off_stub:
        jmp DRAWK + KOFF_OFS

; scrow: the scatter over row PG. Eight cells to a random byte (both bytes of
; the RNG's state ANDed, so each bit is set one time in four); a cell that
; changes is drawn or rubbed out, every cell's byte becomes its new state
; with no count, and the live cells are listed at LP.
.macro SCELL mask
        .local wr, dd, zz, nx
        lda lf_board,x          ; +0: page byte at +2
        cmp #ALIVE              ; carry: alive now
        tya
        and #mask
        beq dd
        bcs wr                   ; alive and staying alive
        jsr on_stub
wr:      lda #ALIVE
        sta lf_board,x          ; +17: page byte at +19
        txa
        sta (LP)
        inc LP
        bra nx
dd:      bcc zz                   ; dead and staying dead
        jsr off_stub
zz:      stz lf_board,x          ; +32: page byte at +34
nx:      inx
.endmacro

scrow:  ldx #1
sc_oct:   lda RNG+1               ; rng_next, inlined
        lsr a
        lda RNG
        ror a
        eor RNG+1
        sta RNG+1
        ror a
        eor RNG
        sta RNG
        eor RNG+1
        sta RNG+1
        and RNG
        tay
scells:
        SCELL $01
scell1:
        SCELL $02
        SCELL $04
        SCELL $08
        SCELL $10
        SCELL $20
        SCELL $40
        SCELL $80
        cpx #COLS + 1
        beq :+
        jmp sc_oct
:       rts
.assert scell1 - scells = SCELL_SIZE, error, "SCELL is not SCELL_SIZE bytes"

; p2call: to the row's counting kernel (patched by count).
p2call: jmp P2K

blk_end:
        .reloc
.assert blk_end - blk_start <= BLK_END - BLK, error, "FXRAM code block too big"

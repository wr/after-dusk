; Effect 16: Snake. A maze of 38 x 26 cells, 7 dots to a cell, fills the
; screen. A thick snake sets out from a door on one side and hunts for the
; oval marking the exit on the opposite side, one cell a step (30 a second):
; it goes down a random open passage it hasn't been down yet, and when it
; runs out of passages it backs out of the dead end, rubbing out its body as
; it goes. When it runs out through the exit, the picture holds for 3 seconds
; (90 steps) while the next maze is drawn on the hidden page, then the pages
; swap and the snake sets out again.
;
; Mazes are "growing tree": from one cell, pick an active cell (the newest
; half the time, otherwise one of the last 255), carve to a random unseen
; neighbour and make it active, or drop a cell with nothing unseen round it.
; A cell's byte in sn_maze: open bits 1 N, 2 E, 4 S, 8 W; 16 visited by the
; snake; 32 seen by the generator.
;
; The hidden page's maze is made in pieces so that no step takes more than
; 2 ticks: the generator runs CHUNK iterations a step (about two steps a
; row of cells), then one row of cells is drawn a step (its 7 scanlines,
; written whole: nothing else clears the page), then the doors.
;
; Each cell is one screen byte wide, so a wall row is written a byte at a
; time; the body, the doors and the oval are drawn with hspan.

.include "config.inc"

.export sn_maze, sn_active_c, sn_active_r, sn_stack_c, sn_stack_r
.export sn_state, sn_hold, sn_sp, sn_exit_c, sn_exit_r, sn_exit_side, sn_start_side
.export sn_page, sn_alen, sn_phase, sn_row
.export sn_next_c, sn_next_r, sn_next_side, sn_nexit_c, sn_nexit_r, sn_nexit_side

.import rng_next, vbl_poll, hspan, show_page1, show_page2, row_lo, row_hi

; ADDOPT: direction A joins the options.
.macro ADDOPT
        ldx NOPT
        sta OPT,x
        inc NOPT
.endmacro

GC      = 38                    ; cells across
GR      = 26                    ; cells down
CHUNK   = 40                    ; generator iterations a step
HOLD    = 90                    ; steps the solved maze stays up
SEEN    = 32                    ; the generator has reached the cell
VISITED = 16                    ; the snake has been in the cell

; sn_state
ST_SOLVE = 0
ST_HOLD  = 1
; sn_phase: the hidden page's progress during the hold
PH_BEGIN = 0                    ; clear the maze, seed the generator
PH_GEN   = 1                    ; generating
PH_ROWS  = 2                    ; drawing rows (sn_row is the next)
PH_DOORS = 3                    ; doors, oval, start block
PH_DONE  = 4

; ---- FXRAM ----
sn_maze     = FXRAM             ; $0800: 988 cells, row r at + r * 38
sn_active_c = $0C00             ; the generator's active cells
sn_active_r = $1000
sn_stack_c  = $1400             ; the snake, from its start to its head
sn_stack_r  = $1800
VARS        = $1C00
sn_state    = VARS              ; 0 solving, 1 hold
sn_hold     = VARS+1            ; hold steps left
sn_sp       = VARS+2            ; 2: cells on the stack
sn_exit_c   = VARS+4
sn_exit_r   = VARS+5
sn_exit_side = VARS+6           ; 0 top, 1 right, 2 bottom, 3 left
sn_start_side = VARS+7
sn_page     = VARS+8            ; $20 or $40: the page the snake is on
sn_alen     = VARS+9            ; 2: active cells
sn_phase    = VARS+11
sn_row      = VARS+12           ; the next row to draw, 0-26 (26 is the bottom wall)
sn_next_c   = VARS+13           ; the next maze's start...
sn_next_r   = VARS+14
sn_next_side = VARS+15
sn_nexit_c  = VARS+16           ; ...and exit
sn_nexit_r  = VARS+17
sn_nexit_side = VARS+18
sn_vrow     = VARS+32           ; 40: a row of cells' vertical walls, as screen bytes

; ---- zero page ----
CC    = FXZ                     ; the cell in hand
CR    = FXZ+1
NC    = FXZ+2                   ; its neighbour
NR    = FXZ+3
MP    = FXZ+4                   ; 2: sn_maze row of CR
NP    = FXZ+6                   ; 2: sn_maze row of NR
AP    = FXZ+8                   ; 2: into the active list or the stack
OPT   = FXZ+10                  ; 4: directions open to go
NOPT  = FXZ+14
DIR   = FXZ+15
CNT   = FXZ+16                  ; iterations left in a chunk
TMP   = FXZ+17
K     = FXZ+18                  ; 2: an index
BX    = FXZ+20                  ; 2: the cell's block, left x
BY    = FXZ+22                  ; top y
PTR2  = FXZ+23                  ; 2: a screen row
WCAR  = FXZ+25                  ; a wall row: the dot carried into the next byte
CURW  = FXZ+26                  ; 1 when the row has cells (not the bottom wall)
PREVW = FXZ+27                  ; 1 when there is a row above
TMSK  = FXZ+28                  ; the bit that says "no wall along the top": 1, or 4 for the bottom
MP2   = FXZ+29                  ; 2: sn_maze row above
SIDE  = FXZ+31
OX    = FXZ+32                  ; 2: the oval's centre
CUR   = FXZ+34                  ; the cell's byte
RB    = FXZ+35                  ; the screen byte being built
ROWY  = FXZ+36                  ; scanline
TMP2  = FXZ+37

.segment "FX16"
        jmp init                ; the overlay's entry points
        jmp step

; ================================================================ init
; The first maze, all at once, on page 1 (showing, wiped): page 1 is the
; "hidden" page of a pretend page 2, so the usual flip shows it.
init:
        lda #PAGE2
        sta sn_page
        stz sn_phase
@work:  jsr hold_work
        lda sn_phase
        cmp #PH_DONE
        bne @work
        jmp flip

; ================================================================ step
step:
        lda sn_page
        sta PAGE
        lda sn_state
        beq solve_step
        jmp hold_step

; ---------------------------------------------------------------- solving
solve_step:
        jsr top_cell
        lda CC
        cmp sn_exit_c
        bne @go
        lda CR
        cmp sn_exit_r
        bne @go
        jmp exit_reached
@go:    jsr find_opts           ; open passages to cells not yet visited
        lda NOPT
        beq @back
        jsr pick_opt
        jsr neighbour
        jsr nrow
        ldy NC
        lda (NP),y
        ora #VISITED
        sta (NP),y
        lda #1
        sta PCOL
        jsr draw_link
        lda sn_sp               ; push the new head
        sta AP
        lda sn_sp+1
        clc
        adc #>sn_stack_c
        sta AP+1
        lda NC
        sta (AP)
        jsr ap_r
        lda NR
        sta (AP)
        inc sn_sp
        bne :+
        inc sn_sp+1
:       rts
@back:  lda sn_sp               ; a dead end: pop, and rub out the link from
        bne :+                  ; the cell below to this one
        dec sn_sp+1
:       dec sn_sp
        lda CC
        sta NC
        lda CR
        sta NR
        jsr top_cell
        ldx #0                  ; which way the head was from it
        lda NC
        cmp CC
        bne @h
        lda NR
        cmp CR
        bcc @d                  ; above: north
        ldx #2
        bra @d
@h:     ldx #1                  ; right of it: east
        bcs @d
        ldx #3
@d:     stz PCOL
        jmp draw_link

; exit_reached: the head is in the exit cell. Run out through the door, over
; the oval, then hold while the next maze is made.
exit_reached:
        lda #1
        sta PCOL
        lda sn_exit_side
        sta SIDE
        jsr draw_stub
        jsr draw_oval
        lda #HOLD
        sta sn_hold
        lda #ST_HOLD
        sta sn_state
        stz sn_phase
        rts

; top_cell: CC, CR = the head of the snake (the top of the stack).
top_cell:
        lda sn_sp
        sec
        sbc #1
        sta AP
        lda sn_sp+1
        sbc #0
        clc
        adc #>sn_stack_c
        sta AP+1
        lda (AP)
        sta CC
        jsr ap_r
        lda (AP)
        sta CR
        rts

; ap_r: AP from a c array to the matching r array ($0400 further on).
ap_r:   lda AP+1
        clc
        adc #4
        sta AP+1
        rts

; ---------------------------------------------------------------- hold
; Count the hold down while the next maze is made on the hidden page; when
; both are done, swap the pages.
hold_step:
        lda sn_phase
        cmp #PH_DONE
        beq @count
        jsr hold_work
@count: lda sn_hold
        beq @zero
        dec sn_hold
        bne @rts
@zero:  lda sn_phase
        cmp #PH_DONE
        bne @rts
        jmp flip
@rts:   rts

; hold_work: one step's worth of the next maze, on the hidden page.
hold_work:
        lda sn_page
        eor #$60
        sta PAGE
        lda sn_phase
        bne :+
        jmp gen_begin
:       cmp #PH_GEN
        bne :+
        jmp gen_chunk
:       cmp #PH_ROWS
        bne :+
        jmp render_row
:       jmp doors_step

; flip: the next maze's doors become the current ones, the snake is put at
; its start, and the page it is on is shown.
flip:
        lda sn_nexit_c
        sta sn_exit_c
        lda sn_nexit_r
        sta sn_exit_r
        lda sn_nexit_side
        sta sn_exit_side
        lda sn_next_side
        sta sn_start_side
        lda sn_next_c
        sta sn_stack_c
        sta CC
        lda sn_next_r
        sta sn_stack_r
        sta CR
        lda #1
        sta sn_sp
        stz sn_sp+1
        jsr mrow
        ldy CC
        lda (MP),y
        ora #VISITED
        sta (MP),y
        stz sn_state
        lda sn_page
        eor #$60
        sta sn_page
        sta PAGE
        cmp #PAGE2
        beq :+
        jmp show_page1
:       jmp show_page2

; ---------------------------------------------------------------- generator
; gen_begin: an empty maze and one seen cell on the active list.
gen_begin:
        lda #0
        tax
@clr:   sta sn_maze,x
        sta sn_maze+$100,x
        sta sn_maze+$200,x
        sta sn_maze+$300,x
        inx
        bne @clr
        lda #GC
        jsr rand_below
        sta CC
        sta sn_active_c
        lda #GR
        jsr rand_below
        sta CR
        sta sn_active_r
        jsr mrow
        ldy CC
        lda #SEEN
        sta (MP),y
        lda #1
        sta sn_alen
        stz sn_alen+1
        lda #PH_GEN
        sta sn_phase
        rts

; gen_chunk: up to CHUNK iterations of the growing tree.
gen_chunk:
        lda #CHUNK
        sta CNT
@it:    lda sn_alen
        ora sn_alen+1
        bne :+
        jmp @done
:       jsr rng_next            ; the newest cell, or one of the last 255
        lsr a
        bcs @newest
        lda sn_alen+1
        bne @big
        lda sn_alen
        jsr rand_below
        bra @off
@big:   jsr rng_next
        cmp #$FF
        beq @big
@off:   sta TMP                 ; K = alen - 1 - offset
        lda sn_alen
        sec
        sbc TMP
        sta K
        lda sn_alen+1
        sbc #0
        sta K+1
        bra @dec1
@newest:
        lda sn_alen
        sta K
        lda sn_alen+1
        sta K+1
@dec1:  lda K
        bne :+
        dec K+1
:       dec K
        lda K                   ; the cell at K
        sta AP
        lda K+1
        clc
        adc #>sn_active_c
        sta AP+1
        lda (AP)
        sta CC
        jsr ap_r
        lda (AP)
        sta CR
        jsr mrow                ; which neighbours inside the grid are unseen
        ldy CC
        stz NOPT
        lda CR                  ; north: 38 bytes back
        beq @no_n
        lda MP
        sec
        sbc #GC
        sta NP
        lda MP+1
        sbc #0
        sta NP+1
        lda (NP),y
        and #SEEN
        bne @no_n
        lda #0
        ADDOPT
@no_n:  lda CR                  ; south: 38 bytes on
        cmp #GR-1
        beq @no_s
        lda MP
        clc
        adc #GC
        sta NP
        lda MP+1
        adc #0
        sta NP+1
        lda (NP),y
        and #SEEN
        bne @no_s
        lda #2
        ADDOPT
@no_s:  tya                     ; west
        beq @no_w
        dey
        lda (MP),y
        iny
        and #SEEN
        bne @no_w
        lda #3
        ADDOPT
@no_w:  cpy #GC-1               ; east
        beq @no_e
        iny
        lda (MP),y
        dey
        and #SEEN
        bne @no_e
        lda #1
        ADDOPT
@no_e:  lda NOPT
        bne @carve
        lda sn_alen             ; none: the last active cell takes its place
        bne :+
        dec sn_alen+1
:       dec sn_alen
        lda sn_alen
        sta NP
        lda sn_alen+1
        clc
        adc #>sn_active_r
        sta NP+1
        lda (NP)
        sta (AP)
        lda AP+1
        sec
        sbc #4
        sta AP+1
        lda NP+1
        sec
        sbc #4
        sta NP+1
        lda (NP)
        sta (AP)
        bra @next
@carve: jsr pick_opt
        jsr neighbour
        jsr nrow
        ldy CC
        lda (MP),y
        ora dbit,x
        sta (MP),y
        ldy NC
        lda (NP),y
        ora dback,x
        ora #SEEN
        sta (NP),y
        lda sn_alen             ; the neighbour joins the active list
        sta AP
        lda sn_alen+1
        clc
        adc #>sn_active_c
        sta AP+1
        lda NC
        sta (AP)
        jsr ap_r
        lda NR
        sta (AP)
        inc sn_alen
        bne @next
        inc sn_alen+1
@next:  lda CNT
        and #7
        bne :+
        jsr vbl_poll            ; a chunk can outlast a frame
:       dec CNT
        beq :+
        jmp @it
:       rts
@done:  lda #PH_ROWS
        sta sn_phase
        stz sn_row
        rts

; ---------------------------------------------------------------- cells
; mrow: MP = the sn_maze row of CR.
mrow:   ldx CR
        lda row38_lo,x
        sta MP
        lda row38_hi,x
        sta MP+1
        rts

; nrow: NP = the sn_maze row of NR.
nrow:   ldy NR
        lda row38_lo,y
        sta NP
        lda row38_hi,y
        sta NP+1
        rts

; neighbour: NC, NR = the cell next to CC, CR in direction X.
neighbour:
        lda CC
        clc
        adc dc_tab,x
        sta NC
        lda CR
        clc
        adc dr_tab,x
        sta NR
        rts

; find_opts: the snake's ways on from CC, CR, in OPT (NOPT of them): open
; passages to cells it hasn't visited. Sets MP.
find_opts:
        stz NOPT
        jsr mrow
        ldy CC
        lda (MP),y
        sta CUR
        ldx #0
@dir:   lda CUR
        and dbit,x
        beq @next
        jsr neighbour
        jsr nrow
        ldy NC
        lda (NP),y
        and #VISITED
        bne @next
        txa
        phx                     ; ADDOPT uses X, the loop's direction
        ADDOPT
        plx
@next:  inx
        cpx #4
        bne @dir
        rts

; rand_below: A = n (1-255); returns 0 to n - 1 in A, evenly (draws under the
; next power of two and throws back what lands at n or over). Keeps X, Y.
rand_below:
        sta TMP2
        dec a
        sta TMP                 ; the mask: every bit under the top bit of n - 1
        lsr a
        ora TMP
        sta TMP
        lsr a
        ora TMP
        sta TMP
        lsr a
        lsr a
        ora TMP
        sta TMP
        lsr a
        lsr a
        lsr a
        lsr a
        ora TMP
        sta TMP
@draw:  jsr rng_next
        and TMP
        cmp TMP2
        bcs @draw
        rts

; pick_opt: one of the NOPT options at random, in X and DIR.
pick_opt:
        lda NOPT
        cmp #2
        bcc @one
        beq @two
        cmp #4
        beq @four
@three: jsr rng_next
        and #3
        cmp #3
        beq @three
        bra @got
@four:  jsr rng_next
        and #3
        bra @got
@two:   jsr rng_next
        and #1
        bra @got
@one:   lda #0
@got:   tax
        lda OPT,x
        sta DIR
        tax
        rts

; ---------------------------------------------------------------- drawing
; cell_xy: BX, BY = the top left of the block in cell CC, CR.
cell_xy:
        ldy CC
        lda bx_lo,y
        sta BX
        lda bx_hi,y
        sta BX+1
        ldy CR
        lda by_tab,y
        sta BY
        rts

; setpx, setpx2: PX (PX2) = BX + A, A signed. Keep X.
setpx:  ldy #0
        cmp #$80
        bcc :+
        dey
:       clc
        adc BX
        sta PX
        tya
        adc BX+1
        sta PX+1
        rts

setpx2: ldy #0
        cmp #$80
        bcc :+
        dey
:       clc
        adc BX
        sta PX2
        tya
        adc BX+1
        sta PX2+1
        rts

; rect_rows: TMP rows of the span PX-PX2 from row PY down, in mode PCOL.
rect_rows:
        jsr hspan
        inc PY
        dec TMP
        bne rect_rows
        rts

; draw_link: the body from the block in CC, CR to the block in the next cell
; in direction X, less the block in CC, CR itself: 4 x 7 dots.
draw_link:
        jsr cell_xy
        txa
        lsr a
        bcs @horiz
        lda #0                  ; north or south: the block's columns
        jsr setpx
        lda #3
        jsr setpx2
        lda #7
        sta TMP
        cpx #0
        bne @south
        lda BY
        sec
        sbc #7
        bra @rows
@south: lda BY
        clc
        adc #4
        bra @rows
@horiz: lda #4
        sta TMP
        cpx #1
        bne @west
        lda #4                  ; east: bx + 4 .. bx + 10
        jsr setpx
        lda #10
        jsr setpx2
        bra @hrows
@west:  lda #<-7                ; west: bx - 7 .. bx - 1
        jsr setpx
        lda #<-1
        jsr setpx2
@hrows: lda BY
@rows:  sta PY
        stz PY+1
        jmp rect_rows

; draw_block: the 4 x 4 block in cell CC, CR.
draw_block:
        jsr cell_xy
        lda #0
        jsr setpx
        lda #3
        jsr setpx2
        lda BY
        sta PY
        stz PY+1
        lda #4
        sta TMP
        jmp rect_rows

; draw_stub: the run from the block in CC, CR (on side SIDE of the maze)
; out through its door, past the outer wall.
draw_stub:
        jsr cell_xy
        lda SIDE
        lsr a
        bcs @lr
        lda #0                  ; top or bottom: the block's columns, 6 rows
        jsr setpx
        lda #3
        jsr setpx2
        lda #6
        sta TMP
        lda SIDE
        bne @bot
        lda #2                  ; rows 2 .. 7
        bra @go
@bot:   lda BY                  ; rows by + 3 .. 190
        clc
        adc #3
        bra @go
@lr:    lda #4                  ; left or right: the block's rows
        sta TMP
        lda SIDE
        cmp #1
        bne @left
        lda #3                  ; bx + 3 .. 276
        jsr setpx
        lda #<276
        sta PX2
        lda #>276
        sta PX2+1
        bra @y
@left:  lda #4                  ; 4 .. bx
        sta PX
        stz PX+1
        lda #0
        jsr setpx2
@y:     lda BY
@go:    sta PY
        stz PY+1
        jmp rect_rows

; draw_oval: the exit's oval, 7 x 5 dots, on the outer wall at cell CC, CR,
; side SIDE: rows of 5, 7, 7, 7, 5 dots.
draw_oval:
        jsr cell_xy
        lda SIDE
        lsr a
        bcs @lr
        lda BX                  ; top or bottom: centred on bx + 2
        clc
        adc #2
        sta OX
        lda BX+1
        adc #0
        sta OX+1
        lda SIDE
        bne @bot
        lda #5
        bra @cy
@bot:   lda #187
        bra @cy
@lr:    lda SIDE
        cmp #1
        bne @left
        lda #<273               ; right: on the outer wall
        sta OX
        lda #>273
        sta OX+1
        bra @ry
@left:  lda #7
        sta OX
        stz OX+1
@ry:    lda BY                  ; centred on by + 2
        clc
        adc #2
@cy:    sec
        sbc #2
        sta PY
        stz PY+1
        ldx #0
@row:   stx TMP
        lda OX
        sec
        sbc ohw,x
        sta PX
        lda OX+1
        sbc #0
        sta PX+1
        lda OX
        clc
        adc ohw,x
        sta PX2
        lda OX+1
        adc #0
        sta PX2+1
        jsr hspan
        inc PY
        ldx TMP
        inx
        cpx #5
        bne @row
        rts

ohw:    .byte 2, 3, 3, 3, 2     ; the oval's half-widths by row

; door_clear: open the outer wall at cell CC, CR on side SIDE: 6 dots, the
; posts left standing. PCOL must be 0.
door_clear:
        jsr cell_xy
        lda SIDE
        lsr a
        bcs @lr
        lda #<-1                ; top or bottom: bx - 1 .. bx + 4
        jsr setpx
        lda #4
        jsr setpx2
        lda #1
        sta TMP
        lda SIDE
        bne @bot
        lda #5
        bra @go
@bot:   lda #187
        bra @go
@lr:    lda SIDE
        cmp #1
        bne @left
        lda #<273
        sta PX
        sta PX2
        lda #>273
        sta PX+1
        sta PX2+1
        bra @y
@left:  lda #7
        sta PX
        sta PX2
        stz PX+1
        stz PX2+1
@y:     lda #6                  ; rows by - 1 .. by + 4
        sta TMP
        lda BY
        sec
        sbc #1
@go:    sta PY
        stz PY+1
        jmp rect_rows

; ---------------------------------------------------------------- rows
; set_row: PTR2 = scanline A on PAGE.
set_row:
        tax
        lda row_lo,x
        sta PTR2
        lda PAGE
        eor #$20
        eor row_hi,x
        sta PTR2+1
        rts

; clear_row: the 40 bytes of the scanline at PTR2.
clear_row:
        lda #0
        ldy #39
:       sta (PTR2),y
        dey
        bpl :-
        rts

; clear_rows: TMP scanlines from ROWY + 1 on.
clear_rows:
        inc ROWY
        lda ROWY
        jsr set_row
        jsr clear_row
        dec TMP
        bne clear_rows
        rts

; render_row: row sn_row of the maze on PAGE: its wall line (the tops of its
; cells, with the posts of the row above and the vertical walls' last dot)
; and the six scanlines under it with its vertical walls. Row 26 is the
; bottom wall. The blank scanlines above and below the maze are cleared
; with the first and last rows.
render_row:
        ldx sn_row
        lda #1
        sta TMSK
        sta CURW
        cpx #GR
        bcc :+
        ldx #GR-1               ; the bottom wall: row 25's south sides
        lda #4
        sta TMSK
        stz CURW
:       lda row38_lo,x
        sta MP
        lda row38_hi,x
        sta MP+1
        ldx sn_row
        stz PREVW
        beq @top
        lda #1
        sta PREVW
        dex
        lda row38_lo,x
        sta MP2
        lda row38_hi,x
        sta MP2+1
        bra @wall
@top:   lda #$FF                ; scanlines 0-4
        sta ROWY
        lda #5
        sta TMP
        jsr clear_rows
@wall:  ldx sn_row
        lda wy_tab,x
        jsr set_row
        stz WCAR
        lda #0
        tay
        sta (PTR2),y            ; byte 0, left of the maze
@cell:  lda WCAR                ; Y = c: byte c + 1
        sta RB
        stz WCAR
        lda (MP),y
        and TMSK
        bne :+
        lda #$7F                ; a wall along the top: 7 dots, and one more
        sta RB                  ; into the next byte
        lda #1
        sta WCAR
:       lda CURW
        beq :+
        lda (MP),y
        and #8
        bne :+
        lda RB                  ; the cell's left wall
        ora #1
        sta RB
:       lda PREVW
        beq :+
        lda (MP2),y
        and #8
        bne :+
        lda RB                  ; the last dot of the left wall above
        ora #1
        sta RB
:       iny
        lda RB
        sta (PTR2),y
        cpy #GC
        bne @cell
        ldy #GC-1               ; byte 39: the right outer wall
        lda WCAR
        sta RB
        lda CURW
        beq :+
        lda (MP),y
        and #2
        bne :+
        lda RB
        ora #1
        sta RB
:       lda PREVW
        beq :+
        lda (MP2),y
        and #2
        bne :+
        lda RB
        ora #1
        sta RB
:       lda RB
        ldy #39
        sta (PTR2),y
        lda CURW
        beq @bottom
        stz sn_vrow             ; the vertical walls, as a row of bytes
        ldy #0
@vc:    lda (MP),y
        and #8
        beq :+
        lda #0
        bra :++
:       lda #1
:       iny
        sta sn_vrow,y
        cpy #GC
        bne @vc
        ldy #GC-1
        lda (MP),y
        and #2
        beq :+
        lda #0
        bra :++
:       lda #1
:       sta sn_vrow+39
        ldx sn_row
        lda wy_tab,x
        sta ROWY
        lda #6
        sta TMP
@vl:    inc ROWY
        lda ROWY
        jsr set_row
        ldy #39
@cp:    lda sn_vrow,y
        sta (PTR2),y
        dey
        bpl @cp
        dec TMP
        bne @vl
        inc sn_row
        rts
@bottom:
        lda #187                ; scanlines 188-191
        sta ROWY
        lda #4
        sta TMP
        jsr clear_rows
        lda #PH_DOORS
        sta sn_phase
        rts

; ---------------------------------------------------------------- doors
; doors_step: choose the next maze's start and exit (a random cell on a
; random side, and one on the side opposite), open the wall at both, and
; draw the exit's oval, the start's stub and its block.
doors_step:
        jsr rng_next
        and #3
        sta sn_next_side
        eor #2
        sta sn_nexit_side
        lda sn_next_side
        jsr edge_cell
        stx sn_next_c
        sty sn_next_r
        lda sn_nexit_side
        jsr edge_cell
        stx sn_nexit_c
        sty sn_nexit_r
        stz PCOL
        jsr next_start
        jsr door_clear
        lda sn_nexit_side
        sta SIDE
        lda sn_nexit_c
        sta CC
        lda sn_nexit_r
        sta CR
        jsr door_clear
        lda #1
        sta PCOL
        jsr draw_oval
        jsr next_start
        jsr draw_stub
        jsr draw_block
        lda #PH_DONE
        sta sn_phase
        rts

next_start:
        lda sn_next_side
        sta SIDE
        lda sn_next_c
        sta CC
        lda sn_next_r
        sta CR
        rts

; edge_cell: a random cell on side A: X = c, Y = r.
edge_cell:
        sta SIDE
        lsr a
        bcs @lr
        lda #GC
        jsr rand_below
        tax
        ldy #0
        lda SIDE
        beq @ok
        ldy #GR-1
        rts
@lr:    lda #GR
        jsr rand_below
        tay
        ldx #GC-1
        lda SIDE
        cmp #1
        beq @ok
        ldx #0
@ok:    rts

; ---------------------------------------------------------------- tables
dc_tab: .byte 0, 1, 0, <-1      ; N E S W
dr_tab: .byte <-1, 0, 1, 0
dbit:   .byte 1, 2, 4, 8
dback:  .byte 4, 8, 1, 2

row38_lo:
.repeat GR, i
        .byte <(sn_maze + i * GC)
.endrepeat
row38_hi:
.repeat GR, i
        .byte >(sn_maze + i * GC)
.endrepeat

bx_lo:                          ; the block's left x: 9 + 7c
.repeat GC, i
        .byte <(9 + 7 * i)
.endrepeat
bx_hi:
.repeat GC, i
        .byte >(9 + 7 * i)
.endrepeat

by_tab:                         ; the block's top y: 7 + 7r
.repeat GR, i
        .byte 7 + 7 * i
.endrepeat

wy_tab:                         ; wall lines: 5 + 7r, r = 0-26
.repeat GR + 1, i
        .byte 5 + 7 * i
.endrepeat

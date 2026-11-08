; Fish!'s cache engine (included by fx_fish.s: FISHCODE2 for the code that
; patches itself as it draws, FISHLC for the part that reads aux memory,
; and the overlay for init's part and the tables).
;
; Every slot keeps a cache in page 2: its frame shifted into place, 216
; bytes of lit dots (36 rows x 6 bytes, X = row x 6) and, 256 bytes on, the
; mask inverted, so a row over something is bg AND maski OR lit; neither
; part crosses a page. A cache is built from the frame in aux (plain, or
; the mirrored copy init makes for a swimmer facing left; frames are 5 bytes
; a row) through the shift tables, also in aux, by lc_build: 121 cycles a
; row, once per hop for the lit dots, and only when the creature is over the
; floor or in front of another for the mask. fish_locate works out a slot's
; place (frame, cache column, shift, box) when it moves; after that the box
; is read, not worked out.
;
; The caller names a rectangle of at most 8 bytes by any number of rows
; (FR_C0..FR_C1-1, FR_R0..FR_R1-1). fish_rect_begin lists the slots whose
; boxes touch it; fish_rect_rows draws it top to bottom in runs of rows
; holding the same creatures. A run is drawn by one of eight straight-line
; kernels (black or the floor, 0-3 layers; built at init from column
; templates), unrolled for 8 columns right to left and entered at the
; rectangle's width, with every layer's operands patched in for the run:
; column j of layer L reads L's cache at column j - cL when that is 0-5,
; else a page of 0 (lit) and $7F (mask). Rows with four or more creatures
; go through the pass kernels, copies of the three-layer floor kernel
; composing three at a time through the row buffer W. Every screen byte is
; written once a row.
;
; Every piece pays before it runs, in FR_LEFT's units of 16 cycles: a call,
; a run's scan, each cache build, each layer patched, and its rows exactly
; (rows x the kernel's cycles a row at the width, rounded up to a unit);
; what doesn't fit is left for the next call, which carries on from there.
;
; FISH_BG (the floor with every Seaweed) is rebuilt by the background job
; the same way: each row the floor's bytes from aux, then the Seaweed
; through the floor kernels in place. It lists the Seaweed and patches again
; on every call, so creature rects may run between its calls.

; ---- zero page ----
RD_T    = $10           ; 2: temporaries (the step's afford and charge too)
WRP     = $12           ; 2: kernel: the row being written (screen, FISH_BG or W)
RDP     = $14           ; 2: kernel: the background it reads (FISH_BG, W or zeros)
ROWN    = $16           ; kernel: the screen row
CNT     = $17           ; kernel, lc_build, lc_mirror: rows to go
YLAST   = $18           ; FR_C1 - 1
KT      = $19           ; $19-$1E temporaries
WID     = $1F           ; FR_C1 - FR_C0
FR_C0   = FXZ+7         ; rectangle: byte columns FR_C0..FR_C1-1 (0-40)
FR_C1   = FXZ+8
FR_R0   = FXZ+9         ; rows FR_R0..FR_R1-1 (0-192)
FR_R1   = FXZ+10
FR_ROW  = FXZ+11        ; the next row to draw
FR_LEFT = FXZ+12        ; 2: budget, units of 16 cycles
RD_NEXT = FXZ+14        ; the next row where the run changes
RUN_R0  = FXZ+15        ; the run's first row: X = (row - RUN_R0) * 6
BGR     = FXZ+16        ; 2: the background job's FISH_BG row; the pass kernels' background
FLP     = FXZ+18        ; 2: the background job's floor row, in aux
FR_ZP_END = FXZ+20      ; the first byte free for the rest of Fish!
W       = DSX           ; $80-$87: the row buffer for four or more layers
PL      = DSX+8         ; 2: patch: the L operand being patched
PM      = DSX+10        ; 2: the MI operand (none if its high byte is 0)
OUTP    = DSX+8         ; 2: lc_build: the cache row (a build happens before any patching)
                        ; LSRC/LDST (DSX+12..15): aux_copy's, for the floor
P_D     = SPX           ; patch: FR_C0 less the layer's cache column
P_LO    = SPX+1         ; (RUN_R0 - its top) * 6
P_HI    = SPX+2         ; its cache page
P_ST    = SPX+3         ; the kernel's bytes per column
WP      = SPX+4         ; 2: W - FR_C0
SCRS    = SPX+6         ; 2: the pass kernels: the screen row while W is written
P_I     = SPX+8         ; patching: the next active layer
MP_J    = SPX+9         ; passes: the pass being set up,
MP_I    = SPX+10        ;   its layer (0-2),
MP_BODY = SPX+11        ;   2: its kernel,
MP_TAIL = SPX+13        ;   2: and the tail the last one ends in
WID1    = SPX+15        ; WID - 1

; ---- RAM: the renderer's, after the state arrays ----
FISH_RD   = FISH_STATE + $48
sl_vis    = FISH_RD             ; 10 each, per slot (fish_locate): its box shows,
sl_lit    = FISH_RD + 10        ;   its cache's lit dots are built,
sl_msk    = FISH_RD + 20        ;   and its mask,
sl_c0     = FISH_RD + 30        ;   cache column X / 7 (signed), shift X mod 7,
sl_k      = FISH_RD + 40
sl_top    = FISH_RD + 50        ;   y + by (low byte),
sl_r0     = FISH_RD + 60        ;   its box clipped: rows,
sl_r1     = FISH_RD + 70
sl_bc0    = FISH_RD + 80        ;   columns,
sl_bc1    = FISH_RD + 90
sl_srcl   = FISH_RD + 100       ;   its frame in aux (lit rows; mask rows r5 on),
sl_srch   = FISH_RD + 110
sl_rows   = FISH_RD + 120       ;   its rows,
sl_bcl    = FISH_RD + 130       ;   what a build of its lit dots costs, in units (its frame's
sl_bch    = FISH_RD + 140       ;   page crossings counted),
sl_bml    = FISH_RD + 150       ;   and of its mask
sl_bmh    = FISH_RD + 160
l_slot    = FISH_RD + 170       ; 10 each, the slots listed for the rectangle:
l_top     = FISH_RD + 180       ;   first row in it, the row after the last
l_bot     = FISH_RD + 190
rd_act    = FISH_RD + 200       ; 10: list entries in this run, in slot order
rd_nlist  = FISH_RD + 210
rd_nact   = FISH_RD + 211
rd_pend   = FISH_RD + 212       ; 1 while a creature rect is pending
rd_mode   = FISH_RD + 213       ; 0 the screen, 1 the background job
rd_floor  = FISH_RD + 214       ; this run is over the floor
rd_pass   = FISH_RD + 215       ; kernel passes: 1, or 2-4 for four or more layers
rd_cost   = FISH_RD + 216       ; 2: a row's cycles in this run
rd_kern   = FISH_RD + 218       ; the kernel, 0-7
bj_c0     = FISH_RD + 219       ; the background job: its columns,
bj_c1     = FISH_RD + 220
bj_row    = FISH_RD + 221       ;   its next row and the row after its last,
bj_r1     = FISH_RD + 222
bj_pend   = FISH_RD + 223       ;   1 until it is finished
bj_live   = FISH_RD + 224       ;   1 while its run is set up from the last call (nothing drew since)
bx_c0     = FISH_RD + 225       ; box_of: the box, clipped (for the queue)
bx_c1     = FISH_RD + 226
bx_r0     = FISH_RD + 227
bx_r1     = FISH_RD + 228
k_endlo   = FISH_RD + 229       ; 8 each: the kernel bodies' ends (their jumps), made at init
k_endhi   = FISH_RD + 237
sl_weed   = FISH_RD + 245       ; 10: 1 for a Seaweed slot (fish_locate), for the listings
FISH_RD_END = FISH_RD + 255
.assert FISH_RD_END <= FISH_STATE + $150, error, "renderer RAM runs past FISH_STATE + $150"
bq_tab    = FISH_STATE + $400 - 16 * FISH_NKIND ; 4 bytes a kind, frame and facing (kind x 16 +
                                ;   frame x 8 + left x 4): what its lit build and its mask build
                                ;   cost, in units (lo, hi each); made at init (make_build_table)

FISH_MAX   = 10
ROLE_STILL = 4                  ; Seaweed: part of the background
FLOOR_OFF  = __FISHFLOOR_LOAD__ - FISH_BG       ; a FISH_BG row's floor row in aux
PASS_LEN   = 8 * 23 + 3         ; a pass kernel: the three-layer floor body and its jump
BODY_STEP  = 192                ; the kernel bodies, FISH_BODY on
.assert FISH_PASS + 4 * PASS_LEN <= FISH_BODY && FISH_BODY + 8 * BODY_STEP <= $6000, error, "page 2's kernels"

; ---- costs: units of 16 cycles ----
; Measured on py65 (tests/test_fx_fish.py's charge tests hold every call to
; them), each with a unit or two over its worst for the cycles that move
; with code placement (a branch across a page) and a multiply's bit pattern.
FC_CALL   = 16                  ; fish_rect_rows itself, and the charge that stops it: the dearest
                                ;   is a set-up's of four or more layers (244 with the call's
                                ;   own 93; a set-up of fewer 231, a run's start 172; a call that
                                ;   draws instead costs 92-167)
FC_EVENT  = 15                  ; a run's start apart from the slots: the row loop's turn to it
                                ;   (22, after the first run of a call), its two charges, the
                                ;   scan's fixed part and the width (191-201)
FC_EVPER  = 3                   ;   per slot listed: the scan (26-34; run_start multiplies by 3)
FC_EVACT  = 4                   ;   per layer in the row: the scan's extra and the cache checks
                                ;   (69 more: 90-103 with FC_EVPER; paid after the scan, before
                                ;   the checks; run_start multiplies by 4)
FC_SETUP  = 26                  ;   the kernel: choosing it, its charge, jumps, entry and row cost
                                ;   (397 over the sea, 406 over the floor, 418-423 in the
                                ;   background job, which pays a unit more: rs_setup adds rd_mode)
FC_PATCH  = 13                  ;   per layer patched: its offsets, values and operand set-up
                                ;   (189-197), and
FC_PATCHCOL = 9                 ;   per two columns of the rectangle (71 cycles a column, 66 for one
                                ;   outside the layer's six; an odd width rounds up half a column: 8)
FC_MANY   = 24                  ; four or more layers (run_many) instead of FC_SETUP: the kernel's
                                ;   charge, jumps and row cost (319-363: the multiply by the
                                ;   passes varies with their bits, and the tables' pages)
FC_MLAYER = 4                   ;   per layer: its values (61)
FC_PASS   = 40                  ;   per pass: its glue, jumps, and three operand slots (629), and
                                ;   its three slots' columns (13.5 units a column, rounded up:
                                ;   mpu_lo/hi; a slot past the layers misses every column: 66 each)
FC_ROWS   = 36                  ;   working out the rows' charge and calling the kernel (360 over
                                ;   black; the multiply varies with the rows' bits, up to 160 more)
FC_ROWFLR = 5                   ;   and over the floor or in the background job: the row's FISH_BG
                                ;   address and the floor pointer (67)
FC_PART   = 28                  ;   and finding how many fit when they don't all: the tries cost
                                ;   120 to 400 by how many sizes are tried (a constant-time
                                ;   division would cost about 700, more than the worst try path)
FC_BGCALL = 22                  ; fish_bg_rows itself, its poll and its rectangle, carrying its run
                                ;   on (184), and the charge that stops it (a set-up's of four or
                                ;   more layers: 160)
FC_BGSETUP = 8                  ;   listing the Seaweed again: its fixed part and the charge (113)
FC_BGPER  = 8                   ;   per Seaweed slot: counted and listed (123; not listed 73)
FC_BGANY  = 3                   ;   per other slot: counted and passed over (32)
; cycles: a cache build is RC_BUILDFIX + rows x RC_BUILD; a kernel row is
; k_loop + width x k_byte for the kernel (black or floor, 0-3 layers), and
; RC_BGROW + width x RC_BGBYTE more in the background job (the floor's bytes
; from aux); a row of passes is k_loop (for black or floor) + RC_MPFIX +
; passes x (RC_MPPASS + width x RC_MPBYTE).
RC_BUILD   = 121                ; lc_build: a row, and 1 for each source read that crosses a
                                ;   page: fish_locate counts them for each slot's frame (5 x rows
                                ;   + the source's low byte - 256, when positive: the Crab facing
                                ;   left, frame 1, lit: 153 of its 155 reads; the Seaweed's frame 1
                                ;   mask, 36 rows, is the dearest build at 4,744)
RC_BUILDFIX = 312               ; build_lit/build_msk apart from the rows: the charge and patching
                                ;   the operands (301-312, by the kind's row count and tables' pages)
RC_BGROW   = 68                 ; head_bg, aux_copy's start and end, and the floor pointer's
                                ;   step into a new page (4): with the loop's and the bytes' own
RC_BGBYTE  = 16                 ;   allowances a background row is charged 72 + 17 a byte over
                                ;   its kernel row; measured 83-88, 147-156 and 195-207 at 1, 5
                                ;   and 8 wide (aux_copy's source may cross a page: 1 a byte)
RC_MPFIX   = 31                 ; glue0 and glue_last (29 over black, 27 over the floor, measured
                                ;   from one row's head to the next)
RC_MPPASS  = 21                 ; a pass's jump and glue
RC_MPBYTE  = 37                 ; a pass kernel's byte (three layers over the floor), and 1 more
                                ;   in the first pass: over black always, over the floor when the
                                ;   FISH_BG row crosses a page (W, the later passes' background,
                                ;   is in zero page)
; the step's estimate (fish_est), cycles
EST_FIXC   = 900 + 16 * (11 + FC_CALL + FC_EVENT + FC_SETUP + FC_PATCH + (7 * FC_PATCHCOL + 1) / 2 + FC_ROWS)
                                ; fish_hop, a begin (11: ST_BEGIN 9 and a unit or two), a run's start
EST_SLOTC  = 16 * (8 + FC_EVPER); per slot in use: the listing (ST_BEGPER 8) and the scan

.segment "FISHCODE2"
; ================================================================ entry points

; fish_box: X = slot. Its box on screen, clipped, in FR_C0..FR_R1 and carry
; set; carry clear if none of it is on screen (as fish_locate last worked it
; out). Y = kind. Keeps X.
fish_box:
        ldy fish_kind,x
        lda sl_vis,x
        beq @no
        lda sl_bc0,x
        sta FR_C0
        lda sl_bc1,x
        sta FR_C1
        lda sl_r0,x
        sta FR_R0
        lda sl_r1,x
        sta FR_R1
        sec
        rts
@no:    clc
        rts

; box_of: X = slot. fish_locate, then its box in bx_c0..bx_r1 and carry
; set, or carry clear if none of it is on screen. Y = kind. Keeps X.
box_of:
        jsr fish_locate
        bcc @rts
        lda sl_bc0,x
        sta bx_c0
        lda sl_bc1,x
        sta bx_c1
        lda sl_r0,x
        sta bx_r0
        lda sl_r1,x
        sta bx_r1
        sec
@rts:   rts

; fish_locate: X = slot. Works out where it is drawn from its state, into
; the slot's sl_*: its frame in aux (by frame and facing), cache column and
; shift from X = x + bx (x + cw - bx - 35 facing left), and its box clipped
; (the bytes holding its bw dots, its rows); its cache is marked unbuilt.
; Carry set if its box shows. Y = kind. Keeps X.
fish_locate:
        stz sl_lit,x            ; moved: its cache no longer fits
        stz sl_msk,x
        stz sl_vis,x
        stz bj_live             ; (a background run set up before this is stale)
        ldy fish_kind,x
        lda fk_rows,y
        sta sl_rows,x
        lda fk_role,y           ; a Seaweed (the background's): 1, or 0
        cmp #ROLE_STILL
        beq :+
        lda #0
        bra :++
:       lda #1
:       sta sl_weed,x
        lda fish_yl,x           ; rows y + by .. + rows - 1
        clc
        adc fk_by,y
        sta sl_top,x
        sta KT
        lda fish_yh,x
        adc #0
        sta KT+1
        bmi @top0
        bne @off1
        lda KT
        cmp #192
        bcs @off1
        bra @top
@off1:  jmp @off
@top0:  lda #0
@top:   sta sl_r0,x
        lda KT                  ; the row after the last, or 192
        clc
        adc fk_rows,y
        sta KT
        lda KT+1
        adc #0
        bmi @off1
        bne @r192
        lda KT
        bne :+
        jmp @off
:
        cmp #192
        bcc @r1
@r192:  lda #192
@r1:    sta sl_r1,x
        lda fish_dir,x          ; the frame and X, by facing
        beq @right
        lda fk_role,y
        cmp #ROLE_STILL
        bcs @right              ; Seaweed and Bubbles never face left
        lda #4                  ; (bq_tab: facing left)
        sta KT+3
        lda fish_frame,x
        bne :+
        lda fk_m0lo,y
        sta sl_srcl,x
        lda fk_m0hi,y
        bra @src
:       lda fk_m1lo,y
        sta sl_srcl,x
        lda fk_m1hi,y
@src:   sta sl_srch,x
        lda fk_pad,y            ; the drawing's dots start 35 - bw in
        sta KT+2
        lda fk_xm,y             ; X = x + cw - bx - 35
        bra @add
@right: stz KT+3
        lda fish_frame,x
        bne :+
        lda fk_f0lo,y
        sta sl_srcl,x
        lda fk_f0hi,y
        bra :++
:       lda fk_f1lo,y
        sta sl_srcl,x
        lda fk_f1hi,y
:       sta sl_srch,x
        stz KT+2
        lda fk_bx,y             ; X = x + bx
@add:   pha
        tya                     ; what its builds will cost: bq_tab's entry for the
        asl a                   ; kind, frame and facing
        asl a
        asl a
        asl a
        ora KT+3
        sta KT+3
        lda fish_frame,x
        asl a
        asl a
        asl a
        ora KT+3
        tay
        lda bq_tab,y
        sta sl_bcl,x
        lda bq_tab+1,y
        sta sl_bch,x
        lda bq_tab+2,y
        sta sl_bml,x
        lda bq_tab+3,y
        sta sl_bmh,x
        ldy fish_kind,x
        pla
        pha
        clc
        adc fish_xl,x
        sta KT
        pla
        and #$80                ; the offset's sign
        beq :+
        lda #$FF
:       adc fish_xh,x
        sta KT+1
        bmi @neg
        lda KT                  ; X >= 280: off the right
        cmp #<280
        lda KT+1
        sbc #>280
        bcc @cols
@off:   clc
        rts
@neg:   lda KT                  ; X + 35 <= 0: off the left
        clc
        adc #35
        sta KT+3
        lda KT+1
        adc #0
        bmi @off
        ora KT+3
        beq @off
@cols:  phy
        lda KT                  ; the cache column and shift, from 6 bytes on
        clc
        adc #42
        tay
        lda KT+1
        adc #0
        bne @hi
        lda xmod_lo,y
        sta sl_k,x
        lda xbyte_lo,y
        bra @c0
@hi:    lda xmod_hi,y
        sta sl_k,x
        lda xbyte_hi,y
@c0:    sec
        sbc #6
        sta sl_c0,x
        sta KT+3
        ply
        lda KT+2                ; the drawing's dots: from X + pad
        clc
        adc sl_k,x
        phx
        tax                     ; the first dot's byte and dot in it
        lda KT+3
        clc
        adc xbyte_lo,x
        sta KT+4                ; the first byte
        lda xmod_lo,x           ; bytes: up to its last dot's
        clc
        adc fk_bw,y
        adc #6
        tax
        lda KT+4
        clc
        adc xbyte_lo,x
        plx
        dec a                   ; the last byte < 0: off the left
        bmi @off
        cmp #40
        bcc :+
        lda #39
:       inc a
        sta sl_bc1,x
        lda KT+4                ; the first >= 40: off the right
        bmi @bc00
        cmp #40
        bcs @off
        bra :+
@bc00:  lda #0
:       sta sl_bc0,x
        lda #$80
        sta sl_vis,x
        sec
        rts

; fish_rect_begin: lists the slots (not Seaweed) whose boxes touch the
; rectangle in FR_C0..FR_R1, in slot order, and sets FR_ROW = FR_R0. The
; rect is then pending until fish_rect_rows finishes it, or something
; abandons it: another fish_rect_begin, or fish_bg_begin / fish_bg_rows.
fish_rect_begin:
        lda #1
        sta rd_pend
        stz rd_mode
        jsr vbl_poll
        lda FR_R0
        sta FR_ROW
        ; fall through
; list: the slots the rectangle touches, by rd_mode (0: all but Seaweed; 1:
; the Seaweed), with their rows in it; RD_NEXT = FR_ROW (a run starts there).
list:   lda FR_ROW
        sta RD_NEXT
        stz rd_nlist
        ldx #0
@slot:  cpx fish_n
        bcs @done
        lda sl_weed,x           ; the Seaweed for the background job, the rest for the screen
        cmp rd_mode
        bne @nx
        lda sl_vis,x
        beq @nx
        lda sl_r0,x
        cmp FR_R1
        bcs @nx
        lda FR_R0
        cmp sl_r1,x
        bcs @nx
        lda sl_bc0,x
        cmp FR_C1
        bcs @nx
        lda FR_C0
        cmp sl_bc1,x
        bcs @nx
        ldy rd_nlist
        txa
        sta l_slot,y
        lda sl_r0,x             ; its first row in the rect, and the row after its last
        cmp FR_R0
        bcs :+
        lda FR_R0
:       sta l_top,y
        lda sl_r1,x
        cmp FR_R1
        bcc :+
        lda FR_R1
:       sta l_bot,y
        inc rd_nlist
@nx:    inx
        bra @slot
@done:  rts

; fish_rect_rows: draws rows from FR_ROW, paying for each piece from
; FR_LEFT first and stopping before one that doesn't fit: carry clear.
; Carry set when the rectangle is finished, and at once, drawing nothing, if
; it isn't pending (finished already, or abandoned). The call itself costs
; FC_CALL: with less than that in FR_LEFT, it zeroes FR_LEFT and draws
; nothing.
fish_rect_rows:
        lda rd_pend
        bne :+
        sec
        rts
:       lda #FC_CALL
        jsr pay_call
        jsr rr_loop
        bcc :+
        stz rd_pend             ; finished
:       rts

; pay_call: FR_LEFT less A, or 0 if it hasn't that much.
pay_call:
        eor #$FF
        sec
        adc FR_LEFT
        sta FR_LEFT
        bcs :+
        lda FR_LEFT+1
        beq :++
        dec FR_LEFT+1
:       rts
:       stz FR_LEFT
        rts

; rr_loop: the rows from FR_ROW to FR_R1, run by run, while FR_LEFT pays:
; carry set when FR_ROW reaches FR_R1.
rr_loop:
        lda FR_ROW
        cmp FR_R1
        bcs @done
        cmp RD_NEXT
        bne :+
        jsr run_start           ; a run starts here
        bcc @stop
:       jsr rr_rows
        bcs rr_loop
@stop:  clc
        rts
@done:  sec
        rts

; charge_a: charge A units: carry set and FR_LEFT less them, or carry clear
; and FR_LEFT as it was. Keeps X, Y.
charge_a:
        eor #$FF
        sec
        adc FR_LEFT             ; FR_LEFT - A, low byte
        sta RD_T
        lda FR_LEFT+1
        sbc #0
        bcc :+
        sta FR_LEFT+1
        lda RD_T
        sta FR_LEFT
:       rts
; charge: the same for RD_T (2 bytes) units.
charge:
        lda FR_LEFT
        sec
        sbc RD_T
        pha
        lda FR_LEFT+1
        sbc RD_T+1
        bcc :+
        sta FR_LEFT+1
        pla
        sta FR_LEFT
        sec
        rts
:       pla
        clc
        rts

; add_t: RD_T (2 bytes) += A. Keeps X, Y.
add_t:  clc
        adc RD_T
        sta RD_T
        bcc :+
        inc RD_T+1
:       rts

; charge_cyc: charge RD_T cycles, rounded up to units. Keeps X, Y.
charge_cyc:
        lda RD_T
        clc
        adc #15
        sta RD_T
        bcc :+
        inc RD_T+1
:       .repeat 4
        lsr RD_T+1
        ror RD_T
        .endrepeat
        bra charge

; mul: RD_T = A x KT+3/KT+4 (16-bit), 16-bit. KT+3/4 are shifted out. Keeps X, Y.
mul:    sta KT+5
        stz RD_T
        stz RD_T+1
@bit:   lsr KT+5
        bcc :+
        lda RD_T
        clc
        adc KT+3
        sta RD_T
        lda RD_T+1
        adc KT+4
        sta RD_T+1
:       lda KT+5
        beq @done
        asl KT+3
        rol KT+4
        bra @bit
@done:  rts

; bgrow: A = a row 156-191. RD_T = its row of FISH_BG. Keeps X.
bgrow:
        sec
        sbc #FLOOR_TOP
        sta RD_T
        asl a
        asl a
        adc RD_T                ; * 5
        stz RD_T+1
        asl a
        rol RD_T+1
        asl a
        rol RD_T+1
        asl a
        rol RD_T+1              ; * 40
        adc #<FISH_BG
        sta RD_T
        lda RD_T+1
        adc #>FISH_BG
        sta RD_T+1
        rts

; ================================================================ a run
; scan_row: X = a row. rd_act/rd_nact: the list entries in it, in slot order;
; RD_NEXT: the next row where that changes (by FR_R1, and at the floor's top).
scan_row:
        stx KT
        lda FR_R1
        sta RD_NEXT
        stz rd_nact
        ldy #0
@scan:  cpy rd_nlist
        bcs @done
        lda KT
        cmp l_top,y
        bcc @before
        cmp l_bot,y
        bcs @after
        ldx rd_nact             ; in this row
        tya
        sta rd_act,x
        inc rd_nact
        lda l_bot,y
        bra @min
@before:
        lda l_top,y
@min:   cmp RD_NEXT
        bcs @after
        sta RD_NEXT
@after: iny
        bra @scan
@done:  lda KT                  ; a run never crosses onto the floor
        cmp #FLOOR_TOP
        bcs :+
        lda RD_NEXT
        cmp #FLOOR_TOP
        bcc :+
        lda #FLOOR_TOP
        sta RD_NEXT
:       rts

; run_start: a run begins at FR_ROW. Pays for the scan, then for each cache
; build it needs and each layer it patches, as it goes; sets the kernel up
; for the run (rd_kern, rd_pass, rd_cost, the jumps and operands). Carry
; clear if something couldn't be paid for: RD_NEXT = FR_ROW, so the next
; call starts the run again.
run_start:
        lda rd_nlist            ; FC_EVENT + FC_EVPER (3) per slot listed
        asl a
        adc rd_nlist
        adc #FC_EVENT
        jsr charge_a
        bcc @nob
        lda FR_ROW
        sta RUN_R0
        ldx FR_ROW
        jsr scan_row
        lda rd_nact             ; FC_EVACT (4) per layer in the row: the cache checks
        asl a
        asl a
        jsr charge_a
        bcc @nob
        ldx #0
        lda FR_ROW
        cmp #FLOOR_TOP
        bcc :+
        inx
:       stx rd_floor
        lda FR_C1
        sec
        sbc FR_C0
        sta WID
        dec a
        sta WID1
        ldy #0                  ; the caches the run needs
@bld:   cpy rd_nact
        bcs @built
        ldx rd_act,y
        lda l_slot,x
        tax
        lda sl_lit,x
        bne :+
        jsr build_lit
        bcc @nob
:       tya                     ; the first layer above the floor needs no mask
        bne :+
        lda rd_floor
        beq @nxb
:       lda sl_msk,x
        bne @nxb
        jsr build_msk
        bcc @nob
@nxb:   iny
        bra @bld
@nob:   jmp no_budget
@built:
rs_setup = *                    ; (every cache the run needs is built: the kernel's turn)
        lda rd_nact
        cmp #4
        bcc :+
        jmp run_many
:       asl a                   ; the kernel: floor + 2 x layers
        ora rd_floor
        sta rd_kern
        lda #1
        sta rd_pass
        jsr patch_units         ; FC_SETUP (a unit more in the background job), and
        sta KT+5                ; a layer's patching per layer
        ldx rd_nact
        lda #FC_SETUP
        clc
        adc rd_mode
:       dex
        bmi :+
        adc KT+5
        bra :-
:       jsr charge_a
        bcs :+
        jmp no_budget
:       jsr set_jumps           ; the head; the tail in KT+3/4
        ldx rd_kern
        lda k_endlo,x           ; the body's end jumps to the tail
        sta KT+1
        lda k_endhi,x
        sta KT+2
        ldy #1
        lda KT+3
        sta (KT+1),y
        iny
        lda KT+4
        sta (KT+1),y
        lda k_step,x
        sta P_ST
        jsr body_entry          ; the head goes to its entry for the width
        sta entry_j+1
        lda KT+2
        sta entry_j+2
        txa                     ; column 7's code, the body's start: the end
        asl a                   ; less 8 x step
        asl a
        asl a
        adc #7
        tay
        lda k_endlo,x
        sec
        sbc k_wstep,y
        sta KT+3
        lda k_endhi,x
        sbc #0
        sta KT+4
        stz P_I                 ; each layer's operands
@layer: lda P_I
        cmp rd_nact
        bcs @cost
        lda rd_floor            ; its offsets: floor x 3 + layer
        asl a
        adc rd_floor
        adc P_I
        tax
        lda KT+3
        clc
        adc off_l,x
        sta PL
        lda KT+4
        adc #0
        sta PL+1
        lda off_m,x
        bmi :+
        clc
        adc KT+3
        sta PM
        lda KT+4
        adc #0
        sta PM+1
        bra :++
:       lda PL                  ; no mask operand: its stores land on L's,
        sta PM                  ; which are written last
        lda PL+1
        sta PM+1
:       ldy P_I
        jsr layer_values
        jsr patch_layer
        inc P_I
        bra @layer
@cost:  ldx rd_kern             ; a row: loop + width x byte
        jsr k_index
        lda k_rowlo,y
        sta rd_cost
        lda k_rowhi,y
        sta rd_cost+1
        ; fall through
; bg_cost: the background job's row: the floor's bytes from aux. Carry set.
bg_cost:
        lda rd_mode
        beq @rts
        lda WID                 ; RC_BGROW + width x RC_BGBYTE (16 a byte)
        asl a
        asl a
        asl a
        asl a
        clc
        adc #RC_BGROW
        adc rd_cost
        sta rd_cost
        bcc @rts
        inc rd_cost+1
@rts:   sec
        rts
no_budget:
        lda FR_ROW
        sta RD_NEXT
        clc
        rts

; patch_units: A = KT+5 = what patching one layer costs for width WID:
; FC_PATCH + WID x FC_PATCHCOL / 2, rounded up. Keeps X, Y.
patch_units:
        lda WID
        asl a
        asl a
        asl a
        adc WID                 ; x 9
        lsr a                   ; / 2, the odd half into the carry
        adc #FC_PATCH
        sta KT+5
        rts

; set_jumps: the loop's head by rd_mode, and in KT+3/4 the tail the bodies
; end in, by rd_mode, rd_floor and rd_pass.
set_jumps:
        ldx #0
        lda rd_mode
        beq :+
        ldx #2
        lda #<tail_bg
        ldy #>tail_bg
        bra @tail
:       lda rd_floor
        beq @sea
        lda rd_pass
        cmp #2
        bcs @mp
        lda #<tail_flr_scr
        ldy #>tail_flr_scr
        bra @tail
@mp:    lda #<tail_mp
        ldy #>tail_mp
        bra @tail
@sea:   lda #<tail_sea
        ldy #>tail_sea
@tail:  sta KT+3
        sty KT+4
        lda heads,x
        sta head_j+1
        lda heads+1,x
        sta head_j+2
        rts
heads:  .word head_scr, head_bg

; body_entry: A (low) and KT+2 (high) = the entry for width WID of the
; kernel X's body whose end is KT+1/KT+2: the end less the width's bytes.
; Keeps X.
body_entry:
        jsr k_index
        lda KT+1
        sec
        sbc k_wstep,y
        bcs :+
        dec KT+2
:       rts

; k_index: Y = kernel X's index for width WID into the k_row and k_wstep
; tables: kernel x 8 + WID - 1. Keeps X.
k_index:
        txa
        asl a
        asl a
        asl a
        adc WID
        dec a
        tay
        rts

; layer_values: Y = the active layer. Its slot's P_D, P_LO, P_HI for
; patching. Keeps Y.
layer_values:
        ldx rd_act,y
        lda l_slot,x
        tax
        lda FR_C0
        sec
        sbc sl_c0,x
        sta P_D
        lda RUN_R0
        sec
        sbc sl_top,x
        sta RD_T
        asl a
        adc RD_T
        asl a
        sta P_LO                ; (row - top) * 6
        txa
        asl a
        adc #>FISH_CACHE
        sta P_HI
        rts

; patch_layer: one layer's operands in WID columns, P_ST bytes apart, from
; column 0: PL = column 7's L operand (the body's start plus the layer's
; offset), PM = its MI operand (PL itself when the layer has none). Column j
; reads the cache at P_LO + P_D + j when that column is 0-5, else the empty
; page (L) and the transparent page (MI): a mask's page is the page after
; its lit dots' in both cases.
patch_layer:
        lda WID
        sta KT+5
        lda P_ST                ; column 0 is 7 columns on from PL
        asl a
        asl a
        asl a
        sec
        sbc P_ST
        tay
        lda P_ST                ; (and the next column is a step less, from the high byte)
        inc a
        sta RD_T
@col:   lda P_D
        cmp #6
        bcs @miss
        clc
        adc P_LO                ; the cache row's byte, and its page
        ldx P_HI
        bra @put
@miss:  lda #0                  ; the empty page (its mask, the transparent one, is the next)
        ldx #>FISH_ZERO
@put:   sta (PL),y
        sta (PM),y
        iny
        txa
        inc a
        sta (PM),y              ; (the mask's high byte first: with no mask operand PM
        txa                     ; is PL, and L's is written last)
        sta (PL),y
        tya
        sec
        sbc RD_T
        tay
        inc P_D
        dec KT+5
        bne @col
        rts

; run_many: four or more layers: rd_pass passes of three through W, each a
; pass kernel (a copy of the three-layer floor body) with its own operands;
; pass 1 reads the background (black: the empty page), each next one W, the
; last writes the row. Pays FC_MANY (a unit more in the background job),
; FC_MLAYER a layer, and per pass FC_PASS and its three slots' columns (the
; last pass's spare slots are patched transparent).
run_many:
        ldx rd_nact
        lda passes-4,x
        sta rd_pass
        lda #FC_MANY            ; FC_MANY (+ 1 in the background job) + layers x FC_MLAYER
        clc
        adc rd_mode
        sta RD_T
        stz RD_T+1
        txa
        asl a
        asl a
        adc RD_T                ; (under 128: no carry)
        sta RD_T
        lda rd_pass             ; + passes x (FC_PASS + their columns): mpu_lo/hi
        asl a
        asl a
        asl a
        adc WID
        tax
        lda mpu_lo-17,x         ; (entry (passes - 2) x 8 + width - 1)
        clc
        adc RD_T
        sta RD_T
        lda mpu_hi-17,x
        adc #0
        sta RD_T+1
        jsr charge
        bcs :+
        jmp no_budget
:       jsr set_jumps
        lda KT+3
        sta MP_TAIL
        lda KT+4
        sta MP_TAIL+1
        lda #<glue0             ; the head goes to glue0
        sta entry_j+1
        lda #>glue0
        sta entry_j+2
        lda #<W                 ; WP = W - FR_C0
        sec
        sbc FR_C0
        sta WP
        lda #>W
        sbc #0
        sta WP+1
        lda #23
        sta P_ST
        stz P_I
        lda #<FISH_PASS
        sta MP_BODY
        lda #>FISH_PASS
        sta MP_BODY+1
        lda #1
        sta MP_J
@pass:  lda MP_BODY             ; the pass kernel's end: body + 184
        clc
        adc #<(8 * 23)
        sta KT+1
        lda MP_BODY+1
        adc #>(8 * 23)
        sta KT+2
        ldx #7
        jsr body_entry          ; its entry, into the glue before it: glue0,
        pha                     ; glue_last, or glue_m(pass - 1)
        ldx MP_J
        cpx #1
        bne :+
        ldx #0
        bra @gin
:       cpx rd_pass
        bne :+
        ldx #3
        bra @gin
:       dex
@gin:   txa
        asl a
        tax
        lda glue_ops,x
        sta RD_T
        lda glue_ops+1,x
        sta RD_T+1
        pla
        sta (RD_T)
        ldy #1
        lda KT+2
        sta (RD_T),y
        lda MP_J                ; its end jumps to the glue after it, or the tail
        cmp rd_pass
        bne :+
        lda MP_TAIL
        ldy MP_TAIL+1
        bra @end
:       inc a
        cmp rd_pass
        bne :+
        lda #<glue_last
        ldy #>glue_last
        bra @end
:       ldx MP_J
        lda glue_mid_lo-1,x
        ldy glue_mid_hi-1,x
@end:   pha
        lda MP_BODY             ; the jump's operand: body + 185
        clc
        adc #<(8 * 23 + 1)
        sta RD_T
        lda MP_BODY+1
        adc #>(8 * 23 + 1)
        sta RD_T+1
        pla
        sta (RD_T)
        tya
        ldy #1
        sta (RD_T),y
        stz MP_I                ; its three layers (the rest transparent)
@lay:   lda MP_I                ; column 7's operands: body + 6 + 6 x layer (L)
        asl a                   ; and 3 less (MI)
        adc MP_I
        asl a
        clc
        adc #6
        clc
        adc MP_BODY
        sta PL
        lda MP_BODY+1
        adc #0
        sta PL+1
        lda PL
        sec
        sbc #3
        sta PM
        lda PL+1
        sbc #0
        sta PM+1
        ldy P_I
        cpy rd_nact
        bcs @pad
        jsr layer_values
        bra :+
@pad:   lda #99                 ; no layer: every column misses
        sta P_D
:       jsr patch_layer
        inc P_I
        inc MP_I
        lda MP_I
        cmp #3
        bcc @lay
        lda MP_BODY             ; the next pass
        clc
        adc #<PASS_LEN
        sta MP_BODY
        lda MP_BODY+1
        adc #>PASS_LEN
        sta MP_BODY+1
        inc MP_J
        lda MP_J
        cmp rd_pass
        bcc :+
        bne @done
:       jmp @pass
@done:  ldx WID                 ; a row: the loop (black or floor), the glue, and
        lda mpw_lo-1,x          ; the passes: (RC_MPBYTE x width + RC_MPPASS) x passes
        clc
        adc #RC_MPPASS
        sta KT+3
        lda mpw_hi-1,x
        adc #0
        sta KT+4
        lda rd_pass
        jsr mul
        ldx rd_floor
        lda RD_T
        clc
        adc k_loop,x
        sta rd_cost
        lda RD_T+1
        adc #0
        sta rd_cost+1
        lda rd_cost
        clc
        adc #RC_MPFIX
        sta rd_cost
        bcc :+
        inc rd_cost+1
:       lda rd_cost             ; (the first pass's bytes: 1 more each)
        clc
        adc WID
        sta rd_cost
        bcc :+
        inc rd_cost+1
:       jmp bg_cost
passes: .byte 2, 2, 2, 3, 3, 3, 4               ; 4-10 layers
mpu_lo: .repeat 3, P                            ; passes (2-4) x (FC_PASS + three slots' columns, 1-8
        .repeat 8, W                            ;   wide: 13.5 units a column, rounded up)
        .byte <((P + 2) * (FC_PASS + (27 * (W + 1) + 1) / 2))
        .endrepeat
        .endrepeat
mpu_hi: .repeat 3, P
        .repeat 8, W
        .byte >((P + 2) * (FC_PASS + (27 * (W + 1) + 1) / 2))
        .endrepeat
        .endrepeat
mpw_lo: .repeat 8, W                            ; RC_MPBYTE x width, 1-8
        .byte <(RC_MPBYTE * (W + 1))
        .endrepeat
mpw_hi: .repeat 8, W
        .byte >(RC_MPBYTE * (W + 1))
        .endrepeat
glue_ops: .word glue0_j+1, glue_m1_j+1, glue_m2_j+1, glue_last_j+1
glue_mid_lo: .byte <glue_m1, <glue_m2
glue_mid_hi: .byte >glue_m1, >glue_m2

; rr_rows: the rows of the run from FR_ROW: all of them if FR_LEFT pays,
; else as many as it pays for in 64, 32, 16, 8, 4, 2 or 1 (FC_ROWS first for
; the arithmetic, FC_ROWFLR more over the floor, FC_PART more when they don't
; all fit); carry clear if none.
; The rows are charged in cycles: FR_LEFT x 16 less the rows' cycles, back
; to units rounded down (a budget of 4,096 units or more pays for anything).
rr_rows:
        lda #FC_ROWS            ; working out the charge, paid for first (floor rows: more
        ldx rd_floor            ; for their pointers)
        beq :+
        adc #FC_ROWFLR
:       jsr charge_a
        bcs :+
@no1:   jmp @no
:       lda RD_NEXT
        sec
        sbc FR_ROW
        sta KT                  ; rows left in the run
        lda rd_cost
        sta KT+3
        lda rd_cost+1
        sta KT+4
        lda KT
        jsr mul                 ; RD_T = their cycles
        lda FR_LEFT+1
        cmp #$10
        bcc :+
        jsr charge_cyc          ; (no budget to speak of: pay exactly)
        lda KT
        jmp @some
:       lda FR_LEFT             ; FR_LEFT in cycles, KT+3/4
        sta KT+3
        lda FR_LEFT+1
        .repeat 4
        asl KT+3
        rol a
        .endrepeat
        sta KT+4
        lda KT+3                ; the whole run?
        sec
        sbc RD_T
        tay
        lda KT+4
        sbc RD_T+1
        bcc @part
        sta KT+4
        sty KT+3
        lda KT
        bra @paid
@part:  lda #FC_PART            ; some of them: the tries, paid for first
        jsr charge_a
        bcc @no1
        lda FR_LEFT             ; (FR_LEFT again, in cycles)
        sta KT+3
        lda FR_LEFT+1
        .repeat 4
        asl KT+3
        rol a
        .endrepeat
        sta KT+4
        lda rd_cost             ; 64 rows' cycles (16 when 64 would pass 65,535),
        sta RD_T                ; halved for each smaller try
        lda rd_cost+1
        .repeat 4
        asl RD_T
        rol a
        .endrepeat
        ldx #16
        cmp #$40
        bcs :+
        asl RD_T
        rol a
        asl RD_T
        rol a
        ldx #64
:       sta RD_T+1
        txa
@try:   cmp KT
        beq :+
        bcs @half
:       sta KT+1
        lda KT+3
        sec
        sbc RD_T
        tay
        lda KT+4
        sbc RD_T+1
        bcs @fits
        lda KT+1
@half:  lsr RD_T+1
        ror RD_T
        lsr a
        bne @try
@no:    clc
        rts
@fits:  sta KT+4
        sty KT+3
        lda KT+1
@paid:  pha                     ; what is left, in units
        .repeat 4
        lsr KT+4
        ror KT+3
        .endrepeat
        lda KT+3
        sta FR_LEFT
        lda KT+4
        sta FR_LEFT+1
        pla
@some:  sta KT+1
        jsr kernel_call
        lda FR_ROW
        clc
        adc KT+1
        sta FR_ROW
        sec
        rts

; kernel_call: A rows from FR_ROW through the kernel set up for the run.
kernel_call:
        sta CNT
        lda FR_ROW
        sta ROWN
        sec
        sbc RUN_R0
        sta KT+2
        asl a
        adc KT+2
        asl a
        tax                     ; X = (row - RUN_R0) * 6
        lda FR_C1
        dec a
        sta YLAST
        lda rd_mode
        bne @bg
        lda rd_floor
        beq @black
        lda FR_ROW              ; the floor: FISH_BG's row
        jsr bgrow
        lda rd_pass
        cmp #2
        bcs :+
        lda RD_T
        sta RDP
        lda RD_T+1
        sta RDP+1
        bra @go
:       lda RD_T
        sta BGR
        lda RD_T+1
        sta BGR+1
        bra @go
@black: lda rd_pass
        cmp #2
        bcc @go
        lda #<FISH_ZERO         ; the passes' background: zeros
        sec
        sbc FR_C0
        sta BGR
        lda #>FISH_ZERO
        sbc #0
        sta BGR+1
        bra @go
@bg:    lda FR_ROW              ; the background job: FISH_BG's row, and the floor's
        jsr bgrow
        lda RD_T
        sta BGR
        clc
        adc #<FLOOR_OFF
        sta FLP
        lda RD_T+1
        sta BGR+1
        adc #>FLOOR_OFF
        sta FLP+1
@go:    jmp kloop

; ================================================================ the kernels
; The loop: head (the row's pointers; the background job also copies the
; floor's bytes in), the body for the width, the tail (on a row, and back
; to its head). Each body ends in a jump patched to the run's tail, or to
; the glue between passes.
kloop:
head_j: jmp head_scr            ; patched: head_scr or head_bg (the first row)
head_scr:
        ldy ROWN
        lda row_lo,y
        sta WRP
        lda row_hi,y
        sta WRP+1
kgo:    ldy YLAST
entry_j: jmp $FFFF              ; patched: the body's entry, or glue0
head_bg:
        lda BGR
        sta WRP
        sta RDP
        clc
        adc FR_C0
        sta LDST
        lda BGR+1
        sta WRP+1
        sta RDP+1
        adc #0
        sta LDST+1
        lda FLP
        clc
        adc FR_C0
        sta LSRC
        lda FLP+1
        adc #0
        sta LSRC+1
        ldy WID1
        jsr aux_copy
        bra kgo
tail_flr_scr:                   ; a floor run on screen: FISH_BG's next row
        lda RDP
        clc
        adc #40
        sta RDP
        bcc tail_sea
        inc RDP+1
tail_sea:
        txa
        clc
        adc #6
        tax
        inc ROWN
        dec CNT
        bne head_scr
        rts
tail_mp:                        ; passes over the floor: BGR on a row
        lda BGR
        clc
        adc #40
        sta BGR
        bcc tail_sea
        inc BGR+1
        bra tail_sea
tail_bg:                        ; the background job: FISH_BG's and the floor's next rows
        lda BGR
        clc
        adc #40
        sta BGR
        bcc :+
        inc BGR+1
:       lda FLP
        clc
        adc #40
        sta FLP
        bcc :+
        inc FLP+1
:       txa
        clc
        adc #6
        tax
        inc ROWN
        dec CNT
        bne head_bg
        rts
glue0:                          ; before pass 1: the row to W, the background from BGR
        lda WRP
        sta SCRS
        lda WRP+1
        sta SCRS+1
        lda BGR
        sta RDP
        lda BGR+1
        sta RDP+1
        lda WP
        sta WRP
        lda WP+1
        sta WRP+1
glue0_j: jmp $FFFF
glue_m1:                        ; before pass 2 (of 3 or 4): over W
        lda WP
        sta RDP
        lda WP+1
        sta RDP+1
        ldy YLAST
glue_m1_j: jmp $FFFF
glue_m2:                        ; before pass 3 (of 4)
        lda WP
        sta RDP
        lda WP+1
        sta RDP+1
        ldy YLAST
glue_m2_j: jmp $FFFF
glue_last:                      ; before the last pass: over W, to the row
        lda WP
        sta RDP
        lda WP+1
        sta RDP+1
        lda SCRS
        sta WRP
        lda SCRS+1
        sta WRP+1
        ldy YLAST
glue_last_j: jmp $FFFF

; per kernel (black or floor x 0-3 layers): bytes a column, and a row's
; cycles at their worst: the loop (black 49: row_lo/row_hi both crossing a
; page, rows 115 on, 47 below row 51; floor 67: 63, and 4 when FISH_BG's
; pointer steps into a new page, about one row in six), and per byte
; (measured 10, 12, 20, 28 over black; 13, 21, 29, 37 over the floor, and
; 1 for the FISH_BG byte when its row crosses a page)
KS0 = 5
KS1 = 5
KS2 = 6
KS3 = 11
KS4 = 12
KS5 = 17
KS6 = 18
KS7 = 23
KL_BLACK = 49
KL_FLOOR = 67
KB0 = 10
KB1 = 14
KB2 = 12
KB3 = 22
KB4 = 20
KB5 = 30
KB6 = 28
KB7 = 38
k_step: .byte KS0, KS1, KS2, KS3, KS4, KS5, KS6, KS7
k_loop: .byte KL_BLACK, KL_FLOOR, KL_BLACK, KL_FLOOR, KL_BLACK, KL_FLOOR, KL_BLACK, KL_FLOOR
k_byte: .byte KB0, KB1, KB2, KB3, KB4, KB5, KB6, KB7
; and by kernel x 8 + width - 1: a row's cycles (k_loop + width x k_byte),
; and the width's bytes of body (the entry is the body's end less that)
.segment "FX14"
k_rowlo:
.repeat 8, K
.repeat 8, W
        .byte <(((K .mod 2) * (KL_FLOOR - KL_BLACK) + KL_BLACK) + (W + 1) * .ident(.sprintf("KB%d", K)))
.endrepeat
.endrepeat
k_rowhi:
.repeat 8, K
.repeat 8, W
        .byte >(((K .mod 2) * (KL_FLOOR - KL_BLACK) + KL_BLACK) + (W + 1) * .ident(.sprintf("KB%d", K)))
.endrepeat
.endrepeat
k_wstep:
.repeat 8, K
.repeat 8, W
        .byte (W + 1) * .ident(.sprintf("KS%d", K))
.endrepeat
.endrepeat
.segment "FISHCODE2"
; a layer's operands in a column: black layers 1-3, floor layers 1-3
off_l:  .byte 1, 7, 13, 6, 12, 18
off_m:  .byte $FF, 4, 10, 3, 9, 15

; ================================================================ caches
; build_lit, build_msk: X = slot. Its cache's lit dots (or mask) built, paid
; for first (sl_bcl/h, sl_bml/h: what fish_locate worked out): carry clear if
; FR_LEFT can't. Keeps X, Y.
build_lit:
        phy
        jsr build_charge
        bcc :+
        jsr cache_lit
        sec
:       ply
        rts
build_msk:
        phy
        lda sl_bml,x
        sta RD_T
        lda sl_bmh,x
        sta RD_T+1
        jsr charge
        bcc :+
        jsr cache_msk
        sec
:       ply
        rts

build_charge:
        lda sl_bcl,x
        sta RD_T
        lda sl_bch,x
        sta RD_T+1
        jmp charge
.segment "FX14"
; a build's cycles by its rows: RC_BUILDFIX + rows x RC_BUILD
bc_lo:  .repeat 37, R
        .byte <(RC_BUILDFIX + R * RC_BUILD)
        .endrepeat
bc_hi:  .repeat 37, R
        .byte >(RC_BUILDFIX + R * RC_BUILD)
        .endrepeat
.segment "FISHCODE2"

; fish_cache: X = slot (located). Its cache built now, lit dots and mask
; (init, and the tests). Keeps X.
fish_cache:
        jsr cache_lit
        ; fall through
; cache_msk: X = slot. Its mask, inverted, from its frame's mask rows
; through the inverted shift table, into its cache at +256. Keeps X.
cache_msk:
        ldy fish_kind,x
        lda sl_srcl,x
        clc
        adc fk_r5,y
        sta KT
        lda sl_srch,x
        adc #0
        sta KT+1
        txa
        asl a
        adc #>FISH_CACHE + 1
        sta KT+2
        lda sl_k,x
        clc
        adc #>FISH_ISHT
        sta KT+3
        lda #$7F
        sta lcb_f+1
        lda #$3D                ; and abs,x
        jsr cache_go
        lda #1
        sta sl_msk,x
        rts
; cache_lit: X = slot. Its lit dots from its frame through the shift table.
cache_lit:
        lda sl_srcl,x
        sta KT
        lda sl_srch,x
        sta KT+1
        txa
        asl a
        adc #>FISH_CACHE
        sta KT+2
        lda sl_k,x
        clc
        adc #>FISH_SHT
        sta KT+3
        stz lcb_f+1
        lda #$1D                ; ora abs,x
        jsr cache_go
        lda #1
        sta sl_lit,x
        rts
; cache_go: A = the combining opcode, KT = the frame rows (aux), KT+2 =
; the cache page, KT+3 = the shift table's page; lc_build patched (OUTP =
; the cache) and called for sl_rows,x rows. Keeps X.
cache_go:
        .repeat 5, I
        sta .ident(.sprintf("lcb_c%d", I))
        .endrepeat
        lda KT
        .repeat 5, I
        sta .ident(.sprintf("lcb_s%d", I)) + 1
        .endrepeat
        lda KT+1
        .repeat 5, I
        sta .ident(.sprintf("lcb_s%d", I)) + 2
        .endrepeat
        stz OUTP
        lda KT+2
        sta OUTP+1
        lda KT+3
        .repeat 5, I
        sta .ident(.sprintf("lcb_c%d", I)) + 2
        sta .ident(.sprintf("lcb_t%d", I)) + 2
        .endrepeat
        lda sl_rows,x
        sta CNT
        phx
        jsr lc_build
        plx
        rts

; fish_est: X = slot. RD_T = the units its next hop will be charged as a
; lone hop, from its place: fish_hop, a begin and one run's start (EST_FIXC,
; EST_SLOTC per slot in use; patching priced at 7 columns), its lit dots
; built, its mask too if its box reaches the floor, and its rows composed
; one byte wider than its box (a hop's rect is its old box joined with its
; new) over black or the floor by where its rows are (Bubbles: FISH_HOP more
; rows, all over black). It leaves out what a crossing adds (its layers, and
; a run per creature boundary) and the second run of a box straddling row
; 156: enough for the step's pick, which only needs hops ranked and the
; first of a tick started whatever it costs (Task 5); Task 8's early start
; needs an estimate that looks at the scene. A = low, Y = high. Keeps X.
fish_est:
        phx
        stx P_I
        lda #<EST_FIXC
        sta KT+1
        lda #>EST_FIXC
        sta KT+2
        lda #<EST_SLOTC
        sta KT+3
        lda #>EST_SLOTC
        sta KT+4
        lda fish_n
        jsr mul
        jsr est_add
        ldy fish_kind,x
        lda fk_rows,y
        sta KT                  ; rows
        jsr est_build
        ldx P_I
        ldy fish_kind,x
        lda fk_role,y           ; rows over black and over the floor
        cmp #ROLE_RISE
        bne @swim
        lda KT
        clc
        adc #FISH_HOP
        sta KT
        sta P_D                 ; (P_D: rows over black; P_LO: over the floor)
        stz P_LO
        bra @rows
@swim:  lda #FLOOR_TOP          ; over black: FLOOR_TOP - top, 0..rows
        sec
        sbc sl_top,x
        bcs :+
        lda #0
:       cmp KT
        bcc :+
        lda KT
:       sta P_D
        lda KT
        sec
        sbc P_D
        sta P_LO
        beq @rows
        jsr est_build           ; over the floor: its mask too
        ldx P_I
@rows:  lda sl_vis,x            ; its rect's width: the box's and one more
        beq :+
        lda sl_bc1,x
        sec
        sbc sl_bc0,x
        inc a
        cmp #9
        bcc :++
:       lda #8
:       sta WID
        lda #2                  ; a row over black
        jsr est_row
        lda P_D
        jsr mul
        jsr est_add
        lda #3                  ; and over the floor
        jsr est_row
        lda P_LO
        jsr mul
        jsr est_add
        lda KT+1                ; units
        clc
        adc #15
        sta RD_T
        lda KT+2
        adc #0
        .repeat 4
        lsr a
        ror RD_T
        .endrepeat
        sta RD_T+1
        tay
        lda RD_T
        plx
        rts
; est_row: A = a one-layer kernel (2 black, 3 floor): KT+3/4 = a row's cycles
; for width WID.
est_row:
        tax
        jsr k_index
        lda k_rowlo,y
        sta KT+3
        lda k_rowhi,y
        sta KT+4
        rts
; est_build: KT+1/2 += a build of KT rows. Keeps Y.
est_build:
        ldx KT
        lda bc_lo,x
        sta RD_T
        lda bc_hi,x
        sta RD_T+1
; est_add: KT+1/2 += RD_T. Keeps X, Y.
est_add:
        lda KT+1
        clc
        adc RD_T
        sta KT+1
        lda KT+2
        adc RD_T+1
        sta KT+2
        rts

; ================================================================ background job
; fish_bg_begin: sets up a job to rebuild FISH_BG in the rectangle in
; FR_C0..FR_R1 (at most 8 bytes wide, as fish_box gives them; rows clipped
; to 156-191): each row the floor's bytes, then every Seaweed in slot order.
; fish_bg_rows does the work. It abandons a pending creature rect (the step
; never starts a job while one is pending).
fish_bg_begin:
        stz rd_pend
        lda FR_C0
        sta bj_c0
        lda FR_C1
        sta bj_c1
        lda FR_R1               ; rows up to 191
        cmp #192
        bcc :+
        lda #192
:       sta bj_r1
        lda FR_R0
        cmp #FLOOR_TOP
        bcs :+
        lda #FLOOR_TOP
:       sta bj_row
        lda #1
        sta bj_pend
        stz bj_live
        rts

; fish_bg_rows: rebuilds the job's rows of FISH_BG from where it stopped,
; paying for each piece from FR_LEFT first, with the same units and rule as
; fish_rect_rows: carry set when the job is finished (or there is none),
; carry clear when it stopped before something that didn't fit. FR_LEFT =
; $FFFF finishes it. The call itself costs FC_BGCALL (saturating, like
; FC_CALL). When nothing has drawn or moved since its last call (bj_live:
; no creature rect began, no slot was located) it carries its run on; else
; FC_BGSETUP + FC_BGPER per slot to list the Seaweed again (and patch again
; as it goes): creature rects may begin, run and finish between calls. A
; call abandons a pending creature rect (the step never calls it while one
; is pending) and leaves FR_C0..FR_ROW its own.
fish_bg_rows:
        stz rd_pend
        lda bj_pend
        bne :+
        sec
        rts
:       jsr vbl_poll
        lda #FC_BGCALL
        jsr pay_call
        lda bj_c0
        sta FR_C0
        lda bj_c1
        sta FR_C1
        lda bj_row
        sta FR_R0
        sta FR_ROW
        lda bj_r1
        sta FR_R1
        lda rd_mode             ; its run still set up from the last call?
        beq @fresh
        lda bj_live
        bne @go
@fresh: lda #0                  ; FC_BGSETUP, FC_BGANY (3) per slot and 5 more per Seaweed
        ldx fish_n
        beq @list
        clc
:       adc sl_weed-1,x
        dex
        bne :-
@list:  sta RD_T                ; (the Seaweed)
        asl a
        asl a
        adc RD_T                ; x 5
        sta RD_T
        lda fish_n
        asl a
        adc fish_n              ; x 3
        adc RD_T
        adc #FC_BGSETUP
        jsr charge_a
        bcc @stop
        lda #1
        sta rd_mode
        jsr list
@go:    jsr rr_loop
        php
        lda FR_ROW
        sta bj_row
        plp
        bcc @more
        stz bj_pend             ; finished
        stz bj_live
        rts
@more:  lda #1
        sta bj_live
@stop:  clc
        rts

; ================================================================ language card
; Code that reads aux memory: with RAMRD on, instructions in $0200-$BFFF
; would come from aux too.
.segment "FISHLC"

; lc_build: CNT rows of a frame in aux (lcb_s*: the row's 5 bytes, Y = row
; x 5) through a shift table page in aux (lcb_c*: the dots that stay,
; lcb_t*: the dots that spill into the next byte) into a cache in main
; memory, 6 bytes a row ((OUTP),y with OUTP a byte on each row): out[i] =
; stay[src[i]] OP spill[src[i-1]], out[5] = spill[src[4]], OP ora from 0
; for lit dots, and from $7F for masks through the inverted table.
lc_build:
        sta RDCARDRAM
        ldy #0
lcb_row:
lcb_f:  lda #$00
        .repeat 5, I
.ident(.sprintf("lcb_s%d", I)): ldx $FFFF,y
.ident(.sprintf("lcb_c%d", I)): ora $FF00,x
        sta (OUTP),y
.ident(.sprintf("lcb_t%d", I)): lda $FF80,x
        iny
        .endrepeat
        sta (OUTP),y
        inc OUTP                ; (a cache is page aligned: 216 bytes never wrap)
        dec CNT
        bne lcb_row
        sta RDMAINRAM
        rts

; lc_mirror: CNT rows, from aux (lcm_s*: the row's bytes 4-0) to aux
; (lcm_d*: bytes 0-4), each byte's dots turned round through FISH_REV.
lc_mirror:
        sta RDCARDRAM
        sta WRCARDRAM
        ldy #0
lcm_row:
        .repeat 5, I
.ident(.sprintf("lcm_s%d", I)): ldx $FFFF,y
        lda FISH_REV,x
.ident(.sprintf("lcm_d%d", I)): sta $FFFF,y
        .endrepeat
        tya
        clc
        adc #5
        tay
        dec CNT
        bne lcm_row
        sta WRMAINRAM
        sta RDMAINRAM
        rts

.segment "FX14"

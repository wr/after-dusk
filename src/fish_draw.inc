; Fish!'s row renderer (included by fx_fish.s, in segment FX14).
;
; The caller names a rectangle of at most 8 bytes by any number of rows
; (FR_C0..FR_C1-1, FR_R0..FR_R1-1). fish_rect_begin lists the creatures that
; touch it; fish_rect_rows rebuilds its rows top to bottom by the composition
; rule (the background, FISH_BG on the floor and black above it, then every
; creature but Seaweed in slot order: screen = screen AND NOT mask OR lit),
; writing each screen byte once, so nothing flickers. It stops before a row
; its budget can't pay for, and carries on from there next time.
;
; Two stages make a row. Stage 1 shifts one creature's row of lit dots and
; its row of mask into the buffers LA and MA, one byte per rectangle column,
; through FISH_SHT: out[i] = FISH_SHT[k][s(i)] | FISH_SHT[k][128 + s(i-1)].
; Its code (a block) is patched for a creature when a run of rows begins:
; the frame's address, the shift's page, and which buffer byte each output
; goes to (a spare byte when it falls outside the rectangle). A creature
; facing left is its plain row shifted by 7 - k (0 when k is 0) and written
; right to left from column C = (X + 7wb - 1) / 7, each byte turned round by
; FISH_REV in stage 2.
;
; Stage 2 (FISHCODE, in page 2) writes the rectangle's columns right to left,
; unrolled for 8 columns and entered at the rectangle's width. A run of rows
; with one creature or none is a ring of patched jumps: ring_start (the
; screen row), block A, stage 2, then a tail that pays for the next row:
;   empty  no creature: black, or FISH_BG copied
;   sea    one creature above the floor: screen = lit
;   floor  one creature on the floor: screen = FISH_BG AND NOT mask OR lit
; A run with two or more is h_mix: each creature in slot order through
; blocks A and B in turn (patched once for two, for each when more) onto the
; row buffer W, the first over the background and the last to the screen.
; A run's first row pays first for finding who is in it, then for setting
; the run up and any patching.

; ---- macros ----
.macro SETGO go, endl, wl       ; go's jump: endl - wl
        lda #<endl
        sec
        sbc wl
        sta go+1
        lda #>endl
        sbc #0
        sta go+2
.endmacro

.macro SETJ j, target           ; jump j goes to target
        lda #<target
        sta j+1
        lda #>target
        sta j+2
.endmacro

.macro COPYJ j, go              ; jump j goes where go's jump goes
        lda go+1
        sta j+1
        lda go+2
        sta j+2
.endmacro

.macro ADD40C ptr               ; the next row of FISH_BG, carry clear
        lda ptr
        adc #40
        sta ptr
        bcc :+
        inc ptr+1
:
.endmacro

.macro ADD40 ptr                ; the next row of FISH_BG
        clc
        ADD40C ptr
.endmacro

; STAGE1: a block. Step i (5..1) makes output i from source bytes i and i-1,
; FISH_SHT[k][s(i)] | FISH_SHT[k][128 + s(i-1)], and leaves s(i-1) in X for
; the step after; step 0 makes output 0. Patched: the shift's page (+2, +8),
; the source byte's address (+4), the output's buffer byte (+10). Entered with
; A = 0 and Y = its place in the frame at step wb's ldx; the mask part then
; jumps to the lit part's entry. At the end it moves yvar on a row, sets
; Y = RD_LAST, and jumps on (to stage 2, or to an rts when called).
.macro STAGE1 pre, yvar
.repeat 5, I
.ident(.sprintf("%sm%d", pre, 5-I)):
        lda FISH_SHT,x
        ldx $FFFF,y
        ora FISH_SHT+$80,x
        sta $90
.endrepeat
.ident(.concat(pre, "m0")):
        lda FISH_SHT,x
        sta $90
        lda #0
        jmp 0                   ; -> the lit dots' entry
.repeat 5, I
.ident(.sprintf("%sl%d", pre, 5-I)):
        lda FISH_SHT,x
        ldx $FFFF,y
        ora FISH_SHT+$80,x
        sta $90
.endrepeat
.ident(.concat(pre, "l0")):
        lda FISH_SHT,x
        sta $90
        tya
        clc
        adc #5                  ; wb: the next row of the frame
        sta yvar
        ldy RD_LAST
.ident(.concat(pre, "end")):
        jmp just_rts
.endmacro

; OUTPUT: output i's buffer bytes, with A = its column in the rectangle
; (LA + column and MA + column, or $90 and $98 outside it) and X = the
; block's offset from block B; A moves on a column (RD_T+5 = 1 or -1).
.macro OUTPUT op
        sta RD_T+4
        cmp RD_WID
        bcc :+
        lda #16
:       ora #LA
        sta FISH_BLKB + op + LITD, x
        ora #8
        sta FISH_BLKB + op, x
        lda RD_T+4
        clc
        adc RD_T+5
.endmacro

; S2END: the end of a stage-2 routine: jumps on (a ring's tail, or an rts).
.macro S2END name
.ident(.concat(name, "_end")):
        jmp just_rts
.endmacro

; ---- zero page: FXZ+7 on (fx_fish.s's init uses FXZ..FXZ+6) ----
FR_C0   = FXZ+7         ; rectangle: byte columns FR_C0..FR_C1-1 (0-40)
FR_C1   = FXZ+8
FR_R0   = FXZ+9         ; rows FR_R0..FR_R1-1 (0-192)
FR_R1   = FXZ+10
FR_ROW  = FXZ+11        ; the next row to draw
FR_LEFT = FXZ+12        ; 2: budget, units of 16 cycles
RD_PD   = FXZ+14        ; 2: stage 2 writes this row (the screen, or W)
RD_PS   = FXZ+16        ; 2: and reads this one (FISH_BG, W or zeros)
RD_YA   = FXZ+18        ; block A's place in its frame: row * wb
RD_YB   = FXZ+19        ; block B's
RD_NEXT = FXZ+20        ; the next row where the creatures in the row change
FR_ZP_END = FXZ+21      ; the first byte free for the rest of Fish!

; Drawing scratch Fish! has to itself: it never calls hires.s or the sprite
; engine.
LA      = DSX           ; 8: lit row, a byte per rectangle column
MA      = DSX+8         ; 8: mask row
                        ; SPX ($90, $98): where outputs outside the rectangle go
RD_T    = $10           ; $10-$17 temporaries
RD_S2E  = RD_T+5        ; 2: ring_setup: the stage-2 end jump to patch
RD_LAST = $18           ; FR_C1 - 1
RD_WID  = $19           ; FR_C1 - FR_C0, 1-8
RD_COST = $1A           ; 2: each row's cost in this run, units
RD_XTRA = $1C           ; 2: the run's first row costs this much more
RD_H    = $1E           ; 2: where the run's rows start

; ---- RAM: the renderer's, after the state arrays ----
FISH_RD   = FISH_STATE + $48
l_top     = FISH_RD             ; 10 each, per creature touching the rectangle:
l_bot     = FISH_RD + 10        ;   its first row in it, the row after its last,
l_ytop    = FISH_RD + 20        ;   y + by (low byte), its width in bytes,
l_wb      = FISH_RD + 30
l_mir     = FISH_RD + 40        ;   bit 7: facing left
l_c0      = FISH_RD + 50        ;   X / 7 and X mod 7
l_k       = FISH_RD + 60
l_fl      = FISH_RD + 70        ;   its frame: lit rows
l_fh      = FISH_RD + 80
l_ml      = FISH_RD + 90        ;   and mask rows
l_mh      = FISH_RD + 100
rd_act    = FISH_RD + 110       ; 10: the list entries in this run of rows
rd_w      = FISH_RD + 120       ; 8: the row buffer W
rd_bgr    = FISH_RD + 128       ; 2: the background's row (FISH_BG or zeros)
rd_wp     = FISH_RD + 132       ; 2: W as a row (rd_w - FR_C0)
rd_hold   = FISH_RD + 134       ; 2: list entry blocks A, B are patched for ($FF none)
rd_entl   = FISH_RD + 136       ; 4: blocks A, B: the lit dots' entry
rd_entm   = FISH_RD + 140       ; 4: the mask's entry
rd_empty  = FISH_RD + 144       ; 2: empty_go (for ring_setup)
rd_nlist  = FISH_RD + 146
rd_nact   = FISH_RD + 147
rd_floor  = FISH_RD + 148       ; 1: this run is on the floor
rd_i      = FISH_RD + 149
rd_top    = FISH_RD + 150       ; try_list counts rows from here
pl_ytl    = FISH_RD + 151       ; box_of: y + by
pl_yth    = FISH_RD + 152
pl_xl     = FISH_RD + 153       ; X: the left dot of the box as drawn
pl_xh     = FISH_RD + 154
pl_wb     = FISH_RD + 155
pl_mir    = FISH_RD + 157       ; bit 7: facing left
pl_c0     = FISH_RD + 158       ; X / 7 (signed)
pl_k      = FISH_RD + 159       ; X mod 7
bx_c0     = FISH_RD + 160       ; box_of: the box, clipped
bx_c1     = FISH_RD + 161
bx_r0     = FISH_RD + 162
bx_r1     = FISH_RD + 163
p_blk     = FISH_RD + 164       ; patch: the block's offset from blka
p_col0    = FISH_RD + 165       ; output 0's rectangle column
p_page    = FISH_RD + 166       ; the shift's page
rd_next2  = FISH_RD + 167       ; the next row the creatures change, floor or not
rd_kind   = FISH_RD + 168       ; this run: 0-5 as costs, 6 mixed
rd_wm     = FISH_RD + 169       ; 4: the rectangle's width times 5, 8, 11, 15
k_w7      = FISH_RD + 173       ; 14 each, per kind, made at init: 7 * wb,
k_xm      = k_w7 + FISH_NKIND   ;   cw - bx - 7wb (X facing left, from x),
k_pad     = k_xm + FISH_NKIND   ;   7wb - bw (the padding),
k_rwb     = k_pad + FISH_NKIND  ;   rows * wb (mask from lit)
FISH_RD_END = k_rwb + FISH_NKIND
.assert FISH_RD_END <= FISH_STATE + $140, error, "renderer RAM runs past FISH_STATE + $140"

FISH_MAX   = 10
ROLE_STILL = 4                  ; Seaweed: part of the background
LITD       = blka_l5 - blka_m5  ; a block's lit part, from its mask part
BOFF       = blka - FISH_BLKB   ; block A, from block B
STEP1      = blka_m4 - blka_m5  ; bytes in a step

; ---- costs, units of 16 cycles: upper bounds, measured ----
; fish_rect_rows charges a call FC_CALL; a run's first row FC_EVENT +
; FC_EVPER per creature listed, then its row cost, FC_SETUP, and FC_PATCH
; per block it patches; each row after that its row cost (a run of one or
; none reaching the floor: FC_SWITCH more for its first row on it). A row of
; n >= 2 costs FC_MIX + n * FC_MIXPER, and n >= 3 another n * FC_MIXNP.
; Measured worst cases (cycles): a call that has to stop, about 155 (ten
; listed); finding who is in a run 221 + 135 per creature; setting it up
; 622; a patch 654; the switch 452; rows: empty 182, sea 238 / 270 facing
; left, floor 429 / 472, two 1,266, three 4,115, four 5,453, five 6,747 (all
; at 8 bytes wide).
FC_CALL   = 10                  ; fish_rect_rows itself, and finding it must stop
FC_EVENT  = 14                  ; a run's first row: finding who is in it
FC_EVPER  = 9                   ;   per creature touching the rectangle
FC_SETUP  = 40                  ;   setting the run up
FC_PATCH  = 42                  ;   per block patched
FC_SWITCH = 29                  ; a run of one or none reaching the floor
FC_EMPTY  = 12                  ; a row with no creature
FC_SEA_N  = 16                  ; one creature over black, facing right
FC_SEA_M  = 18                  ;   facing left
FC_FLR_N  = 28                  ; one creature over the floor, facing right
FC_FLR_M  = 31                  ;   facing left
FC_MIX    = 8                   ; two or more creatures: the row
FC_MIXPER = 37                  ;   per creature
FC_MIXNP  = 47                  ;   per creature, three or more (each patched)
; fish_rect_begin: FC_BEGIN, then per slot in use FC_BEGPER, or FC_BEGFAR
; for one whose rows miss the rectangle (measured: 149; 562; 143).
FC_BEGIN  = 10
FC_BEGPER = 36
FC_BEGFAR = 10
; fish_bg_rect (not budgeted): FC_BGROW per floor row of the rectangle, and
; per Seaweed touching it FC_BGWEED plus FC_BGWROW per row of it (measured,
; 8 bytes by 36 rows: floor alone 6,690; one Seaweed 24,246; three 59,330).
FC_BGROW  = 12
FC_BGWEED = 72
FC_BGWROW = 29

; ================================================================ entry points

; fish_box: X = slot. Its box on screen, clipped, in FR_C0..FR_R1 and carry
; set; carry clear if none of it is on screen. Keeps X.
fish_box:
        jsr box_of
        bcc :+
        lda bx_c0
        sta FR_C0
        lda bx_c1
        sta FR_C1
        lda bx_r0
        sta FR_R0
        lda bx_r1
        sta FR_R1
:       rts

; fish_rect_begin: lists the creatures (not Seaweed) touching the rectangle
; in FR_C0..FR_R1, in slot order, and sets FR_ROW = FR_R0.
fish_rect_begin:
        jsr vbl_poll
        jsr rect_setup
        stz rd_nlist
        lda FR_R0
        sta rd_top
        sta FR_ROW
        sta RD_NEXT             ; the first row finds who is in it
        stz rd_next2            ; and isn't a run going on over the floor
        ldx #0
@slot:  cpx fish_n
        bcs @done
        ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_STILL
        beq :+
        jsr try_list
:       inx
        bra @slot
@done:  rts

; fish_rect_rows: draws rows from FR_ROW, charging each against FR_LEFT and
; stopping before one that doesn't fit: carry clear. Carry set when the
; rectangle is finished.
fish_rect_rows:
        lda FR_LEFT             ; the call itself
        sec
        sbc #FC_CALL
        sta FR_LEFT
        bcs rr_row
        lda FR_LEFT+1
        beq :+
        dec FR_LEFT+1
        bra rr_row
:       stz FR_LEFT
rr_row: ldx FR_ROW
        cpx RD_NEXT
        beq rr_event_row
        lda RD_COST
        sta RD_T
        lda RD_COST+1
        sta RD_T+1
        jsr charge
        bcc rr_stop
        jmp (RD_H)
rr_event_row:
        cpx FR_R1
        bcs rr_done
        cpx #FLOOR_TOP          ; a run of one creature or none reaching the
        bne @find               ; floor goes on over it as it is
        lda rd_next2
        cmp #FLOOR_TOP+1
        bcc @find
        lda rd_kind
        cmp #2
        bcc :+
        cmp #4
        bne @find
:       jmp floor_switch
@find:  lda #FC_EVENT             ; finding who is in it, paid for first
        ldx rd_nlist
        beq :++
        clc
:       adc #FC_EVPER
        dex
        bne :-
:       sta RD_T
        lda FR_LEFT
        sec
        sbc RD_T
        tay
        lda FR_LEFT+1
        sbc #0
        bcc rr_stop
        sta FR_LEFT+1
        sty FR_LEFT
        ldx FR_ROW
        jsr rr_event
        lda RD_COST             ; then the row, the set-up and any patching
        clc
        adc RD_XTRA
        sta RD_T
        lda RD_COST+1
        adc RD_XTRA+1
        sta RD_T+1
        jsr charge
        bcc @undo
        jsr rr_setup
        jmp (RD_H)
@undo:  lda FR_ROW              ; it runs again next time
        sta RD_NEXT
rr_stop:
        clc
        rts
rr_done:
        sec
just_rts:
        rts

; charge: if FR_LEFT has RD_T (2 bytes) left, takes it off: carry set.
; Otherwise carry clear, and FR_LEFT as it was.
charge:
        lda FR_LEFT
        sec
        sbc RD_T
        tay
        lda FR_LEFT+1
        sbc RD_T+1
        bcc :+
        sta FR_LEFT+1
        sty FR_LEFT
:       rts

; ---- the ring: a run of rows with one creature or none ----
; The tails: stage 2 done with a row, the next if it's in the run. A run
; paid for in full when it began takes tail_flr_p or tail_sea_p; otherwise
; tail_flr or tail_sea pay for each row and stop when the budget runs out.
tail_flr:
        ADD40C RD_PS            ; FISH_BG's next row (carry is clear)
tail_sea:
        inc FR_ROW
        ldx FR_ROW
        cpx RD_NEXT
        beq tail_run
        lda FR_LEFT
        sec
        sbc RD_COST             ; under 256
        bcs :+
        ldy FR_LEFT+1
        beq tail_stop
        dec FR_LEFT+1
:       sta FR_LEFT
        bra ring_x
tail_flr_p:
        ADD40C RD_PS
tail_sea_p:
        inc FR_ROW
        ldx FR_ROW
        cpx RD_NEXT
        beq tail_run
; ring_x: a row, paid for, X = FR_ROW. The screen row, then block A (or
; empty_go), stage 2, and a tail.
ring_x: lda row_lo,x
        sta RD_PD
        lda row_hi,x
        sta RD_PD+1
        ldy RD_YA
        lda #0
ring_j: jmp 0                   ; -> block A's entry, or empty_go
empty_go:
        ldy RD_LAST
        clc                     ; for tail_flr (a block leaves it clear)
empty_j:
        jmp 0                   ; -> stage 2
ring_start:                     ; the run's first row
        ldx FR_ROW
        bra ring_x
tail_run:
        jmp rr_row
tail_stop:
        jmp rr_stop

; floor_switch: a run of one creature or none goes on over the floor: the
; same creature, the floor's costs, stage 2 and FISH_BG's first row.
floor_switch:
        lda rd_kind             ; 0-1 become 2-3, 4 becomes 5
        ora #2
        ldy rd_kind
        cpy #4
        bne :+
        lda #5
:       sta rd_kind
        tax
        lda costs,x
        clc
        adc #FC_SWITCH
        sta RD_T
        stz RD_T+1
        jsr charge
        bcc @stop
        lda costs,x
        sta RD_COST
        lda rd_next2
        sta RD_NEXT
        lda #1
        sta rd_floor
        lda #<FISH_BG
        sta RD_PS
        lda #>FISH_BG
        sta RD_PS+1
        jsr ring_setup
        jmp ring_start
@stop:  lda rd_kind             ; as it was
        and #1
        cpx #5
        bne :+
        lda #4
:       sta rd_kind
        clc
        rts

; batch: a run of one creature or none set up, its first row paid for. If
; the budget pays for the rest too, it takes it now and stage 2 goes on to a
; paid tail; otherwise to a tail that pays for each row. A = 0 above the
; floor, 1 on it.
batch:
        asl a
        sta RD_T+4
        lda RD_NEXT             ; the rows after this one
        clc
        sbc FR_ROW
        beq @each               ; none
        sta RD_T                ; times the cost, into RD_T/RD_T+1
        lda RD_COST
        sta RD_T+1
        lda #0
        ldx #8
        lsr RD_T
:       bcc :+
        clc
        adc RD_T+1
:       ror a
        ror RD_T
        dex
        bne :--
        sta RD_T+1
        jsr charge
        bcc @each
        lda RD_T+4              ; paid: the paid tails
        ora #4
        sta RD_T+4
@each:  ldx RD_T+4
        ldy #1
        lda tails,x
        sta (RD_S2E),y
        iny
        lda tails+1,x
        sta (RD_S2E),y
        rts

tails:  .word tail_sea, tail_flr, tail_sea_p, tail_flr_p

; fish_bg_rect: rebuilds FISH_BG in the rectangle's columns, in its rows
; 156-191 only: the floor, then every Seaweed in slot order.
fish_bg_rect:
        jsr vbl_poll
        lda FR_R0
        cmp #FLOOR_TOP
        bcs :+
        lda #FLOOR_TOP
:       sta rd_top
        cmp FR_R1
        bcc :+
        rts
:       jsr rect_setup
        jsr calls               ; stage 1 and 2 return to their callers
        lda rd_top              ; the floor
        jsr bgrow
        ldx rd_top
        lda FR_R1
        ldy #>(FISH_FLOOR - FISH_BG)
        jsr bg_rows
        ldx #0                  ; then each Seaweed
@slot:  cpx fish_n
        bcs @done
        ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_STILL
        bne @next
        stz rd_nlist
        jsr try_list
        lda rd_nlist
        beq @next
        phx
        jsr vbl_poll
        jsr empty_a
        ldx #<BOFF              ; block A, list entry 0
        ldy #0
        jsr patch
        ldy #0
        lda l_top
        jsr yoff
        sta RD_YA
        lda l_top
        jsr bgrow
        ldx l_top
        lda l_bot
        ldy #0
        jsr bg_rows
        plx
@next:  inx
        bra @slot
@done:  lda #$FF                ; the list was this routine's
        sta rd_hold
        sta rd_hold+1
        stz rd_nlist
        rts

; bg_rows: FISH_BG rows X..A-1 from the row in RD_T on. Y > 0: copied from
; Y pages on (FISH_FLOOR). Y = 0: BG AND NOT mask OR lit, through block A.
bg_rows:
        sta RD_T+3
        sty RD_T+2
        lda RD_T
        sta RD_PD
        sta RD_PS
        lda RD_T+1
        sta RD_PD+1
        clc
        adc RD_T+2
        sta RD_PS+1
@row:   phx
        ldy RD_LAST
        lda RD_T+2
        beq @weed
        jsr go_copy
        bra @on
@weed:  ldy RD_YA
        jsr call_a              ; A = 0
        jsr go_p1a
@on:    ADD40 RD_PD
        ADD40 RD_PS
        plx
        inx
        cpx RD_T+3
        bcc @row
        rts

call_a: jmp (rd_entm)

; ================================================================ placement

; box_of: X = slot. Its box on screen, clipped, in bx_c0..bx_r1 and carry
; set; carry clear if none of it is on screen: the bytes holding the bw dots
; of its drawing (the frame's 7wb dots less the padding), and its rows.
; Also pl_c0 and pl_k for the frame's placement. Y = kind. Keeps X.
box_of:
        jsr box_rows
        bcs box_cols
        rts

; box_rows: X = slot. Y = kind; its box's rows, clipped, in bx_r0/bx_r1 and
; carry set, or carry clear if they're off screen. Keeps X.
box_rows:
        ldy fish_kind,x         ; rows y + by .. y + by + rows - 1
        lda fish_yl,x
        clc
        adc fk_by,y
        sta pl_ytl
        lda fish_yh,x
        adc #0
        sta pl_yth
        bmi @top0
        bne @off0
        lda pl_ytl
        cmp #192
        bcc @top
@off0:  clc
        rts
@top0:  lda #0
@top:   sta bx_r0
        lda pl_ytl
        clc
        adc fk_rows,y
        sta RD_T
        lda pl_yth
        adc #0
        bmi @off0
        bne @bot192
        lda RD_T
        beq @off0
        cmp #192
        bcc @bot
@bot192:
        lda #192
@bot:   sta bx_r1
        sec
        rts

; box_cols: X = slot, Y = kind, after box_rows: its box's columns, clipped,
; in bx_c0/bx_c1 and carry set, or carry clear if they're off screen; and
; pl_c0, pl_k for the frame's placement. Keeps X.
box_cols:
        lda fk_wb,y             ; columns: X, by facing
        sta pl_wb
        stz pl_mir
        lda fish_dir,x
        beq @right
        lda fk_role,y
        cmp #ROLE_STILL
        bcs @right              ; Seaweed and Bubbles never face left
        dec pl_mir
        lda k_xm,y              ; X = x + cw - bx - 7wb
        bra @add
@right: lda fk_bx,y             ; X = x + bx
@add:   pha
        clc
        adc fish_xl,x
        sta pl_xl
        pla
        and #$80                ; the offset's sign
        beq :+
        lda #$FF
:       adc fish_xh,x
        sta pl_xh
        bmi @neg
        lda pl_xl               ; X >= 280: off the right
        cmp #<280
        lda pl_xh
        sbc #>280
        bcc @cols
@off:   clc
        rts
@neg:   lda pl_xl               ; X + 7wb <= 0: off the left
        clc
        adc k_w7,y
        sta RD_T
        lda pl_xh
        adc #0
        bmi @off
        ora RD_T
        beq @off
@cols:  phy
        lda pl_xl               ; X / 7 and X mod 7, from 6 bytes on
        clc
        adc #42
        tay
        lda pl_xh
        adc #0
        bne @hi
        lda xmod_lo,y
        sta pl_k
        lda xbyte_lo,y
        bra @c0
@hi:    lda xmod_hi,y
        sta pl_k
        lda xbyte_hi,y
@c0:    ply
        sec
        sbc #6
        sta pl_c0
        lda #0                  ; its drawing's dots: from X, or X + 7wb - bw
        bit pl_mir              ; facing left (the padding is on the left)
        bpl :+
        lda k_pad,y
:       clc
        adc pl_k
        phx
        tax                     ; first dot's byte and dot in it
        lda pl_c0
        clc
        adc xbyte_lo,x
        sta RD_T+1
        lda xmod_lo,x           ; bytes: up to its last dot's
        clc
        adc fk_bw,y
        adc #6
        tax
        lda RD_T+1
        clc
        adc xbyte_lo,x
        plx
        dec a                   ; the last byte <= 0: off the left
        bmi @off2
        cmp #40
        bcc :+
        lda #39
:       inc a
        sta bx_c1
        lda RD_T+1              ; the first >= 40: off the right
        bmi @c00
        cmp #40
        bcs @off2
        bra :+
@c00:   lda #0
:       sta bx_c0
        sec
        rts
@off2:  clc
        rts

; try_list: X = slot. If its box touches rows rd_top..FR_R1-1 and the
; rectangle's columns, it goes on the list with what patching it needs.
; Keeps X.
try_list:
        jsr box_rows            ; rows first: most slots are elsewhere
        bcc @no
        lda rd_top
        cmp bx_r1
        bcs @no
        lda bx_r0
        cmp FR_R1
        bcs @no
        jsr box_cols            ; then columns
        bcc @no
        lda FR_C0
        cmp bx_c1
        bcs @no
        lda bx_c0
        cmp FR_C1
        bcc @yes
@no:    rts
@yes:   phx
        lda fish_frame,x        ; the frame: lit rows, then mask rows
        ldx rd_nlist
        cmp #0
        bne @f1
        lda fk_f0lo,y
        sta l_fl,x
        lda fk_f0hi,y
        bra @f
@f1:    lda fk_f1lo,y
        sta l_fl,x
        lda fk_f1hi,y
@f:     sta l_fh,x
        lda k_rwb,y             ; mask = lit + rows * wb
        clc
        adc l_fl,x
        sta l_ml,x
        lda l_fh,x
        adc #0
        sta l_mh,x
        lda pl_ytl
        sta l_ytop,x
        lda bx_r0               ; first row: its top, or rd_top
        cmp rd_top
        bcs :+
        lda rd_top
:       sta l_top,x
        lda bx_r1               ; the row after its last: or FR_R1
        cmp FR_R1
        bcc :+
        lda FR_R1
:       sta l_bot,x
        lda pl_wb
        sta l_wb,x
        lda pl_mir
        sta l_mir,x
        lda pl_c0
        sta l_c0,x
        lda pl_k
        sta l_k,x
        inc rd_nlist
        plx
        rts

; rect_setup: the rectangle's width, stage 2's length for it, and no block
; patched for it yet.
rect_setup:
        lda #$FF
        sta rd_hold
        sta rd_hold+1
        lda FR_C1
        sec
        sbc FR_C0
        sta RD_WID
        lda FR_C1
        dec a
        sta RD_LAST
        lda RD_WID              ; w * 5, 8, 11, 15: stage 2's bytes for this
        asl a                   ; width, by its step (5 sea, 8 sea facing
        sta RD_T                ; left, 11 floor, 15 floor facing left)
        asl a
        sta RD_T+1
        asl a
        sta rd_wm+1             ; w*8
        adc RD_T
        adc RD_WID
        sta rd_wm+2             ; w*11
        adc RD_T+1
        sta rd_wm+3             ; w*15
        lda RD_T+1
        adc RD_WID
        sta rd_wm               ; w*5
        rts

; bgrow: A = a row 156-191. RD_T/RD_T+1 = its row of FISH_BG.
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

; yoff: A = row, Y = list entry. A = (row - (y + by)) * wb, its place in
; its frame. Keeps Y.
yoff:
        sec
        sbc l_ytop,y
        ldx l_wb,y
        ; fall through
; times_wb: A * X, for X = 1-5 (the product under 256).
times_wb:
        sta RD_T+6
        dex
        beq @done               ; 1
        asl a
        dex
        beq @done               ; 2
        dex
        beq @add                ; 3
        asl a
        dex
        beq @done               ; 4
@add:   clc                     ; 3, 5
        adc RD_T+6
@done:  rts

; calls: blocks and stage 2 return to their callers (for h_mix and
; fish_bg_rect).
calls:
        SETGO go_p1a, s2_p1a_end, rd_wm+2
        SETGO go_flrm, s2_flrm_end, rd_wm+3
        SETGO go_copy, s2_copy_end, rd_wm
        SETJ blka_end, just_rts
        SETJ blkb_end, just_rts
        SETJ s2_p1a_end, just_rts
        SETJ s2_flrm_end, just_rts
        SETJ s2_copy_end, just_rts
        rts

; ================================================================ runs of rows

; rr_event: X = FR_ROW. Finds the creatures in this row and the next row
; where that changes, and sets the run's costs.
rr_event:
        stx RD_T+7
        lda FR_R1               ; the run ends by FR_R1
        sta RD_NEXT
        stz rd_nact
        ldy #0
@scan:  cpy rd_nlist
        bcs @scanned
        lda RD_T+7
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
@scanned:
        lda RD_NEXT             ; and at the floor's top
        sta rd_next2
        ldx RD_T+7
        cpx #FLOOR_TOP
        bcs :+
        cmp #FLOOR_TOP
        bcc :+
        lda #FLOOR_TOP
        sta RD_NEXT
:       ldx #0                  ; rd_floor: 1 on the floor
        lda RD_T+7
        cmp #FLOOR_TOP
        bcc :+
        inx
:       stx rd_floor
        lda #FC_SETUP           ; the extra: setting the run up, and patching
        sta RD_XTRA
        stz RD_XTRA+1
        stz RD_COST+1
        ldx rd_nact
        bne @some
        lda rd_floor            ; empty: 4 above the floor, 5 on it
        ora #4
        bra @set
@some:  cpx #2
        bcs @mix
        ldx #0                  ; one: block A, handler 0-3
        jsr need
        ldy rd_act
        lda l_mir,y
        asl a
        lda rd_floor
        rol a                   ; 2 * floor + facing left
@set:   sta rd_kind
        tax
        lda costs,x
        sta RD_COST
        rts
@mix:   lda #6                  ; two or more
        sta rd_kind
        lda #FC_MIX
        sta RD_COST
        ldx #0
@each:  lda #FC_MIXPER
        jsr add_cost
        lda rd_nact
        cmp #3
        bcc :+
        lda #FC_MIXNP           ; three or more: patched each row
        jsr add_cost
        bra :++
:       jsr need                ; two: blocks A, B, if not patched already
:       inx
        cpx rd_nact
        bcc @each
        rts

; need: X = 0 or 1. The run's first row pays for a patch unless block X is
; already patched for creature X of the run. Keeps X.
need:
        ldy rd_act,x
        tya
        cmp rd_hold,x
        beq :+
        lda RD_XTRA
        clc
        adc #FC_PATCH
        sta RD_XTRA
        bcc :+
        inc RD_XTRA+1
:       rts

add_cost:
        clc
        adc RD_COST
        sta RD_COST
        bcc :+
        inc RD_COST+1
:       rts

costs:  .byte FC_SEA_N, FC_SEA_M, FC_FLR_N, FC_FLR_M, FC_EMPTY, FC_EMPTY

; rr_setup: a run's first row, paid for: the background's row, the blocks
; patched, the ring's jumps (or h_mix), and the creatures' places in their
; frames.
rr_setup:
        jsr empty_a
        lda rd_floor
        beq :+
        lda FR_ROW              ; on the floor: FISH_BG's row
        jsr bgrow
        lda RD_T
        sta RD_PS
        sta rd_bgr
        lda RD_T+1
        sta RD_PS+1
        sta rd_bgr+1
:       lda #<ring_start
        sta RD_H
        lda #>ring_start
        sta RD_H+1
        lda rd_nact
        bne :+
        jmp ring_setup          ; none
:       cmp #2
        bcc @one
        lda #<rd_w              ; two or more: W as a row, and above the
        sec                     ; floor, zeros for the background
        sbc FR_C0
        sta rd_wp
        lda #>rd_w
        sbc #0
        sta rd_wp+1
        lda rd_floor
        bne :+
        lda #<zero8
        sec
        sbc FR_C0
        sta rd_bgr
        lda #>zero8
        sbc #0
        sta rd_bgr+1
:       lda #<h_mix
        sta RD_H
        lda #>h_mix
        sta RD_H+1
        jsr calls
        lda rd_nact
        cmp #3
        bcc :+
        lda #$FF                ; three or more: patched as they come
        sta rd_hold
        sta rd_hold+1
        rts
:       ldx #1
        ldy rd_act+1
        jsr hold
        ldx #0
        ldy rd_act
        jmp hold
@one:   ldx #0
        ldy rd_act
        jsr hold
        ; fall through

; ring_setup: the ring's jumps for this run's kind (0-5), then batch: into
; block A's lit dots (sea), its mask (floor) or empty_go (none); from there
; into the kind's stage 2; and from that to a tail.
ring_setup:
        ldx rd_kind
        lda k_in,x              ; ring_j: an entry word
        tay
        lda rd_entl,y
        sta ring_j+1
        lda rd_entl+1,y
        sta ring_j+2
        lda k_j_lo,x            ; block A's end (or empty_j) jumps into its
        sta RD_T+2              ; stage 2 at the rectangle's width: the
        lda k_j_hi,x            ; end less the width's bytes
        sta RD_T+3
        lda k_end_lo,x
        sta RD_S2E              ; (and that end goes to a tail)
        ldy k_wm,x
        sec
        sbc rd_wm,y
        ldy #1
        sta (RD_T+2),y
        lda k_end_hi,x
        sta RD_S2E+1
        sbc #0
        iny
        sta (RD_T+2),y
        lda k_floor,x
        jmp batch

; per kind: sea plain, sea facing left, floor plain, floor left, empty sea,
; empty floor
k_in:   .byte 0, 0, rd_entm - rd_entl, rd_entm - rd_entl, rd_empty - rd_entl, rd_empty - rd_entl
k_wm:     .byte 0, 1, 2, 3, 0, 0          ; stage 2's step: 5, 8, 11, 15
k_j_lo:   .byte <blka_end, <blka_end, <blka_end, <blka_end, <empty_j, <empty_j
k_j_hi:   .byte >blka_end, >blka_end, >blka_end, >blka_end, >empty_j, >empty_j
k_end_lo: .byte <s2_sean_end, <s2_seam_end, <s2_p1a_end, <s2_flrm_end, <s2_sean_end, <s2_copy_end
k_end_hi: .byte >s2_sean_end, >s2_seam_end, >s2_p1a_end, >s2_flrm_end, >s2_sean_end, >s2_copy_end
k_floor:  .byte 0, 0, 1, 1, 0, 1

; hold: X = block (0 or 1), Y = list entry. Patches the block for it if it
; isn't already, and finds its place in its frame for FR_ROW. Keeps X.
hold:
        tya
        cmp rd_hold,x
        beq :+
        sta rd_hold,x
        phx
        lda blk_off,x
        tax
        jsr patch
        plx
        ldy rd_hold,x
:       lda FR_ROW
        phx
        jsr yoff
        plx
        sta RD_YA,x
        rts

blk_off:  .byte <BOFF, 0       ; blocks A and B, from block B

; h_mix: a row with two or more creatures. Creature i of the run goes
; through block i AND 1 onto W, from the background (the first) or W, and
; the last from W to the screen.
h_mix:
        stz rd_i
@one:   jsr empty_a
        lda rd_i
        and #1
        tax
        lda rd_nact
        cmp #3
        bcc :+
        ldy rd_i                ; three or more: patch it
        lda rd_act,y
        tay
        jsr hold
:       ldy RD_YA,x
        txa
        asl a
        tax
        lda #0
        jsr @mask
        lda rd_wp               ; onto W
        sta RD_PD
        sta RD_PS
        lda rd_wp+1
        sta RD_PD+1
        sta RD_PS+1
        lda rd_i
        bne :+
        lda rd_bgr              ; the first from the background
        sta RD_PS
        lda rd_bgr+1
        sta RD_PS+1
:       ldy rd_i
        ldx rd_act,y
        inc rd_i
        lda rd_i
        cmp rd_nact
        bcc :+
        ldy FR_ROW              ; the last to the screen
        lda row_lo,y
        sta RD_PD
        lda row_hi,y
        sta RD_PD+1
:       ldy RD_LAST
        lda l_mir,x
        bmi :+
        jsr go_p1a
        bra :++
:       jsr go_flrm
:       lda rd_i
        cmp rd_nact
        bcc @one
        lda rd_floor
        beq @next
        ADD40 rd_bgr
@next:  inc FR_ROW
        jmp rr_row
@mask:  jmp (rd_entm,x)

; empty_a: nothing in the buffers, so stage 2 copies the background.
empty_a:
.repeat 16, I
        stz LA+I
.endrepeat
        rts

; ================================================================ patching

; patch: X = the block's offset from block B (BOFF for A, 0 for B), Y =
; list entry. Patches the block's stage 1 for that creature in this
; rectangle: the shift's page, which buffer byte each output goes to (column
; p_col0 + i, or - i facing left; $90/$98 outside the rectangle), the source
; bytes' addresses and the entries.
patch:
        stx p_blk
        lda l_mir,y
        sta RD_T+6
        lda l_k,y               ; the shift and output 0's column
        ldx l_c0,y
        bit RD_T+6
        bpl @col
        txa                     ; facing left: C = c0 + wb, shift 7 - k;
        clc                     ; C = c0 + wb - 1, shift 0 when k = 0
        adc l_wb,y
        tax
        lda l_k,y
        bne :+
        dex
        bra @col
:       eor #$FF
        sec
        adc #7
@col:   clc
        adc #>FISH_SHT
        sta p_page
        txa
        sec
        sbc FR_C0
        sta p_col0              ; in the rectangle's columns
        ldx p_blk               ; the shift's page in every step
        lda p_page
.repeat 5, I
        sta FISH_BLKB + OM5 + I * STEP1 + 2, x
        sta FISH_BLKB + OM5 + I * STEP1 + 8, x
        sta FISH_BLKB + OM5 + LITD + I * STEP1 + 2, x
        sta FISH_BLKB + OM5 + LITD + I * STEP1 + 8, x
.endrepeat
        sta FISH_BLKB + OM0 + 2, x
        sta FISH_BLKB + OM0 + LITD + 2, x
        lda #1                  ; outputs 0-5, a column on (or back) each
        bit RD_T+6
        bpl :+
        lda #$FF
:       sta RD_T+5
        lda p_col0
        OUTPUT OM0 + 4
.repeat 5, I
        OUTPUT OM5 + (4 - I) * STEP1 + 10
.endrepeat
        lda l_fh,y              ; the source bytes: s(j) in step j+1
.repeat 5, J                    ; (gen_fish.py: no run of 5 crosses a page)
        sta FISH_BLKB + OM1 - J * STEP1 + LITD + 5, x
.endrepeat
        lda l_mh,y
.repeat 5, J
        sta FISH_BLKB + OM1 - J * STEP1 + 5, x
.endrepeat
        lda l_fl,y
.repeat 5, J
        sta FISH_BLKB + OM1 - J * STEP1 + LITD + 4, x
  .if J < 4
        inc a
  .endif
.endrepeat
        lda l_ml,y
.repeat 5, J
        sta FISH_BLKB + OM1 - J * STEP1 + 4, x
  .if J < 4
        inc a
  .endif
.endrepeat
        lda l_wb,y
        sta RD_T+4
        txa                     ; the block as a pointer, for the entries
        clc
        adc #<FISH_BLKB
        sta RD_T+6
        lda #>FISH_BLKB
        adc #0
        sta RD_T+7
        ldx p_blk               ; its width, for the next row's place
        ldy RD_T+4
        tya
        sta FISH_BLKB + OL0 + 8, x
        lda entry_off-1,y       ; the entries: s(wb-1) in step wb
        clc
        adc RD_T+6
        sta RD_T
        lda RD_T+7
        adc #0
        sta RD_T+1
        ldy #2                  ; A's entries first, then B's
        cpx #0
        beq :+
        ldy #0
:       lda RD_T
        sta rd_entm,y
        clc
        adc #<LITD
        sta rd_entl,y
        sta FISH_BLKB + OM0 + 8, x
        lda RD_T+1
        sta rd_entm+1,y
        adc #0
        sta rd_entl+1,y
        sta FISH_BLKB + OM0 + 9, x
        rts

; entry_off: from a block's start, its entry for a width of 1-5 bytes: step
; wb's ldx.
entry_off:
.repeat 5, I
        .byte OM5 + (4 - I) * STEP1 + 3
.endrepeat

; ================================================================ stage 1
; Block A is the first thing in FISHCODE; block B is a copy of it made at
; init (fish_draw_init) at FISH_BLKB, BOFF bytes before it, so one patch
; routine reaches either with X = BOFF or 0. They differ only in whose place
; they move on (RD_YA, RD_YB). Both write LA and MA.
OM5     = blka_m5 - blka        ; a step's offset in its block
OM1     = blka_m1 - blka
OM0     = blka_m0 - blka
OL0     = blka_l0 - blka
BLKLEN  = blka_end + 3 - blka
blkb_end = FISH_BLKB + (blka_end - blka)
.assert OM5 = 0, error, "a block starts with step 5"
.assert STEP1 = 11, error, "a step is 11 bytes"
.assert OL0 + 13 = blka_end - blka, error, "blka_l0's layout"
.assert BOFF < 256 && BLKLEN <= BOFF, error, "block B doesn't fit before block A"
.assert MA = LA + 8, error, "MA follows LA"

; fish_draw_init: each kind's k_w7, k_xm, k_pad, k_rwb, and block B, a copy
; of block A moving on RD_YB.
fish_draw_init:
        ldy #FISH_NKIND-1
@kind:  lda fk_wb,y
        tax
        asl a
        asl a
        asl a
        sec
        sbc fk_wb,y
        sta k_w7,y
        sec
        sbc fk_bw,y
        sta k_pad,y
        lda fk_cw,y
        sec
        sbc fk_bx,y
        sec
        sbc k_w7,y
        sta k_xm,y
        lda fk_rows,y
        jsr times_wb
        sta k_rwb,y
        dey
        bpl @kind
        ldx #0
:       lda blka,x
        sta FISH_BLKB,x
        inx
        cpx #BLKLEN
        bne :-
        lda #RD_YB
        sta FISH_BLKB + OL0 + 10
        lda #<empty_go
        sta rd_empty
        lda #>empty_go
        sta rd_empty+1
        rts

go_copy: jmp s2_copy            ; (RD_PD) = (RD_PS): FISH_FLOOR to FISH_BG,
s2_copy:                        ; and FISH_BG to the screen
.repeat 8
        lda (RD_PS),y
        sta (RD_PD),y
        dey
.endrepeat
        S2END "s2_copy"
.assert s2_copy_end - s2_copy = 8 * 5, error, "s2_copy steps"

; ================================================================ stage 2
; In page 2 (FISHCODE, copied there by fish_init). Each is unrolled for 8
; columns, right to left: column j of the rectangle uses buffer byte j and
; Y = FR_C0 + j. go_X jumps in at the rectangle's width (rect_setup); each
; ends with a patched jump.
.segment "FISHCODE"

blka:   STAGE1 "blka_", RD_YA

s2_sean:                        ; screen = LA
.repeat 8, I
        lda LA+7-I
        sta (RD_PD),y
        dey
.endrepeat
        S2END "s2_sean"

s2_seam:                        ; screen = REV(LA)
.repeat 8, I
        ldx LA+7-I
        lda FISH_REV,x
        sta (RD_PD),y
        dey
.endrepeat
        S2END "s2_seam"

go_flrm: jmp s2_flrm            ; (RD_PD) = (RD_PS) AND NOT REV(MA) OR REV(LA)
s2_flrm:
.repeat 8, I
        ldx MA+7-I
        lda FISH_IREV,x
        and (RD_PS),y
        ldx LA+7-I
        ora FISH_REV,x
        sta (RD_PD),y
        dey
.endrepeat
        S2END "s2_flrm"

go_p1a: jmp s2_p1a              ; (RD_PD) = (RD_PS) AND NOT MA OR LA
s2_p1a:
.repeat 8, I
        lda (RD_PS),y
        ora MA+7-I
        eor MA+7-I
        ora LA+7-I
        sta (RD_PD),y
        dey
.endrepeat
        S2END "s2_p1a"

zero8:  .res 8, 0               ; a row of nothing, for mixes over black

.assert s2_sean_end - s2_sean = 8 * 5, error, "s2_sean steps"
.assert s2_seam_end - s2_seam = 8 * 8, error, "s2_seam steps"
.assert s2_flrm_end - s2_flrm = 8 * 15, error, "s2_flrm steps"
.assert s2_p1a_end - s2_p1a = 8 * 11, error, "s2_p1a steps"

.segment "FX14"

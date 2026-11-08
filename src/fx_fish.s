; Effect 14: Fish! An aquarium: fish, a crab, seaweed, bubbles and jellyfish
; over a sea floor (the randomizer wipes first).
;
; Its code, art and floor all live in FX2, behind the code. init copies the
; art into page 2, which Fish! never shows, the code that doesn't fit the
; overlay to page 2 (FISHCODE) and FXRAM (FISHCODE2), builds the tables the
; drawing needs, places fish_count creatures anywhere in their bands, builds
; FISH_BG from the floor (which stays in aux) and every Seaweed with the
; background job, and draws it all on page 1. The row renderer
; (fish_draw.inc) draws creatures from the state arrays; fish_spawn,
; fish_hop and fish_weed move them, and queue changes to FISH_BG for the
; background job (fish_bgq). The step (fish_step) runs every tick: each
; creature hops on its own beat, every call paid for from one tick's budget.

.include "config.inc"

; The hop size is a build setting: FISH_HOP=4 ./build.sh (ca65 -D FISH_HOP=4)
; makes every swimmer move 4 dots and every Bubble rise 4 rows a hop, on beats
; twice as long, so the speed is the same; the default is 2.
.ifndef FISH_HOP
FISH_HOP = 2
.endif
.assert FISH_HOP = 2 || FISH_HOP = 4, error, "FISH_HOP must be 2 or 4"
FISH_CYCLE = 30 * FISH_HOP      ; the step's load cycle in ticks: the beats
                                ;   (3-6 at 2 dots, 6-12 at 4) all divide it

.export fish_init, fish_step
.export FISH_BG, FISH_CODE2, FISH_SHT, FISH_REV, FISH_IREV, FLOOR_TOP
.export fish_n, fish_kind, fish_frame, fish_dir, fish_xl, fish_xh, fish_yl, fish_yh
.export FISH_MAX, fish_box, fish_rect_begin, fish_rect_rows, fish_bg_begin, fish_bg_rows
.export fish_bg_floor
.export FR_C0, FR_C1, FR_R0, FR_R1, FR_ROW, FR_LEFT, FR_ZP_END, FISH_RD_END
.export FC_CALL, FC_EVENT, FC_EVPER, FC_SETUP, FC_PATCH, FC_SWITCH, FC_EMPTY
.export FC_SEA_N, FC_SEA_M, FC_FLR_N, FC_FLR_M, FC_MIX, FC_MIXPER, FC_MIXNP
.export FC_BEGIN, FC_BEGPER, FC_BEGFAR
.export FC_BGBEGIN, FC_BGCALL, FC_BGSETUP, FC_BGANY, FC_BGSLOT, FC_BGROW, FC_BGWROW
.export FC_BGSCAN, FC_BGSCANPER
.export fish_count, fish_spawn, fish_hop, fish_weed, fish_rnd
.export fish_beat, fish_lifel, fish_lifeh, fish_flip
.export fish_bgq_push, fish_bgq_pop, fish_bgq_reset, FISH_BGQ_MAX
.export fish_bgq_n, fish_bgq_h, fish_bgq_c0, fish_bgq_c1, fish_bgq_r0, fish_bgq_r1
.export MV_N, MV_V, FISH_ZP_END, FISH_MV_END
.export fish_now, fish_now60, fish_duel, fish_dueh, fish_base60, fish_sbeat, fish_cost, fish_costh
.export fish_w, fish_load, fish_pending, fish_late_max, fish_hops, fish_late, STEP_UNITS
.export fish_bgq_peak, fish_bgq_over, fish_bg_busy, fish_bg_busy_max, fish_bgw, fish_bgr
.export fish_newslot, st_lastw, st_nrow, FISH_ST_END, st_hop, st_weed, st_begin, st_worst, st_bg, renew, arrive
.export ST_NWEED, ST_BEGW, ST_BGMIN, ST_DONE, HOP_STAY, HOP_GONE, ARR_UNITS
.export WEED_TICK, WEED_SWAY, WEED_GONE, ST_BEGIN, ST_BEGWEED, ST_BEGMISS, DRAW_MIN

.import aux_fetch, aux_copy, vbl_poll, row_lo, row_hi, xbyte_lo, xbyte_hi, xmod_lo, xmod_hi
.import rng_next, rng_below
.import __FISHART_LOAD__, __FISHART_RUN__, __FISHART_SIZE__
.import __FISHFLOOR_LOAD__
.import __FISHCODE_LOAD__, __FISHCODE_RUN__, __FISHCODE_SIZE__
.import __FISHCODE2_LOAD__, __FISHCODE2_RUN__, __FISHCODE2_SIZE__

FLOOR_TOP   = 156               ; the floor is the bottom 36 rows
FLOOR_BYTES = (192 - FLOOR_TOP) * 40

; The memory map in config.inc, held to what the linker and the art need.
.assert __FISHART_RUN__ = FISH_ART, lderror, "FISHRAM must start at FISH_ART"
.assert __FISHCODE_RUN__ = FISH_CODE, lderror, "FISHCODEMEM must start at FISH_CODE"
.assert __FISHCODE2_RUN__ = FISH_CODE2, lderror, "FISHCODE2MEM must start at FISH_CODE2"
.assert __FISHCODE2_SIZE__ > 0, lderror, "FISHCODE2 can't be empty: init copies whole pages of it"
.assert __FISHART_RUN__ + __FISHART_SIZE__ <= FISH_BLKB, lderror, "the art runs into block B"
.assert FISH_BG + FLOOR_BYTES <= FISH_REV, error, "FISH_BG runs into FISH_REV"
.assert FISH_REV + 128 <= FISH_IREV, error, "FISH_REV runs into FISH_IREV"
.assert FISH_IREV + 128 <= FISH_CODE2, error, "FISH_IREV runs into FISH_CODE2"
.assert (FISH_REV & $7F) = 0 && (FISH_IREV & $7F) = 0, error, "REV and IREV must start on a half page"
.assert FISH_CODE2 + $0600 <= FISH_SHT, error, "FISH_CODE2 runs into FISH_SHT"
.assert FISH_SHT + 7 * 256 <= FISH_STATE, error, "FISH_SHT runs into FISH_STATE"

; ---- zero page ----
SRC   = FXZ             ; 2
DST   = FXZ+2           ; 2
LO    = FXZ+4           ; a value being shifted, low and high
HI    = FXZ+5
K     = FXZ+6           ; shift, 0-6

; ---- creature state (FISH_STATE): slot i is entry i of each array ----
fish_n     = FISH_STATE         ; slots in use
fish_kind  = FISH_STATE + 1     ; 10 bytes each
fish_frame = FISH_STATE + 11    ; 0 or 1
fish_dir   = FISH_STATE + 21    ; 0 heading right, 1 left
fish_xl    = FISH_STATE + 31    ; x: the cell's left dot, signed 16-bit
fish_xh    = FISH_STATE + 41
fish_yl    = FISH_STATE + 51    ; y: the cell's top row, signed 16-bit
fish_yh    = FISH_STATE + 61

.segment "FX14"
        jmp fish_init           ; the overlay's entry points
        jmp fish_step

; ================================================================ init
fish_init:
        lda #<__FISHART_LOAD__  ; the art, from FX2 into page 2
        sta LSRC
        lda #>__FISHART_LOAD__
        sta LSRC+1
        lda #<__FISHART_RUN__
        sta LDST
        lda #>__FISHART_RUN__
        sta LDST+1
        ldx #>(__FISHART_SIZE__ + 255)  ; whole pages, never 0
        jsr aux_fetch
        lda #<__FISHCODE_LOAD__         ; the drawing code, after it
        sta LSRC
        lda #>__FISHCODE_LOAD__
        sta LSRC+1
        lda #<__FISHCODE_RUN__
        sta LDST
        lda #>__FISHCODE_RUN__
        sta LDST+1
        ldx #>(__FISHCODE_SIZE__ + 255)
        jsr aux_fetch
        lda #<__FISHCODE2_LOAD__        ; and more code, into FXRAM
        sta LSRC
        lda #>__FISHCODE2_LOAD__
        sta LSRC+1
        lda #<__FISHCODE2_RUN__
        sta LDST
        lda #>__FISHCODE2_RUN__
        sta LDST+1
        ldx #>(__FISHCODE2_SIZE__ + 255)
        jsr aux_fetch
        jsr make_sht
        jsr make_rev
        stz fish_n              ; no creatures yet
        jsr fish_draw_init
        jsr st_reset            ; the step's clock and counters
        jmp fish_place          ; then the creatures

; ================================================================ set-up
; make_sht: FISH_SHT page k holds, for a byte b of 7 dots shifted k dots
; right on the screen (left in the byte), the dots that stay in this byte,
; (b << k) & $7F, at entry b, and the dots that spill into the next byte,
; b >> (7 - k), at entry 128 + b.
make_sht:
        stz DST
        lda #>FISH_SHT
        sta DST+1
        stz K
@page:  ldy #127
@b:     sty LO                  ; HI:LO = b << k
        stz HI
        ldx K
        beq @put
@shl:   asl LO
        rol HI
        dex
        bne @shl
@put:   lda LO
        and #$7F
        sta (DST),y             ; entry b: the dots that stay
        asl LO                  ; HI = (b << k) >> 7
        rol HI
        tya
        ora #$80
        tay
        lda HI
        sta (DST),y             ; entry 128 + b: the dots that spill
        tya
        and #$7F
        tay
        dey
        bpl @b
        inc DST+1
        inc K
        lda K
        cmp #7
        bne @page
        rts

; make_rev: FISH_REV entry b is b's 7 dots in the opposite order, for drawing
; a creature facing left; FISH_IREV is the same with the dots inverted.
make_rev:
        ldx #127
@b:     txa
        ldy #7
@bit:   lsr a                   ; b's dots from the left, each pushed in at
        rol LO                  ; LO's left, so the first ends up rightmost
        dey
        bne @bit
        lda LO
        and #$7F
        sta FISH_REV,x
        eor #$7F
        sta FISH_IREV,x
        dex
        bpl @b
        rts

; bg_to_screen: draw FISH_BG on page 1, rows FLOOR_TOP-191.
bg_to_screen:
        lda #<FISH_BG
        sta SRC
        lda #>FISH_BG
        sta SRC+1
        ldx #FLOOR_TOP
@row:   lda row_lo,x
        sta DST
        lda row_hi,x
        sta DST+1
        ldy #39
:       lda (SRC),y
        sta (DST),y
        dey
        bpl :-
        lda SRC
        clc
        adc #40
        sta SRC
        bcc :+
        inc SRC+1
:       inx
        cpx #192
        bne @row
        rts

; ================================================================ drawing
.include "fish_draw.inc"

; ---- motion state, after the renderer's RAM (FISH_RD_END) ----
fish_beat  = FISH_RD_END        ; 10 each: ticks between hops (Bubbles 3)
fish_lifel = FISH_RD_END + 10   ; Seaweed: ticks it has left
fish_lifeh = FISH_RD_END + 20
fish_flip  = FISH_RD_END + 30   ; Seaweed: ticks since its frames swapped, 0-89
FISH_BGQ_MAX = 20               ; the queue of background jobs: a ring of rects,
fish_bgq_n  = FISH_RD_END + 40  ;   how many are queued,
fish_bgq_h  = FISH_RD_END + 41  ;   the oldest's entry,
fish_bgq_c0 = FISH_RD_END + 42  ;   and 20 each: FR_C0..FR_R1 (c1 = 0: free)
fish_bgq_c1 = fish_bgq_c0 + FISH_BGQ_MAX
fish_bgq_r0 = fish_bgq_c1 + FISH_BGQ_MAX
fish_bgq_r1 = fish_bgq_r0 + FISH_BGQ_MAX
FISH_MV_END = fish_bgq_r1 + FISH_BGQ_MAX        ; the first byte free for Task 5
.assert FISH_MV_END <= FISH_STATE + $400, error, "motion state runs past FISH_STATE"

; ---- zero page: motion, after the renderer's ----
MV_MODE = FR_ZP_END             ; fish_spawn: 1 anywhere, 0 a newcomer
MV_W    = FR_ZP_END + 1         ;   its cell's width and height
MV_H    = FR_ZP_END + 2
MV_T    = FR_ZP_END + 3
MV_N    = FR_ZP_END + 4         ; 2: fish_rnd's limit
MV_V    = FR_ZP_END + 6         ; 2: and what it drew
MV_OB   = FR_ZP_END + 8         ; 4: fish_hop: the old box, as FR_C0..FR_R1
MV_OV   = FR_ZP_END + 12        ;   bit 7: the old box shows
FISH_ZP_END = FR_ZP_END + 13    ; the first byte free for Task 5
ROLE_RISE = 5                   ; Bubbles

; ================================================================ motion
; As in the approved sample. Every random choice is the core's rng_below
; (fish_rnd for ranges wider than a byte); rng_below and rng_next keep X
; and Y.

; Per role (0 swim, 1 top, 2 floor, 3 low, 4 still, 5 rise anywhere, 6 a
; newcomer Bubble): y = mv_ymax - h (where mv_ymh is $FF) - rng_below(span),
; span = mv_span, less h for swimmers. So swim 2..182-h, top 0..30, floor
; 192-h-(1..4), low 156-h+(4..12), still 192-h, rise 0..156, newcomer 152.
mv_ymax:  .byte 182, 30, 191, 168, 192, 156, 152
mv_ymh:   .byte $FF, 0, $FF, $FF, $FF, 0, 0
mv_span:  .byte 181, 31, 4, 9, 1, 157, 1
mv_beats: .byte 2 * FISH_HOP, 2 * FISH_HOP, 5 * FISH_HOP / 2, 3 * FISH_HOP
mv_dxl:   .byte <FISH_HOP, <-FISH_HOP   ; a hop: FISH_HOP dots the way it faces
mv_dxh:   .byte >FISH_HOP, >-FISH_HOP

; fish_spawn: X = slot, A = 1 to place it anywhere (init), 0 for a newcomer.
; Picks its kind (all 14 alike), frame, beat (4, 4, 5 or 6 ticks, twice
; that for 4-dot hops; Bubbles 3, or 6), heading (swimmers only; the rest face right) and place by its band. A
; newcomer swimmer enters just off a side, facing in (x = -w heading right,
; 280 heading left); a newcomer Bubble 4 rows above the floor. x anywhere:
; 0..280-w (Bubbles 4..280-w-4). A Seaweed also gets its life ((20 +
; rng_below(21)) * 60 ticks) and a sway count to start from (0-89); a
; newcomer Seaweed queues its box for the background job. Keeps X; never
; touches FR_C0..FR_R1.
fish_spawn:
        sta MV_MODE
        stx fish_newslot        ; (the step gives a newcomer its beat)
        lda #FISH_NKIND
        jsr rng_below
        sta fish_kind,x
        tay
        lda fk_cw,y
        sta MV_W
        lda fk_ch,y
        sta MV_H
        lda #2
        jsr rng_below
        sta fish_frame,x
        lda #4
        jsr rng_below
        phy
        tay
        lda mv_beats,y
        ply
        sta fish_beat,x
        stz fish_dir,x
        stz fish_yh,x
        lda fk_role,y
        cmp #ROLE_RISE
        bne @role
        lda #3 * FISH_HOP / 2   ; Bubbles hop every 3 ticks (6 for 4-dot hops)
        sta fish_beat,x
        lda MV_MODE
        eor #1                  ; a newcomer: role 6
        adc #ROLE_RISE          ; (carry set from cmp)
        dec a
@role:  tay                     ; Y = role from here on
        lda mv_span,y           ; y: where its band says
        cpy #0
        bne :+
        sbc MV_H                ; (carry set from cpy)
:       jsr rng_below
        sta MV_T
        lda MV_H
        and mv_ymh,y
        eor #$FF
        sec
        adc mv_ymax,y
        sec
        sbc MV_T
        sta fish_yl,x
        cpy #ROLE_STILL         ; swimmers: a heading
        bcs @x
        lda #2
        jsr rng_below
        sta fish_dir,x
        lda MV_MODE
        bne @x
        lda fish_dir,x          ; a newcomer comes in from the side behind it
        beq :+
        lda #<280
        sta fish_xl,x
        lda #>280
        sta fish_xh,x
        rts
:       sec                     ; A = 0: x = -w
        sbc MV_W
        sta fish_xl,x
        lda #$FF
        sta fish_xh,x
        rts
@x:     lda #<281               ; x = rnd(281 - w), Bubbles 4 + rnd(273 - w)
        cpy #ROLE_RISE
        bcc :+
        lda #<273
:       sec
        sbc MV_W
        sta MV_N
        lda #>281               ; (= >273)
        sbc #0
        sta MV_N+1
        jsr fish_rnd
        lda MV_V
        cpy #ROLE_RISE
        bcc :+
        adc #3                  ; (carry set: + 4)
:       sta fish_xl,x
        lda MV_V+1
        adc #0
        sta fish_xh,x
        cpy #ROLE_STILL
        bne @rts
        lda #21                 ; Seaweed: life (20 + rng_below(21)) * 60,
        jsr rng_below           ; as v * 64 - v * 4
        clc
        adc #20
        asl a
        asl a
        sta MV_T                ; v * 4
        stz fish_lifeh,x
        ldy #4
:       asl a
        rol fish_lifeh,x
        dey
        bne :-
        sec
        sbc MV_T
        sta fish_lifel,x
        bcs :+
        dec fish_lifeh,x
:       lda #90                 ; and where its sway count starts
        jsr rng_below
        sta fish_flip,x
        lda MV_MODE
        bne @rts
        jsr box_of              ; a newcomer: its box to the queue
        jmp bgq_push_bx
@rts:   rts

; fish_rnd: MV_V = 0..MV_N-1 (MV_N 1-511), every value alike: rng_below
; when MV_N fits a byte; otherwise a ninth bit (rng_below(2)) over a byte
; (rng_next), drawn again while it is MV_N or more. Keeps X and Y.
fish_rnd:
        stz MV_V+1
        lda MV_N+1
        bne @wide
        lda MV_N
        jsr rng_below
        sta MV_V
        rts
@wide:  lda #2
        jsr rng_below
        sta MV_V+1
        jsr rng_next
        sta MV_V
        cmp MV_N
        lda MV_V+1
        sbc MV_N+1
        bcs @wide
        rts

; fish_hop: X = slot (never a Seaweed: Task 5's picker skips them). One hop:
; its frames swap; a Bubble rises FISH_HOP rows; the rest turn round 1 time in
; 42 (rng_below(42) = 0), then move FISH_HOP dots the way they face. One that
; has gone (a swimmer once x < -w-FISH_HOP or x > 280+FISH_HOP, a Bubble once
; y < -h) is
; replaced by a newcomer (fish_spawn, A = 0). Leaves the rect to redraw in
; FR_C0..FR_R1 and carry set, or carry clear if none of it shows: the old
; box joined with the new one, clipped (at most 8 bytes wide). For one that
; has gone, its old box if that still shows (a Bubble's last row can), else
; the newcomer's (a Bubble, at row 152); when both show, the newcomer's box
; goes on the queue. A newcomer Seaweed queues its own box. Keeps X.
fish_hop:
        jsr fish_box            ; the old box
        ror MV_OV
        ldy #3
:       lda FR_C0,y
        sta MV_OB,y
        dey
        bpl :-
        lda fish_frame,x
        eor #1
        sta fish_frame,x
        ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_RISE
        bne @swim
        lda fish_yl,x           ; a Bubble rises FISH_HOP rows
        sec
        sbc #FISH_HOP
        sta fish_yl,x
        bcs :+
        dec fish_yh,x
:       clc                     ; gone once y + h < 0
        adc fk_ch,y
        lda fish_yh,x
        adc #0
        bmi @gone
        bra @new
@swim:  lda #42                 ; turn round, 1 time in 42
        jsr rng_below
        cmp #0
        bne :+
        lda fish_dir,x
        eor #1
        sta fish_dir,x
:       ldy fish_dir,x          ; FISH_HOP dots the way it faces
        lda fish_xl,x
        clc
        adc mv_dxl,y
        sta fish_xl,x
        lda fish_xh,x
        adc mv_dxh,y
        sta fish_xh,x
        ldy fish_kind,x         ; gone once x + w + FISH_HOP < 0
        lda fk_cw,y
        sec
        adc #FISH_HOP - 1
        adc fish_xl,x
        lda fish_xh,x
        adc #0
        bmi @gone
        lda fish_xh,x           ; or x > 280 + FISH_HOP
        bmi @new
        lda fish_xl,x
        cmp #<(281 + FISH_HOP)
        lda fish_xh,x
        sbc #>(281 + FISH_HOP)
        bcs @gone
@new:   jsr fish_box            ; the new box
        bcc @old
        bit MV_OV
        bpl @yes                ; the old one didn't show: the new box alone
        lda MV_OB               ; both: joined
        cmp FR_C0
        bcs :+
        sta FR_C0
:       lda MV_OB+1
        cmp FR_C1
        bcc :+
        sta FR_C1
:       lda MV_OB+2
        cmp FR_R0
        bcs :+
        sta FR_R0
:       lda MV_OB+3
        cmp FR_R1
        bcc @yes
        sta FR_R1
@yes:   sec
        rts
@gone:  lda #0                  ; gone: a newcomer in its place
        jsr fish_spawn
        jsr fish_box            ; (Y = its kind)
        bcc @old
        lda fk_role,y
        cmp #ROLE_STILL
        beq @old                ; a Seaweed has queued its own box
        bit MV_OV
        bpl @yes                ; the rect is the newcomer's
        jsr bgq_push_bx         ; both show: the newcomer's waits in the queue
@old:   bit MV_OV               ; the old box, if it showed
        bpl @no
        ldy #3
:       lda MV_OB,y
        sta FR_C0,y
        dey
        bpl :-
        sec
        rts
@no:    clc
        rts

; fish_weed: X = a Seaweed's slot; one tick. Counts its life down: when it
; runs out, its box goes on the queue (the job takes it out of FISH_BG) and
; a newcomer takes the slot (fish_spawn, A = 0), one that shows queuing its
; box too. Otherwise counts its sway: every 90 ticks its frames swap and
; its box goes on the queue. It leaves no rect (each queued job redraws the
; screen after rebuilding FISH_BG), never touches FR_C0..FR_R1 or another
; slot, so it may run while a creature rect is pending. Keeps X.
fish_weed:
        lda fish_lifel,x
        bne :+
        dec fish_lifeh,x
:       dec fish_lifel,x
        bne @sway
        lda fish_lifeh,x
        bne @sway
        jsr box_of              ; gone: its box to the queue
        jsr bgq_push_bx
        lda #0                  ; and a newcomer (a Seaweed queues its own)
        jsr fish_spawn
        jsr box_of
        bcc @rts
        lda fk_role,y
        cmp #ROLE_STILL
        bne @push
@rts:   rts
@sway:  inc fish_flip,x
        lda fish_flip,x
        cmp #90
        bcc @rts
        stz fish_flip,x
        lda fish_frame,x
        eor #1
        sta fish_frame,x
        jsr box_of
@push:  bra bgq_push_bx

; fish_bgq_push: queues a background job for the rect in FR_C0..FR_R1 (at
; most 8 bytes wide), unless it is queued already. Its rows stay as given:
; fish_bg_begin keeps to rows 156-191, and the screen redraw after the job
; takes the rect whole (a Bubble's box reaches above the floor). With 20
; queued, the queue becomes the five full-width strips instead. Keeps X.
fish_bgq_push:
        ldy #3
:       lda FR_C0,y
        sta bx_c0,y
        dey
        bpl :-
; bgq_push_bx: the same, for the rect in bx_c0..bx_r1 (box_of's).
bgq_push_bx:
        ldy #FISH_BGQ_MAX-1     ; queued already? (a free entry's c1 is 0,
@dup:   lda fish_bgq_c1,y       ; and no rect's is)
        cmp bx_c1
        bne @nx
        lda fish_bgq_c0,y
        cmp bx_c0
        bne @nx
        lda fish_bgq_r0,y
        cmp bx_r0
        bne @nx
        lda fish_bgq_r1,y
        cmp bx_r1
        beq @rts
@nx:    dey
        bpl @dup
        lda fish_bgq_n
        cmp #FISH_BGQ_MAX
        bcs @full
        adc fish_bgq_h          ; at the tail: head + n, round the ring
        cmp #FISH_BGQ_MAX
        bcc :+
        sbc #FISH_BGQ_MAX
:       tay
        lda bx_c0
        sta fish_bgq_c0,y
        lda bx_c1
        sta fish_bgq_c1,y
        lda bx_r0
        sta fish_bgq_r0,y
        lda bx_r1
        sta fish_bgq_r1,y
        inc fish_bgq_n
        lda fish_bgq_n          ; the most ever queued at once
        cmp fish_bgq_peak
        bcc @rts
        sta fish_bgq_peak
@rts:   rts
@full:  inc fish_bgq_over       ; full (counted): the five full-width strips
        bne :+                  ; instead, which rebuild all of FISH_BG
        inc fish_bgq_over+1
:       jsr fish_bgq_reset
        ldy #4
@strip: tya
        asl a
        asl a
        asl a
        sta fish_bgq_c0,y
        adc #8
        sta fish_bgq_c1,y
        lda #FLOOR_TOP
        sta fish_bgq_r0,y
        lda #192
        sta fish_bgq_r1,y
        dey
        bpl @strip
        lda #5
        sta fish_bgq_n
        rts

; fish_bgq_pop: carry clear if the queue is empty; else carry set and the
; oldest rect in FR_C0..FR_R1, taken off the queue (so a change while its
; job runs queues it again). fish_bg_rows writes over FR_C0..FR_R1: keep the
; rect to redraw the screen after the job. Keeps X.
fish_bgq_pop:
        clc
        lda fish_bgq_n
        beq @rts
        dec fish_bgq_n
        ldy fish_bgq_h
        lda fish_bgq_c0,y
        sta FR_C0
        lda fish_bgq_c1,y
        sta FR_C1
        lda fish_bgq_r0,y
        sta FR_R0
        lda fish_bgq_r1,y
        sta FR_R1
        lda #0
        sta fish_bgq_c1,y       ; free
        iny
        cpy #FISH_BGQ_MAX
        bcc :+
        ldy #0
:       sty fish_bgq_h
        sec
@rts:   rts

; fish_bgq_reset: empties the queue. Leaves A = 0. Keeps X.
fish_bgq_reset:
        stz fish_bgq_n
        stz fish_bgq_h
        lda #0
        ldy #FISH_BGQ_MAX-1
:       sta fish_bgq_c1,y
        dey
        bpl :-
        rts

; fish_place: the rest of init. fish_count creatures placed anywhere, each
; with its first due tick, FISH_BG built (the floor and every Seaweed), the
; screen drawn: FISH_BG, then the box of each creature that isn't Seaweed.
; Nothing queued.
fish_place:
        jsr fish_bgq_reset      ; nothing queued
        lda fish_count          ; fish_count creatures, anywhere
        sta fish_n
        ldx #0
@spawn: cpx fish_n
        bcs :+
        lda #1
        jsr fish_spawn
        jsr arrive
        inx
        bra @spawn
:       jsr st_worst            ; (for the Seaweed count)
        jsr fish_bg_floor       ; FISH_BG: the floor and every Seaweed
        jsr bg_to_screen
        ldx #0                  ; then every other creature's box
@draw:  cpx fish_n
        bcs @done
        jsr fish_box            ; (Y = its kind)
        bcc :+
        lda fk_role,y
        cmp #ROLE_STILL
        beq :+
        phx
        jsr fish_rect_begin
        lda #$FF
        sta FR_LEFT
        sta FR_LEFT+1
        jsr fish_rect_rows
        plx
:       inx
        bra @draw
@done:  rts

; How many creatures fish_init places (Task 6 sets it; tests poke it).
fish_count: .byte 6

; ================================================================ the step
; Every tick:
;  1. now += 1 (now60 round the load cycle), and the tick's budget: FR_LEFT =
;     STEP_UNITS, in the renderer's units of 16 cycles.
;  2. Every Seaweed's tick (fish_weed), even with a rect pending.
;  3. A creature rect left half drawn goes on; if it still doesn't finish,
;     that's the tick.
;  4. Hops: the one due longest first (ties: the lowest slot), counted late
;     by the ticks it waited, its next due tick a beat on from the planned
;     one. After the first, a hop starts only if its estimate fits. A rect
;     that doesn't finish is left pending, and that's the tick.
;  5. Nothing more due: background work on what is left. The queue's next
;     rect is rebuilt in FISH_BG (fish_bg_rows, over several ticks if need
;     be), then redrawn on screen; a redraw that runs out is dropped and
;     begun again from the row it reached, so it never leaves a rect
;     pending. Then the next rect, while the budget lasts.
; Every call is paid for from FR_LEFT before it runs (or, for a begin, from
; room kept for its worst), by costs measured at their worst: no step runs
; past its tick. Hops are spread over the load cycle, 60 ticks (120 for 4-dot
; hops: beats 8 don't divide 60) as creatures arrive: fish_load sums each
; tick's hop estimates. (The names say 60; FISH_CYCLE is the count.)

; ---- the step's state, after the motion state ----
fish_now60  = FISH_MV_END       ; now mod FISH_CYCLE (60 or 120)
fish_duel   = fish_now60 + 1    ; 10 each: the tick its next hop is due,
fish_dueh   = fish_duel + FISH_MAX
fish_base60 = fish_dueh + FISH_MAX      ;   that mod the cycle when it arrived,
fish_sbeat  = fish_base60 + FISH_MAX    ;   its beat then (fish_load's spacing),
fish_cost   = fish_sbeat + FISH_MAX     ;   its hop's estimate (units),
fish_costh  = fish_cost + FISH_MAX
fish_w      = fish_costh + FISH_MAX     ;   and its weight in fish_load (0: none)
ST_CLEAR    = fish_w + FISH_MAX ; from here to ST_CLEAR_END, zeroed by init:
fish_load   = ST_CLEAR          ; FISH_CYCLE: weights of the hops due on each tick mod it
fish_pending = fish_load + FISH_CYCLE   ; 1 while a creature rect is half drawn
fish_late_max = fish_pending + 1        ; the latest any hop has been (ticks)
fish_hops   = fish_late_max + 1 ; 2: hops,
fish_late   = fish_hops + 2     ; 2: and how many were late
fish_bgq_peak = fish_late + 2   ; the most rects ever queued at once
fish_bgq_over = fish_bgq_peak + 1       ; 2: times the queue overflowed
fish_bg_busy = fish_bgq_over + 2        ; 2: ticks in a row with background
fish_bg_busy_max = fish_bg_busy + 2     ; 2: work waiting, and the most
fish_bgw    = fish_bg_busy_max + 2      ; background work: 0 none, 1 the job,
ST_CLEAR_END = fish_bgw + 1             ;   2 its redraw
fish_bgr    = ST_CLEAR_END      ; 4: its rect (FR_C0..FR_R1; R0: the redraw's next row)
fish_newslot = fish_bgr + 4     ; the slot fish_spawn last filled
st_lastw    = fish_newslot + 1  ; ST_NWEED when ST_BEGW was last worked out
st_nrow     = st_lastw + 1      ; slots fish_rect_begin looked at whose rows touch
FISH_ST_END = st_nrow + 1
.assert FISH_ST_END <= FISH_STATE + $400, error, "the step's state runs past FISH_STATE"

; ---- zero page, after the motion's ----
fish_now = FISH_ZP_END          ; 2: ticks since init
ST_DONE  = FISH_ZP_END + 2      ; hops started this tick
ST_NWEED = FISH_ZP_END + 3      ; Seaweed slots
ST_BEST  = FISH_ZP_END + 4      ; pick: the latest so far, and its slot
ST_BSL   = FISH_ZP_END + 5
ST_BEGW  = FISH_ZP_END + 6      ; 2: a begin at its worst,
ST_BGMIN = FISH_ZP_END + 8      ; 2: and one useful background call
ST_M     = FISH_ZP_END + 10     ; scratch: madd, walk_max
ST_B     = FISH_ZP_END + 11     ; arrive: beat, weight, a walk's start,
ST_W     = FISH_ZP_END + 12
ST_T     = FISH_ZP_END + 13
ST_BM    = FISH_ZP_END + 14     ;   the quietest busiest tick, its tick and p,
ST_BT    = FISH_ZP_END + 15
ST_BP    = FISH_ZP_END + 16
ST_P     = FISH_ZP_END + 17     ;   and the p being tried
.assert ST_P < $80, error, "the step's zero page runs past $7F"

; ---- costs, units of 16 cycles (measured worst cycles in brackets) ----
STEP_UNITS = 920                ; the tick's budget
HOP_STAY   = 110                ; fish_hop, staying (1,720: facing left, clipped at the right)
HOP_GONE   = 245                ;   gone and replaced (3,850)
ARR_UNITS  = 340                ; renew: leaving and arriving (5,072; about
                                ;   5,200 at worst: beat 3 in and out, a Bubble's
                                ;   rows, ten slots, the Seaweed count changing)
WEED_TICK  = 3                  ; fish_weed, a plain tick (39)
WEED_SWAY  = 76                 ;   a sway (1,162)
WEED_GONE  = 235                ;   gone and replaced (3,531)
ST_BEGIN   = FC_BEGIN + 10      ; st_begin: fish_rect_begin (155), its own sums
                                ;   (about 125) and a IIc's slower vbl_poll;
ST_BEGWEED = 2                  ;   per Seaweed slot (23),
ST_BEGMISS = 27 + 2             ;   per other slot whose rows touch (415 + 22),
ST_BEGFAR  = FC_BEGFAR + 2      ;   per other slot whose rows miss (152 + 22)
DRAW_MIN   = FC_CALL + FC_EVENT + 2 * FC_EVPER + FC_SETUP + FC_PATCH + FC_FLR_M
                                ; a first row at its dearest (a redraw waits for it)
EST_FIX    = HOP_STAY + ST_BEGIN + FC_BEGPER + FC_CALL + FC_EVENT + FC_EVPER + FC_SETUP + FC_PATCH
BG_FIX     = FC_BGCALL + FC_BGSETUP + FC_BGSCAN + FC_BGROW + 2 * FC_PATCH
BG_WEED    = FC_BGSLOT + FC_BGSCANPER + FC_BGWROW
LEFT_MIN   = BG_FIX             ; with less left, nothing more can start
.assert LEFT_MIN <= HOP_STAY + ST_BEGIN + FC_BEGPER, error, "LEFT_MIN: a hop needs less"

fish_step:
        inc fish_now            ; 1. the clock
        bne :+
        inc fish_now+1
:       ldy fish_now60
        iny
        cpy #FISH_CYCLE
        bcc :+
        ldy #0
:       sty fish_now60
        lda fish_bgq_n          ; ticks in a row with background work waiting
        ora fish_bgw
        bne :+
        stz fish_bg_busy
        stz fish_bg_busy+1
        bra @budget
:       inc fish_bg_busy
        bne :+
        inc fish_bg_busy+1
:       lda fish_bg_busy_max
        cmp fish_bg_busy
        lda fish_bg_busy_max+1
        sbc fish_bg_busy+1
        bcs @budget
        lda fish_bg_busy
        sta fish_bg_busy_max
        lda fish_bg_busy+1
        sta fish_bg_busy_max+1
@budget:
        lda #<STEP_UNITS
        sta FR_LEFT
        lda #>STEP_UNITS
        sta FR_LEFT+1
        stz ST_DONE
        ldx fish_n              ; 2. every Seaweed's tick (fish_w = 0)
        bra @nw
@weed:  lda fish_w,x
        bne @nw
        jsr st_weed
@nw:    dex
        bpl @weed
        lda fish_pending        ; 3. a rect left half drawn
        beq @hop
        jsr fish_rect_rows
        bcc @rts
        stz fish_pending
@hop:   jsr pick                ; 4. the hops due
        bmi st_bg               ; none: 5.
        ldy ST_DONE
        beq :+
        pha
        lda FR_LEFT             ; after the first, only one that fits
        cmp fish_cost,x
        lda FR_LEFT+1
        sbc fish_costh,x
        pla
        bcc @rts
:       jsr st_hop
        bcc @rts
        lda FR_LEFT+1           ; too little left for any hop or background
        bne @hop                ; call: done
        lda FR_LEFT
        cmp #LEFT_MIN
        bcs @hop
@rts:   rts

; st_bg: nothing more is due. Background work: the next queued rect rebuilt
; in FISH_BG, then redrawn on screen, while FR_LEFT lasts.
st_bg:  lda fish_bgw
        cmp #2
        beq @redraw
        lda ST_BGMIN            ; enough for a useful call?
        ldy ST_BGMIN+1
        jsr afford
        bcc @rts
        lda fish_bgw
        bne @job
        jsr fish_bgq_pop        ; the next rect
        bcc @rts
        ldy #3
:       lda FR_C0,y
        sta fish_bgr,y
        dey
        bpl :-
        jsr fish_bg_begin
        inc fish_bgw            ; 1: rebuilding FISH_BG
@job:   jsr fish_bg_rows
        bcc @rts
        inc fish_bgw            ; 2: and the screen
@redraw:
        lda #DRAW_MIN
        clc
        adc ST_BEGW
        ldy ST_BEGW+1
        bcc :+
        iny
:       jsr afford
        bcc @rts
        ldy #3
:       lda fish_bgr,y
        sta FR_C0,y
        dey
        bpl :-
        jsr st_begin
        jsr fish_rect_rows
        bcc @stop
        stz fish_bgw            ; done: the next
        bra st_bg
@stop:  lda FR_ROW              ; dropped: from this row next time
        sta fish_bgr+2
@rts:   rts

; afford: carry set if FR_LEFT is at least A (low), Y (high), put in RD_T;
; afford_t: at least RD_T.
afford: sta RD_T
        sty RD_T+1
afford_t:
        lda FR_LEFT
        cmp RD_T
        lda FR_LEFT+1
        sbc RD_T+1
        rts

; charge_ay: charge A (low), Y (high): carry set and FR_LEFT less it, or
; carry clear and FR_LEFT as it was.
charge_ay:
        sta RD_T
        sty RD_T+1
        jmp charge

; is_weed: X = slot. Z set if it is a Seaweed; Y = its kind.
is_weed:
        ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_STILL
        rts

; pick: X = the slot whose hop has been due longest (due <= now; ties: the
; lowest slot), A = the ticks it is late (at most 255), or X = $FF and N
; set if none. Seaweed (fish_w = 0) never hops.
pick:   lda #$FF
        sta ST_BSL
        stz ST_BEST
        ldx fish_n
        bra @nx
@slot:  lda fish_w,x
        beq @nx
        lda fish_now            ; late by now - due
        sec
        sbc fish_duel,x
        tay
        lda fish_now+1
        sbc fish_dueh,x
        bcc @nx                 ; not due yet
        beq :+
        ldy #$FF                ; (256 or more)
:       cpy ST_BEST
        bcc @nx
        sty ST_BEST
        stx ST_BSL
@nx:    dex
        bpl @slot
        lda ST_BEST
        ldx ST_BSL
        rts

; st_hop: X = a slot that is due, A = the ticks it is late. If FR_LEFT
; pays for its hop at its worst and a begin: it is counted, its next hop is
; due a beat on from this one, it hops, and its rect is drawn on what is
; left. Carry set to go on; clear to end the tick (no budget for it, or its
; rect left pending).
st_hop: pha
        jsr may_go              ; its hop at its worst, and a begin
        clc
        adc ST_BEGW
        sta RD_T
        tya
        adc ST_BEGW+1
        sta RD_T+1
        jsr afford_t
        ply
        bcc @rts
        tya                     ; counted
        cmp fish_late_max
        bcc :+
        sta fish_late_max
:       inc fish_hops
        bne :+
        inc fish_hops+1
:       tya
        beq :+
        inc fish_late
        bne :+
        inc fish_late+1
:       lda fish_duel,x         ; the next, a beat on from the planned tick
        clc
        adc fish_beat,x
        sta fish_duel,x
        bcc :+
        inc fish_dueh,x
:       lda #HOP_STAY
        jsr charge_a
        lda #$FF
        sta fish_newslot
        jsr fish_hop
        php
        cpx fish_newslot        ; gone, and a newcomer in its place
        bne :+
        lda #<(HOP_GONE + ARR_UNITS - HOP_STAY)
        ldy #>(HOP_GONE + ARR_UNITS - HOP_STAY)
        jsr charge_ay
        jsr renew
:       inc ST_DONE
        plp
        bcc @on                 ; nothing shows
        jsr st_begin
        jsr fish_rect_rows
        bcs @on
        inc fish_pending        ; on with it next tick
        clc
@rts:   rts
@on:    sec
        rts

; may_go: X = slot. A (low), Y (high) = its hop's cost at its worst:
; HOP_GONE + ARR_UNITS if this hop may take it off (a swimmer at x < -w or
; x > 280, whichever way it turns, for either hop size; a Bubble at
; y + h < FISH_HOP), else HOP_STAY.
may_go: ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_RISE
        bne @swim
        lda fish_yl,x
        clc
        adc fk_ch,y
        tay
        lda fish_yh,x
        adc #0
        bmi @go
        bne @stay
        cpy #FISH_HOP
        bcc @go
        bra @stay
@swim:  lda fish_xh,x
        beq @stay
        bmi @left
        lda fish_xl,x
        cmp #<281
        bcs @go
        bra @stay
@left:  lda fish_xl,x
        clc
        adc fk_cw,y
        bcs @stay
@go:    lda #<(HOP_GONE + ARR_UNITS)
        ldy #>(HOP_GONE + ARR_UNITS)
        rts
@stay:  lda #HOP_STAY
        ldy #0
        rts

; st_weed: X = a Seaweed's slot. Its tick (fish_weed), paid for first by
; what it will do; if FR_LEFT can't pay, it waits a tick. A newcomer in its
; place gets its beat (renew). Keeps X.
st_weed:
        lda fish_lifeh,x        ; its life runs out this tick?
        bne @sway
        lda fish_lifel,x
        dec a
        bne @sway
        lda #<(WEED_GONE + ARR_UNITS)
        ldy #>(WEED_GONE + ARR_UNITS)
        bra @pay
@sway:  ldy #0                  ; or it sways
        lda fish_flip,x
        cmp #89
        lda #WEED_TICK
        bcc @pay
        lda #WEED_SWAY
@pay:   jsr charge_ay
        bcc @rts
        lda #$FF
        sta fish_newslot
        jsr fish_weed
        cpx fish_newslot
        beq renew
@rts:   rts

; renew: X = a slot fish_spawn has just filled (in fish_hop or fish_weed).
; The creature that left takes its weight off fish_load (a Seaweed has none:
; one fewer), the newcomer arrives, and ST_BEGW and ST_BGMIN follow the
; Seaweed count. Keeps X.
renew:  lda fish_w,x
        bne :+
        dec ST_NWEED
        bra @in
:       eor #$FF
        inc a
        sta ST_W
        lda fish_sbeat,x
        sta ST_B
        ldy fish_base60,x
        jsr walk_add
@in:    jsr arrive
        jmp st_worst

; arrive: X = a slot just filled. A Seaweed never hops: no due tick, no
; weight, one more in ST_NWEED. Anything else: its estimate (cost_of), then
; its first hop due at now + 1 + p, p = 0..beat-1, the p whose busiest tick
; in fish_load is the quietest (ties: the smallest p), and its weight on
; every tick its hops fall on. Keeps X.
arrive: stz fish_w,x
        jsr is_weed
        bne :+
        inc ST_NWEED
        rts
:       jsr cost_of
        lda fish_beat,x
        sta fish_sbeat,x
        sta ST_B
        lda #$FF
        sta ST_BM
        stz ST_P
        ldy fish_now60
@p:     iny                     ; tick now + 1 + p, mod the cycle
        cpy #FISH_CYCLE
        bcc :+
        ldy #0
:       jsr walk_max
        cmp ST_BM
        bcs :+
        sta ST_BM
        sty ST_BT
        lda ST_P
        sta ST_BP
:       inc ST_P
        lda ST_P
        cmp ST_B
        bcc @p
        lda fish_now            ; due = now + 1 + p
        sec
        adc ST_BP
        sta fish_duel,x
        lda fish_now+1
        adc #0
        sta fish_dueh,x
        ldy ST_BT
        tya
        sta fish_base60,x
        lda fish_w,x
        sta ST_W
        jmp walk_add

; walk_add: fish_load += ST_W at tick Y and every ST_B ticks on, round the
; cycle. Keeps X.
walk_add:
        sty ST_T
@t:     lda fish_load,y
        clc
        adc ST_W
        sta fish_load,y
        tya                     ; ST_B ticks on, round the cycle
        clc
        adc ST_B
        cmp #FISH_CYCLE
        bcc :+
        sbc #FISH_CYCLE
:       tay
        cpy ST_T
        bne @t
        rts

; walk_max: A = the most fish_load holds on tick Y or any ST_B ticks on,
; round the cycle. Keeps X and Y.
walk_max:
        sty ST_T
        stz ST_M
@t:     lda fish_load,y
        cmp ST_M
        bcc :+
        sta ST_M
:       tya                     ; ST_B ticks on, round the cycle
        clc
        adc ST_B
        cmp #FISH_CYCLE
        bcc :+
        sbc #FISH_CYCLE
:       tay
        cpy ST_T
        bne @t
        lda ST_M
        rts

; ---- the rest of the step, in FISHCODE2 (FXRAM, copied by fish_init) ----
.segment "FISHCODE2"

; st_reset: the step's clock, counters, fish_load and background work
; zeroed, nothing pending (Fish! may run again in one boot).
st_reset:
        stz fish_now
        stz fish_now+1
        stz fish_now60
        stz ST_NWEED
        ldx #ST_CLEAR_END - ST_CLEAR
:       stz ST_CLEAR-1,x
        dex
        bne :-
        dex                     ; $FF: ST_BEGW and ST_BGMIN are worked out
        stx st_lastw            ; on the first step
        rts

; st_worst: when the Seaweed count changes, ST_BEGW (a begin at its worst:
; ST_BEGIN, ST_BEGWEED per Seaweed slot, FC_BEGPER per other) and ST_BGMIN
; (a useful background call: the call, listing the Seaweed, a row).
st_worst:
        lda ST_NWEED
        cmp st_lastw
        beq @rts
        sta st_lastw
        ldy #2                  ; ST_BGMIN, then ST_BEGW
@sum:   lda w_base,y
        sta RD_T
        stz RD_T+1
        lda w_weed,y
        ldx ST_NWEED
        jsr madd
        lda fish_n
        sec
        sbc ST_NWEED
        tax
        lda w_other,y
        jsr madd
        lda RD_T
        sta ST_BEGW,y
        lda RD_T+1
        sta ST_BEGW+1,y
        dey
        dey
        bpl @sum
@rts:   rts
w_base:  .byte ST_BEGIN, 0, BG_FIX
w_weed:  .byte ST_BEGWEED, 0, BG_WEED
w_other: .byte FC_BEGPER, 0, FC_BGANY

; madd: RD_T (2 bytes) += A * X. Keeps Y.
madd:   cpx #0
        beq @rts
        sta ST_M
:       lda ST_M
        jsr add_t
        dex
        bne :-
@rts:   rts

; st_begin: fish_rect_begin over FR_C0..FR_R1, paid for after (FR_LEFT
; holds ST_BEGW): ST_BEGW, less FC_BEGPER - ST_BEGFAR for each slot (not
; Seaweed) whose rows miss, and FC_BEGPER - ST_BEGMISS for each whose rows
; touch but that it didn't list.
st_begin:
        jsr fish_rect_begin
        lda ST_BEGW
        sta RD_T
        lda ST_BEGW+1
        sta RD_T+1
        lda fish_n
        sec
        sbc ST_NWEED
        sec
        sbc st_nrow
        tax
        lda #FC_BEGPER - ST_BEGFAR
        jsr msub
        lda st_nrow
        sec
        sbc rd_nlist
        tax
        lda #FC_BEGPER - ST_BEGMISS
        jsr msub
        jmp charge

; msub: RD_T (2 bytes) -= A * X.
msub:   cpx #0
        beq @rts
        sta ST_M
:       lda RD_T
        sec
        sbc ST_M
        sta RD_T
        bcs :+
        dec RD_T+1
:       dex
        bne :--
@rts:   rts

; cost_of: X = slot. Its hop's estimate in units (fish_cost, fish_costh):
; EST_FIX, FC_BEGFAR for each other slot, and its box's rows at a row's
; cost facing left at sea or over the floor, from its y (Bubbles: all at
; sea, 2 more for the rise). fish_w = the estimate / 64, rounded. Keeps X.
cost_of:
        phx
        ldy fish_kind,x
        lda fish_yl,x           ; its box's top row (but for Bubbles)
        clc
        adc fk_by,y
        sta ST_T
        lda #<EST_FIX
        sta RD_T
        lda #>EST_FIX
        sta RD_T+1
        ldx fish_n              ; the other slots
        dex
        lda #FC_BEGFAR
        jsr madd
        ldx fk_rows,y
        lda fk_role,y
        cmp #ROLE_RISE
        bne @swim
        inx                     ; a Bubble
        inx
        lda #FC_SEA_N
        jsr madd
        bra @w
@swim:  lda #FLOOR_TOP          ; rows at sea: FLOOR_TOP - top, 0..rows
        sec
        sbc ST_T
        bcs :+
        lda #0
:       cmp fk_rows,y
        bcc :+
        lda fk_rows,y
:       sta ST_T
        txa                     ; and over the floor
        sec
        sbc ST_T
        pha
        ldx ST_T
        lda #FC_SEA_M
        jsr madd
        plx
        lda #FC_FLR_M
        jsr madd
@w:     plx
        lda RD_T
        sta fish_cost,x
        clc
        adc #32
        sta ST_T
        lda RD_T+1
        sta fish_costh,x
        adc #0
        asl ST_T                ; (cost + 32) / 64
        rol a
        asl ST_T
        rol a
        sta fish_w,x
        rts

; The art's tables, frames and floor (generated). Last: it changes segments.
.include "fish_art.inc"

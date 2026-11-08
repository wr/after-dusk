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
; background job (fish_bgq). The step does nothing yet.

.include "config.inc"

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
        jmp fish_place          ; then the creatures

; ================================================================ step
fish_step:
        rts

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
mv_beats: .byte 4, 4, 5, 6
mv_dxl:   .byte <2, <-2         ; a hop: 2 dots the way it faces
mv_dxh:   .byte >2, >-2

; fish_spawn: X = slot, A = 1 to place it anywhere (init), 0 for a newcomer.
; Picks its kind (all 14 alike), frame, beat (4, 4, 5 or 6 ticks; Bubbles
; 3), heading (swimmers only; the rest face right) and place by its band. A
; newcomer swimmer enters just off a side, facing in (x = -w heading right,
; 280 heading left); a newcomer Bubble 4 rows above the floor. x anywhere:
; 0..280-w (Bubbles 4..280-w-4). A Seaweed also gets its life ((20 +
; rng_below(21)) * 60 ticks) and a sway count to start from (0-89); a
; newcomer Seaweed queues its box for the background job. Keeps X; never
; touches FR_C0..FR_R1.
fish_spawn:
        sta MV_MODE
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
        lda #3                  ; Bubbles hop every 3 ticks
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
; its frames swap; a Bubble rises 2 rows; the rest turn round 1 time in 42
; (rng_below(42) = 0), then move 2 dots the way they face. One that has
; gone (a swimmer once x < -w-2 or x > 282, a Bubble once y < -h) is
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
        lda fish_yl,x           ; a Bubble rises 2 rows
        sec
        sbc #2
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
:       ldy fish_dir,x          ; 2 dots the way it faces
        lda fish_xl,x
        clc
        adc mv_dxl,y
        sta fish_xl,x
        lda fish_xh,x
        adc mv_dxh,y
        sta fish_xh,x
        ldy fish_kind,x         ; gone once x + w + 2 < 0
        lda fk_cw,y
        sec
        adc #1
        adc fish_xl,x
        lda fish_xh,x
        adc #0
        bmi @gone
        lda fish_xh,x           ; or x > 282
        bmi @new
        lda fish_xl,x
        cmp #<283
        lda fish_xh,x
        sbc #>283
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
@rts:   rts
@full:  jsr fish_bgq_reset      ; full: the five full-width strips instead,
        ldy #4                  ; which rebuild all of FISH_BG
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

; fish_place: the rest of init. fish_count creatures placed anywhere, FISH_BG
; built (the floor and every Seaweed), the screen drawn: FISH_BG, then the
; box of each creature that isn't Seaweed. Nothing queued.
fish_place:
        jsr fish_bgq_reset      ; nothing queued
        lda fish_count          ; fish_count creatures, anywhere
        sta fish_n
        ldx #0
@spawn: cpx fish_n
        bcs :+
        lda #1
        jsr fish_spawn
        inx
        bra @spawn
:       jsr fish_bg_floor       ; FISH_BG: the floor and every Seaweed
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

; The art's tables, frames and floor (generated). Last: it changes segments.
.include "fish_art.inc"

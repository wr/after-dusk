; Fish!'s cache engine: the parts that run once, at init (included by
; fx_fish.s after fish_draw.inc, in the overlay: never written). The kernel
; bodies are made here from their column templates; the shift tables, the
; bit-reverse table and the swimmers' mirrored frames are built in aux
; memory; FISH_BG is built from the floor and every Seaweed.

.segment "FX14"
; The bodies, made at init (fish_draw_init) in page 2 from these column
; templates: 8 columns each, column 7 first, each column's code P_ST bytes,
; then a jump; the operands (L: a layer's lit dots; MI: its mask inverted)
; are patched per run.
tmpl0:  lda #0                  ; black, no layer
        sta (WRP),y
        dey
tmpl1:  lda (RDP),y             ; the floor, no layer
        sta (WRP),y
        dey
tmpl2:  lda $FFFF,x             ; black, one layer: L1 at +1
        sta (WRP),y
        dey
tmpl3:  lda (RDP),y             ; floor, one (11 bytes): MI1 +3, L1 +6
        and $FFFF,x
        ora $FFFF,x
        sta (WRP),y
        dey
tmpl4:  lda $FFFF,x             ; black, two: L1 +1, MI2 +4, L2 +7
        and $FFFF,x
        ora $FFFF,x
        sta (WRP),y
        dey
tmpl5:  lda (RDP),y             ; floor, two (17): MI1 +3, L1 +6, MI2 +9, L2 +12
        and $FFFF,x
        ora $FFFF,x
        and $FFFF,x
        ora $FFFF,x
        sta (WRP),y
        dey
tmpl6:  lda $FFFF,x             ; black, three: L1 +1, MI2 +4, L2 +7, MI3 +10, L3 +13
        and $FFFF,x
        ora $FFFF,x
        and $FFFF,x
        ora $FFFF,x
        sta (WRP),y
        dey
tmpl7:  lda (RDP),y             ; floor, three (23): MI1 +3, L1 +6, ..., MI3 +15, L3 +18
        and $FFFF,x
        ora $FFFF,x
        and $FFFF,x
        ora $FFFF,x
        and $FFFF,x
        ora $FFFF,x
        sta (WRP),y
        dey
tmpl_end:
.assert tmpl1 - tmpl0 = 5 && tmpl2 - tmpl1 = 5 && tmpl3 - tmpl2 = 6 && tmpl4 - tmpl3 = 11, error, "a template's size"
.assert tmpl5 - tmpl4 = 12 && tmpl6 - tmpl5 = 17 && tmpl7 - tmpl6 = 18 && tmpl_end - tmpl7 = 23, error, "a template's size"
tmpl_lo: .byte <tmpl0, <tmpl1, <tmpl2, <tmpl3, <tmpl4, <tmpl5, <tmpl6, <tmpl7
tmpl_hi: .byte >tmpl0, >tmpl1, >tmpl2, >tmpl3, >tmpl4, >tmpl5, >tmpl6, >tmpl7

; make_body: A = kernel (0-7), KT+1/2 = where. Its template 8 times, then a
; jump; the end (the jump) in KT+1/2 after. Keeps X.
make_body:
        tay
        lda tmpl_lo,y
        sta KT+3
        lda tmpl_hi,y
        sta KT+4
        lda k_step,y
        sta KT+5
        lda #8
        sta KT
@col:   ldy #0
:       lda (KT+3),y
        sta (KT+1),y
        iny
        cpy KT+5
        bne :-
        tya
        clc
        adc KT+1
        sta KT+1
        bcc :+
        inc KT+2
:       dec KT
        bne @col
        lda #$4C                ; jmp
        sta (KT+1)
        rts

; fish_bg_floor: all of FISH_BG built: the floor's rows copied from aux, then
; every Seaweed's box through the background job, with no budget (init,
; and after a change to the Seaweed set).
fish_bg_floor:
        lda #<FISH_BG
        sta LDST
        lda #>FISH_BG
        sta LDST+1
        lda #<__FISHFLOOR_LOAD__
        sta LSRC
        lda #>__FISHFLOOR_LOAD__
        sta LSRC+1
        ldx #192 - FLOOR_TOP
@row:   ldy #39
        jsr aux_copy
        lda LDST
        clc
        adc #40
        sta LDST
        bcc :+
        inc LDST+1
:       lda LSRC
        clc
        adc #40
        sta LSRC
        bcc :+
        inc LSRC+1
:       dex
        bne @row
        ldx #0                  ; then every Seaweed in its box
@slot:  cpx fish_n
        bcs @done
        ldy fish_kind,x
        lda fk_role,y
        cmp #ROLE_STILL
        bne @nx
        jsr fish_box            ; (a Seaweed's box is at most 6 bytes wide)
        bcc @nx
        phx
        jsr fish_bg_begin
        lda #$FF
        sta FR_LEFT
        sta FR_LEFT+1
        jsr fish_bg_rows
        plx
@nx:    inx
        bra @slot
@done:  rts
; ================================================================ init
; fish_draw_init: the transparent and empty pages, the kernel bodies and
; the pass kernels (four more of the three-layer floor body), every slot's
; cache unbuilt and its box unknown, nothing pending.
fish_draw_init:
        ldx #0
        lda #$7F
:       sta FISH_TRANSP,x
        stz FISH_ZERO,x
        inx
        bne :-
        stz KT+1                ; the bodies, BODY_STEP apart
        lda #>FISH_BODY
        sta KT+2
        ldx #0
@body:  lda KT+1
        pha
        lda KT+2
        pha
        txa
        jsr make_body
        lda KT+1
        sta k_endlo,x
        lda KT+2
        sta k_endhi,x
        pla
        sta KT+2
        pla
        clc
        adc #<BODY_STEP
        sta KT+1
        bcc :+
        inc KT+2
:       inx
        cpx #8
        bne @body
        lda #<FISH_PASS         ; the pass kernels: the three-layer floor body, four times
        sta KT+1
        lda #>FISH_PASS
        sta KT+2
        ldx #4
@pass:  lda #7
        jsr make_body
        lda KT+1                ; (the end: on past the jump)
        clc
        adc #3
        sta KT+1
        bcc :+
        inc KT+2
:       dex
        bne @pass
        ldx #FISH_MAX-1
:       stz sl_vis,x
        stz sl_lit,x
        stz sl_msk,x
        dex
        bpl :-
        stz rd_pend
        stz bj_pend
        ; fall through
; make_build_table: bq_tab, for every kind, frame and facing: what building
; its lit dots and its mask costs, in units (fish_locate copies a slot's
; four bytes): RC_BUILDFIX + rows x RC_BUILD (bc_lo/hi) and 1 for each
; source read that crosses a page (5 x rows + the source's low byte - 256,
; when positive; the mask rows start 5 x rows on).
make_build_table:
        ldx #0                  ; the kind
@kind:  stz KT+5                ; frame x 8 + left x 4
@entry: lda KT+5
        and #4
        beq @r
        lda KT+5
        and #8
        beq :+
        lda fk_m1lo,x
        bra @go
:       lda fk_m0lo,x
        bra @go
@r:     lda KT+5
        and #8
        beq :+
        lda fk_f1lo,x
        bra @go
:       lda fk_f0lo,x
@go:    sta KT+4                ; the frame's source, low byte
        clc                     ; the mask rows' crossings first (build_units writes KT)
        adc fk_r5,x
        clc
        adc fk_r5,x
        bcs :+
        lda #0
:       ldy fk_rows,x
        jsr build_units
        sta KT+3
        lda KT
        sta KT+2
        lda KT+4                ; the lit rows' crossings
        clc
        adc fk_r5,x
        bcs :+
        lda #0
:       ldy fk_rows,x
        jsr build_units
        sta KT+1
        txa                     ; the entry: kind x 16 + KT+5
        asl a
        asl a
        asl a
        asl a
        ora KT+5
        tay
        lda KT
        sta bq_tab,y
        lda KT+1
        sta bq_tab+1,y
        lda KT+2
        sta bq_tab+2,y
        lda KT+3
        sta bq_tab+3,y
        lda KT+5
        clc
        adc #4
        sta KT+5
        cmp #16
        bcc @entry
        inx
        cpx #FISH_NKIND
        bcc @kind
        rts
; build_units: A = the crossings, Y = rows: A (high) and KT (low) = the
; build's units, rounded up. Keeps X.
build_units:
        clc
        adc bc_lo,y
        sta KT
        lda bc_hi,y
        adc #0
        pha
        lda KT
        clc
        adc #15
        sta KT
        pla
        adc #0
        .repeat 4
        lsr a
        ror KT
        .endrepeat
        rts

; make_aux_tables: in aux memory, FISH_REV (entry b: b's 7 dots in the
; opposite order), FISH_SHT (page k, entry b: the dots that stay in a byte
; shifted k, (b << k) & $7F; entry 128 + b: the dots that spill into the
; next, b >> (7 - k)) and FISH_ISHT (the same, inverted, for masks).
make_aux_tables:
        sta WRCARDRAM
        ldx #127
@rev:   txa
        ldy #7
@bit:   lsr a
        rol KT
        dey
        bne @bit
        lda KT
        and #$7F
        sta FISH_REV,x
        dex
        bpl @rev
        stz RD_T                ; page pointers: SHT (RD_T), ISHT (KT+2)
        stz KT+2
        ldy #127
@b:     sty KT                  ; KT+1:KT = b << k
        stz KT+1
        lda #>FISH_SHT
        sta RD_T+1
        lda #>FISH_ISHT
        sta KT+3
        ldx #7
@k:     lda KT
        and #$7F
        sta (RD_T),y            ; entry b: the dots that stay
        eor #$7F
        sta (KT+2),y
        tya
        eor #$80
        tay
        lda KT                  ; entry 128 + b: the dots that spill
        asl a
        lda KT+1
        rol a
        sta (RD_T),y
        eor #$7F
        sta (KT+2),y
        tya
        eor #$80
        tay
        asl KT
        rol KT+1
        inc RD_T+1
        inc KT+3
        dex
        bne @k
        dey
        bpl @b
        sta WRMAINRAM
        rts

; MIROP ptr, op: op's operand = ptr, then ptr += 1.
.macro MIROP ptr, op
        lda ptr
        sta op+1
        lda ptr+1
        sta op+2
        inc ptr
        bne :+
        inc ptr+1
:
.endmacro

; mirror_art: every swimmer's frames mirrored into aux at fk_m0/fk_m1: each
; row's 5 bytes bit-reversed through FISH_REV and turned round (lc_mirror,
; patched with the rows' addresses: a frame's lit rows, then its mask rows).
; A kind narrower than 5 bytes mirrors as 5 wide: its drawing then sits
; 35 - bw dots in, which fish_locate allows for.
mirror_art:
        ldx #FISH_NKIND-1
@kind:  lda fk_role,x
        cmp #ROLE_STILL
        bcs @nxk
        lda fk_f0lo,x
        sta KT
        lda fk_f0hi,x
        sta KT+1
        lda fk_m0lo,x
        sta KT+2
        lda fk_m0hi,x
        sta KT+3
        jsr @frame
        lda fk_f1lo,x
        sta KT
        lda fk_f1hi,x
        sta KT+1
        lda fk_m1lo,x
        sta KT+2
        lda fk_m1hi,x
        sta KT+3
        jsr @frame
@nxk:   dex
        bpl @kind
        rts
@frame: ldy #1                  ; lit rows, then mask rows
@part:  phy
        MIROP KT, lcm_s4        ; the operands: src + 0..4 (read in that order
        MIROP KT, lcm_s3        ; from byte 4), dst + 0..4
        MIROP KT, lcm_s2
        MIROP KT, lcm_s1
        MIROP KT, lcm_s0
        MIROP KT+2, lcm_d0
        MIROP KT+2, lcm_d1
        MIROP KT+2, lcm_d2
        MIROP KT+2, lcm_d3
        MIROP KT+2, lcm_d4
        lda fk_rows,x
        sta CNT
        lda fk_r5,x             ; on to the mask rows: src + r5 - 5, dst + r5 - 5
        sec
        sbc #5
        clc
        adc KT
        sta KT
        bcc :+
        inc KT+1
:       lda fk_r5,x
        sec
        sbc #5
        clc
        adc KT+2
        sta KT+2
        bcc :+
        inc KT+3
:       phx
        jsr lc_mirror
        plx
        ply
        dey
        bmi :+
        jmp @part
:       rts
.segment "FX14"

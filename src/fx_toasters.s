; Effect 0: Flying Toasters. Winged toasters and slices of toast fly from
; the upper right towards the lower left: slices slowest, toasters slow or
; fast (fast with chance 2 in 3, picked each time one comes in).
;
; Drawn with page flipping: each step first shows the page drawn by the last
; one (the step begins just past a vertical blank, so the flip is not seen),
; then on the other page erases what it showed two updates ago, moves
; everything and draws it all. Each page keeps its own record of what was
; drawn on it. The first step has nothing to show yet.

.include "config.inc"

.export fx_toasters_init, fx_toasters_step
.export tst_count, tst_xf, tst_xl, tst_xh, tst_yf, tst_yl, tst_yh, tst_kind, tst_frame, tst_cls
.export cls_vxf, cls_vxi, cls_vyf, cls_vyi

.import rng_next, rng_below, sprite_tables, sprite_draw, sprite_erase, clear_page
.import show_page1, show_page2

; With everything on screen a full flap's worst update is 65,771 cycles, inside
; the 67,820 that 4 ticks allow. With objects clipped at the screen edges an
; update can reach about 93,000 and slip a frame, so the effect averages about
; 14.3 updates a second instead of 15. 7 objects are kept on purpose.
NTOAST = 4
NSLICE = 3
NOBJ   = NTOAST + NSLICE

TOAST_W = 41                    ; the drawings' cells
TOAST_H = 40
SLICE_W = 31
SLICE_H = 23

; ---- state in FXRAM: one byte per object in each array ----
tst_xf   = FXRAM                ; x, 8.8 fixed point plus a sign/high byte
tst_xl   = tst_xf + NOBJ
tst_xh   = tst_xl + NOBJ
tst_yf   = tst_xh + NOBJ        ; y, the same
tst_yl   = tst_yf + NOBJ
tst_yh   = tst_yl + NOBJ
tst_kind = tst_yh + NOBJ        ; 0 toaster, 1 slice
tst_frame = tst_kind + NOBJ     ; wing position, 0-5 into flap_ids
tst_cls  = tst_frame + NOBJ     ; 0 slice, 1 slow toaster, 2 fast toaster
; what was drawn on each page: entries 0..NOBJ-1 page 1, NOBJ.. page 2
rec_xl   = tst_cls + NOBJ
rec_xh   = rec_xl + 2 * NOBJ
rec_yl   = rec_xh + 2 * NOBJ
rec_yh   = rec_yl + 2 * NOBJ
rec_id   = rec_yh + 2 * NOBJ    ; sprite id, $FF = nothing
tst_drawn = rec_id + 2 * NOBJ   ; 1 once a page waits to be shown

I       = FXZ
BACKREC = FXZ+1                 ; 0 or NOBJ: which page's records
TMP     = FXZ+2
SPR     = FXZ+3
TMP2    = FXZ+4

.segment "FX0"
        jmp fx_toasters_init        ; the overlay's entry points
        jmp fx_toasters_step

tst_count:
        .byte NOBJ

; speed per update by class, 8.8: left, then down
cls_vxf: .byte $18, $30, $48
cls_vxi: .byte $01, $02, $03
cls_vyf: .byte $90, $1F, $AF
cls_vyi: .byte $00, $01, $01

flap_ids:
        .byte 0, 1, 2, 3, 2, 1  ; wings highest to lowest and back

; ---------------------------------------------------------------- init
fx_toasters_init:
        lda #PAGE2              ; page 1 was wiped; clear the other one
        sta PAGE
        jsr clear_page
        jsr show_page1
        jsr sprite_tables       ; the sprites' row tables, in FXRAM above our state
        ldx #NOBJ-1
@l:     lda #0
        cpx #NTOAST
        bcc :+
        lda #1
:       sta tst_kind,x
        jsr spawn_anywhere
        lda #6
        jsr rng_below
        sta tst_frame,x
        lda #$FF
        sta rec_id,x
        sta rec_id+NOBJ,x
        dex
        bpl @l
        stz tst_drawn
        rts

; ---------------------------------------------------------------- step
fx_toasters_step:
        lda tst_drawn           ; show what the last step drew
        beq @pick
        lda DISP
        bne :+
        jsr show_page2
        bra @pick
:       jsr show_page1
@pick:  lda DISP                ; draw on the page that isn't showing
        beq :+
        lda #PAGE1
        sta PAGE
        stz BACKREC
        bra @erase
:       lda #PAGE2
        sta PAGE
        lda #NOBJ
        sta BACKREC

@erase: ldx #NOBJ-1             ; erase this page's last frame
@e:     stx I
        txa
        clc
        adc BACKREC
        tay
        lda rec_id,y
        bmi @enext
        lda rec_xl,y
        sta PX
        lda rec_xh,y
        sta PX+1
        lda rec_yl,y
        sta PY
        lda rec_yh,y
        sta PY+1
        lda rec_id,y
        jsr sprite_erase
@enext: ldx I
        dex
        bpl @e

        ldx #NOBJ-1             ; move everything
:       jsr move_one
        dex
        bpl :-

        ldx #0                  ; draw in order: toasters, then slices on top
@d:     stx I
        lda tst_kind,x
        beq :+
        lda #4
        bra :++
:       ldy tst_frame,x
        lda flap_ids,y
:       sta SPR
        lda tst_xl,x
        sta PX
        lda tst_xh,x
        sta PX+1
        lda tst_yl,x
        sta PY
        lda tst_yh,x
        sta PY+1
        lda SPR
        jsr sprite_draw
        lda I                   ; remember it for this page
        clc
        adc BACKREC
        tay
        lda PX
        sta rec_xl,y
        lda PX+1
        sta rec_xh,y
        lda PY
        sta rec_yl,y
        lda PY+1
        sta rec_yh,y
        lda SPR
        sta rec_id,y
        ldx I
        inx
        cpx #NOBJ
        bne @d

        lda #1                  ; shown at the start of the next step
        sta tst_drawn
        rts

; ---------------------------------------------------------------- motion
; move_one: X = object. Moves it by its class's speed, flaps, and replaces
; it at once when it has left (x < -w or y > 192). Keeps X.
move_one:
        ldy tst_cls,x
        sec                     ; x -= speed left
        lda tst_xf,x
        sbc cls_vxf,y
        sta tst_xf,x
        lda tst_xl,x
        sbc cls_vxi,y
        sta tst_xl,x
        lda tst_xh,x
        sbc #0
        sta tst_xh,x
        clc                     ; y += speed down
        lda tst_yf,x
        adc cls_vyf,y
        sta tst_yf,x
        lda tst_yl,x
        adc cls_vyi,y
        sta tst_yl,x
        lda tst_yh,x
        adc #0
        sta tst_yh,x
        inc tst_frame,x
        lda tst_frame,x
        cmp #6
        bcc :+
        stz tst_frame,x
:
        lda tst_xh,x            ; gone off the left: x < -w?
        bpl @y
        cmp #$FF
        bne respawn
        lda tst_kind,x
        bne :+
        lda tst_xl,x
        cmp #<-TOAST_W
        bcc respawn
        bra @y
:       lda tst_xl,x
        cmp #<-SLICE_W
        bcc respawn
@y:     lda tst_yh,x            ; or off the bottom: y > 192?
        bmi @ok
        bne respawn
        lda tst_yl,x
        cmp #193
        bcs respawn
@ok:    rts

; respawn: X = object; comes in from the right (1 in 2) or the top.
respawn:
        stz tst_xf,x
        stz tst_yf,x
        jsr rng_next
        bmi @top
        lda #<280               ; x = 280
        sta tst_xl,x
        lda #>280
        sta tst_xh,x
        lda tst_kind,x          ; y = -h..110
        bne :+
        lda #TOAST_H+111
        jsr rng_below
        sec
        sbc #TOAST_H
        bra @ysigned
:       lda #SLICE_H+111
        jsr rng_below
        sec
        sbc #SLICE_H
@ysigned:
        sta tst_yl,x
        lda #0
        sbc #0
        sta tst_yh,x
        bra set_class
@top:   lda #241                ; x 60..300
        jsr rng_below
        clc
        adc #60
        sta tst_xl,x
        lda #0
        adc #0
        sta tst_xh,x
        lda tst_kind,x          ; y = -h
        bne :+
        lda #<-TOAST_H
        bra :++
:       lda #<-SLICE_H
:       sta tst_yl,x
        lda #$FF
        sta tst_yh,x
        bra set_class

; spawn_anywhere: first placement, scattered over the screen and just off
; its edges: toaster x -20..259, y -20..151; slice x -15..264, y -11..168.
; X = object.
spawn_anywhere:
        stz tst_xf,x
        stz tst_yf,x
        lda #140                ; 280 values of x: a random even plus a bit
        jsr rng_below
        asl a
        sta TMP
        lda #0
        rol a                   ; the even's 9th bit
        sta TMP2
        jsr rng_next
        and #1
        ora TMP
        sec
        ldy tst_kind,x
        sbc spawn_xoff,y
        sta tst_xl,x
        lda TMP2
        sbc #0
        sta tst_xh,x
        lda spawn_yn,y
        jsr rng_below
        sec
        ldy tst_kind,x
        sbc spawn_yoff,y
        sta tst_yl,x
        lda #0
        sbc #0
        sta tst_yh,x
        ; fall through

; set_class: X = object. Slices 0; toasters fast (2) with chance 2 in 3,
; else slow (1).
set_class:
        lda tst_kind,x
        beq :+
        stz tst_cls,x
        rts
:       lda #3
        jsr rng_below
        cmp #1                  ; rng_below's flags say nothing about A
        bcc :+
        lda #2
        sta tst_cls,x
        rts
:       lda #1
        sta tst_cls,x
        rts

spawn_xoff: .byte 20, 15        ; by kind: x = 0..279 minus this
spawn_yn:   .byte 172, 180      ; y: this many values...
spawn_yoff: .byte 20, 11        ; ...minus this

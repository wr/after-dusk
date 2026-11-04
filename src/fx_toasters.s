; Effect 0: Flying Toasters. Winged toasters and slices of toast fly from
; the upper right towards the lower left at slightly different speeds.
;
; Drawn with page flipping: each step erases what this page showed two
; steps ago, moves everything, draws it all on the hidden page, then shows
; that page. Each page keeps its own record of what was drawn on it.

.include "config.inc"

.export fx_toasters_init, fx_toasters_step
.export tst_count, tst_xl, tst_xh, tst_yl, tst_yh, tst_kind, tst_frame

.import rng_next, rng_below, sprite_draw, sprite_erase, clear_page
.import show_page1, show_page2

; 7 toasters were planned; 4 is what the IIc can draw in every step at 15
; steps a second (measured worst case about 64,000 of the 68,120 cycles in
; 4 ticks). Fewer objects at a steady speed beats more that stutter.
NTOAST = 4
NSLICE = 3
NOBJ   = NTOAST + NSLICE

; ---- state in FXRAM: one byte per object in each array ----
tst_xf   = FXRAM                ; x, 8.8 fixed point plus a sign/high byte
tst_xl   = tst_xf + NOBJ
tst_xh   = tst_xl + NOBJ
tst_yf   = tst_xh + NOBJ        ; y, the same
tst_yl   = tst_yf + NOBJ
tst_yh   = tst_yl + NOBJ
tst_vxf  = tst_yh + NOBJ        ; speed left, 8.8
tst_vxi  = tst_vxf + NOBJ
tst_vyf  = tst_vxi + NOBJ       ; speed down, 8.8
tst_vyi  = tst_vyf + NOBJ
tst_kind = tst_vyi + NOBJ       ; 0 toaster, 1 toast
tst_frame = tst_kind + NOBJ     ; flap counter
; what was drawn on each page: entries 0..NOBJ-1 page 1, NOBJ.. page 2
rec_xl   = tst_frame + NOBJ
rec_xh   = rec_xl + 2 * NOBJ
rec_yl   = rec_xh + 2 * NOBJ
rec_yh   = rec_yl + 2 * NOBJ
rec_id   = rec_yh + 2 * NOBJ    ; sprite id, $FF = nothing

I       = FXZ
BACKREC = FXZ+1                 ; 0 or NOBJ: which page's records
TMP     = FXZ+2                 ; 2
TMP2    = FXZ+4                 ; 2
SPR     = FXZ+6

.segment "CODE"

tst_count:
        .byte NOBJ

; ---------------------------------------------------------------- init
fx_toasters_init:
        lda #PAGE2              ; page 1 was wiped; clear the other one
        sta PAGE
        jsr clear_page
        jsr show_page1
        ldx #NOBJ-1
@l:     lda #0
        cpx #NTOAST
        bcc :+
        lda #1
:       sta tst_kind,x
        jsr spawn_anywhere
        jsr rng_next
        and #7
        sta tst_frame,x
        lda #$FF
        sta rec_id,x
        sta rec_id+NOBJ,x
        dex
        bpl @l
        rts

; ---------------------------------------------------------------- step
fx_toasters_step:
        lda DISP                ; draw on the page that isn't showing
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

        ldx #0                  ; draw in order, later ones on top
@d:     stx I
        lda tst_kind,x
        beq :+
        lda #3
        bra :++
:       lda tst_frame,x
        lsr a
        and #3
        tay
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

        lda PAGE                ; show what we drew
        cmp #PAGE2
        beq :+
        jmp show_page1
:       jmp show_page2

flap_ids:
        .byte 0, 1, 2, 1        ; wing up, middle, down, middle

; ---------------------------------------------------------------- motion
; move_one: X = object. Keeps X.
move_one:
        sec                     ; x -= speed
        lda tst_xf,x
        sbc tst_vxf,x
        sta tst_xf,x
        lda tst_xl,x
        sbc tst_vxi,x
        sta tst_xl,x
        lda tst_xh,x
        sbc #0
        sta tst_xh,x
        clc                     ; y += speed down
        lda tst_yf,x
        adc tst_vyf,x
        sta tst_yf,x
        lda tst_yl,x
        adc tst_vyi,x
        sta tst_yl,x
        lda tst_yh,x
        adc #0
        sta tst_yh,x
        inc tst_frame,x

        lda tst_xh,x            ; gone off the left (x < -42)?
        bpl @y
        cmp #$FF
        bne respawn
        lda tst_xl,x
        cmp #<-42
        bcc respawn
@y:     lda tst_yh,x            ; or off the bottom (y > 194)?
        bmi @ok
        bne respawn
        lda tst_yl,x
        cmp #195
        bcs respawn
@ok:    rts

; respawn: X = object; comes back in from the right (60%) or the top.
respawn:
        stz tst_xf,x
        stz tst_yf,x
        jsr rng_next
        cmp #154
        bcs @top
        lda #40                 ; x 280-319
        jsr rng_below
        clc
        adc #<280
        sta tst_xl,x
        lda #>280
        adc #0
        sta tst_xh,x
        lda #135                ; y -30..104
        jsr rng_below
        sec
        sbc #30
        sta tst_yl,x
        lda #0
        sbc #0
        sta tst_yh,x
        jmp set_speed
@top:   lda #230                ; x 70-299
        jsr rng_below
        clc
        adc #70
        sta tst_xl,x
        lda #0
        adc #0
        sta tst_xh,x
        lda #20                 ; y -40..-59
        jsr rng_below
        sta TMP
        lda #<-40
        sec
        sbc TMP
        sta tst_yl,x
        lda #$FF
        sbc #0
        sta tst_yh,x
        jmp set_speed

; spawn_anywhere: first placement, scattered over the screen. X = object.
spawn_anywhere:
        stz tst_xf,x
        stz tst_yf,x
        lda #250                ; x -10..239
        jsr rng_below
        sec
        sbc #10
        sta tst_xl,x
        lda #0
        sbc #0
        sta tst_xh,x
        lda #170                ; y -20..149
        jsr rng_below
        sec
        sbc #20
        sta tst_yl,x
        lda #0
        sbc #0
        sta tst_yh,x
        ; fall through

; set_speed: X = object. Toasters 1.5-2.5 dots per step, toast 1.2-2.0;
; down at 0.5625 of that.
set_speed:
        lda tst_kind,x
        bne @toast
        lda #250
        jsr rng_below
        clc
        adc #$80
        sta tst_vxf,x
        lda #1
        adc #0
        sta tst_vxi,x
        bra @down
@toast: lda #205
        jsr rng_below
        clc
        adc #$33
        sta tst_vxf,x
        lda #1
        adc #0
        sta tst_vxi,x
@down:  lda tst_vxi,x           ; TMP = speed / 2
        lsr a
        sta TMP+1
        lda tst_vxf,x
        ror a
        sta TMP
        lda TMP+1               ; TMP2 = speed / 16
        sta TMP2+1
        lda TMP
        sta TMP2
        ldy #3
:       lsr TMP2+1
        ror TMP2
        dey
        bne :-
        clc
        lda TMP
        adc TMP2
        sta tst_vyf,x
        lda TMP+1
        adc TMP2+1
        sta tst_vyi,x
        rts

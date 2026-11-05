; Effect 8: Rose, by the original After Dark Rose's method. Each step draws
; 16 big 2 x 2 dots, k = 1..16, u = 22.5k degrees:
;   x = 140 + floor(1.1 C (B sin(A u) + sin(t + u)))
;   y =  96 + floor(    C (B cos(A u) + cos(t + u)))
; so each dot circles (radius C) round its own centre, and t turns 1.5
; degrees a step (240 to a turn). sin(A u) comes from a 128-step table: u is
; 8k 128ths of a turn, so its index is floor(8 k A) & 127.
; A is 0, 1, 4, 9 or 16, B one of 64 values from -1.28 to 1.24, C one of 32
; sizes up to 4/9 of the half-height; all three glide in a straight line to
; new random values over 250 steps, then pick again. C starts at 0. The last
; 720 dots stay (45 steps): before each new dot is drawn, the one it
; replaces is rubbed out. Drawn straight onto page 1.

.include "config.inc"

.export fx_rose_init, fx_rose_step
.export rose_ring, rose_slot, rose_full, rose_n, rose_t, rose_from, rose_to
.export rose_curl, rose_curh, rose_rem

.import rng_below, show_page1, vbl_poll
.import row_lo, row_hi, xbyte_lo, xbit_lo

DOTS    = 16                    ; dots a step
SLOTS   = 45                    ; steps kept: 720 dots
GLIDE   = 250                   ; steps from one value to the next
STEPS   = 240                   ; t's steps to a turn

; The gliding values, each a whole number plus 250ths so the glide is exact:
GA = 0                          ; 8 A (the angle index's step from dot to dot)
GB = 1                          ; B, signed, 8192 = 1
GC = 2                          ; C, 8.8 dots (x 256/255, see gen_rose.py)
GX = 3                          ; 1.1 C, likewise

; ---- state in FXRAM ----
rose_ring  = FXRAM              ; 45 x 32: the kept dots, a step's 16 (x, y)
rose_txl   = FXRAM + SLOTS * DOTS * 2   ; 16: 1.1 C sin(t + 22.5 j), 8.8
rose_txh   = rose_txl + 16
rose_tyl   = rose_txh + 16      ; 16: C sin(t + 22.5 j), 8.8
rose_tyh   = rose_tyl + 16
rose_curl  = rose_tyh + 16      ; 4: each value now, whole part
rose_curh  = rose_curl + 4
rose_rem   = rose_curh + 4      ; 4: ... and its 250ths
rose_dwl   = rose_rem + 4       ; 4: its step, whole part (signed)
rose_dwh   = rose_dwl + 4
rose_dr    = rose_dwh + 4       ; 4: ... and its 250ths
rose_tvl   = rose_dr + 4        ; 4: its target
rose_tvh   = rose_tvl + 4
rose_from  = rose_tvh + 4       ; 3: table indices of A, B, C at the glide's start
rose_to    = rose_from + 3      ; 3: ... and at its end
rose_n     = rose_to + 3        ; steps into the glide, 0-249
rose_t     = rose_n + 1         ; t, 0-239
rose_slot  = rose_t + 1         ; the ring's next step slot, 0-44
rose_full  = rose_slot + 1      ; step slots filled, 0-45

; ---- zero page ----
ML   = FXZ                      ; mul: the 16-bit multiplicand
MH   = FXZ+1
MF   = FXZ+2                    ; ... the multiplier, then the product's low byte
PM   = FXZ+3                    ; ... the product's middle byte
CBL  = FXZ+4                    ; C |B|, 8.8
CBH  = FXZ+5
CBXL = FXZ+6                    ; 1.1 C |B|
CBXH = FXZ+7
ABL  = FXZ+8                    ; |B|
ABH  = FXZ+9
SGNB = FXZ+10                   ; $80 when B < 0
ACCW = FXZ+11                   ; k x 8 A: whole part (mod 256)...
ACCR = FXZ+12                   ; ... and 250ths
K    = FXZ+13                   ; the dot, 1-16
RO   = FXZ+14                   ; its (x, y) in the ring slot, 0-30
RP   = FXZ+15                   ; 2: the ring slot
NX   = FXZ+17                   ; the new dot
NY   = FXZ+18
IDX  = FXZ+19                   ; its angle index
TL   = FXZ+20                   ; a signed 8.8 term
TH   = FXZ+21
P1   = FXZ+22                   ; mulb: the product's bytes 1 and 2
P2   = FXZ+23
TA   = FXZ+24                   ; t + 15 j, 0-239
TM   = FXZ+25                   ; its sine's magnitude
J    = FXZ+26
ROW0 = FXZ+27                   ; 2: the dot's top row
ROW1 = FXZ+29                   ; 2: its bottom row
MASK = FXZ+31

.segment "FX8"
        jmp fx_rose_init        ; the overlay's entry points
        jmp fx_rose_step

; ================================================================ init
fx_rose_init:
        jsr show_page1
        stz rose_n
        stz rose_t
        stz rose_slot
        stz rose_full
        lda #5                  ; A and B start anywhere, C at 0
        jsr rng_below
        sta rose_to
        lda #64
        jsr rng_below
        sta rose_to+1
        stz rose_to+2
        jsr targets
        ; fall through: start the first glide from there

; glide: the targets are reached; they become the start, and new ones are
; picked.
glide:  stz rose_n
        ldx #2
:       lda rose_to,x
        sta rose_from,x
        dex
        bpl :-
        ldx #3
:       lda rose_tvl,x
        sta rose_curl,x
        lda rose_tvh,x
        sta rose_curh,x
        stz rose_rem,x
        dex
        bpl :-
        lda #5                  ; new targets
        jsr rng_below
        sta rose_to
        lda #64
        jsr rng_below
        sta rose_to+1
        lda #32
        jsr rng_below
        sta rose_to+2
        jsr targets
        ldx #3                  ; each value's step: (target - now) / 250,
@each:  sec                     ; floored, and the 250ths left over
        lda rose_tvl,x
        sbc rose_curl,x
        sta TL
        lda rose_tvh,x
        sbc rose_curh,x
        sta TH
        bpl @pos
        jsr neg_t               ; down: divide the size...
        jsr div250
        tay
        lda TL                  ; ...then whole = -q - 1 = ~q, 250ths = 250 - r
        eor #$FF
        sta rose_dwl,x
        lda TH
        eor #$FF
        sta rose_dwh,x
        tya
        beq @exact
        eor #$FF                ; 250 - r = 251 + ~r
        clc
        adc #251
        sta rose_dr,x
        bra @next
@exact: inc rose_dwl,x          ; r = 0: whole = -q, nothing left over
        bne :+
        inc rose_dwh,x
:       stz rose_dr,x
        bra @next
@pos:   jsr div250
        sta rose_dr,x
        lda TL
        sta rose_dwl,x
        lda TH
        sta rose_dwh,x
@next:  dex
        bpl @each
        rts

; targets: each value's target, from the tables.
targets:
        ldx rose_to
        lda rose_a8,x
        sta rose_tvl+GA
        stz rose_tvh+GA
        ldx rose_to+1
        lda rose_bl,x
        sta rose_tvl+GB
        lda rose_bh,x
        sta rose_tvh+GB
        ldx rose_to+2
        lda rose_cl,x
        sta rose_tvl+GC
        lda rose_ch,x
        sta rose_tvh+GC
        lda rose_cxl,x
        sta rose_tvl+GX
        lda rose_cxh,x
        sta rose_tvh+GX
        rts

; div250: TL/TH (unsigned) /= 250; A = the remainder. Keeps X.
div250: lda #0
        ldy #16
@bit:   asl TL
        rol TH
        rol a
        bcs @sub                ; 256 or more
        cmp #GLIDE
        bcc @no
@sub:   sbc #GLIDE              ; (carry is set either way)
        inc TL
@no:    dey
        bne @bit
        rts

; neg_t: TL/TH = -TL/TH.
neg_t:  sec
        lda #0
        sbc TL
        sta TL
        lda #0
        sbc TH
        sta TH
        rts

; mul: A x ML/MH (unsigned) -> A (high), PM, MF (low). Keeps X.
mul:    lsr a
        sta MF
        lda #0
        sta PM
        .repeat 8
        bcc :+
        tay
        clc
        lda PM
        adc ML
        sta PM
        tya
        adc MH
:       ror a
        ror PM
        ror MF
        .endrepeat
        rts

; mulb: TL/TH = ML/MH x |B| / 8192.
mulb:   lda ABL
        jsr mul
        sta P2
        lda PM
        sta P1
        lda ABH
        jsr mul                 ; this one's three bytes go one byte up
        tay
        clc
        lda P1
        adc MF
        sta P1
        lda P2
        adc PM
        sta P2
        tya
        adc #0
        .repeat 3               ; bytes 1-3, three bits up, are the top 16
        asl P1                  ; bits of the product / 8192
        rol P2
        rol a
        .endrepeat
        sta TH
        lda P2
        sta TL
        rts

; ================================================================ step
fx_rose_step:
        jsr vbl_poll
        ; B's sign and size, and C |B|, 1.1 C |B|
        lda rose_curl+GB
        sta ABL
        lda rose_curh+GB
        sta ABH
        and #$80
        sta SGNB
        beq :+
        sec
        lda #0
        sbc ABL
        sta ABL
        lda #0
        sbc ABH
        sta ABH
:       lda rose_curl+GC
        sta ML
        lda rose_curh+GC
        sta MH
        jsr mulb
        lda TL
        sta CBL
        lda TH
        sta CBH
        lda rose_curl+GX
        sta ML
        lda rose_curh+GX
        sta MH
        jsr mulb
        lda TL
        sta CBXL
        lda TH
        sta CBXH

        ; C sin(t + 22.5 j) and 1.1 C sin(t + 22.5 j) for j = 0-15: eight
        ; products, and their negatives half a turn on.
        jsr vbl_poll
        lda rose_t
        sta TA
        ldx #0
@tj:    ldy TA
        lda rose_s240,y
        sta TM
        lda rose_curl+GC
        sta ML
        lda rose_curh+GC
        sta MH
        lda TM
        jsr mul
        jsr signed
        lda TL
        sta rose_tyl,x
        lda TH
        sta rose_tyh,x
        jsr neg_t
        lda TL
        sta rose_tyl+8,x
        lda TH
        sta rose_tyh+8,x
        lda rose_curl+GX
        sta ML
        lda rose_curh+GX
        sta MH
        lda TM
        jsr mul
        jsr signed
        lda TL
        sta rose_txl,x
        lda TH
        sta rose_txh,x
        jsr neg_t
        lda TL
        sta rose_txl+8,x
        lda TH
        sta rose_txh+8,x
        lda TA                  ; 22.5 degrees on
        clc
        adc #15
        cmp #STEPS
        bcc :+
        sbc #STEPS
:       sta TA
        inx
        cpx #8
        bne @tj

        ; the ring slot this step fills: slot x 32
        lda rose_slot
        lsr a
        lsr a
        lsr a
        clc
        adc #>rose_ring
        sta RP+1
        lda rose_slot
        asl a
        asl a
        asl a
        asl a
        asl a
        sta RP                  ; (rose_ring is page-aligned)
        stz RO
        stz ACCW
        stz ACCR
        lda #1
        sta K

@dot:   jsr vbl_poll
        clc                     ; k x 8 A, a whole number plus 250ths
        lda ACCR
        adc rose_rem+GA
        bcs @over
        cmp #GLIDE
        bcc @in
@over:  sbc #GLIDE
        sec
@in:    sta ACCR
        lda ACCW
        adc rose_curl+GA
        sta ACCW
        and #127
        sta IDX
        ; x = 140 + 1.1 C B sin(A u) + 1.1 C sin(t + u)
        tay
        lda CBXL
        sta ML
        lda CBXH
        sta MH
        lda rose_s128,y
        jsr mul
        sta TH
        lda PM
        sta TL
        lda IDX                 ; negative in the second half turn, and
        asl a                   ; when B is
        eor SGNB
        bpl :+
        jsr neg_t
:       lda K
        and #15
        tax
        clc
        lda TL
        adc rose_txl,x
        lda TH
        adc rose_txh,x
        clc
        adc #140
        sta NX
        ; y = 96 + C B cos(A u) + C cos(t + u), the cosines a quarter turn on
        lda IDX
        clc
        adc #32
        and #127
        sta IDX
        tay
        lda CBL
        sta ML
        lda CBH
        sta MH
        lda rose_s128,y
        jsr mul
        sta TH
        lda PM
        sta TL
        lda IDX
        asl a
        eor SGNB
        bpl :+
        jsr neg_t
:       lda K
        clc
        adc #4
        and #15
        tax
        clc
        lda TL
        adc rose_tyl,x
        lda TH
        adc rose_tyh,x
        clc
        adc #96
        sta NY

        lda rose_full           ; rub out the dot this one replaces
        cmp #SLOTS
        bne @keep
        ldy RO
        lda (RP),y
        tax
        iny
        lda (RP),y
        tay
        jsr dot_clear
@keep:  ldy RO                  ; keep the new one, and draw it
        lda NX
        sta (RP),y
        iny
        lda NY
        sta (RP),y
        iny
        sty RO
        ldx NX
        ldy NY
        jsr dot_set
        inc K
        lda K
        cmp #DOTS + 1
        beq :+
        jmp @dot

:       lda rose_full           ; the slot is filled
        cmp #SLOTS
        beq :+
        inc rose_full
:       ldx rose_slot
        inx
        cpx #SLOTS
        bne :+
        ldx #0
:       stx rose_slot
        ldx rose_t              ; t turns on
        inx
        cpx #STEPS
        bne :+
        ldx #0
:       stx rose_t

        ldx #3                  ; each value glides on
@g:     clc
        lda rose_rem,x
        adc rose_dr,x
        bcs @gover
        cmp #GLIDE
        bcc @gin
@gover: sbc #GLIDE
        sec
@gin:   sta rose_rem,x
        lda rose_curl,x
        adc rose_dwl,x
        sta rose_curl,x
        lda rose_curh,x
        adc rose_dwh,x
        sta rose_curh,x
        dex
        bpl @g
        inc rose_n              ; at the end, new targets
        lda rose_n
        cmp #GLIDE
        bne :+
        jmp glide
:       rts

; signed: TL/TH = A/PM (mul's top 16 bits), negative when sin(TA) is
; (TA in the second half turn). Keeps X.
signed: sta TH
        lda PM
        sta TL
        lda TA
        cmp #STEPS / 2
        bcc :+
        jmp neg_t
:       rts

; ================================================================ dots
; dot_set / dot_clear: the 2 x 2 dot with its top-left at x = X (0-254),
; y = Y (0-190), on page 1.
.macro DOT apply
        .local split
        lda row_lo,y
        sta ROW0
        lda row_hi,y
        sta ROW0+1
        lda row_lo+1,y
        sta ROW1
        lda row_hi+1,y
        sta ROW1+1
        ldy xbyte_lo,x
        lda xbit_lo,x
        cmp #$40
        beq split
        sta MASK                ; x and x + 1 in the same byte
        asl a
        ora MASK
        jmp apply
split:  lda #$40                ; x is the byte's last dot, x + 1 the next's first
        jsr apply
        iny
        lda #$01
        jmp apply
.endmacro

dot_set:   DOT apply1
dot_clear: DOT apply0

; apply1 / apply0: set / clear the dots A in byte Y of both rows.
apply1: sta MASK
        lda (ROW0),y
        ora MASK
        sta (ROW0),y
        lda (ROW1),y
        ora MASK
        sta (ROW1),y
        rts
apply0: eor #$7F
        sta MASK
        lda (ROW0),y
        and MASK
        sta (ROW0),y
        lda (ROW1),y
        and MASK
        sta (ROW1),y
        rts

.include "rose_tables.inc"

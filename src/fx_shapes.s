; Effect 10: Shapes, after the original (After Dark 2, Mode: Mixed, black
; and white). One shape a step, 20 a second: a filled rectangle, oval or
; triangle, 10-140 dots wide and 8-96 tall, its box's corner anywhere from
; (-35, -35) to (279, 191), so shapes run off the edges. Half are opaque
; (every dot of the shape set or cleared by a grey dither, level 0-16), half
; see-through (only the lit dots go down, level 2-16). Shapes pile up on the
; cleared screen; nothing takes them away. Drawn straight onto page 1.
;
; Each shape must be drawn within its 3 ticks (50,790 cycles), so the
; biggest are left out: sizes with h (w + 161) over 13,851 are picked again.
; A row costs about as much as 161 + w dots, so that keeps the worst shape
; under 90% of the time: 81 tall at most when 10 wide, 59 when 70 wide, 50
; when 115 wide and 46 when 140 wide.
;
; Every dot is exactly the sample's: a dot (x, y) of the box is in the oval
; when (2(x - x0) - w)^2 h^2 + (2(y - y0) - h)^2 w^2 <= w^2 h^2, and in the
; triangle when its centre (x + 1/2, y + 1/2) is. Each row is one pspan run.

.include "config.inc"

.export fx_shapes_init, fx_shapes_step, sh_pick, sh_draw
.export sh_kind, sh_x0, sh_y0, sh_w, sh_h, sh_mode, sh_lev, sh_ax, sh_bx, sh_cx, sh_by

.import rng_next, rng_below, pspan, show_page1, vbl_poll

RECT    = 0
OVAL    = 1
TRI     = 2
WPAD    = 161                   ; a row costs about as much as WPAD + w dots
HWMAX   = 13851                 ; so h (w + WPAD) at most this fits 3 ticks

; ---- state in FXRAM: the shape being drawn ----
sh_kind = FXRAM                 ; RECT, OVAL or TRI
sh_x0   = sh_kind + 1           ; 2: its box, signed
sh_y0   = sh_x0 + 2             ; 2
sh_w    = sh_y0 + 2             ; 10-140
sh_h    = sh_w + 1              ; 8-96
sh_mode = sh_h + 1              ; 0 opaque, 1 see-through (pspan's PCOL)
sh_lev  = sh_mode + 1           ; grey level
sh_ax   = sh_lev + 1            ; 2: triangle: A = (ax, y0) on the top edge,
sh_bx   = sh_ax + 2             ; 2: B = (bx, by) on a side,
sh_cx   = sh_bx + 2             ; 2: C = (cx, y0 + h) at a bottom corner
sh_by   = sh_cx + 2             ; 2

; ---- zero page ----
NR    = FXZ                     ; rows left
TMP   = FXZ+1                   ; 2
TMP2  = FXZ+3
HOOK  = FXZ+4                   ; 2: the kind's work for each row
H2    = FXZ+6                   ; 2: oval: h^2
TQ    = FXZ+8                   ; 2: t = w^2 (h^2 - v^2) / h^2 for this pair:
TR    = FXZ+10                  ; 2:   whole part and remainder (in 1/h^2)
DQ    = FXZ+12                  ; 2: what t gains to the next pair
DR    = FXZ+14                  ; 2
DDQ   = FXZ+16                  ; 2: and what that loses each pair
DDR   = FXZ+18                  ; 2
UU    = FXZ+20                  ; the pair's |u| at most: |u|^2 <= t
SS    = FXZ+21                  ; 2: |u|^2
NS    = FXZ+23                  ; 2: (|u| + 2)^2
PYT   = FXZ+25                  ; 2: the pair's top row
PYB   = FXZ+27                  ; 2: and bottom row
QQ    = FXZ+29                  ; pair: rows q and h - q of the box
TB    = FXZ+6                   ; 2: triangle: rows until B's row, and b = by - y0
MA    = FXZ+30                  ; 2: mul16
MB    = FXZ+32                  ; 2
PROD  = FXZ+34                  ; 4: product, and div32's dividend
DVD   = PROD
DVS   = FXZ+38                  ; 2: div32's divisor
SGN   = FXZ+40                  ; fdiv
EPX   = FXZ+41                  ; 2: edge_init: the two ends' x
EQX   = FXZ+43                  ; 2
EDX   = FXZ+45                  ; 2
EDY   = FXZ+47
ED    = FXZ+48                  ; two triangle edges, 7 bytes each (slot X):
E_XL  = ED                      ; x of the edge at this row's centre, rounded
E_XH  = ED+1                    ;   down,
E_R   = ED+2                    ; and what was rounded off, in 1/D of a dot
E_D   = ED+3                    ; D = 2 x the edge's height
E_SL  = ED+4                    ; x moves a row: SH:SL whole dots and
E_SH  = ED+5                    ;   SR / D
E_SR  = ED+6
ESZ   = 7

; EDGE_STEP slot: one edge down a row: x += its step, and one dot more when
; the remainders add up to D.
.macro EDGE_STEP n
        .local wrap, ok
        clc
        lda E_XL+n
        adc E_SL+n
        sta E_XL+n
        lda E_XH+n
        adc E_SH+n
        sta E_XH+n
        clc
        lda E_R+n
        adc E_SR+n
        bcs wrap
        cmp E_D+n
        bcc ok
wrap:   sbc E_D+n               ; (the carry is set)
        inc E_XL+n
        bne ok
        inc E_XH+n
ok:     sta E_R+n
.endmacro

.segment "FX10"
        jmp fx_shapes_init      ; the overlay's entry points
        jmp fx_shapes_step

; ================================================================ init
fx_shapes_init:
        jmp show_page1

; ================================================================ step
fx_shapes_step:
        jsr sh_pick
        jmp sh_draw

; ================================================================ pick
; sh_pick: a new random shape, as the sample picks it.
sh_pick:
        lda #3
        jsr rng_below
        sta sh_kind
@size:  lda #131                ; w = 10-140
        jsr rng_below
        clc
        adc #10
        sta sh_w
        lda #89                 ; h = 8-96
        jsr rng_below
        clc
        adc #8
        sta sh_h
        sta TMP2                ; too big to draw in time? again:
        clc                     ; PROD = h (w + WPAD), h under 128
        lda sh_w
        adc #<WPAD
        sta MA
        lda #>WPAD
        adc #0
        sta MA+1
        stz PROD
        stz PROD+1
:       lsr TMP2
        bcc :+
        clc
        lda PROD
        adc MA
        sta PROD
        lda PROD+1
        adc MA+1
        sta PROD+1
:       asl MA
        rol MA+1
        lda TMP2
        bne :--
        lda PROD
        cmp #<(HWMAX + 1)
        lda PROD+1
        sbc #>(HWMAX + 1)
        bcs @size
@x:     jsr rng_next            ; x0 = -35 to 279: 0-314, less 35
        and #1
        tax
        jsr rng_next
        cpx #0
        beq :+
        cmp #315 - 256
        bcs @x
:       sec
        sbc #35
        sta sh_x0
        txa
        sbc #0
        sta sh_x0+1
        lda #227                ; y0 = -35 to 191
        jsr rng_below
        sec
        sbc #35
        sta sh_y0
        lda #0
        sbc #0
        sta sh_y0+1
        jsr rng_next            ; opaque or see-through, half and half
        asl a
        lda #0
        rol a
        sta sh_mode
        bne :+
        lda #17                 ; opaque: level 0-16
        jsr rng_below
        bra @lev
:       lda #15                 ; see-through: 2-16
        jsr rng_below
        clc
        adc #2
@lev:   sta sh_lev
        lda sh_kind
        cmp #TRI
        beq :+
        rts
:       ; the triangle: A on the top edge at a random x, B on the right edge
        ; half to all of the way down, C at the bottom left; each corner then
        ; mirrored left to right at random (x -> 2 x0 + w - x)
        lda sh_w
        jsr rng_below
        clc
        adc sh_x0
        sta sh_ax
        lda sh_x0+1
        adc #0
        sta sh_ax+1
        clc
        lda sh_x0
        adc sh_w
        sta sh_bx
        lda sh_x0+1
        adc #0
        sta sh_bx+1
        lda sh_x0
        sta sh_cx
        lda sh_x0+1
        sta sh_cx+1
        lda sh_x0               ; TMP = 2 x0 + w
        asl a
        sta TMP
        lda sh_x0+1
        rol a
        sta TMP+1
        clc
        lda TMP
        adc sh_w
        sta TMP
        bcc :+
        inc TMP+1
:       ldx #4                  ; C, B, A
@m:     jsr rng_next
        bpl @keep
        sec
        lda TMP
        sbc sh_ax,x
        sta sh_ax,x
        lda TMP+1
        sbc sh_ax+1,x
        sta sh_ax+1,x
@keep:  dex
        dex
        bpl @m
        lda sh_h                ; by = y0 + ceil(h/2) + 0 to floor(h/2) - 1
        lsr a
        sta TMP2
        adc #0
        sta TMP
        lda TMP2
        jsr rng_below
        clc
        adc TMP
        clc
        adc sh_y0
        sta sh_by
        lda sh_y0+1
        adc #0
        sta sh_by+1
@done:  rts

; ================================================================ draw
; sh_draw: draw the shape in sh_*.
sh_draw:
        lda #PAGE1
        sta PAGE
        lda sh_mode
        sta PCOL
        lda sh_y0
        sta PY
        lda sh_y0+1
        sta PY+1
        lda sh_h
        sta NR
        lda sh_kind
        cmp #OVAL
        bne :+
        jmp oval
:       bcs tri_setup
        ; fall through

; ---------------------------------------------------------------- rectangle
        lda sh_x0               ; every row is the whole box
        sta PX
        lda sh_x0+1
        sta PX+1
        clc
        lda sh_x0
        adc sh_w
        tax
        lda sh_x0+1
        adc #0
        tay
        txa
        bne :+
        dey
:       dec a
        sta PX2
        sty PX2+1
        lda #<no_hook
        ldx #>no_hook
        ; fall through

; rows: the rows of the box from the top, each one run from PX to PX2 after
; the hook at X:A has had its turn (every row, those above the screen too).
rows:   sta HOOK
        stx HOOK+1
@row:   jsr rows_hook
        lda sh_lev
        jsr pspan               ; (nothing, quickly, for rows off the screen)
        lda NR                  ; count blanks every 4 rows (a row is under
        and #3                  ; 1,000 cycles)
        bne :+
        jsr vbl_poll
:       dec NR
        beq no_hook
        inc PY
        bne :+
        inc PY+1
:       lda PY+1
        bne @row                ; still above the screen
        lda PY
        cmp #192
        bcc @row
no_hook:
        rts
rows_hook:
        jmp (HOOK)

; ---------------------------------------------------------------- triangle
; Each row's dots have centres between the two edges the row's centre line
; crosses: A to C, and A to B above B, B to C below. An edge from (px, py)
; down to (qx, qy) crosses row y's centre at x = px + (n dx - dy) / D + 1/2,
; n = 2(y - py) + 1, dx = qx - px, dy = qy - py, D = 2 dy; the dot just right
; of it is ceil, the one just left floor, of x - 1/2. Kept exactly, a whole
; part and a remainder in 1/D, stepped once a row.
tri_setup:
        ldx #0                  ; A to C
        lda sh_cx
        sta EQX
        lda sh_cx+1
        sta EQX+1
        lda sh_h
        jsr edge_from_a
        ldx #ESZ                ; A to B
        lda sh_bx
        sta EQX
        lda sh_bx+1
        sta EQX+1
        sec
        lda sh_by
        sbc sh_y0
        sta TB                  ; rows until B's
        sta TB+1
        jsr edge_from_a
        ; The edges only meet at A and C, so the side B is on (A to B, then
        ; B to C) stays left or right of A to C all the way down: left when
        ; A to B slopes less (x a row: whole part, then remainder / D).
        lda E_SL+ESZ
        cmp E_SL
        lda E_SH+ESZ
        sbc E_SH
        bvc :+
        eor #$80
:       bmi @left
        lda E_SL+ESZ
        cmp E_SL
        bne @right
        lda E_SH+ESZ
        cmp E_SH
        bne @right
        lda E_SR+ESZ            ; same whole part: SR(AB) D(AC) < SR(AC) D(AB)?
        sta MA
        lda E_D
        sta MB
        stz MA+1
        stz MB+1
        jsr mul16
        lda PROD
        sta TMP
        lda PROD+1
        sta TMP+1
        lda E_SR
        sta MA
        lda E_D+ESZ
        sta MB
        jsr mul16
        lda TMP
        cmp PROD
        lda TMP+1
        sbc PROD+1
        bcc @left
@right: lda #<tri_br
        ldx #>tri_br
        jmp rows
@left:  lda #<tri_bl
        ldx #>tri_bl
        jmp rows

; ---------------------------------------------------------------- oval
; Row q of the box has v = 2q - h, and its dots u = 2(x - x0) - w, as odd or
; even as w, with u^2 <= t = w^2 (h^2 - v^2) / h^2 = w^2 4q(h - q) / h^2.
; Rows q and h - q are the same, so they go in pairs from the top and bottom
; in, and t only grows: t and what it gains each pair are kept exactly as
; whole parts and remainders in 1/h^2.
oval:
        lda sh_h                ; H2 = h^2
        sta MA
        sta MB
        stz MA+1
        stz MB+1
        jsr mul16
        lda PROD
        sta H2
        sta DVS
        lda PROD+1
        sta H2+1
        sta DVS+1
        lda sh_w                ; w^2...
        sta MA
        sta MB
        stz MA+1
        stz MB+1
        jsr mul16
        lda PROD                ; ...x 8, / h^2: what t's gain loses a pair
        sta MA
        lda PROD+1
        sta MA+1
        ldx #3
:       asl PROD
        rol PROD+1
        rol PROD+2
        dex
        bne :-
        jsr div32
        lda DVD
        sta DDQ
        lda DVD+1
        sta DDQ+1
        lda DVD+2
        sta DDR
        lda DVD+3
        sta DDR+1
        lda sh_h                ; w^2 x 4 (h - 1), / h^2: t's first gain
        dec a
        asl a
        asl a
        sta MB
        lda #0
        rol a
        sta MB+1
        jsr mul16
        jsr div32
        lda DVD
        sta DQ
        lda DVD+1
        sta DQ+1
        lda DVD+2
        sta DR
        lda DVD+3
        sta DR+1
        stz TQ                  ; row 0: t = 0
        stz TQ+1
        stz TR
        stz TR+1
        lda sh_w                ; |u| starts as small as it can be: 0 or 1
        and #1
        sta UU
        sta SS
        stz SS+1
        asl a                   ; (|u| + 2)^2 = |u|^2 + 4|u| + 4
        asl a
        sec
        adc SS
        adc #3
        sta NS
        stz NS+1
        stz QQ
        lda sh_y0               ; the pair's rows: y0 + q and y0 + h - q
        sta PYT
        lda sh_y0+1
        sta PYT+1
        clc
        lda sh_y0
        adc sh_h
        sta PYB
        lda sh_y0+1
        adc #0
        sta PYB+1

@pair:  lda TQ                  ; |u| two bigger while (|u| + 2)^2 <= t
        cmp NS
        lda TQ+1
        sbc NS+1
        bcc @fit
        lda NS
        sta SS
        lda NS+1
        sta SS+1
        inc UU
        inc UU
        lda UU                  ; NS += 4|u| + 4
        stz TMP+1
        asl a
        rol TMP+1
        asl a
        rol TMP+1
        adc #4
        bcc :+
        inc TMP+1
:       clc
        adc NS
        sta NS
        lda TMP+1
        adc NS+1
        sta NS+1
        bra @pair
@fit:   lda TQ                  ; even the smallest |u| too big: no dots
        cmp SS
        lda TQ+1
        sbc SS+1
        bcc @next
@span:  sec                     ; PX = x0 + (w - |u|) / 2
        lda sh_w
        sbc UU
        lsr a
        clc
        adc sh_x0
        sta PX
        lda sh_x0+1
        adc #0
        sta PX+1
        lda sh_w                ; PX2 = x0 + (w + |u|) / 2, inside the box
        clc
        adc UU
        ror a
        cmp sh_w
        bcc :+
        dec a
:       clc
        adc sh_x0
        sta PX2
        lda sh_x0+1
        adc #0
        sta PX2+1
        lda PYT                 ; row q...
        sta PY
        lda PYT+1
        sta PY+1
        lda sh_lev
        jsr pspan
        lda QQ                  ; ...and h - q, unless it is q or outside
        beq @next
        lda PYB
        cmp PYT
        beq @next
        sta PY
        lda PYB+1
        sta PY+1
        lda sh_lev
        jsr pspan
@next:  lda QQ                  ; count blanks every other pair
        lsr a
        bcs :+
        jsr vbl_poll
:       lda sh_h                ; past the middle: done
        lsr a
        cmp QQ
        beq @done
        inc QQ
        clc                     ; t += its gain
        lda TR
        adc DR
        sta TR
        lda TR+1
        adc DR+1
        sta TR+1
        clc
        lda TQ
        adc DQ
        sta TQ
        lda TQ+1
        adc DQ+1
        sta TQ+1
        lda TR                  ; remainder past h^2: one more whole
        cmp H2
        lda TR+1
        sbc H2+1
        bcc :+
        sta TR+1
        lda TR
        sbc H2
        sta TR
        inc TQ
        bne :+
        inc TQ+1
:       sec                     ; the gain shrinks
        lda DR
        sbc DDR
        sta DR
        lda DR+1
        sbc DDR+1
        sta DR+1
        bcs :+
        clc                     ; remainder below 0: borrow a whole
        lda DR
        adc H2
        sta DR
        lda DR+1
        adc H2+1
        sta DR+1
        sec
        lda DQ
        sbc #1
        sta DQ
        bcs :+
        dec DQ+1
:       sec
        lda DQ
        sbc DDQ
        sta DQ
        lda DQ+1
        sbc DDQ+1
        sta DQ+1
        inc PYT                 ; rows one further in
        bne :+
        inc PYT+1
:       lda PYB
        bne :+
        dec PYB+1
:       dec PYB
        jmp @pair
@done:  rts

edge_from_a:
        pha
        lda sh_ax
        sta EPX
        lda sh_ax+1
        sta EPX+1
        pla
        ; fall through

; edge_init: the edge from (EPX, y) to (EQX, y + A) into slot X, at row y.
edge_init:
        sta EDY
        asl a
        sta E_D,x
        sec                     ; dx
        lda EQX
        sbc EPX
        sta EDX
        lda EQX+1
        sbc EPX+1
        sta EDX+1
        sec                     ; row y: (dx - dy) / D
        lda EDX
        sbc EDY
        sta DVD
        lda EDX+1
        sbc #0
        sta DVD+1
        lda E_D,x
        jsr fdiv
        sta E_R,x
        clc
        lda EPX
        adc DVD
        sta E_XL,x
        lda EPX+1
        adc DVD+1
        sta E_XH,x
        lda EDX                 ; a row: 2 dx / D
        asl a
        sta DVD
        lda EDX+1
        rol a
        sta DVD+1
        lda E_D,x
        jsr fdiv
        sta E_SR,x
        lda DVD
        sta E_SL,x
        lda DVD+1
        sta E_SH,x
        rts

; tri_bl, tri_br: a row of the triangle, B's side on the left or the right;
; then both edges down a row.
tri_bl: jsr tri_b
        lda E_R+ESZ             ; PX = ceil of B's side
        cmp #1
        lda E_XL+ESZ
        adc #0
        sta PX
        lda E_XH+ESZ
        adc #0
        sta PX+1
        lda E_XL                ; PX2 = floor of A to C
        sta PX2
        lda E_XH
        sta PX2+1
        bra tri_step
tri_br: jsr tri_b
        lda E_R                 ; PX = ceil of A to C
        cmp #1
        lda E_XL
        adc #0
        sta PX
        lda E_XH
        adc #0
        sta PX+1
        lda E_XL+ESZ            ; PX2 = floor of B's side
        sta PX2
        lda E_XH+ESZ
        sta PX2+1
tri_step:
        EDGE_STEP 0
        EDGE_STEP ESZ
        rts

; tri_b: at B's row, the second edge becomes B to C.
tri_b:  lda TB
        beq :+
        dec TB
        rts
:       dec TB
        lda sh_bx
        sta EPX
        lda sh_bx+1
        sta EPX+1
        lda sh_cx
        sta EQX
        lda sh_cx+1
        sta EQX+1
        sec
        lda sh_h
        sbc TB+1                ; B to C's height: h - b
        ldx #ESZ
        jmp edge_init

; ================================================================ arithmetic
; mul16: PROD = MA x MB (MB is used up).
mul16:  stz PROD+2
        stz PROD+3
        ldy #16
@l:     lsr MB+1
        ror MB
        bcc :+
        clc
        lda PROD+2
        adc MA
        sta PROD+2
        lda PROD+3
        adc MA+1
        sta PROD+3
:       ror PROD+3
        ror PROD+2
        ror PROD+1
        ror PROD
        dey
        bne @l
        rts

; div32: DVD (32 bits) / DVS (under 32768) -> quotient in DVD's low 16 bits,
; remainder in its high 16. The quotient must fit 16 bits. Keeps X.
div32:  ldy #16
@l:     asl DVD
        rol DVD+1
        rol DVD+2
        rol DVD+3
        lda DVD+2
        sec
        sbc DVS
        sta TMP2
        lda DVD+3
        sbc DVS+1
        bcc :+
        sta DVD+3
        lda TMP2
        sta DVD+2
        inc DVD
:       dey
        bne @l
        rts

; fdiv: DVD's low 16 bits, signed, / A (1-255), rounded down: the quotient
; in DVD (16 bits, signed), the remainder (0 to A - 1) in A. Keeps X.
fdiv:   sta DVS
        stz DVS+1
        stz DVD+2
        stz DVD+3
        lda DVD+1
        sta SGN
        bpl :+
        jsr neg_dvd
:       jsr div32
        lda DVD+2
        bit SGN
        bpl @rts
        jsr neg_dvd             ; -(q + r/D) = -q - 1 + (D - r)/D
        lda DVD+2
        beq @rts
        lda DVD
        bne :+
        dec DVD+1
:       dec DVD
        lda DVS
        sec
        sbc DVD+2
@rts:   rts


neg_dvd:
        sec
        lda #0
        sbc DVD
        sta DVD
        lda #0
        sbc DVD+1
        sta DVD+1
        rts

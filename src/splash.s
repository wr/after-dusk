; The boot splash: HELLO's machine code. While DOS reads the disk, a title
; picture draws itself on hi-res page 1 and the last four text lines say what's
; loading. HELLO calls the routines at the top of this file by their fixed
; addresses; everything else runs from a hook on the one place DOS calls its
; disk routine, once for every sector it reads, between sector reads.
;
; Nothing here may land on $2000-$3FFF, so the effects files load at $4000 and
; AFTERDUSK comes last. This code and the first part of the picture ride in the
; HELLO file behind the BASIC program; the rest of the picture is the PAINT file
; at $8000 (see tools/gen_splash.py for the stream's format).

.include "config.inc"

.import __FX0_SIZE__, __FX1_SIZE__, __FX2_SIZE__, __FX3_SIZE__, __FX4_SIZE__
.import __FX5_SIZE__, __FX6_SIZE__, __FX7_SIZE__, __FX8_SIZE__, __FX9_SIZE__
.import __FX10_SIZE__, __FX11_SIZE__, __FX12_SIZE__, __FX13_SIZE__
.import __FX15_SIZE__, __FX16_SIZE__, __FX17_SIZE__

MIXSET    = $C053
WNDBTM    = $23                 ; text window's bottom, and the cursor
CH        = $24
CV        = $25
VTAB      = $FC22               ; Monitor: set up the cursor's row
DOS_RWTS  = $BD00               ; DOS's disk routine
RWTS_CALL = $B7B8               ; the address in DOS's one JSR to it

; Zero page that Applesoft and DOS leave free. The hook uses it only while it
; runs; the stash routines only between disk reads.
SRC       = $06
SCR       = $08

ROW_LO    = $1E00               ; row addresses of the top 160 rows, built by init
ROW_HI    = $1EA0

TXT20     = $0650               ; text rows 20-23: the strip under the picture
TXT21     = $06D0
TXT22     = $0750
TXT23     = $07D0
INVERSE_SPACE = $20

SPLASH_TAIL = $8000             ; the PAINT file
TOTAL_OPS = 280                 ; how many sectors DOS reads after init (measured)
OPEN_OPS  = 9                   ; about how many of a file's reads come before its data
BAR_WIDTH = 38
NSTAGES   = 21

.macro msg s
        .repeat .strlen(s), i
        .byte .strat(s, i) | $80
        .endrep
        .byte 0
.endmacro

.segment "SPLASH"

; ---- HELLO's entry points: CALL 2816, 2819, 2822, 2825, 2828, 2831
        jmp splash_init
        jmp splash_next
        jmp stash_fx
        jmp stash_fx3
        jmp stash_fx2
        jmp splash_done

; ---------------------------------------------------------------- init
splash_init:
        jsr make_rows
        stz SCR                 ; black screen before it's shown
        lda #PAGE1
        sta SCR+1
        lda #0
        tay
@clear: sta (SCR),y
        iny
        bne @clear
        inc SCR+1
        ldx SCR+1
        cpx #PAGE1 + $20
        bne @clear
        ldx #39
        lda #$A0                ; the strip: blank, with the bar's track
:       sta TXT20,x
        sta TXT21,x
        sta TXT22,x
        sta TXT23,x
        dex
        bpl :-
        ldx #BAR_WIDTH
        lda #$AE                ; '.'
:       sta TXT22,x
        dex
        bne :-
        lda #20                 ; BASIC's carriage returns stay behind the picture
        sta WNDBTM
        stz CH
        stz CV
        jsr VTAB
        sta TXTCLR
        sta MIXSET
        sta LOWSCR
        sta HIRES
        lda #<hook
        sta RWTS_CALL
        lda #>hook
        sta RWTS_CALL+1
        lda #0
        jmp set_stage

; make_rows: the screen address of each of the top 160 rows.
make_rows:
        ldx #0
@row:   txa                     ; high byte: $20 + (y & 7) * 4 + block / 2,
        and #7                  ; where block = (y >> 3) & 7
        asl a
        asl a
        ora #PAGE1
        sta ROW_HI,x
        txa
        lsr a
        lsr a
        lsr a
        and #7
        tay
        lsr a
        ora ROW_HI,x
        sta ROW_HI,x
        tya                     ; low byte: block & 1 * $80 + third * 40
        and #1
        beq :+
        lda #$80
:       sta ROW_LO,x
        txa
        asl a                   ; the top two bits of y give the third
        lda #0
        rol a
        sta SRC
        txa
        asl a
        asl a
        lda SRC
        rol a
        tay
        lda ROW_LO,x
        clc
        adc thirds,y
        sta ROW_LO,x
        inx
        cpx #160
        bne @row
        rts

thirds: .byte 0, 40, 80

; ---------------------------------------------------------------- the hook
; DOS calls this in place of its disk routine: paint a little, then go on.
hook:   pha
        phx
        phy
        jsr tick
        ply
        plx
        pla
        jmp DOS_RWTS

; tick: one sector read. Advance the picture, the icon, the stage and the bar.
tick:   clc                     ; the picture: SPLASH_STEPS steps over TOTAL_OPS reads
        lda pacc
        adc #<SPLASH_STEPS
        sta pacc
        lda pacc+1
        adc #>SPLASH_STEPS
        sta pacc+1
@paint: sec
        lda pacc
        sbc #<TOTAL_OPS
        tax
        lda pacc+1
        sbc #>TOTAL_OPS
        bcc @bar
        sta pacc+1
        stx pacc
        jsr stream_step
        bra @paint

@bar:   clc                     ; the bar: BAR_WIDTH cells over TOTAL_OPS reads
        lda bacc
        adc #BAR_WIDTH
        sta bacc
        bcc @bar2
        inc bacc+1
@bar2:  sec
        lda bacc
        sbc #<TOTAL_OPS
        tax
        lda bacc+1
        sbc #>TOTAL_OPS
        bcc @icon
        sta bacc+1
        stx bacc
        jsr bar_cell
        bra @bar2

@icon:  ldx stage               ; the icon: its 14 rows over its stage's reads
        lda stage_icon,x
        bmi @stage
        lda irow
        cmp #14
        bcs @stage
        clc
        lda iacc
        adc #14
        sta iacc
@irow:  ldx stage
        lda iacc
        cmp stage_ops,x
        bcc @stage
        sbc stage_ops,x
        sta iacc
        jsr icon_row
        lda irow
        cmp #14
        bcc @irow

@stage: lda ops_left            ; stage's reads used up: on to the next, unless
        beq @done               ; the next starts a new file (HELLO says when)
        dec ops_left
        bne @done
        ldx stage
        lda stage_file+1,x
        bne @done
        jsr finish_icon
        ldx stage
        inx
        txa
        jmp set_stage
@done:  rts

; bar_cell: fill the next cell of the progress bar.
bar_cell:
        ldx bcol
        cpx #BAR_WIDTH
        bcs :+
        lda #INVERSE_SPACE
        sta TXT22+1,x
        inc bcol
:       rts

; ---------------------------------------------------------------- stages
; set_stage: A = the stage to show.
set_stage:
        sta stage
        tax
        lda stage_ops,x
        sta ops_left
        stz iacc
        lda stage_icon,x
        bmi @noicon
        stz irow
        inc islot
        bra @text
@noicon:
        lda #14
        sta irow
@text:  ldy #38                 ; clear the status line
        lda #$A0
:       sta TXT21,y
        dey
        bne :-
        lda stage_text_lo,x
        sta SRC
        lda stage_text_hi,x
        sta SRC+1
        ldy #0
:       lda (SRC),y
        beq @num
        sta TXT21+1,y
        iny
        bra :-
@num:   lda stage_num,x
        beq @rts
        cmp #10
        bcc @one
        ldy #$B1                ; 10 to 18: a leading 1
        sty TXT21+31
        sbc #10
@one:   ora #$B0
        sta TXT21+32
        ldx #5
:       lda of_18,x
        sta TXT21+33,x
        dex
        bpl :-
@rts:   rts

of_18:  .byte $A0,$EF,$E6,$A0,$B1,$B8   ; " of 18"

; finish_icon: draw whatever rows the current stage's icon still needs.
finish_icon:
        ldx stage
        lda stage_icon,x
        bmi @rts
@row:   lda irow
        cmp #14
        bcs @rts
        jsr icon_row
        bra @row
@rts:   rts

; icon_row: draw the next row of the current stage's icon. Icons sit two bytes
; wide in slot order from column 2.
icon_row:
        ldx stage
        ldy stage_icon,x
        lda icon_lo,y
        sta SRC
        lda icon_hi,y
        sta SRC+1
        lda irow
        asl a
        tay
        clc
        lda irow
        adc #SPLASH_ICON_Y
        tax
        lda ROW_LO,x
        sta SCR
        lda ROW_HI,x
        sta SCR+1
        lda islot
        asl a
        clc
        adc #2
        sta col
        lda (SRC),y
        phy
        ldy col
        sta (SCR),y
        ply
        iny
        lda (SRC),y
        ldy col
        iny
        sta (SCR),y
        inc irow
        rts

; splash_next: HELLO is about to read the next file. Show that file's first
; stage, finishing anything the last file's reads didn't reach.
splash_next:
        jsr finish_icon
        ldx stage
        inx
        cpx #NSTAGES
        bcs @rts
        txa
        jsr set_stage
        ldx stage
        lda stage_file,x
        beq splash_next
@rts:   rts

; splash_done: everything is loaded: finish the picture and the bar, and take
; the hook back out.
splash_done:
        jsr finish_icon
@paint: jsr stream_step
        bcc @paint
@bar:   lda bcol
        cmp #BAR_WIDTH
        bcs @out
        jsr bar_cell
        bra @bar
@out:   stz RWTS_CALL
        lda #>DOS_RWTS
        sta RWTS_CALL+1
        rts

; ---------------------------------------------------------------- the stream
; stream_step: paint one step. Carry set means the stream has ended.
stream_step:
        lda pptr
        sta SRC
        lda pptr+1
        sta SRC+1
@rec:   lda (SRC)
        cmp #$80
        bne :+
        jsr nextb
        clc
        bra @save
:       cmp #$FF
        bne :+
        sec
        bra @save
:       cmp #$FE
        bne @seg
        lda #<SPLASH_TAIL
        sta SRC
        lda #>SPLASH_TAIL
        sta SRC+1
        bra @rec
@save:  lda SRC
        sta pptr
        lda SRC+1
        sta pptr+1
        rts

@seg:   jsr nextb
        pha
        and #$3F
        sta col
        pla
        and #$40
        bne @down
        lda (SRC)
        sta cury
        jsr nextb
        bra @row
@down:  inc cury
@row:   ldx cury
        lda ROW_LO,x
        sta SCR
        lda ROW_HI,x
        sta SCR+1
        lda (SRC)
        jsr nextb
        pha
        and #$3F
        tax
        pla
        and #$C0
        beq @lit
        cmp #$40
        beq @run
        lda (SRC)               ; two values, alternating
        sta val
        jsr nextb
        lda (SRC)
        sta val+1
        jsr nextb
@alt:   lda val
        jsr put
        dex
        beq @again
        lda val+1
        jsr put
        dex
        bne @alt
@again: jmp @rec
@run:   lda (SRC)
        sta val
        jsr nextb
:       lda val
        jsr put
        dex
        bne :-
        jmp @rec
@lit:   lda (SRC)
        jsr nextb
        jsr put
        dex
        bne @lit
        jmp @rec

nextb:  inc SRC
        bne :+
        inc SRC+1
:       rts

; put: OR A into the current row at col, and move right.
put:    ldy col
        ora (SCR),y
        sta (SCR),y
        inc col
        rts

; ---------------------------------------------------------------- stash
; stash_*: copy main $4000-, where HELLO has just loaded a file, to its home in
; aux memory. Called from BASIC between reads.
stash_fx:
        lda #>FXSTORE
        ldx #>FXSTORE_END
        bra stash
stash_fx3:
        lda #>FXSTORE3
        ldx #>FXSTORE3_END
        bra stash
stash_fx2:
        lda #>FXSTORE2
        ldx #>FXSTORE2_END
stash:  ldy #0
        sty SRC
        sty SCR
        sta SCR+1
        lda #$40
        sta SRC+1
        sta WRCARDRAM           ; writes to aux; reads (and this code) main
@copy:  lda (SRC),y
        sta (SCR),y
        iny
        bne @copy
        inc SRC+1
        inc SCR+1
        cpx SCR+1
        bne @copy
        sta WRMAINRAM
        rts

; ---------------------------------------------------------------- state
pptr:   .word paint_head
pacc:   .word 0
bacc:   .word 0
bcol:   .byte 0
stage:  .byte 0
ops_left: .byte 0
iacc:   .byte 0
irow:   .byte 14
islot:  .byte $FF
col:    .byte 0
cury:   .byte 0
val:    .res 2

; ---------------------------------------------------------------- stages
; The order HELLO reads things. stage_file marks a stage that starts a new
; file, which only HELLO can advance to; inside a file, each effect's stage
; lasts about as many reads as its code has sectors.
.define SECTORS(sz) (((sz) + 128) / 256)

stage_ops:
        .byte 27                ; the SEED file
        .byte 31                ; the PAINT file
        .byte <(OPEN_OPS + SECTORS(__FX0_SIZE__))
        .byte <SECTORS(__FX1_SIZE__), <SECTORS(__FX2_SIZE__), <SECTORS(__FX3_SIZE__)
        .byte <SECTORS(__FX4_SIZE__), <SECTORS(__FX5_SIZE__), <SECTORS(__FX6_SIZE__)
        .byte <SECTORS(__FX7_SIZE__), <SECTORS(__FX8_SIZE__), <SECTORS(__FX9_SIZE__)
        .byte <SECTORS(__FX10_SIZE__), <SECTORS(__FX11_SIZE__), <SECTORS(__FX12_SIZE__)
        .byte <SECTORS(__FX13_SIZE__)
        .byte <(OPEN_OPS + SECTORS(__FX15_SIZE__))
        .byte <SECTORS(__FX16_SIZE__), <SECTORS(__FX17_SIZE__)
        .byte 74                ; Fish! is the whole FX2 file
        .byte 48                ; AFTERDUSK
stage_file:
        .byte 1, 1, 1, 0,0,0,0,0,0,0,0,0,0,0,0,0, 1, 0,0, 1, 1, 1
stage_icon:
        .byte $FF, $FF, 0,1,2,3,4,5,6,7,8,9,10,11,12,13, 15,16,17, 14, $FF
stage_num:
        .byte 0, 0, 1,2,3,4,5,6,7,8,9,10,11,12,13,14, 15,16,17, 18, 0
stage_text_lo:
        .lobytes m_shuffle, m_picture, m_fx0, m_fx1, m_fx2, m_fx3, m_fx4, m_fx5
        .lobytes m_fx6, m_fx7, m_fx8, m_fx9, m_fx10, m_fx11, m_fx12, m_fx13
        .lobytes m_fx15, m_fx16, m_fx17, m_fx14, m_ready
stage_text_hi:
        .hibytes m_shuffle, m_picture, m_fx0, m_fx1, m_fx2, m_fx3, m_fx4, m_fx5
        .hibytes m_fx6, m_fx7, m_fx8, m_fx9, m_fx10, m_fx11, m_fx12, m_fx13
        .hibytes m_fx15, m_fx16, m_fx17, m_fx14, m_ready

m_shuffle:  msg "Shuffling the screen savers"
m_picture:  msg "Loading the picture"
m_fx0:      msg "Loading Flying Toasters"
m_fx1:      msg "Loading Warp"
m_fx2:      msg "Loading Starry Night"
m_fx3:      msg "Loading Zot!"
m_fx4:      msg "Loading Can of Worms"
m_fx5:      msg "Loading Lissajous"
m_fx6:      msg "Loading Nightlines"
m_fx7:      msg "Loading String Theory"
m_fx8:      msg "Loading Rose"
m_fx9:      msg "Loading Doodles"
m_fx10:     msg "Loading Shapes"
m_fx11:     msg "Loading Spheres"
m_fx12:     msg "Loading Bouncing Ball"
m_fx13:     msg "Loading Rainstorm"
m_fx14:     msg "Loading Fish!"
m_fx15:     msg "Loading Hard Rain"
m_fx16:     msg "Loading Snake"
m_fx17:     msg "Loading Life II"
m_ready:    msg "Almost ready"

.include "splash_art.inc"

.segment "SPLASH"
icon_lo:
        .repeat 18, i
        .byte <(icons + i * 28)
        .endrep
icon_hi:
        .repeat 18, i
        .byte >(icons + i * 28)
        .endrep

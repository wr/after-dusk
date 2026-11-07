; After Dusk: start-up and the randomizer.
;
; start (from HELLO) and restart (from Ctrl-Reset) set up the machine, then
; the randomizer runs forever: pick an effect that isn't the current one,
; wipe the screen first if the effect wants that, call its init once, then
; its step every ticks_per_step ticks until a key is pressed or FX_TICKS
; ticks have passed.
;
; The effects themselves aren't in this program. They come in two files that
; HELLO loads at $2000 one after the other, once it has loaded this program:
; FX2 first, which it hands to fx2_stash (at $6003) to copy to aux $6000;
; then FX, which start copies to aux $2000. Each effect is copied from aux
; into the overlay slot at $8800 when its turn comes. See after-dusk.cfg.

.include "config.inc"

.export start, restart, begin_effect, step_once, pick_next, normalize_display
.export fx_table, fx_count, fx_stash, fx2_stash, lc_install, load_fx, aux_fetch

.import timing_init, wait_ticks, timing_sync, rng_seed, rng_below, key_pressed
.import clear_page, copy_page, show_page1, wipe_to_black, plot
.import sprite_setup, make_tables
.import __LCCODE_LOAD__, __LCCODE_SIZE__
.import __FX0_LOAD__, __FX0_SIZE__, __FX1_LOAD__, __FX1_SIZE__
.import __FX2_LOAD__, __FX2_SIZE__, __FX3_LOAD__, __FX3_SIZE__
.import __FX4_LOAD__, __FX4_SIZE__, __FX5_LOAD__, __FX5_SIZE__
.import __FX6_LOAD__, __FX6_SIZE__, __FX7_LOAD__, __FX7_SIZE__
.import __FX8_LOAD__, __FX8_SIZE__, __FX9_LOAD__, __FX9_SIZE__
.import __FX10_LOAD__, __FX10_SIZE__, __FX11_LOAD__, __FX11_SIZE__
.import __FX12_LOAD__, __FX12_SIZE__, __FX13_LOAD__, __FX13_SIZE__
.import __FX14_LOAD__, __FX14_SIZE__

FXOFF   = CORE+6        ; current effect's offset into fx_table (id * 6)
F2SRC   = $06           ; 2: fx2_stash's source, in zero page that
F2DST   = $08           ; 2: Applesoft and DOS leave free

SOFTEV  = $03F2         ; reset vector, and its check byte at $03F4
PWREDUP = $03F4

.segment "CODE"

; HELLO enters at fixed addresses, so they lead the program.
start:  jmp boot                ; CALL 24576 ($6000), once FX is loaded
        jmp fx2_stash           ; CALL 24579 ($6003), once FX2 is loaded

boot:
        sei
        jsr fx_stash            ; the effects, before anything clears the screen
        jsr setup
        jsr rng_seed
        lda #$FF
        sta ST_FX
        bra run

restart:                        ; Ctrl-Reset lands here; keeps RNG and ST_FX
        jsr setup

run:    jsr begin_effect
@step:  jsr step_once
        bcc @step
        jsr normalize_display
        bra run

; ---------------------------------------------------------------- setup
setup:
        sei                     ; interrupts stay masked, always
        cld
        pla                     ; keep our return address, reset the stack
        tay
        pla
        ldx #$FF
        txs
        pha
        tya
        pha
        sta TXTCLR              ; full-screen hi-res, page 1
        sta MIXCLR
        sta HIRES
        jsr show_page1
        lda #PAGE1
        sta PAGE
        jsr clear_page
        lda #PAGE2
        sta PAGE
        jsr clear_page
        stz KEYHELD
        jsr timing_init         ; reads the ROM: before the language card
        jsr sprite_setup        ; language card RAM in from here on
        jsr make_tables
        jsr lc_install
        lda #<restart           ; Ctrl-Reset comes back to us
        sta SOFTEV
        lda #>restart
        sta SOFTEV+1
        eor #$A5
        sta PWREDUP
        rts

; ---------------------------------------------------------------- effects
; begin_effect: choose the next effect, wipe if it wants, reset TICKS, init.
begin_effect:
        jsr pick_next
        sta ST_FX
        inc ST_STARTS
        asl a                   ; FXOFF = id * 6
        sta FXOFF
        asl a
        clc
        adc FXOFF
        sta FXOFF
        lda ST_FX               ; its code into the overlay slot
        jsr load_fx
        ldx FXOFF
        jsr timing_sync         ; ticks count from now, not from before
        lda fx_table+4,x
        beq :+
        jsr wipe_to_black
:       jsr OVL                 ; the effect's init
        stz TICKS
        stz TICKS+1
        jmp timing_sync         ; and again after a long set-up

; step_once: one step of the current effect, then wait out its ticks.
; Returns carry set when the effect should end (key, or time up).
step_once:
        jsr @step
        inc ST_BEAT
        bne :+
        inc ST_BEAT+1
:       ldx FXOFF
        lda ST_TIMING
        beq @slow
        lda fx_table+5,x
        jsr wait_ticks
        bra @keys
@slow:  ldy ST_FX               ; no vertical blank: wait only what the step's
        lda fx_slow,y           ; own work leaves of its ticks, then count
        jsr wait_ticks          ; its full ticks
        ldx FXOFF
        ldy ST_FX
        lda fx_table+5,x
        sec
        sbc fx_slow,y
        clc
        adc TICKS
        sta TICKS
        bcc @keys
        inc TICKS+1
@keys:  jsr key_pressed
        bcs @end
        lda TICKS               ; carry set once TICKS >= FX_TICKS
        cmp #<FX_TICKS
        lda TICKS+1
        sbc #>FX_TICKS
@end:   rts
@step:  jmp OVL_STEP

; pick_next: a random effect id in A, never the one in ST_FX.
pick_next:
:       lda #NFX
        jsr rng_below
        cmp ST_FX
        beq :-
        rts

; normalize_display: leave the last frame on page 1, showing.
normalize_display:
        lda DISP
        beq @done
        lda #PAGE1
        sta PAGE
        lda #PAGE2
        jsr copy_page
        jsr show_page1
@done:  rts

; ---------------------------------------------------------------- table
; Without vertical blank (the cycle-counted fallback), ticks to wait after
; each effect's step: its ticks minus its typical work (measured medians:
; toasters 2.7 ticks, Warp 1.6, Starry Night 0.1, Zot! idle, worms 1.7,
; Lissajous 0.9, Nightlines 1.6, String Theory 2.2, Rose 1.4, Doodles 0.26,
; Shapes 1.3, Spheres 1.2, Bouncing Ball 0.4, Rainstorm 2.3, Fish! idle
; (so far only its floor)).
fx_slow:
        .byte 1, 0, 4, 3, 1, 1, 3, 4, 1, 2, 2, 3, 2, 1, 1

; Per effect: where it is in aux memory and its size, wipe first (1/0),
; ticks per step. The FX file is effects 0-13 one after another from aux
; $2000; FX2 is effect 14 on, from aux $6000.
fx_count:
        .byte NFX
fx_table:
        .word __FX0_LOAD__, __FX0_SIZE__
        .byte 1, 4              ; 0 Flying Toasters
        .word __FX1_LOAD__, __FX1_SIZE__
        .byte 1, 2              ; 1 Warp
        .word __FX2_LOAD__, __FX2_SIZE__
        .byte 1, 4              ; 2 Starry Night
        .word __FX3_LOAD__, __FX3_SIZE__
        .byte 1, 3              ; 3 Zot!
        .word __FX4_LOAD__, __FX4_SIZE__
        .byte 0, 3              ; 4 Can of Worms
        .word __FX5_LOAD__, __FX5_SIZE__
        .byte 1, 2              ; 5 Lissajous
        .word __FX6_LOAD__, __FX6_SIZE__
        .byte 1, 5              ; 6 Nightlines
        .word __FX7_LOAD__, __FX7_SIZE__
        .byte 1, 6              ; 7 String Theory
        .word __FX8_LOAD__, __FX8_SIZE__
        .byte 1, 2              ; 8 Rose
        .word __FX9_LOAD__, __FX9_SIZE__
        .byte 1, 2              ; 9 Doodles
        .word __FX10_LOAD__, __FX10_SIZE__
        .byte 1, 3              ; 10 Shapes
        .word __FX11_LOAD__, __FX11_SIZE__
        .byte 1, 4              ; 11 Spheres
        .word __FX12_LOAD__, __FX12_SIZE__
        .byte 1, 2              ; 12 Bouncing Ball
        .word __FX13_LOAD__, __FX13_SIZE__
        .byte 1, 3              ; 13 Rainstorm
        .word __FX14_LOAD__, __FX14_SIZE__
        .byte 1, 1              ; 14 Fish!

; ---------------------------------------------------------------- loader
; fx_stash: copy main $2000-$5FFF, where HELLO loaded the FX file, to the
; same addresses in aux memory. Once, at start; Ctrl-Reset keeps the copy.
fx_stash:
        stz LSRC
        lda #>FXSTORE
        sta LSRC+1
        ldy #0
        sta WRCARDRAM           ; writes to aux; reads (and this code) main
@copy:  lda (LSRC),y
        sta (LSRC),y
        iny
        bne @copy
        inc LSRC+1
        lda LSRC+1
        cmp #>FXSTORE_END
        bne @copy
        sta WRMAINRAM
        rts

; lc_install: put aux_fetch into language-card RAM. setup calls it once the
; card's RAM is switched in.
lc_install:
        ldx #<__LCCODE_SIZE__
:       lda __LCCODE_LOAD__-1,x
        sta aux_fetch-1,x
        dex
        bne :-
        rts

; load_fx: copy effect A's code from aux memory into the overlay slot, in
; whole pages (the slot is whole pages, so the overrun stays inside it).
load_fx:
        asl a                   ; X = A * 6
        sta LSRC
        asl a
        clc
        adc LSRC
        tax
        lda fx_table,x
        sta LSRC
        lda fx_table+1,x
        sta LSRC+1
        stz LDST
        lda #>OVL
        sta LDST+1
        lda fx_table+2,x        ; pages = size high byte, plus one if the
        cmp #1                  ; low byte isn't 0
        lda fx_table+3,x
        adc #0
        tax                     ; never 0: every overlay starts with two jmps
        jmp aux_fetch           ; (0 would copy 256 pages over everything)

.segment "ONCE"
; Run once, from BASIC, so it sits after all the resident code: code added
; here doesn't move the drawing routines' loops, whose timing can depend on
; where they cross page boundaries.
; fx2_stash: copy main $2000-$5FFF, where HELLO has just loaded the FX2 file,
; to aux $6000-$9FFF. HELLO calls it from BASIC before loading FX over the
; same memory, so it keeps to zero page $06-$09, leaves interrupts as they
; are, and returns to BASIC with writes back on main.
fx2_stash:
        ldy #0
        sty F2SRC
        sty F2DST
        lda #>FXSTORE
        sta F2SRC+1
        lda #>FXSTORE2
        sta F2DST+1
        sta WRCARDRAM           ; writes to aux; reads (and this code) main
@copy:  lda (F2SRC),y
        sta (F2DST),y
        iny
        bne @copy
        inc F2SRC+1
        inc F2DST+1
        lda F2DST+1
        cmp #>FXSTORE2_END
        bne @copy
        sta WRMAINRAM
        rts

.segment "LCCODE"
; aux_fetch: copy X pages from aux memory at LSRC to main memory at LDST.
; It runs from language-card RAM because while RAMRD is on, the CPU would
; fetch its own instructions from aux too if they were in $0200-$BFFF.
aux_fetch:
        sta RDCARDRAM
        ldy #0
@copy:  lda (LSRC),y
        sta (LDST),y
        iny
        bne @copy
        inc LSRC+1
        inc LDST+1
        dex
        bne @copy
        sta RDMAINRAM
        rts

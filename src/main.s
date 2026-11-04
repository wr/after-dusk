; After Dusk: start-up and the randomizer.
;
; start (from BRUN) and restart (from Ctrl-Reset) set up the machine, then
; the randomizer runs forever: pick an effect that isn't the current one,
; wipe the screen first if the effect wants that, call its init once, then
; its step every ticks_per_step ticks until a key is pressed or FX_TICKS
; ticks have passed.

.include "config.inc"

.export start, restart, begin_effect, step_once, pick_next, normalize_display
.export fx_table

.import timing_init, wait_ticks, rng_seed, rng_below, key_pressed
.import clear_page, copy_page, show_page1, wipe_to_black, plot
.import sprite_setup
.import fx_toasters_init, fx_toasters_step

FXOFF   = CORE+6        ; current effect's offset into fx_table (id * 6)

SOFTEV  = $03F2         ; reset vector, and its check byte at $03F4
PWREDUP = $03F4

.segment "CODE"

start:                          ; BRUN enters here ($6000)
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
        jsr timing_init         ; reads the ROM: before the language card
        jsr sprite_setup        ; language card RAM in from here on
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
        tax
        lda fx_table+4,x
        beq :+
        jsr wipe_to_black
:       stz TICKS
        stz TICKS+1
        ldx FXOFF
        jmp (fx_table,x)        ; the effect's init returns to our caller

; step_once: one step of the current effect, then wait out its ticks.
; Returns carry set when the effect should end (key, or time up).
step_once:
        jsr @step
        inc ST_BEAT
        bne :+
        inc ST_BEAT+1
:       ldx FXOFF
        lda fx_table+5,x
        jsr wait_ticks
        jsr key_pressed
        bcs @end
        lda TICKS               ; carry set once TICKS >= FX_TICKS
        cmp #<FX_TICKS
        lda TICKS+1
        sbc #>FX_TICKS
@end:   rts
@step:  ldx FXOFF
        jmp (fx_table+2,x)

; pick_next: a random effect id in A, never the one in ST_FX.
pick_next:
:       lda #6
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
; Per effect: init, step, wipe first (1/0), ticks per step.
fx_table:
        .word fx_toasters_init, fx_toasters_step
        .byte 1, 4              ; 0 Flying Toasters
        .word ph_init, ph_step
        .byte 1, 2              ; 1 Warp
        .word ph_init, ph_step
        .byte 1, 4              ; 2 Starry Night
        .word ph_init, ph_step
        .byte 0, 3              ; 3 Zot!
        .word ph_init, ph_step
        .byte 0, 3              ; 4 Can of Worms
        .word ph_init, ph_step
        .byte 1, 2              ; 5 Lissajous

; ---------------------------------------------------------------- placeholder
; Stands in for an effect until it is written: one dot, placed by id.
ph_init:
        lda #1
        bra ph_dot
ph_step:
        lda #2
ph_dot: sta PCOL
        lda #PAGE1
        sta PAGE
        lda ST_FX
        asl a                   ; x = id * 40 + 20
        asl a
        asl a
        sta PX
        asl a
        asl a
        clc
        adc PX
        adc #20
        sta PX
        stz PX+1
        lda #96
        sta PY
        stz PY+1
        jmp plot

; After Dusk: entry point.

.include "config.inc"

.export start, restart
.import timing_init, wait_ticks

.segment "CODE"

start:                          ; BRUN enters here ($6000)
restart:
        sei                     ; interrupts stay masked, always
        cld
        sta TXTCLR              ; graphics
        sta MIXCLR              ; full screen
        sta LOWSCR              ; page 1
        sta HIRES               ; hi-res

        lda #0                  ; clear page 1
        sta DSCR
        lda #PAGE1
        sta DSCR+1
        ldx #$20                ; 32 pages of 256 bytes
        lda #0
        tay
@clr:   sta (DSCR),y
        iny
        bne @clr
        inc DSCR+1
        dex
        bne @clr

        lda #$FF
        sta ST_FX
        jsr timing_init

@loop:  inc ST_BEAT
        bne :+
        inc ST_BEAT+1
:       lda #1
        jsr wait_ticks
        bra @loop

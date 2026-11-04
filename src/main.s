; After Dusk: entry point.

.include "config.inc"

.export start, restart

.segment "CODE"

start:                          ; BRUN enters here ($6000)
restart:
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

@loop:  inc ST_BEAT
        bne @loop
        inc ST_BEAT+1
        bra @loop

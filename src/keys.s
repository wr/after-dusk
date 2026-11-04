; Keyboard: has a key been pressed?

.include "config.inc"

.export key_pressed

.segment "CODE"

; key_pressed: carry set for a new key press (and consumes it), else clear.
; The IIc repeats a held key, so after a press, further key strobes are
; ignored until a poll sees no key down ($C010 bit 7 is "any key down").
key_pressed:
        lda KBD
        bmi @strobe
        lda KBDSTRB             ; no new key: has the held one been let go?
        bmi @no
        stz KEYHELD
@no:    clc
        rts
@strobe:
        lda KBDSTRB             ; clear the strobe
        lda KEYHELD
        bne @no                 ; the same key, repeating
        lda #1
        sta KEYHELD
        sec
        rts

; Keyboard: has a key been pressed?

.include "config.inc"

.export key_pressed

.segment "CODE"

; key_pressed: carry set if a key is waiting (and consumes it), else clear.
key_pressed:
        lda KBD
        bpl @none
        bit KBDSTRB             ; clear the strobe
        sec
        rts
@none:  clc
        rts

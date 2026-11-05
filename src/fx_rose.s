; Effect 8: Rose. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_rose_init, fx_rose_step

.segment "FX8"
        jmp fx_rose_init        ; the overlay's entry points
        jmp fx_rose_step

fx_rose_init:
        rts

fx_rose_step:
        rts

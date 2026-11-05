; Effect 7: String Theory. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_strings_init, fx_strings_step

.segment "FX7"
        jmp fx_strings_init        ; the overlay's entry points
        jmp fx_strings_step

fx_strings_init:
        rts

fx_strings_step:
        rts

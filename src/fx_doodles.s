; Effect 9: Doodles. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_doodles_init, fx_doodles_step

.segment "FX9"
        jmp fx_doodles_init        ; the overlay's entry points
        jmp fx_doodles_step

fx_doodles_init:
        rts

fx_doodles_step:
        rts

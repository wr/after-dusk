; Effect 6: Nightlines. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_night_init, fx_night_step

.segment "FX6"
        jmp fx_night_init        ; the overlay's entry points
        jmp fx_night_step

fx_night_init:
        rts

fx_night_step:
        rts

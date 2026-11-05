; Effect 13: Rainstorm. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_rain_init, fx_rain_step

.segment "FX13"
        jmp fx_rain_init        ; the overlay's entry points
        jmp fx_rain_step

fx_rain_init:
        rts

fx_rain_step:
        rts

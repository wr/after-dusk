; Effect 10: Shapes. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_shapes_init, fx_shapes_step

.segment "FX10"
        jmp fx_shapes_init        ; the overlay's entry points
        jmp fx_shapes_step

fx_shapes_init:
        rts

fx_shapes_step:
        rts

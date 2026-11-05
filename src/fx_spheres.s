; Effect 11: Spheres. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_spheres_init, fx_spheres_step

.segment "FX11"
        jmp fx_spheres_init        ; the overlay's entry points
        jmp fx_spheres_step

fx_spheres_init:
        rts

fx_spheres_step:
        rts

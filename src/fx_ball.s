; Effect 12: Bouncing Ball. Not drawn yet: a placeholder so the slot exists.

.include "config.inc"

.export fx_ball_init, fx_ball_step

.segment "FX12"
        jmp fx_ball_init        ; the overlay's entry points
        jmp fx_ball_step

fx_ball_init:
        rts

fx_ball_step:
        rts

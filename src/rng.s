; Random numbers: 16-bit xorshift (shifts 7, 9, 8; John Metcalf's "798").
; Period 65535; the state in RNG is never 0.

.include "config.inc"

.export rng_seed, rng_next, rng_below

NBELOW = CORE          ; rng_below's limit
NTMP   = CORE+1
NMASK  = CORE+2

.segment "CODE"

; rng_seed: start from the boot seed HELLO left at $0300, mixed with a
; constant so small seeds spread out, never zero.
rng_seed:
        lda SEED_LO
        eor #$A5
        sta RNG
        lda SEED_HI
        eor #$C3
        sta RNG+1
        ora RNG
        bne :+
        inc RNG
:       ldx #4                  ; stir a little
:       jsr rng_next
        dex
        bne :-
        rts

; rng_next: advance the state; returns its low byte in A. Keeps X and Y.
rng_next:
        lda RNG+1
        lsr a
        lda RNG
        ror a
        eor RNG+1
        sta RNG+1
        ror a
        eor RNG
        sta RNG
        eor RNG+1
        sta RNG+1
        lda RNG
        rts

; rng_below: A = n (1-255). Returns 0..n-1 in A, without modulo bias
; (draws under the next power of two and rejects values >= n). Keeps X and Y.
rng_below:
        sta NBELOW
        sec
        sbc #1
        sta NTMP
        stz NMASK
@mask:  lda NTMP                ; NMASK = smallest 2^k - 1 >= n - 1
        beq @draw
        lsr NTMP
        sec
        rol NMASK
        bra @mask
@draw:  jsr rng_next
        and NMASK
        cmp NBELOW
        bcs @draw
        rts

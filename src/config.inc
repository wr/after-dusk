; After Dusk: shared addresses and constants. The maps here are the contract
; between modules; AGENTS.md mirrors them.

.ifndef FX_TICKS
FX_TICKS = 10800              ; ticks (1/60 s) per effect: 3 minutes
.endif

TICK_CYCLES = 17030           ; CPU cycles in one NTSC video frame

; ---- zero page: drawing parameters ($10-$1F, hires.s) ----
PX      = $10                 ; x, signed 16-bit
PY      = $12                 ; y, signed 16-bit
PX2     = $14                 ; second x for line
PY2     = $16                 ; second y for line
PCOL    = $18                 ; 0 = clear, 1 = set, 2 = invert
PAGE    = $19                 ; $20 or $40: page being drawn
RAD     = $1A                 ; radius for disc
DSCR    = $1B                 ; $1B-$1F scratch for hires.s

; ---- zero page: core state ($20-$2F) ----
RNG     = $20                 ; 16-bit xorshift state, never 0
TICKS   = $22                 ; 16-bit ticks elapsed in this effect
DISP    = $24                 ; 0 = page 1 shown, 1 = page 2 shown
CORE    = $25                 ; $25-$2F scratch for core modules

; ---- zero page: sprite engine ($30-$3F) ----
SPZ     = $30

; ---- zero page: private to the running effect ($40-$7F) ----
FXZ     = $40

; ---- zero page: extra drawing scratch ($80-$8F, hires.s) ----
; After Dusk never returns to BASIC or DOS (Ctrl-Reset restarts it), so the
; upper zero page is ours.
DSX     = $80

; ---- seed POKEd by HELLO ----
SEED_LO = $0300
SEED_HI = $0301

; ---- status block, read by the emulator tests ----
ST_FX     = $0310             ; current effect 0-5, $FF before the first
ST_STARTS = $0311             ; effects started, wraps
ST_BEAT   = $0312             ; 16-bit steps since boot, wraps
ST_TIMING = $0314             ; 1 = vertical-blank pacing, 0 = cycle-counted
ST_FAST   = $0315             ; 1 = IIc Plus (4 MHz) detected

; ---- RAM private to the running effect ----
FXRAM     = $0800             ; $0800-$1FFF
FXRAM_END = $2000

; ---- hi-res pages ----
PAGE1   = $20
PAGE2   = $40

; ---- soft switches ----
KBD     = $C000
KBDSTRB = $C010
TXTCLR  = $C050
MIXCLR  = $C052
LOWSCR  = $C054
HISCR   = $C055
HIRES   = $C057

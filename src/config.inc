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

; ---- zero page: extra sprite-engine scratch ($90-$9F, sprite.s) ----
SPX     = $90

; ---- seed POKEd by HELLO ----
SEED_LO = $0300
SEED_HI = $0301

; ---- status block, read by the emulator tests ----
ST_FX     = $0310             ; current effect 0 to NFX-1, $FF before the first
ST_STARTS = $0311             ; effects started, wraps
ST_BEAT   = $0312             ; 16-bit steps since boot, wraps
ST_TIMING = $0314             ; 1 = vertical-blank pacing, 0 = cycle-counted
ST_FAST   = $0315             ; 1 = IIc Plus (4 MHz) detected
KEYHELD   = $0316             ; 1 while the key that last skipped is still down

; ---- effects: kept in aux memory, run one at a time in the overlay slot ----
NFX       = 10                ; effects
OVL       = $8800             ; overlay slot, $8800-$95FF: jmp init at OVL,
OVL_STEP  = OVL+3             ; jmp step at OVL+3
FXSTORE   = $2000             ; the FX file: main $2000-$5FFF at boot, then aux
FXSTORE_END = $6000

; ---- IIc memory switches ----
RDMAINRAM = $C002             ; reads of $0200-$BFFF from main memory
RDCARDRAM = $C003             ; ... from aux memory
WRMAINRAM = $C004             ; writes to main
WRCARDRAM = $C005             ; writes to aux

; ---- RAM private to the running effect ----
FXRAM     = $0800             ; $0800-$1FFF
FXRAM_END = $2000

; ---- tables built at start-up in the language card (after the sprites) ----
sar4    = $F000
shl4    = $F100
shr4    = $F200
sar5    = $F300
shl3    = $F400
shr5    = $F500

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

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
LSRC    = DSX+12              ; 2: aux_fetch's and aux_copy's source, and
LDST    = DSX+14              ; 2: destination: drawing scratch, set just before each call
                              ; (Fish!'s background job does it mid-row)

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
NFX       = 15                ; effects
OVL       = $8800             ; overlay slot, $8800-$95FF: jmp init at OVL,
OVL_STEP  = OVL+3             ; jmp step at OVL+3
FXSTORE   = $2000             ; the FX file: main $2000-$5FFF at boot, then aux
FXSTORE_END = $6000
FXSTORE2  = $6000             ; the FX2 file: main $2000-$5FFF at boot, then
FXSTORE2_END = $A000          ; aux $6000-$9FFF

; ---- IIc memory switches ----
RDMAINRAM = $C002             ; reads of $0200-$BFFF from main memory
RDCARDRAM = $C003             ; ... from aux memory
WRMAINRAM = $C004             ; writes to main
WRCARDRAM = $C005             ; writes to aux

; ---- RAM private to the running effect ----
FXRAM     = $0800             ; $0800-$1FFF
FXRAM_END = $2000

; ---- Fish! (effect 14): memory while it runs ----
; Page 1 is the only page it shows. Page 2 holds each slot's cache (its
; frame pre-shifted to its place: 216 bytes of lit dots, then at +256 the
; mask inverted, so neither crosses a page), two pages of transparent and
; empty bytes for the columns a creature misses, the eight kernel bodies
; (built at init from column templates) and four copies of the three-layer
; floor one for rows with four or more creatures. FXRAM holds
; the live background and the drawing code that patches itself (FISH_CODE2,
; copied from FX2 at init: the overlay is never written). The code that reads
; aux memory runs from the language card (FISH_LC, copied from FX2 at init).
FISH_BG    = $0800            ; $0800-$0D9F live background: rows 156-191, 40 bytes each
FISH_CODE2 = $0E00            ; $0E00-$1BFF code copied from FX2 at init
FISH_STATE = $1C00            ; $1C00-$1FFF creatures, renderer and scheduler
FISH_CACHE = $4000            ; $4000-$53FF ten caches of 512 bytes
FISH_ZERO  = $5400            ; $5400-$54FF 256 x 0 (and $5500 is its mask: the pages a
FISH_TRANSP = $5500           ; $5500-$55FF 256 x $7F   layer misses read, like a cache)
FISH_PASS  = $5600            ; $5600-$58EB the pass kernels (4 x 187 bytes), made at init
FISH_BODY  = $5900            ; $5900-$5EFF the eight kernel bodies (192 bytes apart), made at init
FISH_LC    = $F700            ; $F700-$FFF9 code that reads aux memory (after aux_fetch)
FISH_LC_END = $FFFA           ; the vectors: never written
; Aux memory: the art stays in FX2 (5 bytes a row), and fish_init builds the
; shift tables, the bit-reverse table and a mirrored copy of every swimmer's
; frames there (the shift reads them with RAMRD on, so they must all be in
; aux). FX ($2000-$5FFF) and FX2 ($6000-$9FFF) are never written.
FISH_SHT   = $0800            ; aux $0800-$0EFF shift tables: shift k in page $08+k
FISH_ISHT  = $0F00            ; aux $0F00-$15FF the same, inverted (masks)
FISH_REV   = $1600            ; aux $1600-$167F 7-bit bit-reverse table
FISH_MIRB  = $1680            ; aux $1680-$1FFF mirrored frames that don't fit area A (none today)
FISH_MIRB_END = $2000
FISH_MIRA  = $A000            ; aux $A000-$BFFF mirrored frames
FISH_MIRA_END = $C000

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

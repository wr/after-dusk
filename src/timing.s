; Timing in ticks of 1/60 s (one NTSC video frame, 17,030 cycles at 1 MHz).
;
; On the IIc, vertical blank is an interrupt source, not the IIe's
; free-running bit: with the IOU enabled ($C07F) and VBL interrupts on
; ($C05B), bit 7 of $C019 latches at each vertical blank until reading
; $C070 clears it. Interrupts stay masked (SEI), so no IRQ is ever taken;
; we only poll the latch. timing_init probes it, because emulators and
; machines differ: no clean edge means we fall back to cycle-counted waits
; (four times longer on the 4 MHz IIc Plus).

.include "config.inc"

.export timing_init, wait_ticks, delay_tick

IOUDISOFF = $C07F     ; write: allow access to the IOU switches
ENVBL     = $C05B     ; write: enable the VBL interrupt source
VBLINT    = $C019     ; read: bit 7 set once a VBL has happened
RSTVBL    = $C070     ; read: clear the VBL latch
ROMID     = $FBBF     ; $05 on the IIc Plus

NLEFT     = CORE+3    ; ticks still to wait

.segment "CODE"

; timing_init: must run while the ROM is visible (before the language card
; is switched in). Sets ST_FAST and ST_TIMING.
timing_init:
        stz ST_FAST
        lda ROMID
        cmp #$05
        bne :+
        inc ST_FAST
:       stz ST_TIMING
        sta IOUDISOFF
        sta ENVBL
        bit RSTVBL              ; clear the latch...
        bit VBLINT
        bmi @no                 ; ...a latch that won't clear is no use
        jsr wait_edge           ; two clean edges in a row means it works
        bcc @no
        bit RSTVBL
        jsr wait_edge
        bcc @no
        bit RSTVBL
        inc ST_TIMING
@no:    rts

; wait_edge: carry set if the VBL latch sets within ~120,000 cycles
; (several frames even on a 4 MHz IIc Plus).
wait_edge:
        ldy #44
        ldx #0
@l:     bit VBLINT
        bmi @yes
        dex
        bne @l
        dey
        bne @l
        clc
        rts
@yes:   sec
        rts

; wait_ticks: A = n. Waits n ticks and adds n to TICKS. In VBL mode a
; blank that happened while the caller was working counts as the first,
; so a step that takes less than n ticks is paced to exactly n.
wait_ticks:
        sta NLEFT
        clc
        adc TICKS
        sta TICKS
        bcc :+
        inc TICKS+1
:       lda NLEFT
        beq @done
        lda ST_TIMING
        beq @slow
@vbl:   bit VBLINT
        bpl @vbl
        bit RSTVBL
        dec NLEFT
        bne @vbl
@done:  rts
@slow:  jsr delay_tick
        lda ST_FAST
        beq :+
        jsr delay_tick          ; IIc Plus: four times the cycles
        jsr delay_tick
        jsr delay_tick
:       dec NLEFT
        bne @slow
        rts

; delay_tick: about 17,030 cycles including the JSR and RTS.
delay_tick:
        ldy #13
@o:     ldx #0
@i:     dex
        bne @i
        dey
        bne @o
        ldx #61
@f:     dex
        bne @f
        rts

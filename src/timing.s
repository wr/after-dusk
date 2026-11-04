; Timing in ticks of 1/60 s (one NTSC video frame, 17,030 cycles at 1 MHz).
;
; On the IIc, vertical blank is an interrupt source, not the IIe's
; free-running bit: with the IOU enabled ($C07F) and VBL interrupts on
; ($C05B), bit 7 of $C019 latches at each vertical blank until reading
; $C070 clears it. Interrupts stay masked (SEI), so no IRQ is ever taken;
; we only poll the latch. timing_init probes it, because emulators and
; machines differ: no clean edge means we fall back to cycle-counted waits
; (four times longer on the 4 MHz IIc Plus).
;
; The latch holds only one blank, so a step that works for longer than a
; frame would lose the rest. vbl_poll counts the latch into FRAMES and
; clears it; effects whose steps can take more than a frame call it during
; their work (the sprite engine does it for every sprite). wait_ticks then
; waits until FRAMES reaches a deadline n ticks after the last one, so a
; step's period is n ticks however long it worked, as long as it finished
; within them.

.include "config.inc"

.export timing_init, wait_ticks, delay_tick, vbl_poll, timing_sync, timing_restart

IOUDISOFF = $C07F     ; write: allow access to the IOU switches
ENVBL     = $C05B     ; write: enable the VBL interrupt source
VBLINT    = $C019     ; read: bit 7 set once a VBL has happened
RSTVBL    = $C070     ; read: clear the VBL latch
ROMID     = $FBBF     ; $05 on the IIc Plus

NLEFT     = CORE+3    ; ticks still to wait
FRAMES    = CORE+7    ; 2: vertical blanks counted so far
NEXT      = CORE+9    ; 2: the frame the current step ends on
LASTF     = CORE+4    ; 2: FRAMES when the last wait ended

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
        jsr wait_edge           ; two clean edges in a row means it works,
        bcc @no                 ; and the latch must clear after each one
        bit RSTVBL
        bit VBLINT
        bmi @no
        jsr wait_edge
        bcc @no
        bit RSTVBL
        bit VBLINT
        bmi @no
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

; wait_ticks: A = n. Waits until n ticks after the end of the last wait
; (VBL mode) or for n ticks (fallback). Adds the frames that really passed
; since the last wait to TICKS (n in fallback). A step that ran past its
; deadline starts the next one from now rather than catching up.
wait_ticks:
        sta NLEFT
        lda NLEFT
        beq @done
        lda ST_TIMING
        beq @slow
        clc                     ; NEXT += n
        lda NEXT
        adc NLEFT
        sta NEXT
        bcc @vbl
        inc NEXT+1
@vbl:   jsr vbl_poll
        sec                     ; until FRAMES - NEXT >= 0
        lda FRAMES
        sbc NEXT
        sta NLEFT               ; (low byte of the difference)
        lda FRAMES+1
        sbc NEXT+1
        bmi @vbl
        sec                     ; TICKS += frames since the last wait: real
        lda FRAMES              ; time, even for a step that ran long
        sbc LASTF
        clc
        adc TICKS
        sta TICKS
        bcc :+
        inc TICKS+1
:       lda FRAMES
        sta LASTF
        lda FRAMES+1
        sta LASTF+1
        lda NLEFT               ; late (FRAMES > NEXT)? the next step counts
        beq @done               ; from now rather than catching up
        jmp timing_restart
@done:  rts
@slow:  lda NLEFT               ; fallback: TICKS += n
        clc
        adc TICKS
        sta TICKS
        bcc @delay
        inc TICKS+1
@delay: jsr delay_tick
        lda ST_FAST
        beq :+
        jsr delay_tick          ; IIc Plus: four times the cycles
        jsr delay_tick
        jsr delay_tick
:       dec NLEFT
        bne @delay
        rts

; vbl_poll: count a vertical blank into FRAMES if one has happened since the
; last poll. Cheap; keeps A, X and Y. Does nothing in fallback mode.
vbl_poll:
        pha
        lda ST_TIMING
        beq @no
        bit VBLINT
        bpl @no
        bit RSTVBL
        inc FRAMES
        bne @no
        inc FRAMES+1
@no:    pla
        rts

; timing_sync: the next wait's ticks count from now, and the time until now
; isn't counted into TICKS (after long set-up work).
timing_sync:
        lda FRAMES
        sta LASTF
        lda FRAMES+1
        sta LASTF+1
        ; fall through
; timing_restart: the next wait's deadline counts from now; the time so far
; still counts into TICKS.
timing_restart:
        lda FRAMES
        sta NEXT
        lda FRAMES+1
        sta NEXT+1
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

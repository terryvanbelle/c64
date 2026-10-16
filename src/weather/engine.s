; A Mouthful of Weather -- one imagined voice, played by the stock SID.
; CIA1 Timer A: score/keyboard at 100 Hz. CIA2 Timer A: packed 4-bit PCM.
; NMI owns the PCM cursor. IRQ publishes a complete fragment only while idle.
; All three SID voices provide a static DC level (pulse + TEST + gate), making
; the volume DAC audible on 8580 as well as 6581, without a hardware digi mod.
.setcpu "6502"
.import visual_init, visual_tick
.import __RODATA_RUN__, __RODATA_SIZE__
.export start, main_loop, irq, irq_done, nmi, nmi_done, sample_ptr
.export video_standard, play_tick, song_done, mouth_open, voice_shape
.export phrase_index, record_left, music_reset, music_tick, key_sampled
.export key_raw, irq_count, song_finished, sample_start, sample_end
.exportzp score_ptr, playing, paused, bytes_left, nibble_phase, byte_cache

SID = $d400

.segment "ZEROPAGE"
score_ptr:    .res 2
playing:      .res 1
paused:       .res 1
bytes_left:   .res 2
nibble_phase: .res 1
byte_cache:   .res 1

.segment "BASIC"
    .word basic_end
    .word 10
    .byte $9e, "2061", 0
basic_end:
    .word 0

.segment "CODE"
start:
    sei
    cld
    ldx #$ff
    txs
    lda #0
    sta $d015
    sta $d01a
    sta $dc0e
    sta $dc0f
    sta $dd0e
    sta $dd0f
    sta $d020
    sta $d021
    lda #$0b
    sta $d011
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #$0f
    sta $d019
    lda #<irq
    sta $fffe
    lda #>irq
    sta $ffff
    lda #<nmi
    sta $fffa
    lda #>nmi
    sta $fffb
    lda $00
    ora #7
    sta $00
    lda $01
    and #$f8
    ora #5
    sta $01
    lda #0
    ldx #0
clear_state:
    sta $0200,x
    sta $0300,x
    inx
    bne clear_state
    jsr detect_video
    jsr visual_init
    jsr sid_init
    jsr music_reset

    ; Start the sample timer in its harmless idle path. Subsequent fragments
    ; set their own rate. CIA2 Timer B/FLAG/serial/alarms remain masked.
    ldy #16
    jsr set_sample_timer
    lda #$81
    sta $dd0d
    lda #$11
    sta $dd0e
    ldx video_standard
    lda timer_lo,x
    sta $dc04
    lda timer_hi,x
    sta $dc05
    lda #$81
    sta $dc0d
    lda #$11
    sta $dc0e
    cli
main_loop:
    lda visual_request
    cmp visual_seen
    beq main_loop
    sta visual_seen
    jsr visual_tick
    jmp main_loop

.proc detect_video
low:
    bit $d011
    bmi low
high:
    bit $d011
    bpl high
measure:
    lda $d012
    cmp highest_raster
    bcc same
    sta highest_raster
same:
    bit $d011
    bmi measure
    lda highest_raster
    cmp #32
    bcs done
    ldx #1
    cmp #6
    bcs store
    inx
store:
    stx video_standard
done:
    rts
.endproc

.proc sid_init
    lda #0
    ldx #24
clear:
    sta SID,x
    dex
    bpl clear
    lda #$f0                    ; Sustain 15, attack 2 ms, no filter routing.
    sta SID+6
    sta SID+13
    sta SID+20
    lda #$49                    ; Pulse + TEST + gate: stable DC, no oscillator.
    sta SID+4
    sta SID+11
    sta SID+18
    lda #8
    sta SID+24
    rts
.endproc

irq:
    pha
    txa
    pha
    tya
    pha
    cld
    lda $dc0d
    and #1
    beq irq_done
    inc irq_count
    bne :+
    inc irq_count+1
:
    jsr poll_keys
key_sampled:
    lda key_raw
    eor key_previous
    and key_raw
    tax
    lda key_raw
    sta key_previous
    txa
    and #2
    beq check_pause
    jsr music_reset
    jmp tick_display
check_pause:
    txa
    and #1
    beq play
    lda paused
    eor #1
    sta paused                   ; Atomic: NMI either advances or holds a nibble.
play:
    lda paused
    ora song_done
    beq active
    lda #0
    sta mouth_open
    jmp tick_display
active:
    jsr music_tick
tick_display:
    inc visual_divider
    lda visual_divider
    and #3
    bne irq_done
    inc visual_request
irq_done:
    pla
    tay
    pla
    tax
    pla
    rti

; One page contains every sample-path branch, so none gains a page-cross cycle.
; The longest path is 81 instruction cycles (high nibble / length borrow or
; final byte). Add 7 NMI entry, at most 7 interrupted-instruction cycles and
; 43 VIC bad-line stall cycles: 138 cycles. Fastest supported PAL period is
; at least 142 cycles. No sprites, nested IRQ, or raster effects are enabled.
; X/Y are untouched. RTI restores flags, including the interrupted carry.
; CODE is fixed at $080d. Pad to an absolute page boundary without imposing
; an incompatible alignment requirement on the BASIC-adjacent CODE segment.
.res .lobyte(-(*-start)-$0d), $ea
nmi:
    pha
    lda $dd0d                    ; Release CIA2 NMI before the next timer edge.
    and #1
    beq nmi_done                 ; RESTORE alone does not advance the sample.
    lda paused
    bne nmi_idle
    lda playing
    beq nmi_idle
    lda nibble_phase
    bne nmi_high
sample_fetch:
    lda $ffff                    ; Writable absolute operand avoids using X/Y.
sample_ptr = sample_fetch+1
    sta byte_cache
    and #$0f
    sta SID+24
    inc nibble_phase
    inc sample_ptr
    bne nmi_done
    inc sample_ptr+1
    jmp nmi_done
nmi_high:
    lda byte_cache
    lsr
    lsr
    lsr
    lsr
    sta SID+24
    dec nibble_phase
    lda bytes_left
    bne nmi_decrement
    dec bytes_left+1
nmi_decrement:
    dec bytes_left
    lda bytes_left
    ora bytes_left+1
    bne nmi_done
sample_end:
    lda #0
    sta playing                  ; Publish completion only after the high nibble.
nmi_done:
    pla
    rti
nmi_idle:
    lda #8
    sta SID+24
    bne nmi_done
nmi_limit:
.assert >nmi = >(nmi_limit-1), lderror, "PCM NMI must fit within one page"

; Safe low-only keyboard columns: Space PA7/PB4, R PA2/PB1.
; Never drive a high output against a held key or port-1 joystick switch.
.proc poll_keys
    lda #0
    sta $dc02
    sta $dc03
    sta key_raw
    lda #$ff
    sta $dc00
    sta $dc01
    lda $dc01
    sta key_baseline
    lda #$7f
    sta $dc00
    lda #$80
    sta $dc02
    lda $dc01
    eor #$ff
    and key_baseline
    and #$10
    beq no_space
    inc key_raw
no_space:
    lda #0
    sta $dc02
    lda #$fb
    sta $dc00
    lda #4
    sta $dc02
    lda $dc01
    eor #$ff
    and key_baseline
    and #2
    ora key_raw
    sta key_raw
    lda #0
    sta $dc02
    lda #$ff
    sta $dc00
    rts
.endproc

.proc music_reset
    lda #0
    sta playing                  ; First store: NMI may no longer read the cursor.
    sta paused
    sta song_done
    sta play_tick
    sta play_tick+1
    sta mouth_open
    sta voice_shape
    sta phrase_index
    sta event_energy
    sta bytes_left
    sta bytes_left+1
    sta nibble_phase
    sta byte_cache
    sta sample_ptr
    sta sample_ptr+1
    lda #8
    sta SID+24
    lda #<score_data
    sta score_ptr
    lda #>score_data
    sta score_ptr+1
    lda #20                      ; Allow SID DC/envelopes to settle before speech.
    sta record_left
    rts
.endproc

.proc music_tick
    lda record_left
    bne count
    lda playing
    bne mouth                    ; Graceful overrun: finish PCM before next event.
    jsr next_event
    lda song_done
    bne done
count:
    dec record_left
    inc play_tick
    bne mouth
    inc play_tick+1
mouth:
    lda playing
    beq closing
    lda event_energy
    sta mouth_open
    rts
closing:
    lda mouth_open
    beq done
    dec mouth_open
done:
    rts
.endproc

; Every record is six bytes: sample ID, duration in 100 Hz ticks, rate index,
; mouth shape, energy and section. $fe is a rest, $ff the end marker.
; A non-rest fragment is only published after the preceding fragment finishes.
.proc next_event
    ldy #0
    lda (score_ptr),y
    cmp #$ff
    beq ended
    sta event_sample
    iny
    lda (score_ptr),y
    sta record_left
    iny
    lda (score_ptr),y
    sta event_rate
    iny
    lda (score_ptr),y
    sta voice_shape
    iny
    lda (score_ptr),y
    sta event_energy
    iny
    lda (score_ptr),y
    sta phrase_index
    clc
    lda score_ptr
    adc #6
    sta score_ptr
    bcc :+
    inc score_ptr+1
:
    ldx event_sample
    cpx #$fe
    beq done
    jsr sample_start
done:
    rts
ended:
    jmp song_finished
.endproc

; X = sample ID. The NMI sees playing=0 for this entire publication sequence.
sample_start:
    lda sample_lo,x
    sta sample_ptr
    lda sample_hi,x
    sta sample_ptr+1
    lda sample_len_lo,x
    sta bytes_left
    lda sample_len_hi,x
    sta bytes_left+1
    ora bytes_left
    beq sample_start_done         ; Empty input cannot underflow the length.
    lda #0
    sta nibble_phase
    sta byte_cache
    sta $dd0e                    ; Stop, then acknowledge any old pending edge.
    lda $dd0d
    ldy event_rate
    jsr set_sample_timer
    lda #$11                    ; Reload before publishing; first edge is future.
    sta $dd0e
    lda #1
    sta playing                  ; The only publication store; all fields ready.
sample_start_done:
    rts

; Y = pitch/rate index 0..31. Caller has stopped CIA2 Timer A.
.proc set_sample_timer
    lda video_standard
    bne ntsc
    lda sample_timer_pal_lo,y
    sta $dd04
    lda sample_timer_pal_hi,y
    sta $dd05
    rts
ntsc:
    lda sample_timer_ntsc_lo,y
    sta $dd04
    lda sample_timer_ntsc_hi,y
    sta $dd05
    rts
.endproc

song_finished:
    lda #0
    sta playing
    sta record_left
    sta mouth_open
    lda #8
    sta SID+24
    lda #1
    sta song_done
    rts

.segment "RODATA"
timer_lo: .byte <9851, <10226, <10226
timer_hi: .byte >9851, >10226, >10226
.include "rate.inc"
.include "score.inc"
.include "voice.inc"
.assert __RODATA_RUN__ + __RODATA_SIZE__ <= $4000, lderror, "Code/art overlap display bank"

.segment "BSS"
video_standard: .res 1
highest_raster: .res 1
play_tick: .res 2
irq_count: .res 2
song_done: .res 1
mouth_open: .res 1
voice_shape: .res 1
phrase_index: .res 1
record_left: .res 1
event_energy: .res 1
event_sample: .res 1
event_rate: .res 1
key_raw: .res 1
key_baseline: .res 1
key_previous: .res 1
visual_divider: .res 1
visual_request: .res 1
visual_seen: .res 1

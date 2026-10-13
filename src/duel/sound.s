; Original compact arcade sound score: "Signal and Response".
;
; ABI, all calls clobber A/X/Y and flags:
;   duel_sound_init:    A=0 PAL, A=1 common NTSC, A=2 early NTSC.
;   duel_sound_tick:    call at nominal 50 Hz, including the victory screen.
;   duel_sound_event:   A=1 shot, 2 hit, 3 flag pickup, 4 capture, 5 victory,
;                       6 flag return; X=player 0 or 1.
;   duel_sound_silence: immediate mute; discard pending effects. The next ticks
;                       resume the sparse background phrase after one second.
;
; SID must be CPU-visible. Caller serializes calls; the game IRQ owns updates,
; and startup calls init with interrupts disabled. No zero page, no banking,
; no SID reads, and no self-modifying code. Voices 1/2 belong to players 0/1;
; voice 3 plays the quiet triangle pulse or shared objective fanfares. A shot
; cannot interrupt its player's hit/pickup/return feedback. A capture cannot
; interrupt a victory. Event submission clears the gate/waveform; its new note
; starts on the next tick, leaving one complete tick for retriggering. Each
; sequenced note releases two calls before the next note. Every sound is finite.
;
; Only individual pulse, triangle, and noise waveforms are used. Master volume
; is 7; no filtering, sync, ring modulation, combined waveforms, or digi volume
; changes. PWM is a fixed 50% duty. The background is one short note per second.
; The original eight-note phrase takes eight seconds; capture/victory melodies
; preempt it. Both PAL/NTSC tuning and 50 Hz scheduling are required separately.
;
; Register layout, gate/envelope semantics, and pitch relation checked against:
; https://myoldcomputer.nl/Files/mos_6581_sid.pdf
; frequency = SID word * machine clock / 2^24. Tables use A4=440 Hz and the
; repository's 985248 Hz PAL / 1022730 Hz NTSC clock assumptions.

.setcpu "6502"
.export duel_sound_init, duel_sound_tick, duel_sound_event, duel_sound_silence

SID = $d400
AMBIENT = 7

.segment "CODE"
sound_code_start:

.proc duel_sound_init
    cmp #0
    beq region_ready
    lda #1
region_ready:
    pha
    lda #0
    ldx #24
clear_sid:
    sta SID,x
    dex
    bpl clear_sid

    ; No CRT initializes standalone assembly BSS.
    ldx #sound_state_end-sound_state-1
clear_state:
    sta sound_state,x
    dex
    bpl clear_state
    pla
    sta sound_region
    lda #50
    sta ambient_timer
    lda #8
    sta SID+3
    sta SID+10
    sta SID+17
    lda #7
    sta SID+24
    rts
.endproc

.proc duel_sound_silence
    ; Dropping waveform as well as gate makes pause immediately silent even
    ; while an envelope's release tail still runs inside the SID.
    lda #0
    sta SID+4
    sta SID+11
    sta SID+18
    ldx #sound_state_end-sound_state-1
clear_state:
    sta sound_state,x
    dex
    bpl clear_state
    lda #50
    sta ambient_timer
    rts
.endproc

.proc duel_sound_event
    cmp #1
    bcc done
    cmp #AMBIENT
    bcs done
    sta event_number
    cmp #4
    beq shared
    cmp #5
    bne player
shared:
    ldx #2
    ; Do not let a later capture replace the winner's fanfare.
    lda voice_kind,x
    cmp #5
    beq check_victory
    lda voice_pending,x
    cmp #5
    bne accept
check_victory:
    lda event_number
    cmp #5
    bne done
    jmp accept
player:
    cpx #2
    bcs done
    ; Shot spam is useful feedback, but must not erase important events.
    lda event_number
    cmp #1
    bne accept
    lda voice_kind,x
    cmp #2
    bcs done
    lda voice_pending,x
    cmp #2
    bcs done
accept:
    lda event_number
    sta voice_pending,x
    lda voice_offset,x
    tay
    lda #0
    sta SID+4,y
done:
    rts
.endproc

.proc duel_sound_tick
    ldx #0
next_voice:
    lda voice_pending,x
    beq update_voice
    sta voice_kind,x
    tay
    lda #0
    sta voice_pending,x
    lda sequence_count,y
    sta voice_remaining,x
    lda sequence_start,y
    sta voice_step,x
    cpy #AMBIENT
    bne start_note
    ; The ambient phrase has one-note events, advancing only when played.
    clc
    adc ambient_step
    sta voice_step,x
    inc ambient_step
    lda ambient_step
    and #7
    sta ambient_step
start_note:
    jsr configure_note
    jmp advance_voice

update_voice:
    lda voice_kind,x
    beq advance_voice
    dec voice_phase,x
    beq next_note
    lda voice_phase,x
    cmp #2
    bne advance_voice
    ; Release while retaining this note's waveform; no write-only readback.
    lda voice_kind,x
    tay
    lda waveform,y
    and #$fe
    pha
    lda voice_offset,x
    tay
    pla
    sta SID+4,y
    jmp advance_voice

next_note:
    dec voice_remaining,x
    beq finish_voice
    inc voice_step,x
    jsr configure_note
    jmp advance_voice
finish_voice:
    lda #0
    sta voice_kind,x
advance_voice:
    inx
    cpx #3
    bne next_voice

    dec ambient_timer
    bne done
    lda #50
    sta ambient_timer
    lda voice_kind+2
    ora voice_pending+2
    bne done
    lda #AMBIENT
    sta voice_pending+2
done:
    rts
.endproc

; X = logical voice 0/1/2; preserves X for the bounded tick loop.
; Tables contain only single waveforms and notes C4=0 through B6=35.
.proc configure_note
    stx current_voice
    lda voice_kind,x
    tay
    lda voice_offset,x
    tax
    lda attack_decay,y
    sta SID+5,x
    lda sustain_release,y
    sta SID+6,x
    lda waveform,y
    and #$fe
    sta SID+4,x

    ldx current_voice
    ldy voice_step,x
    lda sequence_notes,y
    asl
    tay
    lda voice_offset,x
    tax
    lda sound_region
    bne ntsc
    lda frequency_pal,y
    sta SID,x
    lda frequency_pal+1,y
    sta SID+1,x
    jmp pitch_ready
ntsc:
    lda frequency_ntsc,y
    sta SID,x
    lda frequency_ntsc+1,y
    sta SID+1,x
pitch_ready:
    ; X is still the SID offset; retrieve the instrument without a SID read.
    ldy current_voice
    lda voice_kind,y
    tay
    lda waveform,y
    sta SID+4,x
    lda note_period,y
    ldx current_voice
    sta voice_phase,x
    rts
.endproc

sound_code_end:
.assert sound_code_end-sound_code_start < 1024, error, "Duel sound code budget"

.segment "RODATA"
sound_data_start:
voice_offset:    .byte 0, 7, 14
sequence_start:  .byte 0, 0, 1, 2, 5, 9, 17, 20
sequence_count:  .byte 0, 1, 1, 3, 4, 8, 3, 1
note_period:     .byte 0, 6, 10, 6, 7, 8, 6, 6
waveform:        .byte 0, $41, $81, $11, $41, $41, $11, $11
attack_decay:    .byte 0, $02, $03, $02, $02, $03, $02, $22
sustain_release: .byte 0, $01, $02, $01, $01, $02, $01, $01

; Shot: A5 pulse; hit: D4 noise; pickup/return: opposing C-major triads.
; Capture: rising four notes; winner: resolved eight-note response.
; Background: sparse C/D phrases; nothing competes with both player's SFX.
sequence_notes:
    .byte 21
    .byte 2
    .byte 12, 16, 19
    .byte 12, 16, 19, 24
    .byte 16, 19, 24, 28, 26, 24, 19, 24
    .byte 19, 16, 12
    .byte 0, 4, 7, 4, 2, 5, 9, 5
sequence_notes_end:
.assert sequence_notes_end-sequence_notes = 28, error, "Duel sound sequences"

frequency_pal:
    .word $1167, $1270, $1389, $14b2, $15ed, $173b, $189c, $1a13, $1ba0, $1d45, $1f02, $20da
    .word $22ce, $24e0, $2711, $2964, $2bda, $2e76, $3139, $3426, $3740, $3a89, $3e04, $41b4
    .word $459c, $49c0, $4e23, $52c8, $57b4, $5ceb, $6272, $684c, $6e80, $7512, $7c08, $8368
frequency_ntsc:
    .word $10c4, $11c3, $12d1, $13f0, $151f, $1661, $17b6, $191e, $1a9d, $1c32, $1ddf, $1fa6
    .word $2188, $2386, $25a3, $27e0, $2a3f, $2cc2, $2f6b, $323d, $353a, $3864, $3bbe, $3f4c
    .word $430f, $470c, $4b46, $4fbf, $547d, $5983, $5ed6, $647a, $6a73, $70c8, $777c, $7e97
sound_data_end:
.assert sound_data_end-sound_data_start < 256, error, "Duel sound data budget"

.segment "BSS"
sound_region: .res 1
sound_state:
voice_kind:      .res 3
voice_pending:   .res 3
voice_phase:     .res 3
voice_step:      .res 3
voice_remaining: .res 3
ambient_timer:   .res 1
ambient_step:    .res 1
current_voice:   .res 1
event_number:    .res 1
sound_state_end:
.assert sound_state_end-sound_region < 32, error, "Duel sound state budget"

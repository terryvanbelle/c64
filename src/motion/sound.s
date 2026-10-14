; BORROWED MOTION: original miniature score, "An Unwound Room".
; Main-thread ABI; all calls clobber A/X/Y/flags. No ZP, CIA, IRQ or banking.
; sound_init: A=0 PAL, 1 common NTSC, 2 early NTSC. Enables sound initially.
; sound_tick: nominal 50 Hz. sound_event: A=1 select,2 take,3 give,4 swap,
; 5 bounce,6 settle,7 clear,8 undo,9 start. Highest-priority queued event wins.
; sound_silence: gates off all voices and discards events, preserves enabled.
; External sound_enabled=0 mutes on the next tick; 1 resumes the score.
;
; Four soft triangle roots and eight brief pulse droplets form a 16-second
; Dm(add9), Fmaj9, Bbmaj7, Csus progression. Silence between notes leaves space
; for decisions. Voice 3 has distinct short action gestures; settle rises and
; undo falls. Low-priority selection/bumps cannot cut off completion gestures.
; One full 20ms tick gates off an interrupted effect before its next attack.
; Sequential effect notes release 40ms before the next attack. No combined
; waveforms, filter, sync, ring modulation or volume digi; master volume 6.
; Pitch tables: round(440*2**((MIDI-69)/12)*2**24/clock), MIDI36..83,
; clocks 985248 PAL and 1022730 NTSC. Both NTSC variants use NTSC pitch.
; Caller serializes entry points and keeps I/O visible. All BSS initialized.
.setcpu "6502"
.export sound_init,sound_tick,sound_event,sound_silence,sound_enabled
SID=$d400
REST=$ff

.segment "BSS"
sound_state:
sound_enabled: .res 1
sound_was_enabled: .res 1
sound_region: .res 1
music_clock: .res 1
music_step: .res 1
root_life: .res 1
drop_life: .res 1
effect_pending: .res 1
effect_current: .res 1
effect_step: .res 1
effect_life: .res 1
effect_wait: .res 1
event_number: .res 1
event_priority: .res 1
voice_offset: .res 1
sound_state_end:

.segment "CODE"
.proc sound_init
    pha
    lda #0
    ldx #sound_state_end-sound_state-1
state:
    sta sound_state,x
    dex
    bpl state
    ldx #24
sid:
    sta SID,x
    dex
    bpl sid
    pla
    cmp #0
    beq region
    lda #1
region:
    sta sound_region
    lda #1
    sta sound_enabled
    sta sound_was_enabled
    sta music_clock
    lda #15
    sta music_step
    lda #6
    sta SID+24
    lda #$68
    sta SID+5
    lda #$36
    sta SID+6
    lda #$24
    sta SID+12
    lda #$05
    sta SID+13
    lda #2
    sta SID+10             ; voice 2: 12.5% pulse
    lda #4
    sta SID+17             ; effect pulse: 25%
    rts
.endproc

.proc sound_silence
    lda #0
    sta SID+4
    sta SID+11
    sta SID+18
    sta root_life
    sta drop_life
    sta effect_pending
    sta effect_current
    sta effect_step
    sta effect_life
    sta effect_wait
    lda #50
    sta music_clock
    rts
.endproc

.proc sound_event
    cmp #1
    bcc done
    cmp #10
    bcs done
    ldx sound_enabled
    beq done
    sta event_number
    tax
    lda priorities,x
    sta event_priority
    ldx effect_current
    cmp priorities,x
    bcc done
    ldx effect_pending
    lda event_priority
    cmp priorities,x
    bcc done
    lda event_number
    sta effect_pending
done:
    rts
.endproc

.proc sound_tick
    lda sound_enabled
    bne enabled
    lda sound_was_enabled
    beq done
    jsr sound_silence
    lda #0
    sta sound_was_enabled
done:
    rts
enabled:
    lda sound_was_enabled
    bne clocks
    lda #1
    sta sound_was_enabled
    sta music_clock
clocks:
    lda root_life
    beq drop
    dec root_life
    bne drop
    lda #$10
    sta SID+4
drop:
    lda drop_life
    beq music
    dec drop_life
    bne music
    lda #$40
    sta SID+11
music:
    dec music_clock
    bne effects
    lda #50
    sta music_clock
    inc music_step
    lda music_step
    and #15
    sta music_step
    tax
    lda roots,x
    cmp #REST
    beq droplet
    ldy #0
    jsr set_pitch
    lda #$11
    sta SID+4
    lda #70
    sta root_life
droplet:
    ldx music_step
    lda droplets,x
    cmp #REST
    beq effects
    ldy #7
    jsr set_pitch
    lda #$41
    sta SID+11
    lda #12
    sta drop_life
effects:
    lda effect_pending
    beq ongoing
    sta effect_current
    lda #0
    sta effect_pending
    sta effect_step
    sta effect_life
    sta SID+18
    lda #1
    sta effect_wait
    rts
ongoing:
    lda effect_current
    beq finished
    lda effect_wait
    beq life
    dec effect_wait
    jmp next_note
life:
    dec effect_life
    lda effect_life
    cmp #2
    bne maybe_next
    lda #0
    sta SID+18
maybe_next:
    lda effect_life
    bne finished
next_note:
    ldx effect_current
    lda sequence_starts,x
    clc
    adc effect_step
    tay
    lda sequence_notes,y
    cmp #REST
    beq end_sequence
    ldy #14
    jsr set_pitch
    ldx effect_current
    lda attacks,x
    sta SID+19
    lda releases,x
    sta SID+20
    lda durations,x
    sta effect_life
    lda waveforms,x
    sta SID+18
    inc effect_step
finished:
    rts
end_sequence:
    lda #0
    sta effect_current
    sta effect_life
    sta SID+18
    rts
.endproc

; A=note C2..B5 (0..47), Y=SID voice offset 0/7/14. Clobbers A/X/Y.
.proc set_pitch
    sty voice_offset
    asl
    tax
    ldy sound_region
    bne ntsc
    ldy voice_offset
    lda frequency_pal,x
    sta SID,y
    lda frequency_pal+1,x
    sta SID+1,y
    rts
ntsc:
    ldy voice_offset
    lda frequency_ntsc,x
    sta SID,y
    lda frequency_ntsc+1,x
    sta SID+1,y
    rts
.endproc

.segment "RODATA"
roots:
    .byte 14,REST,REST,REST,17,REST,REST,REST
    .byte 10,REST,REST,REST,12,REST,REST,REST
droplets:
    .byte REST,33,REST,28,REST,36,REST,31
    .byte REST,29,REST,33,REST,38,REST,31
priorities: .byte 0,1,3,3,4,2,5,8,7,8
durations:  .byte 0,5,6,6,6,4,10,12,7,10
attacks:    .byte 0,$01,$03,$03,$03,$01,$05,$06,$03,$05
releases:   .byte 0,$02,$03,$03,$03,$00,$04,$05,$03,$04
waveforms:  .byte 0,$41,$11,$11,$11,$41,$11,$11,$11,$11
sequence_starts:
    .byte 0,select-sequence_notes,take-sequence_notes,give-sequence_notes
    .byte swap-sequence_notes,bounce-sequence_notes,settle-sequence_notes
    .byte clear-sequence_notes,undo-sequence_notes,begin-sequence_notes
sequence_notes:
select: .byte 26,REST
take:   .byte 33,40,REST
give:   .byte 40,33,REST
swap:   .byte 31,38,43,REST
bounce: .byte 14,REST
settle: .byte 33,36,40,REST
clear:  .byte 26,33,38,41,45,REST
undo:   .byte 40,36,33,REST
begin:  .byte 26,29,33,36,REST
frequency_pal:
    .word $045a,$049c,$04e2,$052d,$057b,$05cf,$0627,$0685,$06e8,$0751,$07c1,$0837
    .word $08b4,$0938,$09c4,$0a59,$0af7,$0b9d,$0c4e,$0d0a,$0dd0,$0ea2,$0f81,$106d
    .word $1167,$1270,$1389,$14b2,$15ed,$173b,$189c,$1a13,$1ba0,$1d45,$1f02,$20da
    .word $22ce,$24e0,$2711,$2964,$2bda,$2e76,$3139,$3426,$3740,$3a89,$3e04,$41b4
frequency_ntsc:
    .word $0431,$0471,$04b4,$04fc,$0548,$0598,$05ed,$0648,$06a7,$070c,$0778,$07e9
    .word $0862,$08e1,$0969,$09f8,$0a90,$0b30,$0bdb,$0c8f,$0d4e,$0e19,$0ef0,$0fd3
    .word $10c4,$11c3,$12d1,$13f0,$151f,$1661,$17b6,$191e,$1a9d,$1c32,$1ddf,$1fa6
    .word $2188,$2386,$25a3,$27e0,$2a3f,$2cc2,$2f6b,$323d,$353a,$3864,$3bbe,$3f4c
.assert sound_state_end-sound_state = 15,error,"Sound state size"

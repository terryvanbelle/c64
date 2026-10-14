; IRONVEIL original SID feedback: "Steel and Signals".
;
; ABI, all calls clobber A/X/Y and flags:
;   duel_sound_init:    A=0 PAL, A=1 common NTSC, A=2 early NTSC.
;   duel_sound_tick:    call after game_tick at nominal 50 Hz.
;   duel_sound_event:   A=1 cannon, 2 armour impact, 4 knockout, 5 victory;
;                       X=player 0/1 for a cannon. Shared events ignore X.
;   duel_sound_silence: immediately stop all voices and synchronize motion.
;   duel_sound_motion_sync: synchronize fixed-point positions/hulls only.
;
; Voices 1/2 are distinct low pulse engines, borrowed briefly by their own
; cannon. Voice 3 supplies finite impact/knockout/victory feedback. There is no
; periodic music. Actual translation (including fractions) or hull rotation
; powers an engine; blocked throttle, turret-only input and parked tanks are
; quiet. Engines are disabled outside live play and during respawn. Pause and
; match setup use silence to discard effects and avoid a false teleport sound.
;
; CPU mode: own cyan engine has modest constant sustain; gold enemy engine is
; stronger within 96px, softer through 160/224px, inaudible beyond 224px. PvP
; applies the same proximity curve to both voices, with a faint sustain-1 floor
; beyond 224px so each moving player still has its own engine on the shared SID.
; Distance
; is Chebyshev, using declared world positions solely for this hearing cue.
; A volume-band change releases the gate for a full tick before retriggering:
; SID sustain cannot be relied on to raise an already decaying envelope.
;
; Caller owns serialization and CPU-visible SID I/O. No zero page, banking,
; SID reads or self-modifying code. Register intent is kept in scalar shadows.
; Only individual pulse/noise waveforms are used. Pulse duties are fixed at
; 50% cyan and 37.5% gold, pitches A1/D2; global volume is fixed at 6. No filter,
; sync, ring, combined waves or volume digi. Release 0 gives engine retriggers
; a quiet full 20ms interval; cannon/shared notes release two ticks in advance.
; Both PAL/NTSC tuning and 50 Hz scheduling are required separately.
;
; SID register/envelope semantics and f = word * clock / 2^24 checked against:
; https://myoldcomputer.nl/Files/mos_6581_sid.pdf
; Tuning uses 985248Hz PAL / 1022730Hz NTSC, A4=440Hz. No 6581-only filter trick.

.setcpu "6502"
.export duel_sound_init, duel_sound_tick, duel_sound_event, duel_sound_silence
.export duel_sound_motion_sync
.export duel_sound_tick_done
.import game_state, computer_player2, respawn, hull
.import tank_xlo, tank_xhi, tank_y, tank_xfrac, tank_yfrac

SID = $d400

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
    ldx #sound_state_end-sound_state-1
clear_state:
    sta sound_state,x
    dex
    bpl clear_state
    pla
    sta sound_region
    lda #8
    sta SID+3
    sta SID+17
    lda #6
    sta SID+10
    lda #6
    sta SID+24
    rts
.endproc

.proc duel_sound_motion_sync
    ldx #1
copy:
    lda tank_xlo,x
    sta previous_xlo,x
    lda tank_xhi,x
    sta previous_xhi,x
    lda tank_y,x
    sta previous_y,x
    lda tank_xfrac,x
    sta previous_xfrac,x
    lda tank_yfrac,x
    sta previous_yfrac,x
    lda hull,x
    sta previous_hull,x
    lda respawn,x
    sta previous_respawn,x
    lda #0
    sta engine_motion,x
    dex
    bpl copy
    rts
.endproc

.proc duel_sound_silence
    lda #0
    sta SID+4
    sta SID+11
    sta SID+18
    ldx #sound_state_end-sound_state-1
clear_state:
    sta sound_state,x
    dex
    bpl clear_state
    jmp duel_sound_motion_sync
.endproc

.proc duel_sound_event
    cmp #1
    beq player
    cmp #2
    beq shared
    cmp #4
    beq shared
    cmp #5
    bne done
shared:
    sta event_number
    ldx #2
    ; Neither an impact nor a KO interrupts the winner; an impact also waits
    ; behind a KO. Repeated small impacts may retrigger immediate feedback.
    lda voice_kind,x
    cmp #4
    bcc pending_priority
    cmp event_number
    bcs done
pending_priority:
    lda voice_pending,x
    cmp #4
    bcc accept
    cmp event_number
    bcs done
    jmp accept
player:
    cpx #2
    bcs done
    sta event_number
    lda #0
    sta engine_active,x
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

; Snapshot every fixed-point component/hull every tick. A wrap or a movement
; smaller than one pixel still registers; joystick throttle itself is ignored.
.proc detect_motion
    ldx #1
next:
    lda #0
    sta engine_motion,x
    lda game_state
    cmp #1
    bne copy
    lda respawn,x
    bne copy
    lda previous_respawn,x
    bne copy                 ; a teleport from respawn is not engine movement
    lda tank_xlo,x
    cmp previous_xlo,x
    bne moved
    lda tank_xhi,x
    cmp previous_xhi,x
    bne moved
    lda tank_y,x
    cmp previous_y,x
    bne moved
    lda tank_xfrac,x
    cmp previous_xfrac,x
    bne moved
    lda tank_yfrac,x
    cmp previous_yfrac,x
    bne moved
    lda hull,x
    cmp previous_hull,x
    beq copy
moved:
    inc engine_motion,x
copy:
    lda tank_xlo,x
    sta previous_xlo,x
    lda tank_xhi,x
    sta previous_xhi,x
    lda tank_y,x
    sta previous_y,x
    lda tank_xfrac,x
    sta previous_xfrac,x
    lda tank_yfrac,x
    sta previous_yfrac,x
    lda hull,x
    sta previous_hull,x
    lda respawn,x
    sta previous_respawn,x
    dex
    bpl next
    rts
.endproc

; Returns shared proximity sustain in event_number. current_voice is scratch
; here, then configure_note restores its normal role. Neither scratch is read
; by an asynchronous caller: game IRQ exclusively owns the complete driver.
.proc hearing_level
    lda tank_xlo+1
    sec
    sbc tank_xlo
    sta event_number
    lda tank_xhi+1
    sbc tank_xhi
    sta current_voice
    bpl positive
    lda event_number
    eor #$ff
    clc
    adc #1
    sta event_number
    lda current_voice
    eor #$ff
    adc #0
    sta current_voice
positive:
    lda current_voice
    bne inaudible
    lda tank_y+1
    sec
    sbc tank_y
    bcs y_positive
    lda tank_y
    sec
    sbc tank_y+1
y_positive:
    cmp event_number
    bcs range_ready
    lda event_number
range_ready:
    cmp #225
    bcs inaudible
    ldx #0
    cmp #97
    bcc level
    inx
    cmp #161
    bcc level
    inx
level:
    lda proximity_sustain,x
    sta event_number
    rts
inaudible:
    lda #0
    sta event_number
    rts
.endproc

.proc duel_sound_tick
    jsr detect_motion
    lda #0
    sta engine_distance_ready
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
    jsr configure_note
    jmp advance_voice
update_voice:
    lda voice_kind,x
    beq engine
    dec voice_phase,x
    beq next_note
    lda voice_phase,x
    cmp #2
    bne advance_voice
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
    lda voice_offset,x
    tay
    lda #0
    sta SID+4,y
engine:
    cpx #2
    bcs advance_voice
    jsr update_engine
advance_voice:
    inx
    cpx #3
    bne next_voice
::duel_sound_tick_done:
    rts
.endproc

; X = player, preserved. Only register changes are written. Changing a running
; engine's level gives it a complete silent tick before starting a fresh attack.
.proc update_engine
    lda engine_motion,x
    bne moving
    jmp quiet
moving:
    cpx #1
    beq proximity
    ldy computer_player2
    beq proximity
    lda #$30
    bne target
proximity:
    ; A cannon borrows its whole player voice. Distance is calculated only
    ; when an available engine can use it, once for both engines in PvP.
    lda engine_distance_ready
    bne distance_ready
    txa
    pha
    jsr hearing_level
    pla
    tax
    lda #1
    sta engine_distance_ready
distance_ready:
    lda event_number
    bne target
    ldy computer_player2
    bne target                ; only the remote CPU tank becomes inaudible
    lda #$10                  ; symmetric faint own-engine floor in PvP
target:
    cmp engine_level,x
    beq level_same
    sta engine_level,x
    lda engine_active,x
    bne quiet
level_same:
    lda engine_level,x
    beq quiet
    lda engine_active,x
    bne done
    ; Start a low engine after at least one released tick, or from an idle voice.
    stx current_voice
    lda sound_region
    asl
    asl
    sta engine_table_offset
    txa
    asl
    clc
    adc engine_table_offset
    tay
    lda engine_frequency,y
    pha
    lda voice_offset,x
    tax
    pla
    sta SID,x
    lda engine_frequency+1,y
    sta SID+1,x
    lda #0
    sta SID+5,x
    ldy current_voice
    lda engine_level,y
    sta SID+6,x
    lda #$41
    sta SID+4,x
    ldx current_voice
    lda #1
    sta engine_active,x
done:
    rts
quiet:
    lda engine_active,x
    beq done
    lda #0
    sta engine_active,x
    lda voice_offset,x
    tay
    lda #0
    sta SID+4,y
    rts
.endproc

; X = logical voice 0/1/2; preserves X for the bounded tick loop.
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
.assert sound_code_end-sound_code_start < 1536, error, "Tank sound code budget"

.segment "RODATA"
sound_data_start:
voice_offset:    .byte 0, 7, 14
sequence_start:  .byte 0, 0, 1, 0, 2, 6
sequence_count:  .byte 0, 1, 1, 0, 4, 8
note_period:     .byte 0, 6, 10, 0, 7, 8
waveform:        .byte 0, $41, $81, 0, $41, $41
attack_decay:    .byte 0, $02, $03, 0, $02, $03
sustain_release: .byte 0, $01, $02, 0, $01, $02
sequence_notes:  .byte 9, 2, 0,7,4,0, 16,19,24,28,26,24,19,24
proximity_sustain: .byte $b0,$70,$30
engine_frequency: .word $03a9,$04e2,$0386,$04b4
frequency_pal:
    .word $1167, $1270, $1389, $14b2, $15ed, $173b, $189c, $1a13, $1ba0, $1d45, $1f02, $20da
    .word $22ce, $24e0, $2711, $2964, $2bda, $2e76, $3139, $3426, $3740, $3a89, $3e04, $41b4
    .word $459c, $49c0, $4e23, $52c8, $57b4, $5ceb, $6272, $684c, $6e80, $7512, $7c08, $8368
frequency_ntsc:
    .word $10c4, $11c3, $12d1, $13f0, $151f, $1661, $17b6, $191e, $1a9d, $1c32, $1ddf, $1fa6
    .word $2188, $2386, $25a3, $27e0, $2a3f, $2cc2, $2f6b, $323d, $353a, $3864, $3bbe, $3f4c
    .word $430f, $470c, $4b46, $4fbf, $547d, $5983, $5ed6, $647a, $6a73, $70c8, $777c, $7e97
sound_data_end:
.assert sound_data_end-sound_data_start < 256, error, "Tank sound data budget"

.segment "BSS"
sound_region: .res 1
sound_state:
voice_kind:      .res 3
voice_pending:   .res 3
voice_phase:     .res 3
voice_step:      .res 3
voice_remaining: .res 3
current_voice:   .res 1
event_number:    .res 1
engine_table_offset: .res 1
engine_distance_ready: .res 1
engine_motion:  .res 2
engine_active:  .res 2
engine_level:   .res 2
previous_xlo:   .res 2
previous_xhi:   .res 2
previous_y:     .res 2
previous_xfrac: .res 2
previous_yfrac: .res 2
previous_hull:  .res 2
previous_respawn: .res 2
sound_state_end:
.assert sound_state_end-sound_region < 48, error, "Tank sound state budget"

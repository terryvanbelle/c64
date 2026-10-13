; Original score: "Suspension", a quiet 24-bar dance in 6/8.
; ABI:
;   music_init: A=0 PAL, A=1 common NTSC, A=2 old NTSC.
;   music_tick: call at 50 Hz; first call starts the first notes.
;   Both clobber A/X/Y and flags. No zero page or self-modifying code.
;   Caller owns interrupt scheduling and register preservation. Init must not
;   run concurrently with a tick. SID I/O at $D400 must be visible.
;
; The loop is 144 eighth notes * 15 calls = 2,160 calls, nominally 43.2 s.
; One dotted-quarter beat is 45 calls (about 66.7 beats/minute). The melody's
; held notes float over broken extended chords and a triangle bass/pad.
; Voice 1: triangle cantabile, 56 ms attack, 168 ms decay, 9/15 sustain,
;          240 ms release. Gate drops two calls before the next note.
; Voice 2: pulse harp, 16 ms attack, 168 ms decay, zero sustain,
;          168 ms release; duty moves gently over a 64-call cycle.
; Voice 3: triangle bass/pad, 300 ms attack, 408 ms decay, 7/15 sustain,
;          750 ms release; gate drops two calls before a new bar.
;
; All 25 writable SID registers are cleared during initialization, including
; filter/routing and voice-3-off. Master volume is 9; no filter, combined
; waveform, sync, ring modulation, digi, CIA, raster, or timer dependencies.
; Register layout, frequency relation and ADSR times checked against MOS 6581:
; https://myoldcomputer.nl/Files/mos_6581_sid.pdf
; Frequency = SID word * machine clock / 2^24. Equal temperament, A4=440 Hz;
; tables rounded from clocks 985248 Hz PAL and 1022730 Hz NTSC.
; Typical held-note call: under 150 CPU cycles before caller IRQ overhead.
; Busiest new-bar call: under 700 cycles, excluding VIC DMA stalls.
; State: 6 BSS bytes, all initialized below; stack: at most one nested JSR
; (2 bytes beyond the caller's return address). Data size asserted below.

.setcpu "6502"

.export music_init, music_tick

SID = $d400
STEPS = 144
BARS = 24
HOLD = $ff
REST = $fe

C2 = 0
D2 = 2
E2 = 4
F2 = 5
G2 = 7
A2 = 9
C3 = 12
D3 = 14
E3 = 16
F3 = 17
G3 = 19
A3 = 21
B3 = 23
C4 = 24
D4 = 26
E4 = 28
F4 = 29
G4 = 31
GS4 = 32
A4 = 33
B4 = 35
C5 = 36
D5 = 38
E5 = 40
F5 = 41
G5 = 43
A5 = 45

.segment "CODE"

.proc music_init
    ; Normalize both NTSC variants to one pitch-table selector.
    cmp #0
    beq store_region
    lda #1
store_region:
    sta music_region
    lda #0
    ldx #24
clear_sid:
    sta SID,x
    dex
    bpl clear_sid

    ; Deliberately initialize every BSS byte; standalone PRGs have no CRT.
    sta music_pulse_phase
    lda #14
    sta music_phase
    lda #STEPS-1
    sta music_step
    lda #BARS-1
    sta music_bar
    lda #5
    sta music_substep

    lda #$55
    sta SID+5
    lda #$96
    sta SID+6
    lda #$10
    sta SID+4

    lda #$25
    sta SID+12
    lda #$05
    sta SID+13
    lda #$06
    sta SID+10
    lda #$80
    sta SID+9
    lda #$40
    sta SID+11

    lda #$87
    sta SID+19
    lda #$78
    sta SID+20
    lda #$10
    sta SID+18
    lda #9
    sta SID+24
    rts
.endproc

.proc music_tick
    ; Pulse-width movement uses one bounded lookup and never reads SID.
    ldx music_pulse_phase
    lda pulse_width,x
    sta SID+9
    inx
    txa
    and #63
    sta music_pulse_phase

    inc music_phase
    lda music_phase
    cmp #15
    beq next_step

    ; The harp has 200 ms gate time and 100 ms release before retrigger.
    cmp #10
    bne check_phrase_release
    lda #$40
    sta SID+11
    rts

check_phrase_release:
    cmp #13
    bne done

    ; Do not interrupt a melody note when the next event is a HOLD.
    ldx music_step
    inx
    cpx #STEPS
    bne have_next
    ldx #0
have_next:
    lda melody_notes,x
    cmp #HOLD
    beq bass_release
    lda #$10
    sta SID+4
bass_release:
    lda music_substep
    cmp #5
    bne done
    lda #$10
    sta SID+18
done:
    rts

next_step:
    lda #0
    sta music_phase
    inc music_step
    lda music_step
    cmp #STEPS
    bne step_ready
    lda #0
    sta music_step
step_ready:
    inc music_substep
    lda music_substep
    cmp #6
    bne bar_ready
    lda #0
    sta music_substep
    inc music_bar
    lda music_bar
    cmp #BARS
    bne bar_ready
    lda #0
    sta music_bar
bar_ready:
    ldx music_step
    lda melody_notes,x
    cmp #HOLD
    beq harp
    cmp #REST
    beq melody_rest
    ldx #0
    jsr write_pitch
    lda #$11
    sta SID+4
    jmp harp
melody_rest:
    lda #$10
    sta SID+4

harp:
    ldx music_step
    lda arpeggio_notes,x
    ldx #7
    jsr write_pitch
    lda #$41
    sta SID+11

    lda music_substep
    bne done
    ldx music_bar
    lda bass_notes,x
    ldx #14
    jsr write_pitch
    lda #$11
    sta SID+18
    rts
.endproc

; A = note index (C2=0 through B6=59); X = voice register offset 0, 7, 14.
; Clobbers A/Y/flags, preserves X. Frequencies are 60 little-endian words.
.proc write_pitch
    asl
    tay
    lda music_region
    bne ntsc
    lda frequency_pal,y
    sta SID,x
    lda frequency_pal+1,y
    sta SID+1,x
    rts
ntsc:
    lda frequency_ntsc,y
    sta SID,x
    lda frequency_ntsc+1,y
    sta SID+1,x
    rts
.endproc

.segment "RODATA"
music_data_start:

melody_notes:
    .byte E5, HOLD, D5, C5, HOLD, B4         ;  1 Am(add9)
    .byte A4, HOLD, HOLD, B4, C5, HOLD       ;  2 Am(add9)
    .byte E5, HOLD, F5, E5, C5, HOLD         ;  3 Fmaj7
    .byte A4, HOLD, HOLD, G4, E4, HOLD       ;  4 Fmaj7
    .byte G4, HOLD, B4, D5, HOLD, E5         ;  5 Cmaj9
    .byte D5, HOLD, HOLD, B4, A4, G4         ;  6 G6
    .byte F4, HOLD, E4, D4, HOLD, E4         ;  7 Dm9
    .byte A4, HOLD, HOLD, C5, D5, HOLD       ;  8 Dm9
    .byte E5, HOLD, D5, C5, B4, HOLD         ;  9 Am(add9)
    .byte A4, HOLD, HOLD, G4, F4, HOLD       ; 10 Fmaj7
    .byte A4, HOLD, B4, D5, HOLD, B4         ; 11 E7sus4
    .byte GS4, HOLD, HOLD, B4, D5, E5        ; 12 E7
    .byte A5, HOLD, G5, E5, HOLD, D5         ; 13 Am(add9)
    .byte E5, HOLD, HOLD, D5, C5, HOLD       ; 14 Cmaj9
    .byte F5, HOLD, E5, C5, HOLD, A4         ; 15 Fmaj7
    .byte D5, HOLD, HOLD, E5, F5, HOLD       ; 16 Dm9
    .byte G5, HOLD, F5, D5, HOLD, B4         ; 17 G6
    .byte E5, HOLD, HOLD, D5, C5, HOLD       ; 18 Cmaj9
    .byte A4, HOLD, C5, E5, HOLD, F5         ; 19 Fmaj7
    .byte D5, HOLD, HOLD, C5, A4, HOLD       ; 20 Dm9
    .byte B4, HOLD, C5, E5, HOLD, D5         ; 21 Am(add9)
    .byte A4, HOLD, HOLD, B4, D5, HOLD       ; 22 E7sus4
    .byte E5, HOLD, D5, B4, HOLD, GS4        ; 23 E7
    .byte A4, HOLD, HOLD, HOLD, HOLD, HOLD   ; 24 Am(add9)
melody_end:
.assert melody_end-melody_notes = STEPS, error, "Melody step count"

arpeggio_notes:
    .byte A3, E4, B4, C5, B4, E4             ;  1 Am(add9)
    .byte A3, C4, E4, B4, E4, C4             ;  2 Am(add9)
    .byte F3, C4, E4, A4, E4, C4             ;  3 Fmaj7
    .byte F3, A3, C4, E4, C5, E4             ;  4 Fmaj7
    .byte C4, G4, B4, E5, D5, G4             ;  5 Cmaj9
    .byte G3, D4, G4, A4, B4, D4             ;  6 G6
    .byte D3, A3, C4, E4, F4, C4             ;  7 Dm9
    .byte D3, F3, A3, C4, E4, A3             ;  8 Dm9
    .byte A3, E4, B4, C5, B4, E4             ;  9 Am(add9)
    .byte F3, C4, E4, A4, E4, C4             ; 10 Fmaj7
    .byte E3, B3, D4, A4, D5, D4             ; 11 E7sus4
    .byte E3, B3, D4, GS4, B4, D4            ; 12 E7
    .byte A3, E4, B4, C5, E5, B4             ; 13 Am(add9)
    .byte C4, G4, B4, D5, E5, G4             ; 14 Cmaj9
    .byte F3, C4, E4, A4, C5, E4             ; 15 Fmaj7
    .byte D3, A3, C4, E4, F4, C4             ; 16 Dm9
    .byte G3, D4, G4, B4, D5, A4             ; 17 G6
    .byte C4, G4, B4, E5, D5, G4             ; 18 Cmaj9
    .byte F3, C4, E4, A4, E4, C4             ; 19 Fmaj7
    .byte D3, A3, C4, E4, F4, C4             ; 20 Dm9
    .byte A3, E4, B4, C5, B4, E4             ; 21 Am(add9)
    .byte E3, B3, D4, A4, D5, D4             ; 22 E7sus4
    .byte E3, B3, D4, GS4, B4, D4            ; 23 E7
    .byte A3, C4, E4, B4, E4, C4             ; 24 Am(add9)
arpeggio_end:
.assert arpeggio_end-arpeggio_notes = STEPS, error, "Arpeggio step count"

bass_notes:
    .byte A2, A2, F2, F2, C3, G2, D2, D2, A2, F2, E2, E2
    .byte A2, C3, F2, D2, G2, C3, F2, D2, A2, E2, E2, A2
bass_end:
.assert bass_end-bass_notes = BARS, error, "Bass bar count"

; 38.3%-43.0% duty; changing only PW low is deliberate, PW high remains 6.
; round(128 + 96*sin(2*pi*index/64)).
pulse_width:
    .byte $80, $89, $93, $9c, $a5, $ad, $b5, $bd, $c4, $ca, $d0, $d5, $d9, $dc, $de, $e0
    .byte $e0, $e0, $de, $dc, $d9, $d5, $d0, $ca, $c4, $bd, $b5, $ad, $a5, $9c, $93, $89
    .byte $80, $77, $6d, $64, $5b, $53, $4b, $43, $3c, $36, $30, $2b, $27, $24, $22, $20
    .byte $20, $20, $22, $24, $27, $2b, $30, $36, $3c, $43, $4b, $53, $5b, $64, $6d, $77

frequency_pal:
    .word $045a, $049c, $04e2, $052d, $057b, $05cf, $0627, $0685, $06e8, $0751
    .word $07c1, $0837, $08b4, $0938, $09c4, $0a59, $0af7, $0b9d, $0c4e, $0d0a
    .word $0dd0, $0ea2, $0f81, $106d, $1167, $1270, $1389, $14b2, $15ed, $173b
    .word $189c, $1a13, $1ba0, $1d45, $1f02, $20da, $22ce, $24e0, $2711, $2964
    .word $2bda, $2e76, $3139, $3426, $3740, $3a89, $3e04, $41b4, $459c, $49c0
    .word $4e23, $52c8, $57b4, $5ceb, $6272, $684c, $6e80, $7512, $7c08, $8368
frequency_pal_end:
.assert frequency_pal_end-frequency_pal = 120, error, "PAL pitch table"

frequency_ntsc:
    .word $0431, $0471, $04b4, $04fc, $0548, $0598, $05ed, $0648, $06a7, $070c
    .word $0778, $07e9, $0862, $08e1, $0969, $09f8, $0a90, $0b30, $0bdb, $0c8f
    .word $0d4e, $0e19, $0ef0, $0fd3, $10c4, $11c3, $12d1, $13f0, $151f, $1661
    .word $17b6, $191e, $1a9d, $1c32, $1ddf, $1fa6, $2188, $2386, $25a3, $27e0
    .word $2a3f, $2cc2, $2f6b, $323d, $353a, $3864, $3bbe, $3f4c, $430f, $470c
    .word $4b46, $4fbf, $547d, $5983, $5ed6, $647a, $6a73, $70c8, $777c, $7e97
frequency_ntsc_end:
.assert frequency_ntsc_end-frequency_ntsc = 120, error, "NTSC pitch table"

music_data_end:
.assert music_data_end-music_data_start = 616, error, "Music RODATA size"

.segment "BSS"
music_region:      .res 1
music_phase:       .res 1
music_step:        .res 1
music_bar:         .res 1
music_substep:     .res 1
music_pulse_phase: .res 1

; The Shape of Listening -- an original three-minute composition for one SID.
; Owns CIA1 Timer A (100 Hz), all SID registers, VIC display and RAM vectors.
; Only documented NMOS 6502 instructions, stock C64, no drive after loading.
.setcpu "6502"
.import visual_init, visual_tick
.import __RODATA_RUN__, __RODATA_SIZE__
.export start, irq, irq_done, main_loop, video_standard, play_tick
.export voice_energy, section_index, song_done, paused, score_ptr
.export synth, record_left, music_reset, key_sampled, key_raw, irq_count
.export song_finished, music_tick, audio_written

SID = $d400

.segment "ZEROPAGE"
score_ptr: .res 2

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
    jsr music_reset
    ldx video_standard
    lda timer_lo,x
    sta $dc04
    lda timer_hi,x
    sta $dc05
    lda #$81
    sta $dc0d
    lda #$11                    ; Force load; continuous phi2 Timer A.
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
    sta paused
play:
    lda paused
    ora song_done
    beq active
    lda #$90
    sta SID+24
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

nmi:
    pha
    lda $dd0d
    pla
    rti                         ; RESTORE safely ignored; R replays the score.

; Safe low-only keyboard columns: Space PA7/PB4, R PA2/PB1.
; CIA timers never drive PB6/PB7. Ignore low PB pins from port-1 joystick.
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
    sta SID+24
    sta paused
    sta song_done
    sta play_tick
    sta play_tick+1
    sta record_left
    sta section_index
    sta voice_energy
    sta voice_energy+1
    sta voice_energy+2
    ldx #34
clear:
    sta synth,x
    dex
    bpl clear
    lda #8
    sta SID+4
    sta SID+11
    sta SID+18
    lda #0
    ldx #23
sid_clear:
    sta SID,x
    dex
    bpl sid_clear
    lda #<score_data
    sta score_ptr
    lda #>score_data
    sta score_ptr+1
    rts
.endproc

music_tick:
    lda record_left
    bne have_record
    jsr read_record
    lda song_done
    bne tick_done
have_record:
    ; Correct the pitch words for the detected SID clock, independently of
    ; the regional CIA timer. Score/delta values always use PAL units.
    ldx #0
    ldy #0
    jsr write_frequency
    ldx #4
    ldy #7
    jsr write_frequency
    ldx #8
    ldy #14
    jsr write_frequency
    lda synth+12
    sta SID+2
    lda synth+13
    and #15
    sta SID+3
    lda synth+16
    and #7
    sta SID+21
    lda synth+17
    asl
    asl
    asl
    asl
    asl
    sta cutoff_top
    lda synth+16
    lsr
    lsr
    lsr
    ora cutoff_top
    sta SID+22
    lda synth+30
    sta SID+24
audio_written:
    ; Five bounded signed 16-bit additions; no multiplication or division.
    ldx #0
advance:
    clc
    lda synth,x
    adc synth+2,x
    sta synth,x
    lda synth+1,x
    adc synth+3,x
    sta synth+1,x
    inx
    inx
    inx
    inx
    cpx #20
    bne advance
    dec record_left
    inc play_tick
    bne tick_done
    inc play_tick+1
tick_done:
    rts

; A record is duration, block mask, changed blocks in ascending bit order.
; The first record sets all 35 bytes; zero duration ends the piece.
.proc read_record
    ldy #0
    lda (score_ptr),y
    bne read
    jmp song_finished
read:
    sta record_left
    iny
    lda (score_ptr),y
    sta record_mask
    iny
    lda #0
    sta block_number
next_block:
    lsr record_mask
    bcc skip
    ldx block_number
    lda block_lengths,x
    sta block_left
    lda block_offsets,x
    tax
copy:
    lda (score_ptr),y
    sta synth,x
    iny
    inx
    dec block_left
    bne copy
skip:
    inc block_number
    lda block_number
    cmp #8
    bne next_block
    tya
    clc
    adc score_ptr
    sta score_ptr
    bcc :+
    inc score_ptr+1
:
    lda synth+21
    sta SID+5
    lda synth+22
    sta SID+6
    lda synth+20
    sta SID+4
    lda synth+24
    sta SID+12
    lda synth+25
    sta SID+13
    lda synth+23
    sta SID+11
    lda synth+27
    sta SID+19
    lda synth+28
    sta SID+20
    lda synth+26
    sta SID+18
    lda synth+29
    sta SID+23
    lda synth+31
    sta section_index
    ldx #2
energy:
    lda synth+32,x
    sta voice_energy,x
    dex
    bpl energy
    rts
.endproc

song_finished:
    lda #1
    sta song_done
    lda #0
    sta SID+4
    sta SID+11
    sta SID+18
    sta voice_energy
    sta voice_energy+1
    sta voice_energy+2
    lda #$90
    sta SID+24
    rts

; X = synth pitch offset, Y = SID voice offset. NTSC split-product tables
; yield round(PAL_word * 985248/1022730) to within one register unit.
.proc write_frequency
    lda video_standard
    bne ntsc
    lda synth,x
    sta SID,y
    lda synth+1,x
    sta SID+1,y
    rts
ntsc:
    sty sid_offset
    lda synth,x
    tay
    lda synth+1,x
    tax
    clc
    lda ntsc_hi_frac,x
    adc #128
    lda ntsc_hi_lo,x
    adc #0
    sta pitch_low
    lda ntsc_hi_hi,x
    adc #0
    sta pitch_high
    ; Fractional carry from the low-byte product into the integer sum.
    clc
    lda ntsc_hi_frac,x
    adc #128
    clc
    adc ntsc_lo_frac,y
    lda pitch_low
    adc ntsc_lo_int,y
    sta pitch_low
    lda pitch_high
    adc #0
    ldy sid_offset
    sta SID+1,y
    lda pitch_low
    sta SID,y
    rts
.endproc

.segment "RODATA"
timer_lo: .byte <9851, <10226, <10226
timer_hi: .byte >9851, >10226, >10226
block_lengths: .byte 4,4,4,4,4,9,2,4
block_offsets: .byte 0,4,8,12,16,20,29,31
.include "pitch.inc"
.assert __RODATA_RUN__ + __RODATA_SIZE__ <= $4000, lderror, "Code/art overlap display bank"
.include "score.inc"

.segment "BSS"
video_standard: .res 1
highest_raster: .res 1
play_tick: .res 2
irq_count: .res 2
voice_energy: .res 3
section_index: .res 1
song_done: .res 1
paused: .res 1
synth: .res 35
record_left: .res 1
record_mask: .res 1
block_number: .res 1
block_left: .res 1
sid_offset: .res 1
pitch_low: .res 1
pitch_high: .res 1
cutoff_top: .res 1
key_raw: .res 1
key_baseline: .res 1
key_previous: .res 1
visual_divider: .res 1
visual_request: .res 1
visual_seen: .res 1

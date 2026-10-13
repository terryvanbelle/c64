; Nocturne: original, text-free ballet for an unexpanded Commodore 64.
; Eight expanded hires sprites form one 96x168 figure. Character graphics
; provide curtains, stars and water. Only documented NMOS 6502 instructions.
; CPU map $35 is maintained throughout: RAM with I/O, our IRQ/NMI vectors.
; Preparation runs outside IRQ; visible sprite storage is never modified.
; Main publishes a complete frame with one final byte store.
.setcpu "6502"
.import music_init, music_tick
.import __BSS_RUN__, __BSS_SIZE__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_RUN__, __RODATA_SIZE__, __BACKGROUND_SIZE__, __FRAMES_SIZE__
.export start, irq, nmi, decode_begin, decode_end, main_loop
.export video_standard, video_frames, simulation_ticks, displayed_pose
.export prepared_frames, missed_requests, frame_ready, active_buffer
SCREEN = $4400
CHARSET = $5000
BUFFER_A = $4800
BUFFER_B = $4A00

.segment "ZEROPAGE"
src: .res 2
dst: .res 2
run_count: .res 1
run_value: .res 1
pages_left: .res 1

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
    txs                         ; Own the stack; application does not return.
    lda #0
    sta $d015
    sta $d01a
    sta $d020
    sta $d021
    lda #$0b                    ; Display off, standard character mode.
    sta $d011
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #$0f
    sta $d019
    ; Install RAM vectors while ROM is visible; SEI protects the IRQ.
    ; CIA2 is masked; RESTORE uses the old ROM vector until the bank switch.
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
    sta __BSS_RUN__,x
    inx
    cpx #<__BSS_SIZE__
    bne clear_state
    jsr detect_video
    ldx video_standard
    lda tick_step_lo,x
    sta tick_step
    lda tick_step_hi,x
    sta tick_step+1
    lda #$ff
    sta tick_fraction
    sta tick_fraction+1
    lda $dd02
    ora #3
    sta $dd02
    lda $dd00
    and #$fc
    ora #2                      ; VIC bank $4000; preserve serial bits.
    sta $dd00
    lda #$14                    ; Screen $4400, charset $5000.
    sta $d018
    lda #$08                    ; Hires, 40 columns, XSCROLL=0.
    sta $d016
    lda #0
    sta $d01b
    sta $d01c
    sta $d010
    lda #$ff
    sta $d017
    sta $d01d                   ; Double sprite height and width.
    lda #<dance_screen_data
    sta src
    lda #>dance_screen_data
    sta src+1
    lda #<SCREEN
    sta dst
    lda #>SCREEN
    sta dst+1
    jsr copy_1000
    lda #<dance_color_data
    sta src
    lda #>dance_color_data
    sta src+1
    lda #<$d800
    sta dst
    lda #>$d800
    sta dst+1
    jsr copy_1000
    lda #<dance_charset_data
    sta src
    lda #>dance_charset_data
    sta src+1
    lda #<CHARSET
    sta dst
    lda #>CHARSET
    sta dst+1
    ldx #8
    jsr copy_pages
    lda #0
    ldx #0
clear_sprite_buffers:
    sta BUFFER_A,x
    sta BUFFER_A+$100,x
    sta BUFFER_B,x
    sta BUFFER_B+$100,x
    inx
    bne clear_sprite_buffers
    ; Pose 95 is the keyframe; delta 0 XOR keyframe gives pose 0.
    lda #<dance_initial_frame
    sta read_stream+1
    lda #>dance_initial_frame
    sta read_stream+2
    lda #>BUFFER_A
    jsr setup_delta_destination
    jsr decode_frame
    lda #dance_frame_count-1
    sta displayed_pose
    lda video_standard
    jsr music_init
    jsr install_sprite_pointers
    jsr position_and_light
    lda #$ff
    sta $d015
    lda #$1b                    ; Display on, YSCROLL=3, IRQ high bit zero.
    sta $d011
    lda #16
    sta $d012                   ; Commit frames above the visible picture.
    lda #1
    sta $d019
    sta $d01a
    sta request_counter
    cli

main_loop:
    lda frame_ready
    bne main_loop
    lda request_counter
    cmp last_request
    beq main_loop
    sta request_snapshot
    sec
    sbc last_request
    sec
    sbc #1
    clc
    adc missed_requests
    sta missed_requests
    lda request_snapshot
    sta last_request
decode_begin:
    jsr copy_active_buffer
    ldx next_pose
    lda dance_frame_lo,x
    sta read_stream+1
    lda dance_frame_hi,x
    sta read_stream+2
    lda active_buffer
    eor #1
    sta pending_buffer
    beq destination_a
    lda #>BUFFER_B
    bne destination_ready
destination_a:
    lda #>BUFFER_A
destination_ready:
    jsr setup_delta_destination
    jsr decode_frame
decode_end:
    lda next_pose
    sta pending_pose
    inc next_pose
    lda next_pose
    cmp #dance_frame_count
    bne pose_ready
    lda #0
    sta next_pose
pose_ready:
    inc prepared_frames
    lda #1
    sta frame_ready            ; Atomic publication: final display-state write.
    jsr animate_glyphs
    jmp main_loop

; High-raster duration: 56 lines PAL, 7 common NTSC, 6 old NTSC.
detect_video:
    bit $d011
    bmi detect_video
wait_high:
    bit $d011
    bpl wait_high
measure_high:
    lda $d012
    cmp highest_raster
    bcc no_new_high
    sta highest_raster
no_new_high:
    bit $d011
    bmi measure_high
    lda highest_raster
    cmp #32
    bcs video_pal
    ldx #1
    cmp #6
    bcs detected
    inx
detected:
    stx video_standard
video_pal:
    rts

; Three pages plus 232 bytes: no writes to the sprite-pointer table.
copy_1000:
    ldx #3
    jsr copy_pages
    ldy #0
copy_tail:
    lda (src),y
    sta (dst),y
    iny
    cpy #232
    bne copy_tail
    rts
copy_pages:
    ldy #0
copy_page:
    lda (src),y
    sta (dst),y
    iny
    bne copy_page
    inc src+1
    inc dst+1
    dex
    bne copy_pages
    rts

copy_active_buffer:
    ldy #0
    lda active_buffer
    bne copy_b_to_a
copy_a_to_b:
    lda BUFFER_A,y
    sta BUFFER_B,y
    lda BUFFER_A+$100,y
    sta BUFFER_B+$100,y
    iny
    bne copy_a_to_b
    rts
copy_b_to_a:
    lda BUFFER_B,y
    sta BUFFER_A,y
    lda BUFFER_B+$100,y
    sta BUFFER_A+$100,y
    iny
    bne copy_b_to_a
    rts

; Main-loop-owned patched operands; the IRQ never calls these routines.
setup_delta_destination:
    sta xor_store+2
    sta xor_store+5
    sta literal_xor+2
    sta literal_xor+5
    lda #2
    sta pages_left
    rts
decode_frame:
    ldx #0                     ; Packed input offset.
    ldy #0                     ; Output offset in the destination page.
next_token:
    jsr read_stream
    bmi repeat_run
    sta run_count
    lda read_stream+1
    sta literal_stream+1
    lda read_stream+2
    sta literal_stream+2
literal_stream:
    lda $ffff,x
    inx
    bne literal_loaded
    inc literal_stream+2
    inc read_stream+2
literal_loaded:
literal_xor:
    eor BUFFER_A,y
    sta BUFFER_A,y
    iny
    bne literal_stored
    inc literal_xor+2
    inc literal_xor+5
    inc xor_store+2
    inc xor_store+5
    dec pages_left
literal_stored:
    dec run_count
    bne literal_stream
    lda pages_left
    bne next_token
    rts
repeat_run:
    and #$7f
    clc
    adc #1
    sta run_count
    jsr read_stream
    sta run_value
    beq skip_unchanged
repeat_loop:
    lda run_value
    jsr xor_store
    dec run_count
    bne repeat_loop
    lda pages_left
    bne next_token
    rts
skip_unchanged:
    tya
    clc
    adc run_count
    tay
    bcc skipped
    inc xor_store+2
    inc xor_store+5
    inc literal_xor+2
    inc literal_xor+5
    dec pages_left
skipped:
    lda pages_left
    bne next_token
    rts
read_stream:
    lda $ffff,x
    inx
    bne stream_ready
    inc read_stream+2
stream_ready:
    ora #0                     ; Return N/Z for the byte, not the input index.
    rts
xor_store:
    eor BUFFER_A,y
    sta BUFFER_A,y
    iny
    bne stored
    inc xor_store+2
    inc xor_store+5
    inc literal_xor+2
    inc literal_xor+5
    dec pages_left
stored:
    rts

animate_glyphs:
    lda simulation_ticks
    lsr
    lsr
    and #7
    tax
    lda dance_glyph_lo,x
    sta src
    lda dance_glyph_hi,x
    sta src+1
    ldy #0
glyph_loop:
    lda (src),y
    sta CHARSET+240*8,y
    iny
    cpy #128
    bne glyph_loop
    rts

irq:
    pha
    txa
    pha
    tya
    pha
    cld
    lda #1
    sta $d019
    inc video_frames
    lda frame_ready
    beq no_new_frame
    lda pending_buffer
    sta active_buffer
    lda pending_pose
    sta displayed_pose
    jsr install_sprite_pointers
    lda #0
    sta frame_ready
no_new_frame:
    clc
    lda tick_fraction
    adc tick_step
    sta tick_fraction
    lda tick_fraction+1
    adc tick_step+1
    sta tick_fraction+1
    bcc no_logic_tick
    jsr music_tick
    inc simulation_ticks
    lda simulation_ticks
    and #1
    bne no_logic_tick
    inc request_counter
    inc motion_phase
    lda simulation_ticks
    and #7
    bne no_logic_tick
    inc light_phase
no_logic_tick:
    jsr position_and_light
    pla
    tay
    pla
    tax
    pla
    rti
nmi:
    pha
    lda $dd0d                 ; Clear CIA2; RESTORE is intentionally ignored.
    pla
    rti

install_sprite_pointers:
    lda active_buffer
    beq pointers_a
    lda #$28
    bne pointers_begin
pointers_a:
    lda #$20
pointers_begin:
    ldx #0
pointer_loop:
    sta SCREEN+$3f8,x
    clc
    adc #1
    inx
    cpx #8
    bne pointer_loop
    rts
position_and_light:
    ldx motion_phase
    lda horizontal_motion,x
    sta $d000
    sta $d004
    sta $d008
    sta $d00c
    clc
    adc #48
    sta $d002
    sta $d006
    sta $d00a
    sta $d00e
    lda vertical_motion,x
    sta $d001
    sta $d003
    clc
    adc #42
    sta $d005
    sta $d007
    clc
    adc #42
    sta $d009
    sta $d00b
    clc
    adc #42
    sta $d00d
    sta $d00f
    lda light_phase
    lsr
    lsr
    lsr
    lsr
    lsr
    asl
    asl
    tax
    lda figure_colors,x
    sta $d027
    sta $d028
    lda figure_colors+1,x
    sta $d029
    sta $d02a
    lda figure_colors+2,x
    sta $d02b
    sta $d02c
    lda figure_colors+3,x
    sta $d02d
    sta $d02e
    rts

.segment "RODATA"
; Nominal 50Hz ticks: round(65536 * 50 / physical frame rate).
tick_step_lo: .byte <$ff5d, <$d5f4, <$d1dc
tick_step_hi: .byte >$ff5d, >$d5f4, >$d1dc
figure_colors:
    .byte 1,15,3,14
    .byte 1,15,13,3
    .byte 1,15,7,10
    .byte 1,15,10,4
    .byte 1,15,10,14
    .byte 1,15,14,3
    .byte 1,15,3,13
    .byte 1,15,3,14
.include "motion.inc"
.include "assets.inc"
.assert __BSS_SIZE__ > 0, lderror, "BSS must not be empty"
.assert __BSS_SIZE__ < 256, lderror, "BSS clear supports one page"
.assert __CODE_RUN__+__CODE_SIZE__ <= $2000, lderror, "CODE budget exceeded"
.assert __RODATA_RUN__+__RODATA_SIZE__ <= $3000, lderror, "RODATA budget exceeded"
.assert __BACKGROUND_SIZE__ = 4048, lderror, "Stage asset sizes changed"
.assert __FRAMES_SIZE__ <= $7000, lderror, "Frames must end below I/O"

.segment "BSS"
video_standard: .res 1
highest_raster: .res 1
video_frames: .res 1
simulation_ticks: .res 1
tick_step: .res 2
tick_fraction: .res 2
request_counter: .res 1
last_request: .res 1
request_snapshot: .res 1
motion_phase: .res 1
light_phase: .res 1
frame_ready: .res 1
active_buffer: .res 1
pending_buffer: .res 1
pending_pose: .res 1
displayed_pose: .res 1
next_pose: .res 1
prepared_frames: .res 1
missed_requests: .res 1

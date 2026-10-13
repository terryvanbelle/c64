; Atlas: The Long March. Stock C64, 16-bit toroidal world coordinates.
; Main alone owns generation, input and render scratch. IRQ publishes completed
; screens, copies Color RAM in raster order, and advances a regional 50Hz clock.
.setcpu "6502"
.macpack longbranch
.import world_tile, world_overview_tile, world_init, input_poll
.import cache_update, cache_remember
.import __BSS_SIZE__, __CODE_RUN__, __CODE_SIZE__, __RODATA_RUN__, __RODATA_SIZE__
.exportzp tile_x, tile_y
.export world_seed, start, irq, main_loop, render_begin, render_end, commit_end
.export army_x, army_y, zoom, cooldown, terrain, frame_ready, active_screen
.export ticks, video_frames, video_standard, viewport, blocked_moves, move_count
.export input_sampled
.export sample_step, map_center_x, map_center_y
.export origin_x, origin_y

SCREEN_A=$8000
SCREEN_B=$8400
CHARSET=$8800
SPRITES=$a000
COLORS=$b000

.segment "ZEROPAGE"
tile_x: .res 2
tile_y: .res 2
source: .res 2
dest: .res 2
color_dest: .res 2
map_ptr: .res 2
text_ptr: .res 2

.macro ADDPTR pointer, amount
    clc
    lda pointer
    adc #amount
    sta pointer
    bcc :+
    inc pointer+1
:
.endmacro
.macro TEXT label, row, column
    lda #<label
    sta text_ptr
    lda #>label
    sta text_ptr+1
    lda #<((row)*40+(column))
    sta dest
    lda screen_high
    clc
    adc #>((row)*40+(column))
    sta dest+1
    jsr print_text
.endmacro
.macro HEX address, row, column
    lda #<((row)*40+(column))
    sta dest
    lda screen_high
    clc
    adc #>((row)*40+(column))
    sta dest+1
    lda address+1
    jsr print_hex
    lda address
    jsr print_hex
.endmacro

.segment "BASIC"
    .word basic_end
    .word 10
    .byte $9e,"2061",0
basic_end: .word 0

.segment "CODE"
start:
    sei
    cld
    ldx #$ff
    txs
    lda #0
    sta $d015
    sta $d01a
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
    ; The six $0200-$07FF state pages are wholly application-owned.
    lda #0
    ldx #0
clear_state:
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear_state
    jsr detect_video
    ldx video_standard
    lda tick_lo,x
    sta tick_step
    lda tick_hi,x
    sta tick_step+1
    lda #$ff
    sta tick_fraction
    sta tick_fraction+1
    lda $dd02
    ora #3
    sta $dd02
    lda $dd00
    and #$fc
    ora #1                      ; VIC bank $8000; preserve serial pins.
    sta $dd00
    lda #2                      ; Screen $8000, charset $8800.
    sta $d018
    lda #8
    sta $d016
    lda #0
    sta $d010
    sta $d017
    sta $d01d
    sta $d01b
    sta $d01c
    sta $dc02
    sta $dc03
    lda #$ff
    sta $dc00
    sta $dc01
    lda #<atlas_charset
    sta source
    lda #>atlas_charset
    sta source+1
    lda #<CHARSET
    sta dest
    lda #>CHARSET
    sta dest+1
    ldx #8
    jsr copy_pages
    lda #<atlas_sprites
    sta source
    lda #>atlas_sprites
    sta source+1
    lda #<SPRITES
    sta dest
    lda #>SPRITES
    sta dest+1
    ldx #2                      ; Four white frames and four black rims.
    jsr copy_pages
    lda #32
    ldx #0
clear_screens:
    sta SCREEN_A,x
    sta SCREEN_A+$100,x
    sta SCREEN_A+$200,x
    sta SCREEN_A+$300,x
    sta SCREEN_B,x
    sta SCREEN_B+$100,x
    sta SCREEN_B+$200,x
    sta SCREEN_B+$300,x
    inx
    bne clear_screens
    lda #15
    ldx #0
clear_colors:
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    sta COLORS,x
    sta COLORS+$100,x
    sta COLORS+$200,x
    sta COLORS+$300,x
    inx
    bne clear_colors
    lda #$80
    sta SCREEN_A+$3f8
    sta SCREEN_B+$3f8
    lda #$84
    sta SCREEN_A+$3f9
    sta SCREEN_B+$3f9
    lda #184                    ; Center tile(10,5); map starts at row2.
    sta $d000
    sta $d002
    lda #146
    sta $d001
    sta $d003
    lda #1
    sta $d027
    lda #0
    sta $d028                   ; Lower-priority black rim behind white army.
    ldx #24
clear_sid:
    sta $d400,x
    dex
    bpl clear_sid
    lda $dc04
    eor $d012
    eor #$73
    sta world_seed
    lda $dc05
    eor $d011
    eor #$a9
    sta world_seed+1
    jsr new_world
    jsr render_view
    lda #$1b
    sta $d011
    lda #16
    sta $d012
    lda #1
    sta $d019
    sta $d01a
    cli
main_loop:
    lda frame_ready
    jne main_loop
    lda ticks
    cmp last_tick
    jeq main_loop
    sta last_tick
    sei                         ; Held snapshot and action latch belong to one tick.
    lda irq_held
input_sampled:
    sta held_input
    eor previous_input
    and held_input
    sta pressed_input
    lda held_input
    sta previous_input
    ; Retain action taps sampled during lengthy overview generation.
    lda irq_pressed
    ora pressed_input
    sta pressed_input
    lda #0
    sta irq_pressed
    cli
    lda pressed_input
    and #32
    beq no_new_world
    jsr advance_seed
    jsr new_world
    jsr render_view
    jmp main_loop
no_new_world:
    lda pressed_input
    and #16
    beq no_zoom
    lda zoom
    clc
    adc #1
    cmp #7
    bcc :+
    lda #0
:   sta zoom
    bne zoom_center_ready
    jsr recenter_map
zoom_center_ready:
    jsr render_view
    jmp main_loop
no_zoom:
    lda zoom
    beq close_movement
    lda cooldown
    jne main_loop
    lda held_input
    and #15
    jeq main_loop
    jsr pan_map
    jsr render_view
    jmp main_loop
close_movement:
    lda cooldown
    jne main_loop
    lda held_input
    and #15
    jeq main_loop
    jsr try_move
    jcc main_loop
    jsr recenter_map
    jsr render_view
    jmp main_loop

new_world:
    jsr world_init
    lda #$80
    sta army_x
    sta army_y
    lda world_seed
    sta army_x+1
    lda world_seed+1
    sta army_y+1
    lda #0
    sta zoom
    sta cooldown
    sta move_count
    sta move_count+1
    sta blocked_moves
    lda #6
    sta terrain
    jsr recenter_map
    rts
recenter_map:
    lda army_x
    sta map_center_x
    lda army_x+1
    sta map_center_x+1
    lda army_y
    sta map_center_y
    lda army_y+1
    sta map_center_y+1
    rts
pan_map:
    ; One overview cell per press/held repeat; army remains in its real place.
    lda #6
    sta cooldown
    lda held_input
    and #1
    beq pan_down
    sec
    lda map_center_y
    sbc sample_step
    sta map_center_y
    lda map_center_y+1
    sbc sample_step+1
    sta map_center_y+1
    rts
pan_down:
    lda held_input
    and #2
    beq pan_left
    clc
    lda map_center_y
    adc sample_step
    sta map_center_y
    lda map_center_y+1
    adc sample_step+1
    sta map_center_y+1
    rts
pan_left:
    lda held_input
    and #4
    beq pan_right
    sec
    lda map_center_x
    sbc sample_step
    sta map_center_x
    lda map_center_x+1
    sbc sample_step+1
    sta map_center_x+1
    rts
pan_right:
    clc
    lda map_center_x
    adc sample_step
    sta map_center_x
    lda map_center_x+1
    adc sample_step+1
    sta map_center_x+1
    rts
advance_seed:
    lda world_seed+1
    lsr
    sta world_seed+1
    ror world_seed
    bcc seed_shifted
    lda world_seed+1
    eor #$b4
    sta world_seed+1
seed_shifted:
    lda world_seed
    eor ticks
    sta world_seed
    ora world_seed+1
    bne seed_done
    inc world_seed
seed_done:
    rts
try_move:
    lda army_x
    sta tile_x
    lda army_x+1
    sta tile_x+1
    lda army_y
    sta tile_y
    lda army_y+1
    sta tile_y+1
    lda held_input
    and #1
    beq move_down
    lda tile_y
    bne :+
    dec tile_y+1
:   dec tile_y
    jmp move_probe
move_down:
    lda held_input
    and #2
    beq move_left
    inc tile_y
    bne move_probe
    inc tile_y+1
    jmp move_probe
move_left:
    lda held_input
    and #4
    beq move_right
    lda tile_x
    bne :+
    dec tile_x+1
:   dec tile_x
    jmp move_probe
move_right:
    inc tile_x
    bne move_probe
    inc tile_x+1
move_probe:
    jsr world_tile
    cmp #0
    bne move_allowed
    inc blocked_moves
    lda #8
    sta cooldown
    clc
    rts
move_allowed:
    sta terrain
    tax
    lda movement_cost,x
    sta cooldown
    lda tile_x
    sta army_x
    lda tile_x+1
    sta army_x+1
    lda tile_y
    sta army_y
    lda tile_y+1
    sta army_y+1
    inc move_count
    bne :+
    inc move_count+1
:   sec
    rts

render_view:
render_begin:
    ldx zoom
    lda step_lo,x
    sta sample_step
    lda step_hi,x
    sta sample_step+1
    ; One sample border supports four-neighbor road/river masks.
    ldx zoom
    sec
    lda map_center_x
    sbc origin_dx_lo,x
    sta origin_x
    lda map_center_x+1
    sbc origin_dx_hi,x
    sta origin_x+1
    sec
    lda map_center_y
    sbc origin_dy_lo,x
    sta origin_y
    lda map_center_y+1
    sbc origin_dy_hi,x
    sta origin_y+1
    jsr cache_update
    jcs generated_all
    lda #<viewport
    sta map_ptr
    lda #>viewport
    sta map_ptr+1
    lda origin_y
    sta tile_y
    lda origin_y+1
    sta tile_y+1
    lda #0
    sta render_row
generate_row:
    lda origin_x
    sta tile_x
    lda origin_x+1
    sta tile_x+1
    lda #0
    sta render_column
generate_tile:
    lda zoom
    beq generate_close
    jsr world_overview_tile
    jmp generated_tile
generate_close:
    jsr world_tile
generated_tile:
    ldy #0
    sta (map_ptr),y
    ADDPTR map_ptr,1
    clc
    lda tile_x
    adc sample_step
    sta tile_x
    lda tile_x+1
    adc sample_step+1
    sta tile_x+1
    inc render_column
    lda render_column
    cmp #22
    bne generate_tile
    clc
    lda tile_y
    adc sample_step
    sta tile_y
    lda tile_y+1
    adc sample_step+1
    sta tile_y+1
    inc render_row
    lda render_row
    cmp #12
    bne generate_row
generated_all:
    jsr cache_remember
    ; Render to inactive screen; main will not touch pending colors after
    ; publication until the entire IRQ color commit has returned.
    lda active_screen
    eor #1
    sta pending_screen
    asl
    asl
    clc
    adc #>SCREEN_A
    sta screen_high
    sta dest+1
    lda #0
    sta dest
    lda #32
    ldy #0
    ldx #3
fill_screen_page:
    sta (dest),y
    iny
    bne fill_screen_page
    inc dest+1
    dex
    bne fill_screen_page
fill_screen_tail:
    sta (dest),y
    iny
    cpy #232
    bne fill_screen_tail
    lda #<(viewport+23)
    sta map_ptr
    lda #>(viewport+23)
    sta map_ptr+1
    lda #80
    sta dest
    sta color_dest
    lda screen_high
    sta dest+1
    lda #>COLORS
    sta color_dest+1
    lda #0
    sta render_row
draw_row:
    lda #0
    sta render_column
draw_tile:
    ldy #0
    lda (map_ptr),y
    sta draw_terrain
    tax
    lda atlas_tile_base,x
    sta draw_glyph
    lda atlas_tile_color,x
    sta draw_color
    cpx #5
    beq draw_connections
    cpx #7
    bcc draw_quadrants
draw_connections:
    jsr connection_mask
    asl
    asl
    clc
    adc draw_glyph
    sta draw_glyph
draw_quadrants:
    ldy #0
    lda draw_glyph
    sta (dest),y
    lda draw_color
    sta (color_dest),y
    iny
    lda draw_glyph
    clc
    adc #1
    sta (dest),y
    lda draw_color
    sta (color_dest),y
    ldy #40
    lda draw_glyph
    clc
    adc #2
    sta (dest),y
    lda draw_color
    sta (color_dest),y
    iny
    lda draw_glyph
    clc
    adc #3
    sta (dest),y
    lda draw_color
    sta (color_dest),y
    ADDPTR dest,2
    ADDPTR color_dest,2
    ADDPTR map_ptr,1
    inc render_column
    lda render_column
    cmp #20
    jne draw_tile
    ADDPTR dest,40
    ADDPTR color_dest,40
    ADDPTR map_ptr,2
    inc render_row
    lda render_row
    cmp #10
    jne draw_row
    jsr place_army
    jsr draw_hud
render_end:
    lda #1
    sta frame_ready             ; Atomic final publication byte.
    rts

connection_mask:
    lda #0
    sta connections
    sec
    lda map_ptr
    sbc #22
    sta text_ptr
    lda map_ptr+1
    sbc #0
    sta text_ptr+1
    ldy #0
    lda (text_ptr),y
    jsr neighbor_connects
    bcc :+
    inc connections
:   ldy #1
    lda (map_ptr),y
    jsr neighbor_connects
    bcc :+
    lda connections
    ora #2
    sta connections
:   ldy #22
    lda (map_ptr),y
    jsr neighbor_connects
    bcc :+
    lda connections
    ora #4
    sta connections
:   sec
    lda map_ptr
    sbc #1
    sta text_ptr
    lda map_ptr+1
    sbc #0
    sta text_ptr+1
    ldy #0
    lda (text_ptr),y
    jsr neighbor_connects
    bcc :+
    lda connections
    ora #8
    sta connections
:   lda connections
    rts
neighbor_connects:
    ldx draw_terrain
    cpx #5
    beq river_neighbor
    cmp #6
    bcc no_connection
    sec
    rts
river_neighbor:
    cmp #0
    beq yes_connection
    cmp #5
    beq yes_connection
    cmp #8
    beq yes_connection
no_connection:
    clc
    rts
yes_connection:
    sec
    rts

place_army:
    sec
    lda army_x
    sbc map_center_x
    sta displacement
    lda army_x+1
    sbc map_center_x+1
    sta displacement+1
    jsr scale_displacement
    clc
    lda displacement
    adc #10
    sta marker_column
    lda displacement+1
    adc #0
    jne hide_army
    lda marker_column
    cmp #20
    jcs hide_army
    sec
    lda army_y
    sbc map_center_y
    sta displacement
    lda army_y+1
    sbc map_center_y+1
    sta displacement+1
    jsr scale_displacement
    clc
    lda displacement
    adc #5
    sta marker_row
    lda displacement+1
    adc #0
    jne hide_army
    lda marker_row
    cmp #10
    jcs hide_army
    ; Full nine-bit VIC X, including columns to the right of pixel255.
    lda #0
    sta pending_xhi
    lda marker_column
    asl
    asl
    asl
    asl
    rol pending_xhi
    clc
    adc #24
    sta pending_x
    bcc :+
    inc pending_xhi
:   lda pending_xhi
    beq :+
    lda #3
:   sta pending_xhi
    lda marker_row
    asl
    asl
    asl
    asl
    clc
    adc #66
    sta pending_y
    lda #3
    sta pending_sprite_enable
    rts
hide_army:
    lda #0
    sta pending_sprite_enable
    rts
scale_displacement:
    lda zoom
    asl
    tax
    beq displacement_done
displacement_shift:
    lda displacement+1
    cmp #$80                   ; Sign-preserving division by powers of four.
    ror displacement+1
    ror displacement
    dex
    bne displacement_shift
displacement_done:
    rts

draw_hud:
    TEXT title_text,0,0
    HEX world_seed,0,36
    TEXT coords_text,1,0
    HEX map_center_x,1,5
    HEX map_center_y,1,17
    ldx zoom
    lda scale_name_lo,x
    sta text_ptr
    lda scale_name_hi,x
    sta text_ptr+1
    lda #75
    sta dest
    lda screen_high
    sta dest+1
    jsr print_text
    TEXT on_text,22,0
    ldx terrain
    lda terrain_name_lo,x
    sta text_ptr
    lda terrain_name_hi,x
    sta text_ptr+1
    lda #<(22*40+4)
    sta dest
    lda screen_high
    clc
    adc #>(22*40+4)
    sta dest+1
    jsr print_text
    TEXT steps_text,22,15
    HEX move_count,22,22
    TEXT pace_text,22,29
    ldx terrain
    lda pace_name_lo,x
    sta text_ptr
    lda pace_name_hi,x
    sta text_ptr+1
    lda #<(22*40+35)
    sta dest
    lda screen_high
    clc
    adc #>(22*40+35)
    sta dest+1
    jsr print_text
    TEXT legend_text,23,0
    lda zoom
    beq hud_close
    TEXT overview_controls,24,0
    rts
hud_close:
    TEXT controls_text,24,0
    rts
print_text:
    ldy #0
print_next:
    lda (text_ptr),y
    beq print_done
    sta (dest),y
    iny
    bne print_next
print_done:
    rts
print_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    tax
    lda hex_digits,x
    ldy #0
    sta (dest),y
    iny
    pla
    and #15
    tax
    lda hex_digits,x
    sta (dest),y
    ADDPTR dest,2
    rts

detect_video:
    bit $d011
    bmi detect_video
wait_high:
    bit $d011
    bpl wait_high
measure_high:
    lda $d012
    cmp highest_raster
    bcc :+
    sta highest_raster
:   bit $d011
    bmi measure_high
    lda highest_raster
    cmp #32
    bcs detected_pal
    ldx #1
    cmp #6
    bcs :+
    inx
:   stx video_standard
detected_pal:
    rts
copy_pages:
    ldy #0
copy_page:
    lda (source),y
    sta (dest),y
    iny
    bne copy_page
    inc source+1
    inc dest+1
    dex
    bne copy_pages
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
    clc
    lda tick_fraction
    adc tick_step
    sta tick_fraction
    lda tick_fraction+1
    adc tick_step+1
    sta tick_fraction+1
    bcc no_tick
    inc ticks
    ; IRQ alone owns CIA input scratch. Main reads atomic snapshots and an
    ; accumulated action-edge latch, so a quick Space/N tap survives rendering.
    jsr input_poll
    sta irq_held
    eor irq_previous
    and irq_held
    and #48
    ora irq_pressed
    sta irq_pressed
    lda irq_held
    sta irq_previous
    lda cooldown
    beq no_tick
    dec cooldown
no_tick:
    lda ticks
    lsr
    lsr
    lsr
    and #3
    ora #$80
    sta SCREEN_A+$3f8
    sta SCREEN_B+$3f8
    clc
    adc #4
    sta SCREEN_A+$3f9
    sta SCREEN_B+$3f9
    lda frame_ready
    jeq irq_done
    lda pending_screen
    sta active_screen
    asl
    asl
    asl
    asl
    ora #2
    sta $d018
    lda pending_x
    sta $d000
    sta $d002
    lda pending_xhi
    sta $d010
    lda pending_y
    sta $d001
    sta $d003
    lda pending_sprite_enable
    sta $d015
    ; Increasing-order colors start at raster16, before map row2 at66.
    ; Sequential pages keep each row ahead of its next badline. Measured on
    ; PAL/commonNTSC/earlyNTSC with both sprites active; no page interleaving.
    ldx #0
color_page0:
    .repeat 8
    lda COLORS+80,x
    sta $d800+80,x
    inx
    .endrepeat
    bne color_page0
color_page1:
    .repeat 8
    lda COLORS+80+$100,x
    sta $d800+80+$100,x
    inx
    .endrepeat
    bne color_page1
color_page2:
    .repeat 8
    lda COLORS+80+$200,x
    sta $d800+80+$200,x
    inx
    .endrepeat
    bne color_page2
color_tail:
    .repeat 4
    lda COLORS+80+$300,x
    sta $d800+80+$300,x
    inx
    .endrepeat
    cpx #32
    bne color_tail
commit_end:
    lda #0
    sta frame_ready
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
    rti

.segment "RODATA"
.include "assets.inc"
tick_lo: .byte <$ff5d,<$d5f4,<$d1dc
tick_hi: .byte >$ff5d,>$d5f4,>$d1dc
step_lo: .byte <1,<4,<16,<64,<256,<1024,<4096
step_hi: .byte >1,>4,>16,>64,>256,>1024,>4096
origin_dx_lo: .byte <11,<44,<176,<704,<2816,<11264,<45056
origin_dx_hi: .byte >11,>44,>176,>704,>2816,>11264,>45056
origin_dy_lo: .byte <6,<24,<96,<384,<1536,<6144,<24576
origin_dy_hi: .byte >6,>24,>96,>384,>1536,>6144,>24576
movement_cost: .byte 0,10,20,24,48,36,6,4,6
hex_digits: .byte "0123456789ABCDEF"
scale0: .byte "1",0
scale1: .byte "4",0
scale2: .byte "16",0
scale3: .byte "64",0
scale4: .byte "256",0
scale5: .byte "1024",0
scale6: .byte "4096",0
scale_name_lo: .byte <scale0,<scale1,<scale2,<scale3,<scale4,<scale5,<scale6
scale_name_hi: .byte >scale0,>scale1,>scale2,>scale3,>scale4,>scale5,>scale6
title_text: .byte "ATLAS : THE LONG MARCH         SEED ",0
coords_text: .byte "EAST ----  SOUTH ----  MAP SCALE 1:",0
on_text: .byte "ON:",0
steps_text: .byte "STEPS:",0
pace_text: .byte "PACE:",0
legend_text: .byte "BLUE WATER  GREEN WOODS  GOLD SAND/ROAD",0
controls_text: .byte "WASD/IJKL/JOY2  SPACE:ZOOM  N:NEW WORLD",0
overview_controls: .byte "WASD/JOY2:PAN SPACE:ZOOM N:NEW WORLD",0
name0: .byte "SEA",0
name1: .byte "PLAINS",0
name2: .byte "FOREST",0
name3: .byte "DESERT",0
name4: .byte "MOUNTAIN",0
name5: .byte "RIVER",0
name6: .byte "CITY",0
name7: .byte "ROAD",0
name8: .byte "BRIDGE",0
fast_text: .byte "FAST",0
slow_text: .byte "SLOW",0
march_text: .byte "MARCH",0
rough_text: .byte "ROUGH",0
ford_text: .byte "FORD",0
stop_text: .byte "STOP",0
terrain_name_lo: .byte <name0,<name1,<name2,<name3,<name4,<name5,<name6,<name7,<name8
terrain_name_hi: .byte >name0,>name1,>name2,>name3,>name4,>name5,>name6,>name7,>name8
pace_name_lo: .byte <stop_text,<march_text,<slow_text,<slow_text,<rough_text,<ford_text,<fast_text,<fast_text,<fast_text
pace_name_hi: .byte >stop_text,>march_text,>slow_text,>slow_text,>rough_text,>ford_text,>fast_text,>fast_text,>fast_text
.assert __BSS_SIZE__ <= $600, lderror, "State overlaps BASIC stub"
.assert __CODE_RUN__+__CODE_SIZE__ <= $4000, lderror, "Code budget exceeded"
.assert __RODATA_RUN__+__RODATA_SIZE__ <= $6000, lderror, "Tables overlap font source"

.segment "CHARSET_SOURCE"
atlas_charset: .incbin "build/atlas/charset.bin"
.segment "SPRITE_SOURCE"
atlas_sprites:
    .incbin "build/atlas/sprites.bin"
    .incbin "build/atlas/army_shadow.bin"

.segment "BSS"
world_seed: .res 2
army_x: .res 2
army_y: .res 2
zoom: .res 1
terrain: .res 1
cooldown: .res 1
blocked_moves: .res 1
move_count: .res 2
video_standard: .res 1
highest_raster: .res 1
ticks: .res 1
video_frames: .res 1
last_tick: .res 1
tick_step: .res 2
tick_fraction: .res 2
held_input: .res 1
previous_input: .res 1
pressed_input: .res 1
frame_ready: .res 1
active_screen: .res 1
pending_screen: .res 1
screen_high: .res 1
sample_step: .res 2
map_center_x: .res 2
map_center_y: .res 2
displacement: .res 2
marker_column: .res 1
marker_row: .res 1
pending_x: .res 1
pending_xhi: .res 1
pending_y: .res 1
pending_sprite_enable: .res 1
irq_held: .res 1
irq_previous: .res 1
irq_pressed: .res 1
origin_x: .res 2
origin_y: .res 2
render_row: .res 1
render_column: .res 1
draw_terrain: .res 1
draw_glyph: .res 1
draw_color: .res 1
connections: .res 1
viewport: .res 264

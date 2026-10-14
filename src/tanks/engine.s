; Ironveil: stock C64 split-screen tank hunting. Static multicolor terrain
; permits atomic screen swaps without copying Color RAM in the live IRQ.
; Main owns map generation, glyph expansion, view drawing and bottom menus.
; IRQ owns simulation, sensing, input, sprites and dynamic HUD fields.
.setcpu "6502"
.macpack longbranch
.import world_generate,world_tiles,game_init,game_start,game_tick
.import game_state,winner,score,health,respawn,invulnerable,stun,hull,turret
.import tank_xlo,tank_xhi,tank_y,shell_active,shell_xlo,shell_xhi,shell_y
.import seconds_left,sudden_death
.import ai_init,ai_tick,sense_init,sense_tick
.import camera_x,camera_y,enemy_visible,bearing,range_band,zone_x,zone_y,terrain_here
.import contact_known
.import duel_input_poll,duel_menu_poll,dual_controls,input_mode,menu_controls,menu_difficulty
.import duel_sound_init,duel_sound_tick,duel_sound_silence,duel_sound_motion_sync
.import __BSS_SIZE__,__WORK_SIZE__,__CODE_RUN__,__CODE_SIZE__,__RODATA_RUN__,__RODATA_SIZE__
.export start,irq,irq_done,frame_published,controls_sampled,ai_controls_ready,simulation_done,main_loop
.export world_seed,computer_player2,ai_difficulty,ticks,video_frames,video_standard
.export ready,new_world_request,active_cam_x,active_cam_y,active_screen,frame_ready
.export world_glyphs,render_begin,render_end,hud_clock,title_active,start_world_request,show_setup,paint_setup
SA=$8000
SB=$8400
FONT=$8800
SPRITES=$a000

.segment "ZEROPAGE"
src: .res 2
dst: .res 2
dst2: .res 2
textptr: .res 2
glyph_ptr: .res 2

.macro TEXT label,row,col
    lda #<label
    sta textptr
    lda #>label
    sta textptr+1
    lda #<(SA+row*40+col)
    sta dst
    sta dst2
    lda #>(SA+row*40+col)
    sta dst+1
    clc
    adc #4
    sta dst2+1
    jsr print_text
.endmacro
.macro BOTH value,offset
    lda value
    sta SA+offset
    sta SB+offset
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
    lda #15
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
@clear:
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clear
    lda #1
    sta ai_difficulty
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
    ora #1
    sta $dd00
    lda #2
    sta $d018
    lda #$18
    sta $d016
    lda #5
    sta $d022
    lda #6
    sta $d023
    lda #11
    sta $d025
    lda #1
    sta $d026
    lda #15
    sta $d01c                 ; four multicolor tank slots; shells are hires
    lda #0
    sta $d010
    sta $d017
    sta $d01d
    sta $d01b
    sta $dc02
    sta $dc03
    lda $dc0e
    and #$fd
    sta $dc0e
    lda $dc0f
    and #$fd
    sta $dc0f
    lda #$ff
    sta $dc00
    sta $dc01
    lda #<font_source
    sta src
    lda #>font_source
    sta src+1
    lda #<FONT
    sta dst
    lda #>FONT
    sta dst+1
    ldx #8
    jsr copy_pages
    lda #<sprite_source
    sta src
    lda #>sprite_source
    sta src+1
    lda #<SPRITES
    sta dst
    lda #>SPRITES
    sta dst+1
    ldx #17
    jsr copy_pages
    lda video_standard
    jsr duel_sound_init
    lda $dc04
    eor $d012
    eor #$59
    sta world_seed
    lda $dc05
    eor $d011
    eor #$a7
    sta world_seed+1
    ora world_seed
    bne :+
    inc world_seed
:
    jsr show_setup
    lda #8
    sta $d012
    lda #1
    sta $d019
    sta $d01a
    cli
main_loop:
    lda start_world_request
    jne enter_battle
    lda game_state
    cmp #2
    beq @setup_phase
    cmp #0
    bne :+
@setup_phase:
    lda title_active
    bne :+
    jsr show_setup
:
    lda new_world_request
    beq :+
    lda #0
    sta new_world_request
    lsr world_seed+1
    ror world_seed
    bcc @seed_ready
    lda world_seed+1
    eor #$b4
    sta world_seed+1
@seed_ready:
    lda world_seed
    eor ticks
    sta world_seed
    inc hud_version
:
    lda title_active
    beq @field
    lda hud_version
    cmp hud_painted
    beq main_loop
    jsr paint_setup
    jmp main_loop
@field:
    lda frame_ready
    bne main_loop
    lda wanted_cam_x
    cmp active_cam_x
    bne @draw
    lda wanted_cam_x+1
    cmp active_cam_x+1
    bne @draw
    lda wanted_cam_y
    cmp active_cam_y
    bne @draw
    lda wanted_cam_y+1
    cmp active_cam_y+1
    bne @draw
    ; A parked viewer must still see the next coarse sensor report. Main
    ; compares the last completed snapshot; publication gates another draw.
    ldx #1
@signal_changed:
    lda contact_known,x
    cmp render_known,x
    bne @draw
    lda zone_x,x
    cmp render_zone_x,x
    bne @draw
    lda zone_y,x
    cmp render_zone_y,x
    bne @draw
    lda bearing,x
    cmp render_bearing,x
    bne @draw
    dex
    bpl @signal_changed
    jmp main_loop
@draw:
    sei
    jsr snapshot_view
    cli
    lda active_screen
    eor #1
    sta render_screen
render_begin:
    jsr render_views
render_end:
    lda #1
    sta frame_ready
    jmp main_loop

; Main-only coherent camera/contact capture. The sensor's sector and bearing
; are the only position data used by markers, including in the solo pane.
snapshot_view:
    ldx #1
@snap:
    lda wanted_cam_x,x
    sta render_cam_x,x
    lda wanted_cam_y,x
    sta render_cam_y,x
    lda contact_known,x
    sta render_known,x
    lda zone_x,x
    sta render_zone_x,x
    lda zone_y,x
    sta render_zone_y,x
    lda bearing,x
    sta render_bearing,x
    dex
    bpl @snap
    rts
enter_battle:
    sei
    lda #$0b
    sta $d011
    lda #0
    sta $d015
    sta start_world_request
    sta title_active
    jsr prepare_world
    lda #1
    sta $d019
    cli
    jmp main_loop

prepare_world:
    lda #<sprite_source
    sta src
    lda #>sprite_source
    sta src+1
    lda #<SPRITES
    sta dst
    lda #>SPRITES
    sta dst+1
    ldx #17
    jsr copy_pages
    lda #$18
    sta $d016
    lda #5
    sta $d022
    lda #6
    sta $d023
    jsr world_generate
    jsr expand_world
    jsr game_start
    jsr sense_init
    jsr ai_init
    jsr duel_sound_motion_sync
    lda #32
    ldx #0
@screens:
    sta SA,x
    sta SA+$100,x
    sta SA+$200,x
    sta SA+$300,x
    sta SB,x
    sta SB+$100,x
    sta SB+$200,x
    sta SB+$300,x
    inx
    bne @screens
    lda #1
    ldx #0
@color:
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    inx
    bne @color
    ; Twenty-four map rows, two nine-tile panes and a clear divider.
    lda #<$d828
    sta dst
    lda #>$d828
    sta dst+1
    lda #<(SA+40)
    sta src
    lda #>(SA+40)
    sta src+1
    lda #<(SB+40)
    sta dst2
    lda #>(SB+40)
    sta dst2+1
    ldx #24
@map_colors:
    ldy #39
    lda #15
@color_row:
    sta (dst),y
    dey
    bpl @color_row
    lda #1
    ldy #0
    sta (dst),y
    ldy #19
    sta (dst),y
    ldy #20
    sta (dst),y
    ldy #39
    sta (dst),y
    lda #248
    ldy #0
    sta (src),y
    sta (dst2),y
    ldy #19
    sta (src),y
    sta (dst2),y
    lda #249
    ldy #20
    sta (src),y
    sta (dst2),y
    ldy #39
    sta (src),y
    sta (dst2),y
    clc
    lda dst
    adc #40
    sta dst
    bcc :+
    inc dst+1
:
    clc
    lda src
    adc #40
    sta src
    bcc :+
    inc src+1
:
    clc
    lda dst2
    adc #40
    sta dst2
    bcc :+
    inc dst2+1
:
    dex
    bne @map_colors
    ldx #19
@team:
    lda #3
    sta $d800,x
    lda #7
    sta $d814,x
    dex
    bpl @team
    jsr choose_display_cameras
    jsr snapshot_view
    ldx #1
@cam:
    lda wanted_cam_x,x
    sta render_cam_x,x
    sta active_cam_x,x
    lda wanted_cam_y,x
    sta render_cam_y,x
    sta active_cam_y,x
    dex
    bpl @cam
    lda #0
    sta render_screen
    jsr render_views
    inc render_screen
    jsr render_views
    lda #0
    sta active_screen
    sta frame_ready
    sta new_world_request
    sta ready
    lda computer_player2
    sta ready+1
    lda #2
    sta $d018
    inc hud_version
    jsr hud_dynamic
    lda #$1b
    sta $d011
    rts

; Main-owned opening/configuration bitmap. Live WORK/Sprite RAM is restored
; only after the user readies, with display off and interrupts masked.
show_setup:
    php
    sei
    lda #$0b
    sta $d011
    lda #1
    sta title_active
    lda #0
    sta $d015
    sta frame_ready
    sta ready
    lda computer_player2
    sta ready+1
    lda game_state
    cmp #2
    beq :+
    jsr duel_sound_silence
:
    lda #<title_packed
    sta src
    lda #>title_packed
    sta src+1
    lda #0
    sta title_run
    lda #<$a000
    sta dst
    lda #>$a000
    sta dst+1
    lda #<8000
    sta title_remaining
    lda #>8000
    sta title_remaining+1
    jsr unpack_title_block
    lda #<$8000
    sta dst
    lda #>$8000
    sta dst+1
    lda #<1000
    sta title_remaining
    lda #>1000
    sta title_remaining+1
    jsr unpack_title_block
    lda #<$d800
    sta dst
    lda #>$d800
    sta dst+1
    lda #<1000
    sta title_remaining
    lda #>1000
    sta title_remaining+1
    jsr unpack_title_block
    lda #8
    sta $d018
    lda #$18
    sta $d016
    lda #$3b
    sta $d011
    inc hud_version
    plp
    jsr paint_setup
    rts

unpack_title_block:
    ldy #0
@byte:
    lda title_run
    bne @emit
    lda (src),y
    sta title_run
    inc src
    bne :+
    inc src+1
:
    lda (src),y
    sta title_value
    inc src
    bne :+
    inc src+1
:
@emit:
    lda title_value
    sta (dst),y
    inc dst
    bne :+
    inc dst+1
:
    dec title_run
    lda title_remaining
    bne :+
    dec title_remaining+1
:
    dec title_remaining
    lda title_remaining
    ora title_remaining+1
    bne @byte
    rts

.macro SETUP label,xpos,ypos,ink
    lda #<label
    sta textptr
    lda #>label
    sta textptr+1
    lda #xpos
    sta menu_x
    lda #ypos
    sta menu_y
    lda #ink
    sta menu_ink
    jsr bitmap_text
.endmacro
paint_setup:
    php
    sei
    lda hud_version
    sta hud_snapshot
    lda game_state
    sta hud_phase
    lda input_mode
    sta hud_input
    lda computer_player2
    sta hud_cpu
    lda ai_difficulty
    sta hud_level
    lda winner
    sta hud_winner
    lda ready
    sta hud_ready
    lda ready+1
    sta hud_ready+1
    plp
    ; Clear only the fixed menu zone, preserving the original upper artwork.
    lda #<$b540
    sta dst
    lda #>$b540
    sta dst+1
    lda #<2560
    sta title_remaining
    lda #>2560
    sta title_remaining+1
    ldy #0
@clear:
    lda #0
    sta (dst),y
    inc dst
    bne :+
    inc dst+1
:
    lda title_remaining
    bne :+
    dec title_remaining+1
:
    dec title_remaining
    lda title_remaining
    ora title_remaining+1
    bne @clear
    SETUP setup_controls,8,140,1
    lda hud_input
    bne @selected_sticks
    SETUP setup_keys,8,140,3
    jmp @opponents
@selected_sticks:
    SETUP setup_sticks,92,140,3
@opponents:
    SETUP setup_opponents,16,149,1
    lda hud_cpu
    bne @selected_cpu
    SETUP setup_humans,16,149,3
    jmp @levels
@selected_cpu:
    SETUP setup_cpu,112,149,3
@levels:
    SETUP setup_levels,8,158,1
    lda hud_cpu
    beq @help
    lda hud_level
    beq @easy
    cmp #1
    beq @medium
    SETUP setup_hard,116,158,3
    jmp @help
@easy:
    SETUP setup_easy,8,158,3
    jmp @help
@medium:
    SETUP setup_medium,56,158,3
@help:
    lda hud_input
    bne @stick_help
    SETUP setup_p1,32,167,2
    SETUP setup_p2,20,176,2
    lda hud_phase
    cmp #2
    beq @start
    SETUP setup_key_extra,20,185,2
    jmp @start
@stick_help:
    SETUP setup_stick_drive,32,167,2
    SETUP setup_stick_aim,20,176,2
    lda hud_phase
    cmp #2
    beq @start
    SETUP setup_stick_extra,20,185,2
@start:
    lda hud_phase
    cmp #2
    bne @ready
    lda hud_winner
    beq @cyan_win
    SETUP setup_gold_win,14,185,3
    jmp @ready
@cyan_win:
    SETUP setup_cyan_win,14,185,3
@ready:
    lda hud_cpu
    beq @both
    lda hud_input
    bne @stick_ready
    SETUP setup_start_cpu,32,193,3
    jmp @done
@both:
    lda hud_ready
    beq @check_gold
    SETUP setup_wait_gold,26,193,3
    jmp @done
@check_gold:
    lda hud_ready+1
    beq @nobody_ready
    SETUP setup_wait_cyan,26,193,3
    jmp @done
@nobody_ready:
    SETUP setup_start_both,26,193,3
    jmp @done
@stick_ready:
    SETUP setup_start_sticks,26,193,3
@done:
    lda hud_snapshot
    sta hud_painted
    rts

; Draw 5x7 letters, six logical multicolor pixels apart. Even X positions
; use two interleaved bitmap-cell bytes per row. All scratch belongs to main.
bitmap_text:
    lda #0
    sta menu_string_index
@char:
    ldy menu_string_index
    lda (textptr),y
    jeq @done
    sta menu_char
    asl
    asl
    asl
    clc
    adc #<font_source
    sta glyph_ptr
    lda menu_char
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #>font_source
    sta glyph_ptr+1
    lda #0
    sta menu_glyph_row
@row:
    ldy menu_glyph_row
    iny
    lda (glyph_ptr),y
    asl
    sta menu_bits
    lda #0
    sta menu_mask
    sta menu_mask+1
    ldx #5
@spread:
    asl menu_mask
    rol menu_mask+1
    asl menu_mask
    rol menu_mask+1
    asl menu_bits
    bcc :+
    lda menu_mask
    ora #3
    sta menu_mask
:
    dex
    bne @spread
    lda menu_x
    and #2
    beq @shift_six
    ldx #2
    bne @shift
@shift_six:
    ldx #6
@shift:
    asl menu_mask
    rol menu_mask+1
    dex
    bne @shift
    lda menu_y
    clc
    adc menu_glyph_row
    tay
    lda bitmap_rowlo,y
    sta dst
    lda bitmap_rowhi,y
    sta dst+1
    lda #0
    sta menu_colhi
    lda menu_x
    and #$fc
    asl
    rol menu_colhi
    clc
    adc dst
    sta dst
    lda dst+1
    adc menu_colhi
    sta dst+1
    ldx menu_ink
    ldy #0
    lda menu_mask+1
    and bitmap_inks,x
    sta menu_pixels
    lda menu_mask+1
    eor #$ff
    and (dst),y
    ora menu_pixels
    sta (dst),y
    ldy #8
    lda menu_mask
    and bitmap_inks,x
    sta menu_pixels
    lda menu_mask
    eor #$ff
    and (dst),y
    ora menu_pixels
    sta (dst),y
    inc menu_glyph_row
    lda menu_glyph_row
    cmp #7
    jne @row
    lda menu_x
    clc
    adc #6
    sta menu_x
    inc menu_string_index
    jmp @char
@done:rts

detect_video:
    bit $d011
    bmi detect_video
@low:
    bit $d011
    bpl @low
@high:
    lda $d012
    cmp highest_raster
    bcc :+
    sta highest_raster
:
    bit $d011
    bmi @high
    lda highest_raster
    cmp #32
    bcs @done
    ldx #1
    cmp #6
    bcs :+
    inx
:
    stx video_standard
@done:rts
copy_pages:
    ldy #0
@copy:
    lda (src),y
    sta (dst),y
    iny
    bne @copy
    inc src+1
    inc dst+1
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
    lda frame_ready
    beq @publish
    lda render_screen
    sta active_screen
    asl
    asl
    asl
    asl
    ora #2
    sta $d018
    ldx #1
@commit:
    lda render_cam_x,x
    sta active_cam_x,x
    lda render_cam_y,x
    sta active_cam_y,x
    dex
    bpl @commit
    lda #0
    sta frame_ready
@publish:
    jsr publish_sprites
frame_published:
    clc
    lda tick_fraction
    adc tick_step
    sta tick_fraction
    lda tick_fraction+1
    adc tick_step+1
    sta tick_fraction+1
    jcc irq_done
    inc ticks
    lda #0
    sta menu_raw
    sta difficulty_raw
    lda game_state
    sta previous_phase
    beq @menu
    cmp #2
    beq @menu
    cmp #3
    bne @input
@menu:
    jsr duel_menu_poll
    sta menu_raw
    lda game_state
    cmp #3
    bne :+
    lda menu_raw
    and #2
    sta menu_raw
    jmp @input
:
    lda menu_difficulty
    sta difficulty_raw
@input:
    jsr duel_input_poll
controls_sampled:
    lda menu_controls
    ora menu_raw
    sta menu_raw
    lda menu_previous
    eor #$ff
    and menu_raw
    sta menu_pressed
    lda menu_raw
    sta menu_previous
    lda difficulty_previous
    eor #$ff
    and difficulty_raw
    sta difficulty_pressed
    lda difficulty_raw
    sta difficulty_previous
    ldx #1
@edge:
    lda controls_previous,x
    eor #$ff
    and dual_controls,x
    and #16
    sta fire_pressed,x
    lda dual_controls,x
    sta controls_previous,x
    dex
    bpl @edge
    jsr handle_menu
    lda game_state
    cmp #1
    bne :+
    lda computer_player2
    beq ai_controls_ready
    jsr ai_tick
ai_controls_ready:
    jsr game_tick
    jsr sense_tick
:
simulation_done:
    jsr choose_display_cameras
    lda game_state
    cmp previous_phase
    beq :+
    inc hud_version
:
    lda game_state
    cmp #3
    beq @hud
    cmp #4
    beq @hud
    jsr duel_sound_tick
@hud:
    inc hud_clock
    lda hud_clock
    cmp #5
    bcc irq_done
    lda #0
    sta hud_clock
    lda title_active
    bne irq_done
    jsr hud_dynamic
irq_done:
    pla
    tay
    pla
    tax
    pla
    rti

handle_menu:
    lda game_state
    cmp #4
    jeq @done
    cmp #1
    jeq @pause
    cmp #3
    jeq @resume
    lda dual_controls
    sta menu_guard
    lda difficulty_raw
    and #2
    beq :+
    lda menu_guard           ; key 2 is also P1 turret-right outside menus
    and #$bf
    sta menu_guard
:
    lda menu_guard
    ora dual_controls+1
    jne @ready
    lda menu_pressed
    and #2
    beq :+
    lda #1
    sta new_world_request
    jmp duel_sound_silence
:
    lda difficulty_pressed
    and #4
    beq :+
    lda #2
    jmp @level
:
    lda difficulty_pressed
    and #2
    beq :+
    lda #1
    jmp @level
:
    lda difficulty_pressed
    and #1
    beq @opponent
    lda #0
@level:
    sta ai_difficulty
    lda #1
    sta computer_player2
    jmp @mode
@opponent:
    lda menu_pressed
    and #32
    beq :+
    lda #1
    sta computer_player2
    jmp @mode
:
    lda menu_pressed
    and #64
    beq :+
    lda #0
    sta computer_player2
    jmp @mode
:
    lda menu_pressed
    and #8
    beq :+
    lda #0
    sta input_mode
    jmp @mode
:
    lda menu_pressed
    and #16
    beq @ready
    lda #1
    sta input_mode
@mode:
    lda #0
    sta ready
    lda computer_player2
    sta ready+1
    inc hud_version
    rts
@ready:
    ldx #1
    lda computer_player2
    beq @player
    sta ready+1
    ldx #0
@player:
    lda fire_pressed,x
    beq :+
    lda #1
    sta ready,x
    inc hud_version
:
    dex
    bpl @player
    lda ready
    and ready+1
    beq @done
    lda #4
    sta game_state
    lda #1
    sta start_world_request
    jmp duel_sound_silence
@pause:
    lda menu_pressed
    and #1
    beq @done
    lda #3
    sta game_state
    jmp duel_sound_silence
@resume:
    lda dual_controls
    ora dual_controls+1
    bne @resume_only
    lda menu_pressed
    and #2
    beq @resume_only
    lda #0
    sta game_state
    lda #1
    sta new_world_request
    inc hud_version
    jmp duel_sound_silence
@resume_only:
    lda menu_pressed
    and #1
    beq @done
    lda #1
    sta game_state
@done:rts

publish_sprites:
    lda #0
    sta sprite_enable
    sta sprite_xhi
    lda title_active
    jne @done
    lda game_state
    cmp #4
    jeq @done
    ldx #0
@slot:
    stx sprite_slot
    lda slot_view,x
    sta viewer
    tay
    lda active_cam_x,y
    asl
    asl
    asl
    asl
    sta cam_pxlo
    lda active_cam_x,y
    lsr
    lsr
    lsr
    lsr
    sta cam_pxhi
    lda active_cam_y,y
    asl
    asl
    asl
    asl
    sta cam_py
    lda slot_actor,x
    sta actor
    tay
    cpx #4
    jcs @shell
    lda respawn,y
    jne @next
    lda computer_player2
    beq @pvp_visibility
    cpx #2
    bne :+
    lda enemy_visible
    jeq @next
    jmp @tank_position
:
    cpx #3
    beq @tank_position
@pvp_visibility:
    lda slot_enemy,x
    beq @tank_position
    ldx viewer
    lda enemy_visible,x
    jeq @next
@tank_position:
    ldy actor
    lda tank_xlo,y
    sec
    sbc cam_pxlo
    sta draw_x
    lda tank_xhi,y
    sbc cam_pxhi
    jne @next
    lda draw_x
    cmp #129
    jcs @next
    lda tank_y,y
    sec
    sbc cam_py
    jcc @next
    cmp #177
    jcs @next
    sta draw_y
    lda hull,y
    asl
    asl
    asl
    clc
    adc turret,y
    clc
    adc #128
    sta draw_pointer
    lda team_colors,y
    sta draw_color
    lda invulnerable,y
    beq @place
    lda ticks
    and #4
    beq @place
    lda #1
    sta draw_color
    jmp @place
@shell:
    lda shell_active,y
    jeq @next
    lda shell_xlo,y
    sec
    sbc cam_pxlo
    sta draw_x
    lda shell_xhi,y
    sbc cam_pxhi
    jne @next
    lda draw_x
    beq @next
    cmp #143
    bcs @next
    dec draw_x
    lda shell_y,y
    sec
    sbc cam_py
    bcc @next
    beq @next
    cmp #191
    bcs @next
    sec
    sbc #1
    sta draw_y
    lda #192
    sta draw_pointer
    lda #1
    sta draw_color
@place:
    ldx sprite_slot
    lda draw_pointer
    sta SA+$3f8,x
    sta SB+$3f8,x
    lda draw_color
    sta $d027,x
    lda sprite_bits,x
    ora sprite_enable
    sta sprite_enable
    ldy viewer
    lda draw_x
    clc
    adc view_left,y
    sta draw_x
    bcc :+
    lda sprite_bits,x
    ora sprite_xhi
    sta sprite_xhi
:
    txa
    asl
    tay
    lda draw_x
    sta $d000,y
    lda draw_y
    clc
    adc #58
    sta $d001,y
@next:
    ldx sprite_slot
    inx
    cpx #8
    jne @slot
@done:
    lda sprite_xhi
    sta $d010
    lda sprite_enable
    sta $d015
    rts

; Solo's second pane follows a coarse sensor sector, never the hidden CPU.
; This routine is IRQ-owned; main snapshots the four wanted bytes atomically.
choose_display_cameras:
    ldx #1
@copy:
    lda camera_x,x
    sta wanted_cam_x,x
    lda camera_y,x
    sta wanted_cam_y,x
    dex
    bpl @copy
    lda computer_player2
    beq @done
    lda zone_x
    asl
    asl
    sec
    sbc #2
    bcs :+
    lda #0
:
    cmp #24
    bcc :+
    lda #23
:
    sta wanted_cam_x+1
    lda zone_y
    asl
    asl
    sec
    sbc #4
    bcs :+
    lda #0
:
    cmp #5
    bcc :+
    lda #4
:
    sta wanted_cam_y+1
@done:rts

; Expand once per battlefield, never in a live IRQ. glyph map is 64x32.
expand_world:
    lda #0
    sta map_row
    sta map_col
    lda #<world_tiles
    sta src
    lda #>world_tiles
    sta src+1
@row:
    lda map_row
    asl
    tax
    lda glyph_rowlo,x
    sta dst
    lda glyph_rowhi,x
    sta dst+1
    lda #0
    sta map_col
@tile:
    ldy map_col
    lda (src),y
    sta map_kind
    tax
    lda tile_bases,x
    sta map_glyph
    lda map_kind
    cmp #6
    bcc @draw
    lda #0
    sta connection
    lda map_row
    beq @east
    lda src
    sec
    sbc #32
    sta textptr
    lda src+1
    sbc #0
    sta textptr+1
    lda (textptr),y
    cmp #6
    bcc @east
    lda #1
    sta connection
@east:
    lda map_col
    cmp #31
    beq @south
    iny
    lda (src),y
    dey
    cmp #6
    bcc @south
    lda connection
    ora #2
    sta connection
@south:
    lda map_row
    cmp #15
    beq @west
    lda src
    clc
    adc #32
    sta textptr
    lda src+1
    adc #0
    sta textptr+1
    lda (textptr),y
    cmp #6
    bcc @west
    lda connection
    ora #4
    sta connection
@west:
    lda map_col
    beq @variant
    dey
    lda (src),y
    iny
    cmp #6
    bcc @variant
    lda connection
    ora #8
    sta connection
@variant:
    lda connection
    asl
    asl
    clc
    adc map_glyph
    sta map_glyph
@draw:
    lda map_col
    asl
    tay
    lda map_glyph
    sta (dst),y
    clc
    adc #1
    iny
    sta (dst),y
    tya
    clc
    adc #63
    tay
    lda map_glyph
    clc
    adc #2
    sta (dst),y
    clc
    adc #1
    iny
    sta (dst),y
    inc map_col
    lda map_col
    cmp #32
    jne @tile
    clc
    lda src
    adc #32
    sta src
    bcc :+
    inc src+1
:
    inc map_row
    lda map_row
    cmp #16
    jne @row
    rts

render_views:
    lda #0
    sta render_view
@view:
    ldx render_view
    lda render_cam_y,x
    asl
    tay
    lda glyph_rowlo,y
    sta src
    lda glyph_rowhi,y
    sta src+1
    lda render_cam_x,x
    asl
    clc
    adc src
    sta src
    bcc :+
    inc src+1
:
    lda render_screen
    asl
    asl
    clc
    adc #$80
    sta dst+1
    lda view_column,x
    clc
    adc #40
    sta dst
    lda #24
    sta render_rows
@row:
    ldy #17
@copy:
    lda (src),y
    sta (dst),y
    dey
    bpl @copy
    clc
    lda src
    adc #64
    sta src
    bcc :+
    inc src+1
:
    clc
    lda dst
    adc #40
    sta dst
    bcc :+
    inc dst+1
:
    dec render_rows
    bne @row
    jsr render_marker
    inc render_view
    lda render_view
    cmp #2
    bne @view
    rts

; Overlay four character cells only in the inactive screen. All map cells
; retain fixed multicolor Color RAM15, so no IRQ palette copy is necessary.
render_marker:
    ldx render_view
    lda computer_player2
    beq :+
    ldx #0                    ; solo contact pane uses human observations
:
    lda render_known,x
    bne :+
    rts
:
    lda render_bearing,x
    and #7
    sta marker_heading
    ldy render_view
    lda render_cam_x,y
    asl
    sta marker_x
    lda render_zone_x,x
    asl
    asl
    asl
    clc
    adc #3                    ; coarse top-left24, centre32, in 8px cells
    sec
    sbc marker_x
    bcc @edge
    cmp #17                   ; two-cell marker stays wholly inside the pane
    bcs @edge
    sta marker_x
    lda render_cam_y,y
    asl
    sta marker_y
    lda render_zone_y,x
    asl
    asl
    asl
    clc
    adc #3
    sec
    sbc marker_y
    bcc @edge
    cmp #23
    bcs @edge
    sta marker_y
    lda #250                  ; a sector diamond is deliberately approximate
    bne @glyph
@edge:
    ldx marker_heading
    lda marker_edge_x,x
    sta marker_x
    lda marker_edge_y,x
    sta marker_y
    txa
    asl
    asl
@glyph:
    sta marker_glyph
    lda marker_y
    tay
    lda marker_rowlo,y
    sta dst
    lda marker_rowhi,y
    sta dst+1
    lda render_screen
    asl
    asl
    clc
    adc #$80
    adc dst+1
    sta dst+1
    ldx render_view
    lda marker_x
    clc
    adc view_column,x
    clc
    adc dst
    sta dst
    bcc :+
    inc dst+1
:
    ldy #0
    lda marker_glyph
    sta (dst),y
    iny
    clc
    adc #1
    sta (dst),y
    ldy #40
    clc
    adc #1
    sta (dst),y
    iny
    clc
    adc #1
    sta (dst),y
    rts

hud_dynamic:
    ldx #0
@player:
    stx hud_actor
    lda hud_offsets,x
    sta hud_offset
    tay
    lda team_letters,x
    sta SA,y
    sta SB,y
    lda #32
    sta SA+6,y
    sta SB+6,y
    sta SA+9,y
    sta SB+9,y
    sta SA+14,y
    sta SB+14,y
    sta SA+19,y
    sta SB+19,y
    ldy #0
@armor:
    tya
    cmp health,x
    lda #'-'
    bcs :+
    lda #'*'
:
    cpx #1
    bne :+
    pha
    lda computer_player2
    beq @armor_known
    lda enemy_visible
    bne @armor_known
    pla
    lda #'?'
    jmp :+
@armor_known:
    pla
:
    pha
    tya
    clc
    adc hud_offset
    tay
    pla
    sta SA+1,y
    sta SB+1,y
    tya
    sec
    sbc hud_offset
    tay
    iny
    cpy #4
    bne @armor
    lda score,x
    clc
    adc #'0'
    ldy hud_offset
    sta SA+5,y
    sta SB+5,y
    cpx #1
    bne :+
    lda computer_player2
    beq :+
    ldx #0
:
    stx hud_sensor
    lda bearing,x
    asl
    tax
    lda compass,x
    sta SA+7,y
    sta SB+7,y
    lda compass+1,x
    sta SA+8,y
    sta SB+8,y
    ldx hud_sensor
    lda zone_x,x
    clc
    adc #'A'
    sta SA+10,y
    sta SB+10,y
    lda zone_y,x
    clc
    adc #'1'
    sta SA+11,y
    sta SB+11,y
    lda range_band,x
    tax
    lda range_first,x
    sta SA+12,y
    sta SB+12,y
    ldx hud_actor
    cpx #1
    bne @own_status
    lda computer_player2
    beq @own_status
    lda enemy_visible
    beq @unknown
    lda #'!'
    bne @status
@unknown:
    lda #'?'
    bne @status
@own_status:
    lda terrain_here,x
    cmp #6
    bcs @open
    txa
    eor #1
    tax
    lda enemy_visible,x
    beq @hide
    lda #'!'
    bne @status
@open:
    lda #'O'
    bne @status
@hide:
    lda #'H'
@status:
    sta SA+13,y
    sta SB+13,y
    lda game_state
    cmp #3
    bne :+
    lda #'P'
    sta SA+15,y
    sta SB+15,y
    lda #'A'
    sta SA+16,y
    sta SB+16,y
    lda #'U'
    sta SA+17,y
    sta SB+17,y
    lda #'S'
    sta SA+18,y
    sta SB+18,y
    jmp @next_player
:
    lda sudden_death
    bne @overtime
    lda seconds_left
    ldx #0
@minutes:
    cmp #60
    bcc @seconds
    sec
    sbc #60
    inx
    bne @minutes
@seconds:
    sta timer_remainder
    txa
    clc
    adc #'0'
    sta SA+15,y
    sta SB+15,y
    lda #':'
    sta SA+16,y
    sta SB+16,y
    lda timer_remainder
    ldx #0
@tens:
    cmp #10
    bcc @ones
    sec
    sbc #10
    inx
    bne @tens
@ones:
    clc
    adc #'0'
    sta SA+18,y
    sta SB+18,y
    txa
    clc
    adc #'0'
    sta SA+17,y
    sta SB+17,y
    jmp @next_player
@overtime:
    lda #'O'
    sta SA+15,y
    sta SB+15,y
    lda #'T'
    sta SA+16,y
    sta SB+16,y
    lda #'!'
    sta SA+17,y
    sta SB+17,y
    sta SA+18,y
    sta SB+18,y
@next_player:
    ldx hud_actor
    inx
    cpx #2
    jne @player
    rts

print_text:
    ldy #0
@next:
    lda (textptr),y
    beq @done
    sta (dst),y
    sta (dst2),y
    iny
    bne @next
@done:rts
nmi:
    pha
    lda $dd0d
    pla
    rti

.segment "RODATA"
bitmap_inks: .byte 0,$55,$aa,$ff
bitmap_rowlo:
.repeat 200,I
    .byte <($a000+(I/8)*320+(I&7))
.endrepeat
bitmap_rowhi:
.repeat 200,I
    .byte >($a000+(I/8)*320+(I&7))
.endrepeat
setup_controls: .byte "K KEYBOARD    J JOYSTICKS",0
setup_keys: .byte "K KEYBOARD",0
setup_sticks: .byte "J JOYSTICKS",0
setup_opponents: .byte "H TWO PLAYERS   C CPU",0
setup_humans: .byte "H TWO PLAYERS",0
setup_cpu: .byte "C CPU",0
setup_levels: .byte "1 EASY  2 MEDIUM  3 HARD",0
setup_easy: .byte "1 EASY",0
setup_medium: .byte "2 MEDIUM",0
setup_hard: .byte "3 HARD",0
setup_p1: .byte "P1 WASD MOVE Q/2 AIM",0
setup_p2: .byte "P2 UBNM MOVE ;/RET AIM",0
setup_key_extra: .byte "X/. FIRE 1 PAUSE F1 MAP",0
setup_stick_drive: .byte "STICK DRIVE/TURN",0
setup_stick_aim: .byte "HOLD FIRE + L/R AIM",0
setup_stick_extra: .byte "RELEASE:SHOT ESC:PAUSE",0
setup_start_cpu: .byte "P1 X TO BEGIN",0
setup_start_both: .byte "F1 MAP BOTH FIRE READY",0
setup_start_sticks: .byte "F1 MAP FIRE TO BEGIN",0
setup_cyan_win: .byte "CYAN WINS - FIRE READY",0
setup_gold_win: .byte "GOLD WINS - FIRE READY",0
setup_wait_gold: .byte "WAITING GOLD FIRE",0
setup_wait_cyan: .byte "WAITING CYAN FIRE",0
tick_lo: .byte <$ff5d,<$d5f4,<$d1dc
tick_hi: .byte >$ff5d,>$d5f4,>$d1dc
team_colors: .byte 3,7
team_letters: .byte 'C','G'
slot_view: .byte 0,0,1,1,0,0,1,1
slot_actor: .byte 0,1,1,0,0,1,1,0
slot_enemy: .byte 0,1,0,1
view_left: .byte 32,192
view_column: .byte 1,21
marker_edge_x: .byte 8,16,16,16,8,0,0,0
marker_edge_y: .byte 0,0,10,22,22,22,10,0
marker_rowlo:
    .repeat 24,I
        .byte <((I+1)*40)
    .endrepeat
marker_rowhi:
    .repeat 24,I
        .byte >((I+1)*40)
    .endrepeat
sprite_bits: .byte 1,2,4,8,16,32,64,128
hud_offsets: .byte 0,20
compass: .byte "N NE ESE SSW WNW"
range_first: .byte 'N','M','F'
range_second: .byte 'E','I','A'
range_third: .byte 'A','D','R'
status_first: .byte 'O','H','S','L','S'
status_second: .byte 'P','I','E','O','C'
status_third: .byte 'E','D','E','C','A'
status_fourth: .byte 'N','E','N','K','N'
glyph_rowlo:
.repeat 32,I
    .byte <(world_glyphs+I*64)
.endrepeat
glyph_rowhi:
.repeat 32,I
    .byte >(world_glyphs+I*64)
.endrepeat
easy_text: .byte "EASY  ",0
medium_text: .byte "MEDIUM",0
hard_text: .byte "HARD  ",0
level_lo: .byte <easy_text,<medium_text,<hard_text
level_hi: .byte >easy_text,>medium_text,>hard_text
.include "assets.inc"
.include "title.inc"
.assert __BSS_SIZE__ <= $600,lderror,"State overlaps BASIC"
.assert __WORK_SIZE__ <= $1f00,lderror,"Work RAM exceeds CFFF"
.assert __CODE_RUN__+__CODE_SIZE__ <= $4800,lderror,"Code overlaps tables"
.assert __RODATA_RUN__+__RODATA_SIZE__ <= $6000,lderror,"Tables overlap font source"
.segment "CHARSET_SOURCE"
font_source: .incbin "build/tanks/charset.bin"
.segment "SPRITE_SOURCE"
sprite_source: .incbin "build/tanks/sprites.bin"

.segment "WORK"
world_glyphs: .res 2048
.segment "BSS"
title_run: .res 1
title_value: .res 1
title_remaining: .res 2
menu_x: .res 1
menu_y: .res 1
menu_ink: .res 1
menu_string_index: .res 1
menu_char: .res 1
menu_glyph_row: .res 1
menu_bits: .res 1
menu_mask: .res 2
menu_pixels: .res 1
menu_colhi: .res 1
title_active: .res 1
start_world_request: .res 1
world_seed: .res 2
computer_player2: .res 1
ai_difficulty: .res 1
ticks: .res 1
video_frames: .res 1
video_standard: .res 1
highest_raster: .res 1
tick_step: .res 2
tick_fraction: .res 2
new_world_request: .res 1
active_screen: .res 1
frame_ready: .res 1
active_cam_x: .res 2
active_cam_y: .res 2
wanted_cam_x: .res 2
wanted_cam_y: .res 2
render_cam_x: .res 2
render_cam_y: .res 2
render_known: .res 2
render_zone_x: .res 2
render_zone_y: .res 2
render_bearing: .res 2
render_screen: .res 1
render_view: .res 1
render_rows: .res 1
marker_heading: .res 1
marker_x: .res 1
marker_y: .res 1
marker_glyph: .res 1
map_row: .res 1
map_col: .res 1
map_kind: .res 1
map_glyph: .res 1
connection: .res 1
ready: .res 2
menu_raw: .res 1
menu_previous: .res 1
menu_pressed: .res 1
menu_guard: .res 1
difficulty_raw: .res 1
difficulty_previous: .res 1
difficulty_pressed: .res 1
controls_previous: .res 2
fire_pressed: .res 2
previous_phase: .res 1
hud_version: .res 1
hud_painted: .res 1
hud_snapshot: .res 1
hud_phase: .res 1
hud_input: .res 1
hud_cpu: .res 1
hud_level: .res 1
hud_winner: .res 1
hud_ready: .res 2
hud_clock: .res 1
hud_actor: .res 1
hud_offset: .res 1
hud_sensor: .res 1
timer_remainder: .res 1
sprite_enable: .res 1
sprite_xhi: .res 1
sprite_slot: .res 1
viewer: .res 1
actor: .res 1
cam_pxlo: .res 1
cam_pxhi: .res 1
cam_py: .res 1
draw_x: .res 1
draw_y: .res 1
draw_pointer: .res 1
draw_color: .res 1

; BORROWED MOTION -- an original solo game for a stock Commodore 64.
; A movement is an object: exchange it with a vessel, then deliberately wind
; time. Stationary pearls settle in empty cradles. No real-time deadline.
;
; Main owns gameplay, input, graphics and SID. Raster IRQ only schedules a
; nominal 50 Hz tick. All animation is presentation; the two microsteps of a
; fast movement are shown separately, including bends and rebounds.
.setcpu "6502"
.macpack longbranch
.import input_init,input_poll,input_controls,input_pressed,menu_pressed
.import sound_init,sound_tick,sound_event,sound_silence,sound_enabled
.export start,irq,main_loop,controls_sampled,tick_done,video_standard,video_frames
.export scene,room_index,unlocked,selected,spool,settled,swaps,wind_count
.export actor_x,actor_y,actor_motion,actor_active,actor_type,actor_count
.export goal_used,goal_count,goal_x,goal_y,room_map,pearl_count
.export anim_left,micro_phase,undo_count,undo_head,undo_buffer,state_begin,state_end
.export tick_ready,late_ticks,wind_begin,swap_motion,undo_one,load_room
.export game_tick,advance_one,probe_x,probe_y,probe_motion
.export controls_buffer,help_return,best_swaps

SCREEN=$8000
FONT=$8800
SPRITES=$a000
COLOR=$d800
ROOMS=10
WIDTH=18
HEIGHT=9
ACTORS=6
HISTORY=32
ANIM_TICKS=16

.repeat 26,I
.charmap $41+I,I+1
.endrepeat

.segment "ZEROPAGE"
src: .res 2
dst: .res 2
colptr: .res 2
textptr: .res 2
snap_ptr: .res 2

.segment "BSS"
video_standard: .res 1
highest_raster: .res 1
video_frames: .res 2
tick_fraction: .res 2
tick_step: .res 2
tick_ready: .res 1
late_ticks: .res 2
ticks: .res 1
scene: .res 1                 ; 0 title, 1 room, 2 help, 3 restored, 4 ending
room_index: .res 1
unlocked: .res 1
help_return: .res 1
best_swaps: .res ROOMS
hud_dirty: .res 1
select_repeat: .res 1
undo_repeat: .res 1
controls_buffer: .res 1
clear_age: .res 1
actor_count: .res 1
actor_type: .res ACTORS
pearl_count: .res 1
room_map: .res WIDTH*HEIGHT
goal_count: .res 1
goal_x: .res 5
goal_y: .res 5
state_begin:
actor_x: .res ACTORS
actor_y: .res ACTORS
actor_motion: .res ACTORS
actor_active: .res ACTORS
goal_used: .res 1
spool: .res 1
selected: .res 1
settled: .res 1
swaps: .res 1
wind_count: .res 2
state_end:
STATE_SIZE=state_end-state_begin
.assert STATE_SIZE<=64,error,"Undo state exceeds its 64-byte record"
old_x: .res ACTORS
old_y: .res ACTORS
fast_pending: .res ACTORS
anim_left: .res 1
micro_phase: .res 1
undo_count: .res 1
undo_head: .res 1
probe_x: .res 1
probe_y: .res 1
probe_motion: .res 1
probe_slow: .res 1
probe_bounce: .res 1
next_x: .res 1
next_y: .res 1
direction: .res 1
speed_offset: .res 1
loop_actor: .res 1
loop_row: .res 1
loop_col: .res 1
loop_tile: .res 1
level_offset: .res 1
cell_kind: .res 1
cell_x: .res 1
cell_y: .res 1
text_color: .res 1
scratch: .res 1
scratch2: .res 1
swap_old: .res 1
bounce_any: .res 1
sprite_slot: .res 1
sprite_enable: .res 1
sprite_high: .res 1
sprite_frame: .res 1
sprite_color: .res 1
pixel_x: .res 2
pixel_y: .res 1
grid_x: .res 1
grid_y: .res 1
interpolate: .res 1
fx_life: .res 1
fx_x: .res 1
fx_y: .res 1
fx_kind: .res 1
preview_x: .res 1
preview_y: .res 1
preview_valid: .res 1

.segment "WORK"
undo_buffer: .res HISTORY*64

.macro TEXT label,row,col,color
    lda #<label
    sta textptr
    lda #>label
    sta textptr+1
    lda #<(SCREEN+row*40+col)
    sta dst
    lda #>(SCREEN+row*40+col)
    sta dst+1
    lda #<(COLOR+row*40+col)
    sta colptr
    lda #>(COLOR+row*40+col)
    sta colptr+1
    lda #color
    sta text_color
    jsr print_text
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
    tax
@clear:
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clear
    ldx #ROOMS-1
    lda #$ff
@best:
    sta best_swaps,x
    dex
    bpl @best
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
    lda #8
    sta $d016
    lda #0
    sta $d010
    sta $d017
    sta $d01b
    sta $d01c
    sta $d01d
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
    ldx #14
    jsr copy_pages
    ; 57 frames = 14 full pages plus the last 64 bytes.
    ldy #63
@last:
    lda (src),y
    sta (dst),y
    dey
    bpl @last
    jsr input_init
    lda video_standard
    jsr sound_init
    jsr show_title
    lda #248
    sta $d012
    lda #1
    sta $d019
    sta $d01a
    cli
main_loop:
    lda tick_ready
    beq main_loop
    sei
    lda #0
    sta tick_ready
    cli
    inc ticks
    jsr input_poll
controls_sampled:
    jsr game_tick
    jsr sound_tick
    lda scene
    cmp #1
    beq @room
    cmp #3
    bne @done
@room:
    jsr render_sprites
    lda hud_dirty
    beq @done
    jsr draw_hud
@done:
tick_done:
    jmp main_loop

.proc game_tick
    lda menu_pressed
    and #16
    beq :+
    lda sound_enabled
    eor #1
    sta sound_enabled
:
    lda scene
    cmp #2
    jeq help_tick
    lda menu_pressed
    and #4
    beq :+
    lda scene
    sta help_return
    jmp show_help
:
    lda scene
    beq title_tick
    cmp #4
    jeq ending_tick
    lda menu_pressed
    and #8
    beq :+
    jmp show_title
:
    lda menu_pressed
    and #2
    beq :+
    jmp load_room
:
    lda scene
    cmp #3
    jeq clear_tick
    jmp room_tick
.endproc

.proc title_tick
    lda input_pressed
    and #4
    beq @right
    lda room_index
    beq @right
    dec room_index
    jsr title_room_name
@right:
    lda input_pressed
    and #8
    beq @start
    lda room_index
    cmp unlocked
    bcs @start
    inc room_index
    jsr title_room_name
@start:
    lda input_pressed
    and #16
    bne @go
    lda menu_pressed
    and #1
    beq @done
@go:
    jmp load_room
@done:
    rts
.endproc

.proc help_tick
    lda input_pressed
    and #16
    bne @close
    lda menu_pressed
    and #13
    beq @done
@close:
    lda help_return
    cmp #1
    beq @room
    cmp #3
    beq @room
    cmp #4
    jeq show_ending
    jmp show_title
@room:
    sta scene
    jsr draw_room
@done:
    rts
.endproc

.proc ending_tick
    lda input_pressed
    and #16
    bne @back
    lda menu_pressed
    and #9
    beq @done
@back:
    lda #0
    sta room_index
    jmp show_title
@done:
    rts
.endproc

.proc clear_tick
    lda clear_age
    cmp #30
    bcs @input
    inc clear_age
    rts
@input:
    lda input_controls
    and #2
    beq @next
    lda #12
    sta undo_repeat
    jmp undo_one
@next:
    lda input_pressed
    and #16
    bne @go
    lda menu_pressed
    and #1
    beq @done
@go:
    inc room_index
    lda room_index
    cmp #ROOMS
    bcc @load
    dec room_index
    jmp show_ending
@load:
    jmp load_room
@done:
    rts
.endproc

.proc room_tick
    lda fx_life
    beq :+
    dec fx_life
:
    lda input_pressed
    and #28
    ora controls_buffer
    sta controls_buffer
    lda anim_left
    beq @commands
    dec anim_left
    jne @done
    lda micro_phase
    cmp #1
    bne @finish
    lda #0
    ldx #ACTORS-1
@fast:
    ora fast_pending,x
    dex
    bpl @fast
    beq @finish
    lda #2
    sta micro_phase
    jsr perform_microstep
    lda #ANIM_TICKS
    sta anim_left
    rts
@finish:
    lda #0
    sta micro_phase
    jsr settle_pearls
    jsr update_preview
    lda #1
    sta hud_dirty
    lda scene
    cmp #1
    jne @done
@commands:
    lda select_repeat
    beq :+
    dec select_repeat
:
    lda undo_repeat
    beq :+
    dec undo_repeat
:
    lda input_controls
    and #2
    beq @select
    lda undo_repeat
    bne @done
    lda #8
    sta undo_repeat
    lda #0
    sta controls_buffer
    jmp undo_one
@select:
    lda controls_buffer
    and #12
    bne @choose
    lda input_controls
    and #12
    beq @exchange
    ldx select_repeat
    bne @exchange
@choose:
    sta scratch
    lda #12
    sta select_repeat
    lda scratch
    and #4
    beq @next
    jsr previous_actor
    jmp @chosen
@next:
    jsr next_actor
@chosen:
    lda controls_buffer
    and #$f3
    sta controls_buffer
    jsr update_preview
    lda #1
    sta hud_dirty
    lda #1
    jsr sound_event
    rts
@exchange:
    lda controls_buffer
    and #16
    beq @wind
    lda #0
    sta controls_buffer
    jmp swap_motion
@wind:
    lda input_controls
    and #1
    beq @done
    jmp wind_begin
@done:
    rts
.endproc

.proc load_room
    lda #0
    sta $d015
    sta scene
    sta undo_count
    sta undo_head
    sta controls_buffer
    sta select_repeat
    sta undo_repeat
    sta anim_left
    sta micro_phase
    sta fx_life
    sta clear_age
    sta pearl_count
    sta goal_count
    ldx #STATE_SIZE-1
@clear_state:
    sta state_begin,x
    dex
    bpl @clear_state
    ldx room_index
    lda map_lo,x
    sta src
    lda map_hi,x
    sta src+1
    ldy #0
@map:
    lda (src),y
    sta room_map,y
    iny
    cpy #WIDTH*HEIGHT
    bne @map
    lda level_actor_count,x
    sta actor_count
    txa
    asl
    sta level_offset
    asl
    clc
    adc level_offset
    tay
    ldx #0
@actors:
    lda level_actor_type,y
    sta actor_type,x
    lda level_actor_x,y
    sta actor_x,x
    sta old_x,x
    lda level_actor_y,y
    sta actor_y,x
    sta old_y,x
    lda level_actor_motion,y
    sta actor_motion,x
    lda #0
    sta fast_pending,x
    cpx actor_count
    bcs @inactive
    lda actor_type,x
    bne :+
    inc pearl_count
:
    lda #1
@inactive:
    sta actor_active,x
    iny
    inx
    cpx #ACTORS
    bne @actors
    lda #0
    sta cell_x
    sta cell_y
    ldx #0
@goals:
    lda room_map,x
    cmp #4
    bne @cell_next
    ldy goal_count
    lda cell_x
    sta goal_x,y
    lda cell_y
    sta goal_y,y
    inc goal_count
@cell_next:
    inc cell_x
    lda cell_x
    cmp #WIDTH
    bne :+
    lda #0
    sta cell_x
    inc cell_y
:
    inx
    cpx #WIDTH*HEIGHT
    bne @goals
    lda room_index
    bne :+
    lda #1
    sta selected                 ; first lesson starts on the moving bell
:
    lda #1
    sta scene
    jsr update_preview
    jsr draw_room
    lda #0
    sta late_ticks
    sta late_ticks+1
    sta tick_ready
    lda #9
    jsr sound_event
    rts
.endproc

.proc previous_actor
    ldx selected
    ldy actor_count
@again:
    dex
    bpl :+
    ldx actor_count
    dex
:
    lda actor_active,x
    bne @found
    dey
    bne @again
    rts
@found:
    stx selected
    rts
.endproc
.proc next_actor
    ldx selected
    ldy actor_count
@again:
    inx
    cpx actor_count
    bcc :+
    ldx #0
:
    lda actor_active,x
    bne @found
    dey
    bne @again
    rts
@found:
    stx selected
    rts
.endproc

.proc swap_motion
    ldx selected
    lda actor_active,x
    beq @done
    lda actor_motion,x
    cmp spool
    beq @done                    ; swapping equal motions is a harmless no-op
    jsr push_undo
    ldx selected
    lda actor_motion,x
    sta swap_old
    lda spool
    sta actor_motion,x
    lda swap_old
    sta spool
    lda swaps
    cmp #$ff
    beq :+
    inc swaps
:
    lda actor_x,x
    sta fx_x
    lda actor_y,x
    sta fx_y
    lda #12
    sta fx_life
    lda #0
    sta fx_kind
    lda spool
    beq @give
    lda actor_motion,x
    bne @both
    lda #2
    bne @sound
@give:
    lda #3
    bne @sound
@both:
    lda #4
@sound:
    jsr sound_event
    jsr settle_pearls
    jsr update_preview
    lda #1
    sta hud_dirty
@done:
    rts
.endproc

.proc wind_begin
    ; Winding an entirely still room changes nothing and must not consume undo.
    ldx #ACTORS-1
@moving:
    lda actor_active,x
    beq @check_next
    lda actor_motion,x
    bne @begin
@check_next:
    dex
    bpl @moving
    rts
@begin:
    jsr push_undo
    inc wind_count
    bne :+
    inc wind_count+1
:
    ldx #ACTORS-1
@fast:
    lda #0
    sta fast_pending,x
    lda actor_motion,x
    cmp #5
    bcc :+
    lda actor_active,x
    sta fast_pending,x
:
    dex
    bpl @fast
    lda #1
    sta micro_phase
    jsr perform_microstep
    lda #ANIM_TICKS
    sta anim_left
    rts
.endproc

.proc perform_microstep
    lda #0
    sta bounce_any
    ldx #0
@actor:
    stx loop_actor
    lda actor_x,x
    sta old_x,x
    sta probe_x
    lda actor_y,x
    sta old_y,x
    sta probe_y
    lda actor_motion,x
    sta probe_motion
    lda actor_active,x
    beq @next
    lda micro_phase
    cmp #2
    bne @move
    lda fast_pending,x
    beq @next
@move:
    jsr advance_one
    ldx loop_actor
    lda probe_x
    sta actor_x,x
    lda probe_y
    sta actor_y,x
    lda probe_motion
    sta actor_motion,x
    lda probe_slow
    beq :+
    lda #0
    sta fast_pending,x
:
    lda probe_bounce
    ora bounce_any
    sta bounce_any
@next:
    inx
    cpx #ACTORS
    bne @actor
    lda bounce_any
    beq :+
    lda #5
    jsr sound_event
:
    rts
.endproc

; One pure microstep, shared by actual movement and next-landing preview.
; X/Y/A clobbered. The external reference model checks this implementation.
.proc advance_one
    lda #0
    sta probe_slow
    sta probe_bounce
    sta speed_offset
    lda probe_motion
    jeq @done
    cmp #5
    bcc @dir
    sec
    sbc #4
    ldx #4
    stx speed_offset
@dir:
    sta direction
    tax
    lda probe_x
    clc
    adc delta_x,x
    sta next_x
    cmp #WIDTH
    bcs @bounce
    lda probe_y
    clc
    adc delta_y,x
    sta next_y
    cmp #HEIGHT
    bcs @bounce
    tax
    lda row_offset,x
    clc
    adc next_x
    tay
    lda room_map,y
    cmp #1
    beq @bounce
    sta cell_kind
    lda next_x
    sta probe_x
    lda next_y
    sta probe_y
    ldx direction
    lda cell_kind
    cmp #2
    beq @slash
    cmp #3
    beq @backslash
    cmp #5
    beq @glass
    rts
@slash:
    lda slash_dir,x
    jmp @new_dir
@backslash:
    lda backslash_dir,x
@new_dir:
    clc
    adc speed_offset
    sta probe_motion
    rts
@glass:
    lda direction
    sta probe_motion
    lda #1
    sta probe_slow
    rts
@bounce:
    ldx direction
    lda reverse_dir,x
    clc
    adc speed_offset
    sta probe_motion
    lda #1
    sta probe_bounce
@done:
    rts
.endproc

.proc update_preview
    lda #0
    sta preview_valid
    ldx selected
    lda actor_active,x
    beq @done
    lda actor_motion,x
    beq @done
    sta probe_motion
    sta scratch2
    lda actor_x,x
    sta probe_x
    lda actor_y,x
    sta probe_y
    jsr advance_one
    lda scratch2
    cmp #5
    bcc @save
    lda probe_slow
    bne @save
    jsr advance_one
@save:
    lda probe_x
    sta preview_x
    lda probe_y
    sta preview_y
    lda #1
    sta preview_valid
@done:
    rts
.endproc

.proc settle_pearls
    ldx #0
@actor:
    stx loop_actor
    lda actor_active,x
    beq @next
    lda actor_type,x
    ora actor_motion,x
    bne @next
    ldy #0
@goal:
    cpy goal_count
    beq @next
    lda goal_used
    and bits,y
    bne @goal_next
    lda actor_x,x
    cmp goal_x,y
    bne @goal_next
    lda actor_y,x
    cmp goal_y,y
    bne @goal_next
    lda goal_used
    ora bits,y
    sta goal_used
    lda #0
    sta actor_active,x
    inc settled
    lda actor_x,x
    sta fx_x
    lda actor_y,x
    sta fx_y
    lda #28
    sta fx_life
    lda #1
    sta fx_kind
    lda #6
    jsr sound_event
    ldx loop_actor
    cpx selected
    bne @next
    jsr next_actor
    ldx loop_actor
    jmp @next
@goal_next:
    iny
    bne @goal
@next:
    inx
    cpx actor_count
    bne @actor
    jsr draw_goals
    lda settled
    cmp pearl_count
    bne @done
    lda #3
    sta scene
    lda #0
    sta clear_age
    ldx room_index
    lda swaps
    cmp best_swaps,x
    bcs :+
    sta best_swaps,x
:
    lda room_index
    cmp #ROOMS-1
    bcs :+
    clc
    adc #1
    cmp unlocked
    bcc :+
    sta unlocked
:
    lda #7
    jsr sound_event
@done:
    rts
.endproc

.proc snapshot_address
    ; A = record index, 64 bytes each, fixed page-aligned WORK region.
    pha
    and #3
    asl
    asl
    asl
    asl
    asl
    asl
    sta snap_ptr
    pla
    lsr
    lsr
    clc
    adc #>undo_buffer
    sta snap_ptr+1
    rts
.endproc
.proc push_undo
    lda undo_head
    jsr snapshot_address
    ldy #STATE_SIZE-1
@save:
    lda state_begin,y
    sta (snap_ptr),y
    dey
    bpl @save
    inc undo_head
    lda undo_head
    and #HISTORY-1
    sta undo_head
    lda undo_count
    cmp #HISTORY
    bcs @done
    inc undo_count
@done:
    rts
.endproc
.proc undo_one
    lda undo_count
    beq @done
    dec undo_count
    lda undo_head
    sec
    sbc #1
    and #HISTORY-1
    sta undo_head
    jsr snapshot_address
    ldy #STATE_SIZE-1
@restore:
    lda (snap_ptr),y
    sta state_begin,y
    dey
    bpl @restore
    lda #0
    sta anim_left
    sta micro_phase
    sta fx_life
    sta controls_buffer
    lda #1
    sta scene
    sta hud_dirty
    jsr draw_goals
    jsr update_preview
    lda #8
    jsr sound_event
@done:
    rts
.endproc

.proc draw_room
    lda #$0b
    sta $d011
    lda #0
    sta $d015
    jsr clear_screen
    lda #0
    sta loop_tile
    sta loop_row
@row:
    lda #0
    sta loop_col
@cell:
    ldx loop_tile
    lda room_map,x
    sta cell_kind
    lda loop_col
    sta cell_x
    lda loop_row
    sta cell_y
    jsr draw_tile
    inc loop_tile
    inc loop_col
    lda loop_col
    cmp #WIDTH
    bne @cell
    inc loop_row
    lda loop_row
    cmp #HEIGHT
    bne @row
    jsr draw_goals
    TEXT heading,0,1,7
    TEXT controls_line,23,1,15
    TEXT tools_line,24,1,12
    jsr draw_hud
    jsr render_sprites
    lda #$1b
    sta $d011
    rts
.endproc

.proc draw_tile
    ldx cell_y
    lda board_lo,x
    sta dst
    sta colptr
    lda board_hi,x
    sta dst+1
    clc
    adc #$58
    sta colptr+1
    lda cell_x
    asl
    tay
    lda cell_kind
    asl
    asl
    tax
    lda tile_chars,x
    sta (dst),y
    lda tile_colors,x
    sta (colptr),y
    iny
    lda tile_chars+1,x
    sta (dst),y
    lda tile_colors+1,x
    sta (colptr),y
    tya
    clc
    adc #39
    tay
    lda tile_chars+2,x
    sta (dst),y
    lda tile_colors+2,x
    sta (colptr),y
    iny
    lda tile_chars+3,x
    sta (dst),y
    lda tile_colors+3,x
    sta (colptr),y
    rts
.endproc
.proc draw_goals
    lda #0
    sta loop_row
@loop:
    ldx loop_row
    cpx goal_count
    beq @done
    lda goal_x,x
    sta cell_x
    lda goal_y,x
    sta cell_y
    lda #4
    sta cell_kind
    lda goal_used
    and bits,x
    beq :+
    lda #6
    sta cell_kind
:
    jsr draw_tile
    inc loop_row
    bne @loop
@done:
    rts
.endproc

.proc draw_hud
    lda #0
    sta hud_dirty
    TEXT hud_template,1,1,15
    ldx spool
    lda motion_chars,x
    sta SCREEN+40+7
    lda #7
    sta COLOR+40+7
    lda spool
    cmp #5
    bcc :+
    lda #50                     ; explicit speed badge beside the spool arrow
    sta SCREEN+40+8
:
    ldx selected
    lda actor_type,x
    beq @pearl
    TEXT bell_label,1,11,7
    jmp @actor
@pearl:
    TEXT pearl_label,1,11,3
@actor:
    ldx selected
    txa
    clc
    adc #49
    sta SCREEN+40+17
    lda actor_motion,x
    tax
    lda motion_chars,x
    sta SCREEN+40+19
    lda #1
    sta COLOR+40+19
    ldx selected
    lda actor_motion,x
    cmp #5
    bcc :+
    lda #50
    sta SCREEN+40+20
:
    lda settled
    clc
    adc #48
    sta SCREEN+40+27
    lda pearl_count
    clc
    adc #48
    sta SCREEN+40+29
    lda room_index
    clc
    adc #1
    jsr decimal_two
    stx SCREEN+0*40+30
    sta SCREEN+0*40+31
    ldx room_index
    lda hint_lo,x
    sta src
    lda hint_hi,x
    sta src+1
    ldy #37
@hint:
    lda (src),y
    sta SCREEN+80+1,y
    lda #12
    sta COLOR+80+1,y
    dey
    bpl @hint
    lda name_lo,x
    sta src
    lda name_hi,x
    sta src+1
    ldy #23
@name:
    lda (src),y
    sta SCREEN+880+2,y
    lda #7
    sta COLOR+880+2,y
    dey
    bpl @name
    TEXT swaps_label,22,28,15
    lda swaps
    jsr decimal_three
    stx SCREEN+880+34
    sty SCREEN+880+35
    sta SCREEN+880+36
    lda scene
    cmp #3
    bne @lesson
    TEXT restored_line,2,1,13
    TEXT clear_controls,23,1,1
    TEXT clear_tools,24,1,12
    rts
@lesson:
    ; Undo can return from the room-clear screen; restore the action labels.
    TEXT controls_line,23,1,15
    TEXT tools_line,24,1,12
    ; Include selection in the first-room lesson: Space acts on the selected
    ; artifact even when the pearl has just arrived on its nest.
    lda room_index
    jne @done
    lda spool
    bne @holding
    lda actor_motion
    jne @drifting
    lda selected
    cmp #1
    bne @choose_bell
    TEXT lesson_take,2,1,3
    rts
@choose_bell:
    TEXT lesson_choose_bell,2,1,3
    rts
@holding:
    lda selected
    bne @choose_pearl
    TEXT lesson_give,2,1,3
    rts
@choose_pearl:
    TEXT lesson_choose_pearl,2,1,3
    rts
@drifting:
    lda selected
    bne @choose_pearl
    lda actor_x
    cmp #12
    bne @wind
    TEXT lesson_brake,2,1,7
    rts
@wind:
    TEXT lesson_wind,2,1,3
@done:
    rts
.endproc

.proc render_sprites
    lda #0
    sta sprite_enable
    sta sprite_high
    sta sprite_slot
    ldx selected
    lda actor_active,x
    beq @others
    jsr render_actor
@others:
    ldx #0
@loop:
    cpx selected
    beq @next
    lda actor_active,x
    beq @next
    jsr render_actor
@next:
    inx
    cpx actor_count
    bne @loop
    ldx selected
    lda actor_active,x
    beq @effect
    jsr actor_pixels
    lda #6
    sta sprite_slot
    lda ticks
    lsr
    lsr
    lsr
    and #3
    clc
    adc #8
    sta sprite_frame
    lda #1
    sta sprite_color
    jsr put_sprite
@effect:
    lda #7
    sta sprite_slot
    lda fx_life
    beq @preview
    lda fx_x
    sta grid_x
    lda fx_y
    sta grid_y
    jsr grid_pixels
    lda fx_life
    lsr
    lsr
    and #3
    clc
    adc #13
    sta sprite_frame
    lda #7
    sta sprite_color
    jsr put_sprite
    jmp @publish
@preview:
    lda anim_left
    bne @publish
    lda preview_valid
    beq @publish
    lda scene
    cmp #1
    bne @publish
    lda preview_x
    sta grid_x
    lda preview_y
    sta grid_y
    jsr grid_pixels
    lda #12
    sta sprite_frame
    lda #4
    sta sprite_color
    jsr put_sprite
@publish:
    lda sprite_high
    sta $d010
    lda sprite_enable
    sta $d015
    rts
.endproc

.proc render_actor
    stx loop_actor
    jsr actor_pixels
    lda actor_motion,x
    cmp #5
    bcc :+
    sec
    sbc #4
:
    asl
    asl
    clc
    adc #17
    sta sprite_frame
    lda actor_type,x
    beq @pearl
    lda sprite_frame
    clc
    adc #20
    sta sprite_frame
    lda #7
    bne @color
@pearl:
    lda #3
@color:
    sta sprite_color
    lda ticks
    lsr
    lsr
    lsr
    and #3
    clc
    adc sprite_frame
    sta sprite_frame
    jsr put_sprite
    inc sprite_slot
    ldx loop_actor
    rts
.endproc

.proc actor_pixels
    lda actor_x,x
    sta grid_x
    lda actor_y,x
    sta grid_y
    lda anim_left
    jeq grid_pixels
    lda old_x,x
    sta grid_x
    lda old_y,x
    sta grid_y
    jsr grid_pixels
    lda #ANIM_TICKS
    sec
    sbc anim_left
    sta interpolate
    lda actor_x,x
    cmp old_x,x
    beq @y
    bcc @left
    lda pixel_x
    clc
    adc interpolate
    sta pixel_x
    bcc @y
    inc pixel_x+1
    jmp @y
@left:
    lda pixel_x
    sec
    sbc interpolate
    sta pixel_x
    bcs @y
    dec pixel_x+1
@y:
    lda actor_y,x
    cmp old_y,x
    beq @done
    bcc @up
    lda pixel_y
    clc
    adc interpolate
    sta pixel_y
    rts
@up:
    lda pixel_y
    sec
    sbc interpolate
    sta pixel_y
@done:
    rts
.endproc
.proc grid_pixels
    lda #0
    sta pixel_x+1
    lda grid_x
    asl
    asl
    asl
    asl
    rol pixel_x+1
    clc
    adc #36
    sta pixel_x
    bcc :+
    inc pixel_x+1
:
    lda grid_y
    asl
    asl
    asl
    asl
    clc
    adc #80
    sta pixel_y
    rts
.endproc
.proc put_sprite
    ldx sprite_slot
    lda bits,x
    ora sprite_enable
    sta sprite_enable
    lda pixel_x+1
    beq :+
    lda bits,x
    ora sprite_high
    sta sprite_high
:
    txa
    asl
    tay
    lda pixel_x
    sta $d000,y
    lda pixel_y
    sta $d001,y
    lda sprite_frame
    clc
    adc #SPRITES/$40-512
    sta SCREEN+$3f8,x
    lda sprite_color
    sta $d027,x
    rts
.endproc

.proc show_title
    lda #0
    sta scene
    sta anim_left
    sta controls_buffer
    sta $d015
    lda #$0b
    sta $d011
    jsr copy_title
    TEXT title_controls,20,2,15
    TEXT title_time,21,2,15
    TEXT title_start,23,3,1
    TEXT title_extra,24,2,12
    jsr title_room_name
    lda #$1b
    sta $d011
    rts
.endproc
.proc title_room_name
    ldx room_index
    lda name_lo,x
    sta src
    lda name_hi,x
    sta src+1
    ldy #23
@name:
    lda (src),y
    sta SCREEN+880+8,y
    lda #7
    sta COLOR+880+8,y
    dey
    bpl @name
    TEXT title_room,22,2,12
    lda room_index
    clc
    adc #1
    jsr decimal_two
    stx SCREEN+880+5
    sta SCREEN+880+6
    rts
.endproc
.proc show_help
    lda #2
    sta scene
    lda #0
    sta $d015
    lda #$0b
    sta $d011
    jsr clear_screen
    TEXT heading,0,1,7
    TEXT help_a,2,1,1
    TEXT help_b,3,1,3
    TEXT help_c,5,1,7
    TEXT help_d,6,1,7
    TEXT help_e,7,1,15
    TEXT help_f,9,1,7
    TEXT help_g,10,1,15
    TEXT help_h,12,1,7
    TEXT help_i,13,1,15
    TEXT help_j,15,1,15
    TEXT help_k,16,1,15
    TEXT help_touch,17,1,15
    TEXT help_l,19,1,12
    TEXT help_m,20,1,12
    TEXT help_n,22,1,3
    TEXT help_close,24,1,1
    lda #$1b
    sta $d011
    rts
.endproc
.proc show_ending
    lda #4
    sta scene
    lda #0
    sta $d015
    lda #$0b
    sta $d011
    jsr copy_title
    TEXT ending_a,20,6,13
    TEXT ending_b,21,2,15
    TEXT ending_c,23,2,7
    TEXT ending_d,24,2,1
    lda #$1b
    sta $d011
    lda #7
    jsr sound_event
    rts
.endproc
.proc copy_title
    lda #<title_screen_source
    sta src
    lda #>title_screen_source
    sta src+1
    lda #<SCREEN
    sta dst
    lda #>SCREEN
    sta dst+1
    ldx #3
    jsr copy_pages
    ldy #231
@screen:
    lda (src),y
    sta (dst),y
    dey
    cpy #$ff
    bne @screen
    lda #<title_color_source
    sta src
    lda #>title_color_source
    sta src+1
    lda #<COLOR
    sta dst
    lda #>COLOR
    sta dst+1
    ldx #3
    jsr copy_pages
    ldy #231
@color:
    lda (src),y
    sta (dst),y
    dey
    cpy #$ff
    bne @color
    rts
.endproc
.proc clear_screen
    lda #32
    ldx #0
@screen:
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    cpx #232
    bcs :+
    sta SCREEN+$300,x
:
    inx
    bne @screen
    lda #12
@color:
    sta COLOR,x
    sta COLOR+$100,x
    sta COLOR+$200,x
    cpx #232
    bcs :+
    sta COLOR+$300,x
:
    inx
    bne @color
    rts
.endproc
.proc print_text
    ldy #0
@char:
    lda (textptr),y
    beq @done
    sta (dst),y
    lda text_color
    sta (colptr),y
    iny
    bne @char
@done:
    rts
.endproc
.proc decimal_two
    ldx #48
@ten:
    cmp #10
    bcc @done
    sec
    sbc #10
    inx
    bne @ten
@done:
    clc
    adc #48
    rts
.endproc
.proc decimal_three
    ldx #48
@hundred:
    cmp #100
    bcc @tens
    sec
    sbc #100
    inx
    bne @hundred
@tens:
    stx scratch
    jsr decimal_two
    pha
    txa
    tay
    ldx scratch
    pla
    rts
.endproc
.proc copy_pages
    ldy #0
@byte:
    lda (src),y
    sta (dst),y
    iny
    bne @byte
    inc src+1
    inc dst+1
    dex
    bne copy_pages
    rts
.endproc
.proc detect_video
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
@done:
    rts
.endproc
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
    bne :+
    inc video_frames+1
:
    clc
    lda tick_fraction
    adc tick_step
    sta tick_fraction
    lda tick_fraction+1
    adc tick_step+1
    sta tick_fraction+1
    bcc @done
    lda tick_ready
    beq :+
    inc late_ticks
    bne :+
    inc late_ticks+1
:
    lda #1
    sta tick_ready
@done:
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
tick_lo: .byte $5d,$f4,$dc
tick_hi: .byte $ff,$d5,$d1
bits: .byte 1,2,4,8,16,32,64,128
delta_x: .byte 0,1,0,255,0
delta_y: .byte 0,0,1,0,255
slash_dir: .byte 0,4,3,2,1
backslash_dir: .byte 0,2,1,4,3
reverse_dir: .byte 0,3,4,1,2
motion_chars: .byte 72,64,65,66,67,68,69,70,71
row_offset: .byte 0,18,36,54,72,90,108,126,144
board_lo:
.repeat HEIGHT,I
    .byte <(SCREEN+4*40+2+I*80)
.endrepeat
board_hi:
.repeat HEIGHT,I
    .byte >(SCREEN+4*40+2+I*80)
.endrepeat
map_lo:
.repeat ROOMS,I
    .byte <(level_maps+I*162)
.endrepeat
map_hi:
.repeat ROOMS,I
    .byte >(level_maps+I*162)
.endrepeat
name_lo:
.repeat ROOMS,I
    .byte <(level_names+I*24)
.endrepeat
name_hi:
.repeat ROOMS,I
    .byte >(level_names+I*24)
.endrepeat
hint_lo:
.repeat ROOMS,I
    .byte <(level_hints+I*38)
.endrepeat
hint_hi:
.repeat ROOMS,I
    .byte >(level_hints+I*38)
.endrepeat
heading: .byte "BORROWED MOTION         ROOM 00/10",0
hud_template: .byte "SPOOL     PEARL 0    REST 0/0         ",0
swaps_label: .byte "SWAPS 000",0
lesson_choose_bell: .byte "A/D: CHOOSE THE BELL. SPACE: TAKE.    ",0
lesson_choose_pearl: .byte "A/D: CHOOSE THE PEARL TO GUIDE IT.    ",0
help_touch: .byte "OBJECTS PASS THROUGH EACH OTHER.      ",0
pearl_label: .byte "PEARL",0
bell_label: .byte "BELL ",0
controls_line: .byte "A/D PICK  SPACE SWAP  TAP/HOLD W WIND ",0
tools_line: .byte "S UNDO  R RESTART  H HELP  M SOUND    ",0
restored_line: .byte "ALL PEARLS REST. SPACE TO CONTINUE.   ",0
clear_controls: .byte "SPACE / RETURN / FIRE: NEXT ROOM      ",0
clear_tools: .byte "S/DOWN: UNDO  R: REPLAY  H: HELP      ",0
lesson_take: .byte "SPACE: TAKE THE BELL'S MOTION.        ",0
lesson_give: .byte "SPACE: LEND THE MOTION TO THE PEARL.  ",0
lesson_wind: .byte "TAP W: ONE BEAT. HOLD W: KEEP GOING.  ",0
lesson_brake: .byte "SPACE: TAKE MOTION. THE PEARL RESTS.  ",0
title_controls: .byte "A/D: SELECT    SPACE/FIRE: EXCHANGE",0
title_time: .byte "TAP W: ONE BEAT   HOLD W: WIND MORE",0
title_start: .byte "RETURN / FIRE: BEGIN   H: HELP",0
title_extra: .byte "JOYSTICK 2: L/R SELECT  UP WIND",0
title_room: .byte "NO.",0
help_a: .byte "YOU CAN BORROW THE WAY THINGS MOVE.   ",0
help_b: .byte "GUIDE EVERY PEARL INTO A GOLDEN NEST. ",0
help_c: .byte "A/D OR LEFT/RIGHT: SELECT AN OBJECT.  ",0
help_d: .byte "SPACE/FIRE: SWAP ITS MOTION WITH YOUR ",0
help_e: .byte "SPOOL. AN EMPTY SPOOL MAKES IT STILL. ",0
help_f: .byte "TAP W/UP: ONE BEAT. HOLD: WIND MORE.  ",0
help_g: .byte "RELEASE TO THINK. ALL OBJECTS WAIT.   ",0
help_h: .byte "ON A NEST, TAKE A PEARL'S MOTION.     ",0
help_i: .byte "IT MUST BE STILL TO SETTLE THERE.     ",0
help_j: .byte "MIRRORS TURN. WALLS REVERSE MOTION.   ",0
help_k: .byte "GLASS SLOWS. ARROW+2: TWO TILES/BEAT. ",0
help_l: .byte "S/DOWN UNDO   R RESTART   M SOUND     ",0
help_m: .byte "RUN/STOP: TITLE. H: THIS GUIDE.       ",0
help_n: .byte "PURPLE GHOST: SELECTED NEXT BEAT.     ",0
help_close: .byte "SPACE / FIRE / RETURN / H: BACK       ",0
ending_a: .byte "THE ARCHIVE IS AWAKE.",0
ending_b: .byte "TEN ROOMS. EVERY PEARL HOME AT LAST.",0
ending_c: .byte "THE SMALL THINGS CAN DREAM AGAIN.",0
ending_d: .byte "SPACE TO REVISIT ANY RESTORED ROOM",0

.include "assets.inc"
.include "levels.inc"
.assert font_source_end-font_source=2048,error,"Charset must contain 256 glyphs"
.assert sprite_source_end-sprite_source=57*64,error,"Sprite contract changed"
.assert *<$8000,error,"Code and source assets reached VIC screen RAM"

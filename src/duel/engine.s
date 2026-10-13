; Bannerfall. One shared battlefield; all live state belongs to the raster IRQ.
; Main generates/paints only with IRQs and display disabled. No ROM services,
; REU, disk access during play, illegal opcodes, or emulator-specific behavior.
.setcpu "6502"
.macpack longbranch
.import arena_generate, arena_tiles, game_init, game_start, game_tick
.import game_state, winner, score, health, respawn, invulnerable
.import p_xlo, p_xhi, p_y, p_progress, b_active, b_xlo, b_xhi, b_y
.import f_state, f_xlo, f_xhi, f_y, seconds_left, sudden_death
.import duel_input_poll, duel_menu_poll, dual_controls, input_mode, menu_controls
.import duel_sound_init, duel_sound_tick, duel_sound_silence
.import ai_init, ai_tick
.import __BSS_SIZE__, __CODE_RUN__, __CODE_SIZE__, __RODATA_RUN__, __RODATA_SIZE__
.export start, irq, irq_done, main_loop, controls_sampled, duel_seed
.export ticks, video_frames, video_standard, ready, new_arena_request
.export frame_published, simulation_done
.export computer_player2, ai_controls_ready

SCREEN=$8000
CHARSET=$8800
SPRITES=$a000

.segment "ZEROPAGE"
source: .res 2
dest: .res 2
color_dest: .res 2
text_ptr: .res 2

.macro TEXT label, row, column
    lda #<label
    sta text_ptr
    lda #>label
    sta text_ptr+1
    lda #<(SCREEN+(row)*40+(column))
    sta dest
    lda #>(SCREEN+(row)*40+(column))
    sta dest+1
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
@clear:
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne @clear
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
    sta $d01d
    sta $d01b
    sta $d01c
    ; Timer pin output overrides ordinary Port B direction. Keep timer clocks
    ; available for startup seed entropy, but release PB6/PB7 for the keyboard.
    lda $dc0e
    and #$fd
    sta $dc0e
    lda $dc0f
    and #$fd
    sta $dc0f
    lda #0
    sta $dc02
    sta $dc03
    lda #$ff
    sta $dc00
    sta $dc01
    lda #<duel_charset
    sta source
    lda #>duel_charset
    sta source+1
    lda #<CHARSET
    sta dest
    lda #>CHARSET
    sta dest+1
    ldx #8
    jsr copy_pages
    lda #<duel_sprites
    sta source
    lda #>duel_sprites
    sta source+1
    lda #<SPRITES
    sta dest
    lda #>SPRITES
    sta dest+1
    ldx #3
    jsr copy_pages
    lda video_standard
    jsr duel_sound_init
    lda $dc04
    eor $d012
    eor #$53
    sta duel_seed
    lda $dc05
    eor $d011
    eor #$a9
    sta duel_seed+1
    ora duel_seed
    bne :+
    inc duel_seed
:
    jsr prepare_arena
    lda #16
    sta $d012
    lda #1
    sta $d019
    sta $d01a
    cli
main_loop:
    lda new_arena_request
    beq main_loop
    sei
    lda #$0b
    sta $d011
    lda #0
    sta $d015
    ; Advance the seed and stir in human timing; no uninitialized RAM entropy.
    lsr duel_seed+1
    ror duel_seed
    bcc :+
    lda duel_seed+1
    eor #$b4
    sta duel_seed+1
:
    lda duel_seed
    eor ticks
    sta duel_seed
    ora duel_seed+1
    bne :+
    inc duel_seed
:
    jsr prepare_arena
    lda #1
    sta $d019
    cli
    jmp main_loop

prepare_arena:
    jsr arena_generate
    jsr game_init
    jsr ai_init
    jsr render_arena
    lda #0
    sta ready
    sta ready+1
    sta new_arena_request
    lda computer_player2
    sta ready+1
    lda #$ff
    sta hud_state
    sta hud_mode
    sta hud_opponent
    jsr hud_static
    jsr hud_dynamic
    lda #$1b
    sta $d011
    rts

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
@done:
    rts

copy_pages:
    ldy #0
@copy:
    lda (source),y
    sta (dest),y
    iny
    bne @copy
    inc source+1
    inc dest+1
    dex
    bne copy_pages
    rts

; Raster 16: publish the previous completed simulation before any actor's Y.
; The full game advances at 50Hz on PAL, common NTSC and early 64-cycle NTSC.
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
    lda game_state
    beq @menu
    cmp #2
    bne @input
@menu:
    jsr duel_menu_poll
    sta menu_raw
@input:
    jsr duel_input_poll
controls_sampled:
    ; Verification may substitute normalized held controls at this boundary.
    ; Production always uses the CIA sample made immediately above.
    lda menu_controls
    ora menu_raw
    sta menu_raw
    lda menu_previous
    eor #$ff
    and menu_raw
    sta menu_pressed
    lda menu_raw
    sta menu_previous
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
:
simulation_done:
    lda game_state
    cmp #3
    beq @hud
    cmp #4
    beq @hud
    jsr duel_sound_tick
@hud:
    jsr hud_static
    inc hud_clock
    lda hud_clock
    cmp #5
    bcc irq_done
    lda #0
    sta hud_clock
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
    ; Title/results only: choose input mode or a new arena with gameplay keys
    ; released. The control switches cannot ghost one another, but a chord
    ; such as D+X+N can electrically close the unmapped J mode-select path.
    ; Held directions/fire therefore bypass administrative menu actions.
    lda dual_controls
    ora dual_controls+1
    bne @ready
    lda menu_pressed
    and #2
    beq :+
    lda #4
    sta game_state
    lda #1
    sta new_arena_request
    jmp duel_sound_silence
:
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
:
    dex
    bpl @player
    lda ready
    and ready+1
    beq @done
    jsr game_start
    jsr ai_init
    lda #0
    sta ready
    sta ready+1
    jmp duel_sound_silence
@pause:
    lda menu_pressed
    and #1
    beq @done
    lda #3
    sta game_state
    jmp duel_sound_silence
@resume:
    lda menu_pressed
    and #1
    beq @done
    lda #1
    sta game_state
@done:
    rts

; X = sprite slot, A low world X, temp_hi high world X, temp_y world Y.
; temp_offset is the X displacement from the map's physical left edge (24).
place_sprite:
    clc
    adc temp_offset
    sta temp_x
    lda temp_hi
    adc #0
    beq :+
    lda sprite_bits,x
    ora sprite_xhi
    sta sprite_xhi
:
    txa
    asl
    tay
    lda temp_x
    sta $d000,y
    lda temp_y
    clc
    adc #66
    sta $d001,y
    lda sprite_bits,x
    ora sprite_enable
    sta sprite_enable
    rts

publish_sprites:
    lda #0
    sta sprite_enable
    sta sprite_xhi
    lda game_state
    cmp #4
    jeq @finish
    ldx #0
@army:
    stx actor
    lda respawn,x
    jne @army_next
    lda invulnerable,x
    beq :+
    lda game_state
    cmp #1
    bne :+
    lda ticks
    and #2
    jne @army_next
:
    lda #128
    sta sprite_frame
    lda p_progress,x
    beq :+
    lda ticks
    lsr
    lsr
    and #3
    clc
    adc #128
    sta sprite_frame
:
    lda sprite_frame
    sta SCREEN+$3f8,x
    lda army_colors,x
    sta $d027,x
    lda #24
    sta temp_offset
    lda p_xhi,x
    sta temp_hi
    lda p_y,x
    sta temp_y
    lda p_xlo,x
    jsr place_sprite
    ldx actor
    lda sprite_frame
    clc
    adc #4
    sta SCREEN+$3fa,x
    lda #0
    sta $d029,x
    lda p_xlo,x
    pha
    txa
    clc
    adc #2
    tax
    pla
    jsr place_sprite
@army_next:
    ldx actor
    inx
    cpx #2
    jne @army
    ldx #0
@flag:
    stx actor
    lda f_xhi,x
    sta temp_hi
    lda f_y,x
    sta temp_y
    lda #28
    sta temp_offset
    lda f_state,x
    cmp #1
    bne :+
    lda #32
    sta temp_offset
    lda temp_y
    sec
    sbc #6
    sta temp_y
:
    lda ticks
    lsr
    lsr
    lsr
    lsr
    and #1
    clc
    adc #136
    sta SCREEN+$3fc,x
    lda army_colors,x
    sta $d02b,x
    lda f_xlo,x
    pha
    txa
    clc
    adc #4
    tax
    pla
    jsr place_sprite
    ldx actor
    inx
    cpx #2
    bne @flag
    ldx #0
@bullet:
    stx actor
    lda b_active,x
    beq @bullet_next
    lda b_xhi,x
    sta temp_hi
    lda b_y,x
    sec
    sbc #1
    sta temp_y
    lda #23
    sta temp_offset
    lda #138
    sta SCREEN+$3fe,x
    lda army_colors,x
    sta $d02d,x
    lda b_xlo,x
    pha
    txa
    clc
    adc #6
    tax
    pla
    jsr place_sprite
@bullet_next:
    ldx actor
    inx
    cpx #2
    bne @bullet
@finish:
    lda sprite_xhi
    sta $d010
    lda sprite_enable
    sta $d015
    rts

; Main-only map paint. The fixed battlefield leaves 5 rows for useful UI.
render_arena:
    lda #32
    ldx #0
@screen:
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$300,x
    inx
    bne @screen
    lda #15
    ldx #0
@colors:
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    inx
    bne @colors
    lda #0
    sta render_row
    sta render_index
@row:
    lda render_row
    asl
    clc
    adc #2
    tax
    lda row_lo,x
    sta dest
    sta color_dest
    lda row_hi,x
    sta dest+1
    clc
    adc #$58
    sta color_dest+1
    lda #0
    sta render_column
@tile:
    ldx render_index
    lda arena_tiles,x
    sta draw_terrain
    tax
    lda atlas_tile_base,x
    sta draw_glyph
    lda atlas_tile_color,x
    sta draw_color
    lda draw_terrain
    cmp #5
    beq @connections
    cmp #7
    bcc @base_color
@connections:
    lda #0
    sta connections
    lda render_row
    beq @east
    lda render_index
    sec
    sbc #20
    tax
    jsr connects
    bcc @east
    lda #1
    sta connections
@east:
    lda render_column
    cmp #19
    beq @south
    ldx render_index
    inx
    jsr connects
    bcc @south
    lda connections
    ora #2
    sta connections
@south:
    lda render_row
    cmp #9
    beq @west
    lda render_index
    clc
    adc #20
    tax
    jsr connects
    bcc @west
    lda connections
    ora #4
    sta connections
@west:
    lda render_column
    beq @variant
    ldx render_index
    dex
    jsr connects
    bcc @variant
    lda connections
    ora #8
    sta connections
@variant:
    lda connections
    asl
    asl
    clc
    adc draw_glyph
    sta draw_glyph
@base_color:
    lda render_row
    cmp #5
    bne @paint
    lda render_column
    cmp #1
    bne :+
    lda #3
    sta draw_color
:
    lda render_column
    cmp #18
    bne @paint
    lda #7
    sta draw_color
@paint:
    lda render_column
    asl
    tay
    lda draw_glyph
    sta (dest),y
    clc
    adc #1
    iny
    sta (dest),y
    tya
    clc
    adc #39
    tay
    lda draw_glyph
    clc
    adc #2
    sta (dest),y
    iny
    clc
    adc #1
    sta (dest),y
    lda draw_color
    sta (color_dest),y
    dey
    sta (color_dest),y
    tya
    sec
    sbc #39
    tay
    lda draw_color
    sta (color_dest),y
    dey
    sta (color_dest),y
    inc render_index
    inc render_column
    lda render_column
    cmp #20
    jne @tile
    inc render_row
    lda render_row
    cmp #10
    jne @row
    TEXT cyan_text,0,0
    TEXT target_text,0,6
    TEXT title_text,0,14
    TEXT gold_text,0,31
    TEXT target_text,0,37
    TEXT hp_text,1,0
    TEXT hp_text,1,31
    ldx #7
@team_colors:
    lda #3
    sta $d800,x
    sta $d828,x
    lda #7
    sta $d81f,x
    sta $d847,x
    dex
    bpl @team_colors
    rts

connects:
    lda arena_tiles,x
    ldy draw_terrain
    cpy #5
    beq @river
    cmp #6
    rts                            ; roads connect to city/road/bridge
@river:
    cmp #0
    beq @yes
    cmp #5
    beq @yes
    cmp #8
    beq @yes
    clc
    rts
@yes:
    sec
    rts

hud_static:
    lda game_state
    cmp hud_state
    bne @change
    lda input_mode
    cmp hud_mode
    bne @change
    lda computer_player2
    cmp hud_opponent
    jeq @done
@change:
    lda game_state
    sta hud_state
    lda input_mode
    sta hud_mode
    lda computer_player2
    sta hud_opponent
    beq :+
    TEXT cpu_label_text,0,31
    jmp @clear_bottom
:
    TEXT gold_text,0,31
@clear_bottom:
    lda #32
    ldx #119
@clear:
    sta SCREEN+22*40,x
    dex
    bpl @clear
    lda input_mode
    bne @sticks
    lda computer_player2
    bne @cpu_keys
    TEXT keys_text,22,0
    jmp @state
@cpu_keys:
    TEXT cpu_keys_text,22,0
    jmp @state
@sticks:
    lda computer_player2
    bne @cpu_stick
    TEXT sticks_text,22,0
    jmp @state
@cpu_stick:
    TEXT cpu_stick_text,22,0
@state:
    lda game_state
    jeq @title
    cmp #2
    jeq @win
    cmp #3
    jeq @paused
    cmp #4
    jeq @generating
    TEXT objective_text,23,0
    TEXT home_rule_text,24,0
@done:
    rts
@title:
    TEXT menu_text,23,0
    lda computer_player2
    bne @cpu_title
    lda input_mode
    bne @joy_title
    TEXT key_legend_text,24,0
    rts
@cpu_title:
    TEXT cpu_ready_text,24,0
    rts
@joy_title:
    TEXT field_text,24,0
    rts
@win:
    lda winner
    bne @gold_win
    TEXT cyan_win_text,23,0
    jmp @rematch
@gold_win:
    lda computer_player2
    bne @cpu_win
    TEXT gold_win_text,23,0
    jmp @rematch
@cpu_win:
    TEXT cpu_win_text,23,0
@rematch:
    lda computer_player2
    bne @cpu_rematch
    TEXT rematch_text,24,0
    rts
@cpu_rematch:
    TEXT cpu_rematch_text,24,0
    rts
@paused:
    TEXT pause_text,23,0
    TEXT unpause_text,24,0
    rts
@generating:
    TEXT generating_text,23,0
    rts

hud_dynamic:
    lda score
    clc
    adc #'0'
    sta SCREEN+5
    lda score+1
    clc
    adc #'0'
    sta SCREEN+36
    ldx #2
@hearts:
    lda #'-'
    cpx health
    bcs :+
    lda #'*'
:
    sta SCREEN+43,x
    lda #'-'
    cpx health+1
    bcs :+
    lda #'*'
:
    sta SCREEN+74,x
    dex
    bpl @hearts
    lda game_state
    cmp #0
    beq @readies
    cmp #2
    bne @flags
@readies:
    lda ready
    beq @wait_cyan
    TEXT ready_short_text,1,7
    jmp @gold_ready
@wait_cyan:
    TEXT wait_text,1,7
@gold_ready:
    lda computer_player2
    beq :+
    TEXT computer_short_text,1,24
    jmp @clock
:
    lda ready+1
    beq @wait_gold
    TEXT ready_short_text,1,24
    jmp @clock
@wait_gold:
    TEXT wait_text,1,24
    jmp @clock
@flags:
    ldx f_state
    lda flag_text_lo,x
    sta text_ptr
    lda flag_text_hi,x
    sta text_ptr+1
    lda #<(SCREEN+47)
    sta dest
    lda #>(SCREEN+47)
    sta dest+1
    jsr print_text
    ldx f_state+1
    lda flag_text_lo,x
    sta text_ptr
    lda flag_text_hi,x
    sta text_ptr+1
    lda #<(SCREEN+64)
    sta dest
    lda #>(SCREEN+64)
    sta dest+1
    jsr print_text
@clock:
    lda sudden_death
    beq @time
    TEXT sudden_text,1,15
    rts
@time:
    lda #' '
    sta SCREEN+55
    sta SCREEN+56
    sta SCREEN+61
    sta SCREEN+62
    sta SCREEN+63
    lda seconds_left
    ldx #'0'
@minute:
    cmp #60
    bcc @minutes_done
    sec
    sbc #60
    inx
    bne @minute
@minutes_done:
    stx SCREEN+57
    ldx #'0'
@tens:
    cmp #10
    bcc @digits
    sec
    sbc #10
    inx
    bne @tens
@digits:
    stx SCREEN+59
    clc
    adc #'0'
    sta SCREEN+60
    lda #':'
    sta SCREEN+58
    rts

print_text:
    ldy #0
@next:
    lda (text_ptr),y
    beq @done
    sta (dest),y
    iny
    bne @next
@done:
    rts
nmi:
    pha
    lda $dd0d
    pla
    rti

.segment "RODATA"
tick_lo: .byte <$ff5d,<$d5f4,<$d1dc
tick_hi: .byte >$ff5d,>$d5f4,>$d1dc
army_colors: .byte 3,7
sprite_bits: .byte 1,2,4,8,16,32,64,128
row_lo:
.repeat 25,I
    .byte <(SCREEN+I*40)
.endrepeat
row_hi:
.repeat 25,I
    .byte >(SCREEN+I*40)
.endrepeat
cyan_text: .byte "CYAN",0
gold_text: .byte "GOLD",0
title_text: .byte "BANNERFALL",0
target_text: .byte "/3",0
hp_text: .byte "HP:",0
keys_text: .byte "CYAN:WASD FIRE:X  GOLD:UBNM FIRE:.",0
sticks_text: .byte "CYAN:JOY PORT 2    GOLD:JOY PORT 1",0
menu_text: .byte "K:KEYS J:JOYS C:CPU H:HUMAN F1:NEW",0
key_legend_text: .byte "BOTH FIRE:START GOLD U/B/N/M=UP/L/D/R",0
field_text: .byte "BOTH FIRE:START. STEAL FLAG, GET HOME.",0
cpu_label_text: .byte "CPU ",0
cpu_keys_text: .byte "CYAN:WASD FIRE:X    GOLD:COMPUTER",0
cpu_stick_text: .byte "CYAN:JOY PORT 2     GOLD:COMPUTER",0
cpu_ready_text: .byte "P1 FIRE:START. STEAL FLAG, GET HOME.",0
objective_text: .byte "STEAL ENEMY FLAG. BRING IT HOME.",0
home_rule_text: .byte "OWN FLAG HOME TO SCORE. RUN/STOP:PAUSE",0
cyan_win_text: .byte "CYAN WINS THE FIELD!",0
gold_win_text: .byte "GOLD WINS THE FIELD!",0
rematch_text: .byte "BOTH FIRE:REMATCH C/H:CPU/HUMAN F1:NEW",0
cpu_rematch_text: .byte "P1 FIRE:REMATCH C/H:CPU/HUMAN F1:NEW",0
cpu_win_text: .byte "COMPUTER WINS THE FIELD!",0
pause_text: .byte "BATTLE PAUSED",0
unpause_text: .byte "RETURN OR RUN/STOP TO CONTINUE",0
generating_text: .byte "FORMING A NEW BATTLEFIELD...",0
ready_short_text: .byte "READY",0
computer_short_text: .byte "CPU  ",0
wait_text: .byte "WAIT ",0
home_text: .byte "HOME ",0
taken_text: .byte "TAKEN",0
drop_text: .byte "DROP ",0
sudden_text: .byte "OVERTIME",0
flag_text_lo: .byte <home_text,<taken_text,<drop_text
flag_text_hi: .byte >home_text,>taken_text,>drop_text
.include "assets.inc"
.assert __BSS_SIZE__ <= $600, lderror, "State overlaps BASIC stub"
.assert __CODE_RUN__+__CODE_SIZE__ <= $4000, lderror, "Code budget exceeded"
.assert __RODATA_RUN__+__RODATA_SIZE__ <= $6000, lderror, "Tables overlap font"
.segment "CHARSET_SOURCE"
duel_charset: .incbin "build/duel/charset.bin"
.segment "SPRITE_SOURCE"
duel_sprites: .incbin "build/duel/sprites.bin"

.segment "BSS"
duel_seed: .res 2
video_standard: .res 1
highest_raster: .res 1
ticks: .res 1
video_frames: .res 1
tick_step: .res 2
tick_fraction: .res 2
new_arena_request: .res 1
ready: .res 2
menu_raw: .res 1
menu_previous: .res 1
menu_pressed: .res 1
controls_previous: .res 2
fire_pressed: .res 2
hud_state: .res 1
hud_mode: .res 1
hud_opponent: .res 1
computer_player2: .res 1
hud_clock: .res 1
actor: .res 1
sprite_enable: .res 1
sprite_xhi: .res 1
sprite_frame: .res 1
temp_x: .res 1
temp_hi: .res 1
temp_y: .res 1
temp_offset: .res 1
render_row: .res 1
render_column: .res 1
render_index: .res 1
draw_terrain: .res 1
draw_glyph: .res 1
draw_color: .res 1
connections: .res 1

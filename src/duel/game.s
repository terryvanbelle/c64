; Bannerfall: two armies, one flag each, a shared procedural battlefield.
;
; Public entry points:
;   game_init  resets actors/flags/score/clock, then selects title state 0.
;   game_start resets the same arena for a live state-1 match.
;   game_tick  runs exactly once per 50 Hz simulation tick, only in state 1.
; The engine owns state 3 (pause), draws public state, and chooses when to start.
; All live logic is single-threaded in the IRQ; init/start must use the same
; ownership. This module touches no VIC/CIA/SID registers, uses no zero page and
; makes only bounded loops. A/X/Y/flags are clobbered by all public entry points.
;
; Position is the top-left of a 16x16 army cell; bullets use centre coordinates.
; Army movement traverses one adjacent map tile at a time, so a fast road move
; cannot jump a wall. Bullets inspect every pixel of their six-pixel advance.
; Both armies move/fire before either bullet is evaluated. A bullet survives its
; owner's defeat, allowing both players to land a shot on the same tick.

.setcpu "6502"
.macpack longbranch
.import arena_tiles, dual_controls, duel_sound_event
.export game_init, game_start, game_tick
.export game_state, winner, score, health, respawn, invulnerable, stun, facing
.export p_xlo, p_xhi, p_y, p_tilex, p_tiley, p_targetx, p_targety, p_progress
.export b_active, b_xlo, b_xhi, b_y, b_dir, b_life, b_cooldown
.export f_state, f_carrier, f_xlo, f_xhi, f_y, f_returnlo, f_returnhi
.export seconds_left, sudden_death

T_WATER = 0
T_MOUNTAIN = 4
LIVE = 1

.segment "BSS"
g_state_begin:
game_state:    .res 1                 ; 0 title, 1 live, 2 result, 3 pause
winner:        .res 1                 ; player index, meaningful in state 2
score:         .res 2
health:        .res 2
respawn:       .res 2
invulnerable:  .res 2
stun:          .res 2
facing:        .res 2                 ; 0 up, 1 down, 2 left, 3 right
p_xlo:         .res 2
p_xhi:         .res 2
p_y:           .res 2
p_tilex:       .res 2                 ; last completed tile
p_tiley:       .res 2
p_targetx:     .res 2
p_targety:     .res 2
p_progress:    .res 2                 ; pixels still to traverse
b_active:      .res 2
b_xlo:         .res 2
b_xhi:         .res 2
b_y:           .res 2
b_dir:         .res 2
b_life:        .res 2
b_cooldown:    .res 2
f_state:       .res 2                 ; indexed by OWNER: home/carried/dropped
f_carrier:     .res 2                 ; carrying player, or $FF
f_xlo:         .res 2
f_xhi:         .res 2
f_y:           .res 2
f_returnlo:    .res 2                 ; indexed low/high arrays, 150 ticks
f_returnhi:    .res 2
seconds_left:  .res 2                 ; ordinary little-endian WORD
sudden_death:  .res 1

g_second:      .res 1
g_previous:    .res 2
g_move_dir:    .res 2
g_speed:       .res 2
g_fresh_drop:  .res 2                 ; don't age a flag on its creation tick
g_player:      .res 1                 ; authoritative loop index across SFX
g_victim:      .res 1
g_flag:        .res 1
g_steps:       .res 1
g_move_steps:  .res 1
g_controls:    .res 1
g_new:         .res 1
g_tile_x:      .res 1
g_axlo:        .res 1                 ; collision query scratch
g_axhi:        .res 1
g_ay:          .res 1
g_bxlo:        .res 1
g_bxhi:        .res 1
g_by:          .res 1
g_radius:      .res 1
g_dxlo:        .res 1
g_dxhi:        .res 1
g_state_end:

.segment "CODE"
game_init:
    jsr g_reset
    lda #0
    sta game_state
    rts

game_start:
    jsr g_reset
    lda #LIVE
    sta game_state
    rts

g_reset:
    lda #0
    ldx #g_state_end-g_state_begin-1
@clear:
    sta g_state_begin,x
    dex
    bpl @clear
    lda #150
    sta seconds_left
    lda #50
    sta g_second
    lda #3
    sta facing
    lda #2
    sta facing+1
    ldx #0
    jsr g_spawn
    ldx #1
    jsr g_spawn
    lda #0
    sta g_flag
    jsr g_flag_home
    inc g_flag
    jsr g_flag_home
    rts

; X is the player. Preserve X, no external calls.
g_spawn:
    lda g_base_xlo,x
    sta p_xlo,x
    lda g_base_xhi,x
    sta p_xhi,x
    lda #80
    sta p_y,x
    lda g_base_tilex,x
    sta p_tilex,x
    sta p_targetx,x
    lda #5
    sta p_tiley,x
    sta p_targety,x
    lda #0
    sta p_progress,x
    sta stun,x
    lda #3
    sta health,x
    lda #35
    sta invulnerable,x
    rts

game_tick:
    lda game_state
    cmp #LIVE
    beq :+
    rts
:
    lda #0
    sta g_fresh_drop
    sta g_fresh_drop+1
    sta g_player
@players:
    jsr g_army_tick
    inc g_player
    lda g_player
    cmp #2
    bne @players
    lda #0
    sta g_player
@bullets:
    jsr g_bullet_tick
    inc g_player
    lda g_player
    cmp #2
    bne @bullets
    lda #0
    sta g_flag
@flags:
    jsr g_flag_tick
    lda game_state
    cmp #LIVE
    beq :+
    rts
:
    inc g_flag
    lda g_flag
    cmp #2
    bne @flags
    ; Resolve both flag returns/pickups before either capture. Otherwise a
    ; player whose own flag has the lower owner index gets a one-tick advantage
    ; when its dropped flag returns on the final tick of a match.
    lda #0
    sta g_player
@captures:
    jsr g_capture_tick
    lda game_state
    cmp #LIVE
    beq :+
    rts
:
    inc g_player
    lda g_player
    cmp #2
    bne @captures
    jmp g_clock_tick

g_army_tick:
    ldx g_player
    lda b_cooldown,x
    beq :+
    dec b_cooldown,x
:
    lda respawn,x
    beq @alive
    dec respawn,x
    bne @done
    jsr g_spawn
@done:
    rts
@alive:
    lda invulnerable,x
    beq :+
    dec invulnerable,x
:
    lda stun,x
    beq @input
    dec stun,x
    rts
@input:
    lda dual_controls,x
    sta g_controls
    lda g_previous,x
    eor #$FF
    and g_controls
    and #15
    sta g_new
    lda g_controls
    sta g_previous,x
    ; New directions take precedence; held directions retain their last facing
    ; while it remains held, instead of a permanent up-first diagonal bias.
    lda g_new
    bne @choose_facing
    ldy facing,x
    lda g_direction_bits,y
    and g_controls
    bne @facing_ready
    lda g_controls
    and #15
    beq @facing_ready
@choose_facing:
    ldy #0
@direction:
    lsr
    bcs @selected
    iny
    cpy #4
    bne @direction
@selected:
    tya
    sta facing,x
@facing_ready:
    lda p_progress,x
    beq @next_tile
    jsr g_advance_army
    ldx g_player
    lda p_progress,x
    bne @fire
@next_tile:
    lda g_controls
    and #15
    beq @fire
    jsr g_choose_target
@fire:
    ldx g_player
    lda g_controls
    and #16
    beq @return
    lda b_active,x
    ora b_cooldown,x
    bne @return
    jmp g_fire
@return:
    rts

; Try the held facing against map bounds and terrain. No diagonal movement.
g_choose_target:
    ldx g_player
    lda p_tilex,x
    sta p_targetx,x
    lda p_tiley,x
    sta p_targety,x
    lda facing,x
    sta g_move_dir,x
    beq @up
    cmp #1
    beq @down
    cmp #2
    beq @left
@right:
    lda p_tilex,x
    cmp #19
    beq @blocked
    inc p_targetx,x
    jmp @terrain
@left:
    lda p_tilex,x
    beq @blocked
    dec p_targetx,x
    jmp @terrain
@up:
    lda p_tiley,x
    beq @blocked
    dec p_targety,x
    jmp @terrain
@down:
    lda p_tiley,x
    cmp #9
    beq @blocked
    inc p_targety,x
@terrain:
    ldy p_targety,x
    lda p_targetx,x
    tax
    jsr g_tile_at
    cmp #T_WATER
    beq @blocked
    cmp #T_MOUNTAIN
    beq @blocked
    tay
    lda g_terrain_speed,y
    ldx g_player
    sta g_speed,x
    lda #16
    sta p_progress,x
@blocked:
    rts

g_advance_army:
    ldx g_player
    lda g_speed,x
    pha
    ; A flag carrier loses one pixel per tick, with a minimum speed of one.
    ldy g_player
    tya
    eor #1
    tay
    lda f_state,y
    cmp #1
    bne @not_carrier_pop
    pla
    cmp #1
    beq @not_carrier
    sec
    sbc #1
    jmp @not_carrier
@not_carrier_pop:
    pla
@not_carrier:
    cmp p_progress,x
    bcc :+
    lda p_progress,x
:
    sta g_move_steps
    sta g_steps
@pixel:
    lda g_move_dir,x
    beq @up
    cmp #1
    beq @down
    cmp #2
    beq @left
@right:
    inc p_xlo,x
    bne @moved
    inc p_xhi,x
    jmp @moved
@left:
    lda p_xlo,x
    bne :+
    dec p_xhi,x
:
    dec p_xlo,x
    jmp @moved
@up:
    dec p_y,x
    jmp @moved
@down:
    inc p_y,x
@moved:
    dec g_steps
    bne @pixel
    lda p_progress,x
    sec
    sbc g_move_steps
    sta p_progress,x
    bne @done
    lda p_targetx,x
    sta p_tilex,x
    lda p_targety,x
    sta p_tiley,x
@done:
    rts

; X/Y tile coordinate, A terrain. X/Y clobbered.
g_tile_at:
    stx g_tile_x
    lda g_row_offsets,y
    clc
    adc g_tile_x
    tay
    lda arena_tiles,y
    rts

g_fire:
    ldx g_player
    lda facing,x
    sta b_dir,x
    lda p_xlo,x
    clc
    adc #8
    sta b_xlo,x
    lda p_xhi,x
    adc #0
    sta b_xhi,x
    lda p_y,x
    clc
    adc #8
    sta b_y,x
    lda b_dir,x
    beq @up
    cmp #1
    beq @down
    cmp #2
    beq @left
@right:
    lda b_xlo,x
    clc
    adc #12
    sta b_xlo,x
    lda b_xhi,x
    adc #0
    sta b_xhi,x
    jmp @ready
@left:
    lda b_xlo,x
    sec
    sbc #12
    sta b_xlo,x
    lda b_xhi,x
    sbc #0
    sta b_xhi,x
    jmp @ready
@up:
    lda b_y,x
    sec
    sbc #12
    sta b_y,x
    jmp @ready
@down:
    lda b_y,x
    clc
    adc #12
    sta b_y,x
@ready:
    lda #12
    sta b_cooldown,x
    lda #32
    sta b_life,x
    jsr g_bullet_bounds
    bcc @outside
    ldx g_player
    lda #1
    sta b_active,x
    jmp duel_sound_event
@outside:
    rts

g_bullet_tick:
    ldx g_player
    lda b_active,x
    jne @active
    rts
@active:
    lda b_life,x
    jeq g_bullet_remove
    ; Armies have completed their moves before this phase, so cache the target
    ; centre once for all six ray steps instead of rebuilding it every pixel.
    lda g_player
    eor #1
    tax
    stx g_victim
    jsr g_player_center_b
    lda #7
    sta g_radius
    lda #6
    sta g_steps
@pixel:
    ldx g_player
    lda b_dir,x
    beq @up
    cmp #1
    beq @down
    cmp #2
    beq @left
@right:
    inc b_xlo,x
    bne @moved
    inc b_xhi,x
    jmp @moved
@left:
    lda b_xlo,x
    bne :+
    dec b_xhi,x
:
    dec b_xlo,x
    jmp @moved
@up:
    dec b_y,x
    jmp @moved
@down:
    inc b_y,x
@moved:
    jsr g_bullet_bounds
    jcc g_bullet_remove
    ; Test the current tile after EVERY pixel step, including cell boundaries.
    ldx g_player
    lda b_y,x
    lsr
    lsr
    lsr
    lsr
    tay
    lda b_xhi,x
    asl
    asl
    asl
    asl
    sta g_tile_x
    lda b_xlo,x
    lsr
    lsr
    lsr
    lsr
    ora g_tile_x
    tax
    jsr g_tile_at
    cmp #T_MOUNTAIN
    jeq g_bullet_remove

    ldx g_victim
    lda respawn,x
    bne @no_hit
    ldx g_player
    lda b_xlo,x
    sta g_axlo
    lda b_xhi,x
    sta g_axhi
    lda b_y,x
    sta g_ay
    jsr g_close
    bcc @no_hit
    jsr g_bullet_remove
    ldx g_victim
    lda invulnerable,x
    bne @done
    jmp g_hit
@no_hit:
    dec g_steps
    jne @pixel
    ldx g_player
    dec b_life,x
    beq g_bullet_remove
@done:
    rts

; C set iff the current bullet is within x0..319, y0..159.
g_bullet_bounds:
    ldx g_player
    lda b_y,x
    cmp #160
    bcs @bad
    lda b_xhi,x
    beq @good
    cmp #1
    bne @bad
    lda b_xlo,x
    cmp #64
    bcs @bad
@good:
    sec
    rts
@bad:
    clc
    rts

g_bullet_remove:
    ldx g_player
    lda #0
    sta b_active,x
    rts

g_hit:
    ldx g_victim
    lda #8
    sta stun,x
    lda #20
    sta invulnerable,x
    dec health,x
    bne @drop
    lda #40
    sta respawn,x
    lda #0
    sta p_progress,x
@drop:
    txa
    eor #1
    tay
    lda f_state,y
    cmp #1
    bne @sound
    lda #2
    sta f_state,y
    lda #1
    sta g_fresh_drop,y
    lda #$FF
    sta f_carrier,y
    lda p_xlo,x
    sta f_xlo,y
    lda p_xhi,x
    sta f_xhi,y
    lda p_y,x
    sta f_y,y
    lda #150
    sta f_returnlo,y
    lda #0
    sta f_returnhi,y
@sound:
    lda #2
    jmp duel_sound_event

g_flag_tick:
    ldx g_flag
    lda f_state,x
    cmp #1
    jeq g_carried_flag
    cmp #2
    bne @pickup
    lda g_fresh_drop,x
    bne @check_owner
    lda f_returnlo,x
    bne :+
    dec f_returnhi,x
:
    dec f_returnlo,x
    lda f_returnlo,x
    ora f_returnhi,x
    beq @return_home

    ; Returning your own dropped flag has priority over an opposing pickup.
@check_owner:
    lda respawn,x
    bne @pickup
    jsr g_flag_close_player
    bcc @pickup
@return_home:
    jsr g_flag_home
    ldx g_flag
    lda #6
    jsr duel_sound_event
    rts
@pickup:
    lda g_flag
    eor #1
    tax
    lda respawn,x
    ora invulnerable,x
    bne @done
    jsr g_flag_close_player
    bcc @done
    ldx g_flag
    lda #1
    sta f_state,x
    txa
    eor #1
    sta f_carrier,x
    tay
    lda p_xlo,y
    sta f_xlo,x
    lda p_xhi,y
    sta f_xhi,x
    lda p_y,y
    sta f_y,x
    tya
    tax
    lda #3
    jsr duel_sound_event
@done:
    rts

g_carried_flag:
    ldx g_flag
    ldy f_carrier,x
    lda p_xlo,y
    sta f_xlo,x
    lda p_xhi,y
    sta f_xhi,x
    lda p_y,y
    sta f_y,x
    rts

g_capture_tick:
    ldx g_player
    lda f_state,x                    ; player's OWN flag must be home
    bne @done
    txa
    eor #1
    tay
    sty g_flag
    lda f_state,y                    ; enemy flag must be carried by player
    cmp #1
    bne @done
    lda f_carrier,y
    cmp g_player
    bne @done
    lda p_xlo,x
    sta g_axlo
    lda p_xhi,x
    sta g_axhi
    lda p_y,x
    sta g_ay
    lda g_base_xlo,x
    sta g_bxlo
    lda g_base_xhi,x
    sta g_bxhi
    lda #80
    sta g_by
    lda #4
    sta g_radius
    jsr g_close
    bcc @done
    jsr g_flag_home
    ldx g_player
    inc score,x
    lda score,x
    cmp #3
    bcs @win
    lda sudden_death
    bne @win
    lda #4
    jmp duel_sound_event
@win:
    jmp g_win
@done:
    rts

g_flag_home:
    ldx g_flag
    lda #0
    sta f_state,x
    sta f_returnlo,x
    sta f_returnhi,x
    lda #$FF
    sta f_carrier,x
    lda g_base_xlo,x
    sta f_xlo,x
    lda g_base_xhi,x
    sta f_xhi,x
    lda #80
    sta f_y,x
    rts

; X is an army; compare its top-left with the indexed flag top-left, radius 8.
g_flag_close_player:
    lda p_xlo,x
    sta g_axlo
    lda p_xhi,x
    sta g_axhi
    lda p_y,x
    sta g_ay
    ldx g_flag
    lda f_xlo,x
    sta g_bxlo
    lda f_xhi,x
    sta g_bxhi
    lda f_y,x
    sta g_by
    lda #8
    sta g_radius
    jmp g_close

; X is an army; fill B with its centre. No X/Y changes.
g_player_center_b:
    lda p_xlo,x
    clc
    adc #8
    sta g_bxlo
    lda p_xhi,x
    adc #0
    sta g_bxhi
    lda p_y,x
    clc
    adc #8
    sta g_by
    rts

; C set iff |A.x-B.x| <= radius AND |A.y-B.y| <= radius. Full 16-bit x distance
; matters at the x255/256 boundary; y uses unsigned subtraction up to 159px.
g_close:
    lda g_axlo
    sec
    sbc g_bxlo
    sta g_dxlo
    lda g_axhi
    sbc g_bxhi
    sta g_dxhi
    bpl @positive_x
    lda g_dxlo
    eor #$FF
    clc
    adc #1
    sta g_dxlo
    lda g_dxhi
    eor #$FF
    adc #0
    sta g_dxhi
@positive_x:
    lda g_dxhi
    bne @far
    lda g_radius
    cmp g_dxlo
    bcc @far
    lda g_ay
    sec
    sbc g_by
    bcs @positive_y
    lda g_by
    sec
    sbc g_ay
@positive_y:
    sta g_dxlo
    lda g_radius
    cmp g_dxlo
    rts
@far:
    clc
    rts

g_clock_tick:
    lda sudden_death
    bne @done
    dec g_second
    bne @done
    lda #50
    sta g_second
    lda seconds_left
    bne :+
    dec seconds_left+1
:
    dec seconds_left
    lda seconds_left
    ora seconds_left+1
    bne @done
    lda score
    cmp score+1
    beq @sudden
    ldx #0
    bcs g_win
    inx
    jmp g_win
@sudden:
    lda #1
    sta sudden_death
@done:
    rts

; X wins. Final sound/phase publish happens after all earlier actor work.
g_win:
    stx winner
    lda #2
    sta game_state
    lda #5
    jmp duel_sound_event

.segment "RODATA"
g_base_xlo:       .byte 16,32
g_base_xhi:       .byte 0,1
g_base_tilex:     .byte 1,18
g_row_offsets:    .byte 0,20,40,60,80,100,120,140,160,180
g_direction_bits:.byte 1,2,4,8
g_terrain_speed:  .byte 0,3,2,2,0,1,3,4,4

.assert g_state_end-g_state_begin < 128, error, "Reset loop exceeds signed byte range"

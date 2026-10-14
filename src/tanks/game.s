; IRONVEIL rules for an unexpanded NMOS 6502 C64.
; All live state is owned by the game IRQ. No zero page or hardware writes.
; game_init selects title (0); game_start selects play (1); game_tick is 50 Hz.
; Both tanks propose before either commits. Body collision rejects both new
; positions symmetrically; an existing spawn overlap is allowed to separate.
; Positions are top-left, with private 8.8 residues. Hull/turret headings are
; independent world headings 0=N, 1=NE, 2=E, ... 7=NW. Shells retain their owner
; even after its knockout, allowing simultaneous hits and fair tied victories.
.setcpu "6502"
.macpack longbranch
.import arena_tiles, tank_controls, duel_sound_event
.export game_init, game_start, game_tick, game_state, winner, score, health
.export respawn, invulnerable, stun, hull, turret, reveal
.export tank_xlo, tank_xhi, tank_y, tank_xfrac, tank_yfrac
.export shell_active, shell_xlo, shell_xhi, shell_y, shell_dir, shell_life
.export shell_cooldown, shell_xfrac, shell_yfrac, seconds_left, sudden_death

.segment "BSS"
g_state_begin:
game_state:     .res 1
winner:         .res 1
score:          .res 2
health:         .res 2
respawn:        .res 2
invulnerable:   .res 2
stun:           .res 2
hull:           .res 2
turret:         .res 2
reveal:         .res 2
tank_xlo:       .res 2
tank_xhi:       .res 2
tank_y:         .res 2
tank_xfrac:     .res 2
tank_yfrac:     .res 2
shell_active:   .res 2
shell_xlo:      .res 2
shell_xhi:      .res 2
shell_y:        .res 2
shell_dir:      .res 2
shell_life:     .res 2
shell_cooldown: .res 2
shell_xfrac:    .res 2
shell_yfrac:    .res 2
seconds_left:   .res 2
sudden_death:   .res 1
g_second:       .res 1
g_hull_wait:    .res 2
g_turret_wait:  .res 2
g_next_xlo:     .res 2
g_next_xhi:     .res 2
g_next_y:       .res 2
g_next_xfrac:   .res 2
g_next_yfrac:   .res 2
g_player:       .res 1
g_victim:       .res 1
g_controls:     .res 1
g_direction:    .res 1
g_speedlo:      .res 1
g_speedhi:      .res 1
g_probe:        .res 1
g_steps:        .res 1
g_tilecolumn:   .res 1
g_query_xlo:    .res 1
g_query_xhi:    .res 1
g_query_y:      .res 1
g_yhi:          .res 1
g_axlo:         .res 1
g_axhi:         .res 1
g_ay:           .res 1
g_bxlo:         .res 1
g_bxhi:         .res 1
g_by:           .res 1
g_radius:       .res 1
g_dxlo:         .res 1
g_dxhi:         .res 1
g_damage:       .res 1
g_state_end:

.segment "CODE"
game_init:
    jsr g_reset
    lda #0
    sta game_state
    rts
game_start:
    jsr g_reset
    lda #1
    sta game_state
    rts
g_reset:
    lda #0
    ldx #0
@clear:
    sta g_state_begin,x
    inx
    cpx #g_state_end-g_state_begin
    bne @clear
    lda #180
    sta seconds_left
    lda #50
    sta g_second
    ldx #0
    jsr g_spawn
    ldx #1
    jmp g_spawn

g_spawn:
    lda g_spawn_xlo,x
    sta tank_xlo,x
    lda g_spawn_xhi,x
    sta tank_xhi,x
    lda #128
    sta tank_y,x
    lda g_spawn_heading,x
    sta hull,x
    sta turret,x
    lda #0
    sta tank_xfrac,x
    sta tank_yfrac,x
    sta stun,x
    sta reveal,x
    sta g_hull_wait,x
    sta g_turret_wait,x
    lda #4
    sta health,x
    lda #60
    sta invulnerable,x
    rts

game_tick:
    lda game_state
    cmp #1
    beq :+
    rts
:
    lda #0
    sta g_player
@tanks:
    jsr g_tank_tick
    inc g_player
    lda g_player
    cmp #2
    bne @tanks
    jsr g_commit_tanks
    lda #0
    sta g_player
@shells:
    jsr g_shell_tick
    inc g_player
    lda g_player
    cmp #2
    bne @shells
    jsr g_check_scores
    lda game_state
    cmp #1
    bne @done
    jmp g_clock_tick
@done:
    rts

g_tank_tick:
    ldx g_player
    lda shell_cooldown,x
    beq :+
    dec shell_cooldown,x
:
    lda reveal,x
    beq :+
    dec reveal,x
:
    lda respawn,x
    beq @alive
    dec respawn,x
    bne @copy_only
    jsr g_spawn
@copy_only:
    jmp g_copy_proposal
@alive:
    lda invulnerable,x
    beq :+
    dec invulnerable,x
:
    lda g_hull_wait,x
    beq :+
    dec g_hull_wait,x
:
    lda g_turret_wait,x
    beq :+
    dec g_turret_wait,x
:
    jsr g_copy_proposal
    lda stun,x
    beq @input
    dec stun,x
    rts
@input:
    lda tank_controls,x
    sta g_controls
    lda g_hull_wait,x
    bne @turret
    lda g_controls
    and #12
    beq @turret
    cmp #12
    beq @turret
    cmp #4
    bne @hull_right
    lda hull,x
    clc
    adc #7
    jmp @hull_store
@hull_right:
    lda hull,x
    clc
    adc #1
@hull_store:
    and #7
    sta hull,x
    lda #10
    sta g_hull_wait,x
@turret:
    lda g_turret_wait,x
    bne @throttle
    lda g_controls
    and #96
    beq @throttle
    cmp #96
    beq @throttle
    cmp #32
    bne @turret_right
    lda turret,x
    clc
    adc #7
    jmp @turret_store
@turret_right:
    lda turret,x
    clc
    adc #1
@turret_store:
    and #7
    sta turret,x
    lda #8
    sta g_turret_wait,x
@throttle:
    lda g_controls
    and #3
    beq @fire
    cmp #3
    beq @fire
    lda hull,x
    sta g_direction
    lda g_controls
    and #2
    beq :+
    lda g_direction
    clc
    adc #4
    and #7
    sta g_direction
:
    jsr g_propose_move
@fire:
    ldx g_player
    lda g_controls
    and #16
    beq @done
    lda shell_active,x
    ora shell_cooldown,x
    bne @done
    jmp g_fire
@done:
    rts

g_copy_proposal:
    lda tank_xlo,x
    sta g_next_xlo,x
    lda tank_xhi,x
    sta g_next_xhi,x
    lda tank_y,x
    sta g_next_y,x
    lda tank_xfrac,x
    sta g_next_xfrac,x
    lda tank_yfrac,x
    sta g_next_yfrac,x
    rts

g_propose_move:
    ; Terrain under the body's centre controls speed; body corners control
    ; passability. Maximum displacement is one pixel, so walls cannot be skipped.
    lda tank_xlo,x
    clc
    adc #8
    sta g_query_xlo
    lda tank_xhi,x
    adc #0
    sta g_query_xhi
    lda tank_y,x
    clc
    adc #8
    sta g_query_y
    jsr g_terrain_point
    tay
    lda g_direction
    and #1
    bne @diagonal
    lda g_speed_low,y
    sta g_speedlo
    lda g_speed_high,y
    sta g_speedhi
    jmp @velocity
@diagonal:
    lda g_speed_diagonal,y
    sta g_speedlo
    lda #0
    sta g_speedhi
@velocity:
    ldx g_player
    ldy g_direction
    lda g_xsign,y
    beq @y_axis
    bmi @x_minus
    lda tank_xfrac,x
    clc
    adc g_speedlo
    sta g_next_xfrac,x
    lda tank_xlo,x
    adc g_speedhi
    sta g_next_xlo,x
    lda tank_xhi,x
    adc #0
    sta g_next_xhi,x
    jmp @y_axis
@x_minus:
    lda tank_xfrac,x
    sec
    sbc g_speedlo
    sta g_next_xfrac,x
    lda tank_xlo,x
    sbc g_speedhi
    sta g_next_xlo,x
    lda tank_xhi,x
    sbc #0
    sta g_next_xhi,x
@y_axis:
    lda g_ysign,y
    beq @bounds
    bmi @y_minus
    lda tank_yfrac,x
    clc
    adc g_speedlo
    sta g_next_yfrac,x
    lda tank_y,x
    adc g_speedhi
    sta g_next_y,x
    jmp @bounds
@y_minus:
    lda tank_yfrac,x
    sec
    sbc g_speedlo
    sta g_next_yfrac,x
    lda tank_y,x
    sbc g_speedhi
    sta g_next_y,x
@bounds:
    lda g_next_y,x
    cmp #241
    jcs @blocked
    lda g_next_xhi,x
    beq @probes
    cmp #1
    jne @blocked
    lda g_next_xlo,x
    cmp #241
    jcs @blocked
@probes:
    lda #0
    sta g_probe
@probe:
    ldx g_player
    ldy g_probe
    lda g_next_xlo,x
    clc
    adc g_probe_x,y
    sta g_query_xlo
    lda g_next_xhi,x
    adc #0
    sta g_query_xhi
    lda g_next_y,x
    clc
    adc g_probe_y,y
    sta g_query_y
    jsr g_terrain_point
    beq @blocked
    cmp #4
    beq @blocked
    inc g_probe
    lda g_probe
    cmp #4
    bne @probe
    rts
@blocked:
    ldx g_player
    jmp g_copy_proposal

g_commit_tanks:
    lda respawn
    ora respawn+1
    bne @commit
    lda #11
    sta g_radius
    lda tank_xlo
    sta g_axlo
    lda tank_xhi
    sta g_axhi
    lda tank_y
    sta g_ay
    lda tank_xlo+1
    sta g_bxlo
    lda tank_xhi+1
    sta g_bxhi
    lda tank_y+1
    sta g_by
    jsr g_close
    bcs @commit                 ; respawn overlap may separate without a trap
    lda g_next_xlo
    sta g_axlo
    lda g_next_xhi
    sta g_axhi
    lda g_next_y
    sta g_ay
    lda g_next_xlo+1
    sta g_bxlo
    lda g_next_xhi+1
    sta g_bxhi
    lda g_next_y+1
    sta g_by
    jsr g_close
    bcs @done                   ; reject BOTH proposals, including residues
@commit:
    ldx #1
@tank:
    lda g_next_xlo,x
    sta tank_xlo,x
    lda g_next_xhi,x
    sta tank_xhi,x
    lda g_next_y,x
    sta tank_y,x
    lda g_next_xfrac,x
    sta tank_xfrac,x
    lda g_next_yfrac,x
    sta tank_yfrac,x
    dex
    bpl @tank
@done:
    rts

; Query centre/corner at full x and byte y. The world is two 256-byte pages.
g_terrain_point:
    lda g_query_y
    lsr
    lsr
    lsr
    lsr
    tay
    lda g_query_xhi
    asl
    asl
    asl
    asl
    sta g_tilecolumn
    lda g_query_xlo
    lsr
    lsr
    lsr
    lsr
    ora g_tilecolumn
    tax
g_tile_at:
    stx g_tilecolumn
    tya
    and #7
    asl
    asl
    asl
    asl
    asl
    clc
    adc g_tilecolumn
    tax
    cpy #8
    bcs @high
    lda arena_tiles,x
    rts
@high:
    lda arena_tiles+$100,x
    rts

g_fire:
    ldx g_player
    lda #25
    sta shell_cooldown,x
    lda #50
    sta reveal,x
    lda #64
    sta shell_life,x
    lda turret,x
    sta shell_dir,x
    tay
    lda tank_xlo,x
    clc
    adc #8
    sta shell_xlo,x
    lda tank_xhi,x
    adc #0
    sta shell_xhi,x
    lda shell_xlo,x
    clc
    adc g_muzzle_xlo,y
    sta shell_xlo,x
    lda shell_xhi,x
    adc g_muzzle_xhi,y
    sta shell_xhi,x
    lda tank_y,x
    clc
    adc #8
    clc
    adc g_muzzle_ylo,y
    sta shell_y,x
    lda #0
    adc g_muzzle_yhi,y
    sta g_yhi
    bne @outside
    lda #0
    sta shell_xfrac,x
    sta shell_yfrac,x
    jsr g_shell_bounds
    bcc @outside
    ldx g_player
    lda #1
    sta shell_active,x
    jmp duel_sound_event
@outside:
    ldx g_player
    lda #1
    jmp duel_sound_event

g_shell_tick:
    ldx g_player
    lda shell_active,x
    bne @active
    rts
@active:
    lda shell_life,x
    jeq g_shell_remove
    txa
    eor #1
    tax
    stx g_victim
    lda tank_xlo,x
    clc
    adc #8
    sta g_bxlo
    lda tank_xhi,x
    adc #0
    sta g_bxhi
    lda tank_y,x
    clc
    adc #8
    sta g_by
    lda #6
    sta g_radius
    lda #3
    sta g_steps
@pixel:
    ldx g_player
    ldy shell_dir,x
    sty g_direction
    tya
    and #1
    bne @diagonal
    lda #0
    sta g_speedlo
    lda #1
    sta g_speedhi
    bne @x_axis
@diagonal:
    lda #181
    sta g_speedlo
    lda #0
    sta g_speedhi
@x_axis:
    lda g_xsign,y
    beq @y_axis
    bmi @x_minus
    lda shell_xfrac,x
    clc
    adc g_speedlo
    sta shell_xfrac,x
    lda shell_xlo,x
    adc g_speedhi
    sta shell_xlo,x
    lda shell_xhi,x
    adc #0
    sta shell_xhi,x
    jmp @y_axis
@x_minus:
    lda shell_xfrac,x
    sec
    sbc g_speedlo
    sta shell_xfrac,x
    lda shell_xlo,x
    sbc g_speedhi
    sta shell_xlo,x
    lda shell_xhi,x
    sbc #0
    sta shell_xhi,x
@y_axis:
    lda g_ysign,y
    beq @bounds
    bmi @y_minus
    lda shell_yfrac,x
    clc
    adc g_speedlo
    sta shell_yfrac,x
    lda shell_y,x
    adc g_speedhi
    sta shell_y,x
    jcs g_shell_remove
    jmp @bounds
@y_minus:
    lda shell_yfrac,x
    sec
    sbc g_speedlo
    sta shell_yfrac,x
    lda shell_y,x
    sbc g_speedhi
    sta shell_y,x
    jcc g_shell_remove
@bounds:
    jsr g_shell_bounds
    jcc g_shell_remove
    ldx g_player
    lda shell_xlo,x
    sta g_query_xlo
    lda shell_xhi,x
    sta g_query_xhi
    lda shell_y,x
    sta g_query_y
    jsr g_terrain_point
    cmp #4
    jeq g_shell_remove
    ldx g_victim
    lda respawn,x
    bne @no_hit
    ldx g_player
    lda shell_xlo,x
    sta g_axlo
    lda shell_xhi,x
    sta g_axhi
    lda shell_y,x
    sta g_ay
    jsr g_close
    bcc @no_hit
    jsr g_shell_remove
    ldx g_victim
    lda invulnerable,x
    bne @done
    jmp g_hit
@no_hit:
    dec g_steps
    jne @pixel
    ldx g_player
    dec shell_life,x
    beq g_shell_remove
@done:
    rts

g_shell_bounds:
    ldx g_player
    lda shell_xhi,x
    cmp #2
    bcs @bad
    sec
    rts
@bad:
    clc
    rts
g_shell_remove:
    ldx g_player
    lda #0
    sta shell_active,x
    rts

g_hit:
    ; A projectile arriving along the victim's forward heading strikes its rear.
    ldy g_player
    lda shell_dir,y
    ldx g_victim
    sec
    sbc hull,x
    and #7
    cmp #2
    bcc @rear
    cmp #7
    beq @rear
    lda #1
    bne @damage
@rear:
    lda #2
@damage:
    sta g_damage
    lda #8
    sta stun,x
    lda #16
    sta invulnerable,x
    lda health,x
    sec
    sbc g_damage
    bcc @knockout
    beq @knockout
    sta health,x
    lda #2
    jmp duel_sound_event
@knockout:
    lda #0
    sta health,x
    lda #75
    sta respawn,x
    ldx g_player
    inc score,x
    lda #4
    jmp duel_sound_event

; C set iff |A.x-B.x| <= radius AND |A.y-B.y| <= radius, across x255/256.
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
    eor #$ff
    clc
    adc #1
    sta g_dxlo
    lda g_dxhi
    eor #$ff
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

g_check_scores:
    lda sudden_death
    bne @leader
    lda score
    cmp #3
    bcs @leader
    lda score+1
    cmp #3
    bcc @done
@leader:
    lda score
    cmp score+1
    beq @tie
    ldx #0
    bcs g_win
    inx
    jmp g_win
@tie:
    lda #1
    sta sudden_death
@done:
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
    beq @tie
    ldx #0
    bcs g_win
    inx
    jmp g_win
@tie:
    lda #1
    sta sudden_death
@done:
    rts
g_win:
    stx winner
    lda #2
    sta game_state
    lda #5
    jmp duel_sound_event

.segment "RODATA"
g_spawn_xlo:    .byte 48,192
g_spawn_xhi:    .byte 0,1
g_spawn_heading:.byte 2,6
g_xsign:       .byte 0,1,1,1,0,$ff,$ff,$ff
g_ysign:       .byte $ff,$ff,0,1,1,1,0,$ff
g_speed_low:   .byte 0,128,64,96,0,64,0,0
g_speed_high:  .byte 0,0,0,0,0,0,1,1
g_speed_diagonal:.byte 0,91,45,68,0,45,181,181
g_probe_x:     .byte 2,13,2,13
g_probe_y:     .byte 2,2,13,13
g_muzzle_xlo:  .byte 0,6,8,6,0,250,248,250
g_muzzle_xhi:  .byte 0,0,0,0,0,$ff,$ff,$ff
g_muzzle_ylo:  .byte 248,250,0,6,8,6,0,250
g_muzzle_yhi:  .byte $ff,$ff,0,0,0,0,0,$ff
.assert g_state_end-g_state_begin < 256, error, "Tank reset exceeds byte index"

; Bannerfall's optional computer opponent. It owns only player 2's normalized
; controls: no actor, flag, damage, timer, terrain or movement-rule changes.
;
; ai_init resets small scalar state; it never clears the large work arrays in
; a start IRQ. ai_tick clears eight visit stamps per tick, then builds a reverse
; flood field with at most four expanded cells per tick. A generation stamp
; makes ordinary replanning constant-time. Generation wrap uses the same staged
; clear. Incomplete plans use legal greedy approaches while the field spreads.
; Terrain ties favor roads/bridges; water and mountains remain impassable.
;
; Tactical priorities: recover the computer's flag from its human carrier or a
; drop, return an enemy flag, otherwise raid the enemy flag. Moving interception
; goals refresh no sooner than 24 ticks and only after the field reaches the
; computer (or its queue empties). Cardinal line-of-sight shots use the same
; fire input, cooldown, single bullet, damage and shield rules as human play.
;
; Main game IRQ only; A/X/Y/flags clobbered; no zero page or hardware access.

.setcpu "6502"
.macpack longbranch
.import computer_player2, arena_tiles, duel_seed, ticks, dual_controls
.import p_xlo, p_xhi, p_y, p_tilex, p_tiley, p_progress
.import respawn, invulnerable, facing, b_active, b_cooldown
.import f_state, f_xlo, f_xhi, f_y
.export ai_init, ai_tick
.export ai_goal, ai_objective, ai_generation, ai_queue_count, ai_queue_head
.export ai_clear_remaining, ai_plan_valid, ai_distance, ai_visit, ai_queue

.segment "BSS"
a_scalar_begin:
ai_goal:            .res 1
ai_objective:       .res 1             ; 0 raid, 1 return, 2 recover, 3 intercept
ai_generation:      .res 1
ai_queue_count:     .res 1
ai_queue_head:      .res 1
a_queue_tail:       .res 1
ai_clear_remaining:.res 1
a_clear_index:      .res 1
ai_plan_valid:      .res 1
a_replan_tick:      .res 1
a_wanted_goal:      .res 1
a_new_mode:         .res 1
a_goal_x:           .res 1
a_goal_y:           .res 1
a_pxlo:             .res 1
a_pxhi:             .res 1
a_py:               .res 1
a_bot_index:        .res 1
a_current:          .res 1
a_next_distance:    .res 1
a_budget:           .res 1
a_field_usable:     .res 1
a_best_control:     .res 1
a_best_distance:    .res 1
a_best_penalty:     .res 1
a_candidate_control:.res 1
a_candidate_distance:.res 1
a_candidate_penalty:.res 1
a_dxlo:             .res 1
a_dxhi:             .res 1
a_dy:               .res 1
a_xdirection:       .res 1
a_ydirection:       .res 1
a_shot_direction:   .res 1
a_human_col:        .res 1
a_bot_col:          .res 1
a_human_row:        .res 1
a_bot_row:          .res 1
a_ray:              .res 1
a_ray_end:          .res 1
a_ray_step:         .res 1
a_scalar_end:
ai_distance:        .res 200
ai_visit:           .res 200
ai_queue:           .res 200

.segment "CODE"
ai_init:
    lda #0
    ldx #a_scalar_end-a_scalar_begin-1
@clear:
    sta a_scalar_begin,x
    dex
    bpl @clear
    lda #200
    sta ai_clear_remaining
    lda #$FF
    sta ai_goal
    sta ai_objective
    rts

ai_tick:
    lda computer_player2
    bne :+
    rts
:
    lda #0
    sta dual_controls+1
    jsr a_select_goal
    ldy p_tiley+1
    lda a_rows,y
    clc
    adc p_tilex+1
    sta a_bot_index
    lda ai_clear_remaining
    beq @active_plan
    lda #8
    sta a_budget
    ldx a_clear_index
    lda #0
@clear_visits:
    sta ai_visit,x
    inx
    dec ai_clear_remaining
    beq @clear_done
    dec a_budget
    bne @clear_visits
    stx a_clear_index
    jmp @steer
@clear_done:
    stx a_clear_index
    jsr a_begin_plan
    jmp @expand
@active_plan:
    lda ai_plan_valid
    beq @new_plan
    lda a_new_mode
    cmp ai_objective
    bne @new_plan
    lda a_wanted_goal
    cmp ai_goal
    beq @expand
    lda a_new_mode
    cmp #3
    bne @new_plan
    lda ticks
    sec
    sbc a_replan_tick
    cmp #24
    bcc @expand
    lda ai_queue_count
    beq @new_plan
    ldx a_bot_index
    lda ai_visit,x
    cmp ai_generation
    bne @expand
@new_plan:
    jsr a_begin_plan
@expand:
    lda ai_plan_valid
    beq @steer
    jsr a_expand_four
@steer:
    lda respawn+1
    bne @done
    lda p_progress+1
    bne @aim
    jsr a_steer
    lda a_best_control
    sta dual_controls+1
@aim:
    jsr a_aim
@done:
    rts

a_select_goal:
    lda f_state+1
    cmp #1
    beq @intercept
    cmp #2
    beq @recover
    lda f_state
    cmp #1
    beq @home
    lda #0
    sta a_new_mode
    lda f_xlo
    sta a_pxlo
    lda f_xhi
    sta a_pxhi
    lda f_y
    jmp @pixels
@intercept:
    lda #3
    sta a_new_mode
    lda p_xlo
    sta a_pxlo
    lda p_xhi
    sta a_pxhi
    lda p_y
    jmp @pixels
@recover:
    lda #2
    sta a_new_mode
    lda f_xlo+1
    sta a_pxlo
    lda f_xhi+1
    sta a_pxhi
    lda f_y+1
@pixels:
    ; Round a mid-crossing dropped flag to its nearest army grid origin, not
    ; the lower origin: either endpoint must be within the pickup's 8px radius.
    clc
    adc #8
    lsr
    lsr
    lsr
    lsr
    sta a_goal_y
    tay
    lda a_pxlo
    clc
    adc #8
    sta a_pxlo
    lda a_pxhi
    adc #0
    asl
    asl
    asl
    asl
    sta a_goal_x
    lda a_pxlo
    lsr
    lsr
    lsr
    lsr
    ora a_goal_x
    sta a_goal_x
    clc
    adc a_rows,y
    sta a_wanted_goal
    rts
@home:
    lda #1
    sta a_new_mode
    lda #18
    sta a_goal_x
    lda #5
    sta a_goal_y
    lda #118
    sta a_wanted_goal
    rts

a_begin_plan:
    lda a_new_mode
    sta ai_objective
    lda a_wanted_goal
    sta ai_goal
    lda ticks
    sta a_replan_tick
    inc ai_generation
    bne @generation_ready
    lda #0
    sta ai_plan_valid
    sta a_clear_index
    sta ai_queue_count
    lda #200
    sta ai_clear_remaining
    rts
@generation_ready:
    ldx ai_goal
    lda ai_generation
    sta ai_visit,x
    lda #0
    sta ai_distance,x
    sta ai_queue_head
    txa
    sta ai_queue
    lda #1
    sta ai_plan_valid
    sta a_queue_tail
    sta ai_queue_count
    rts

a_expand_four:
    lda #4
    sta a_budget
@next:
    lda ai_queue_count
    beq @done
    ldy ai_queue_head
    lda ai_queue,y
    inc ai_queue_head
    dec ai_queue_count
    sta a_current
    tax
    lda ai_distance,x
    clc
    adc #1
    sta a_next_distance
    lda a_current
    cmp #20
    bcc @down
    sec
    sbc #20
    tax
    jsr a_enqueue
@down:
    lda a_current
    cmp #180
    bcs @left
    clc
    adc #20
    tax
    jsr a_enqueue
@left:
    ldx a_current
    lda a_columns,x
    beq @right
    dex
    jsr a_enqueue
@right:
    ldx a_current
    lda a_columns,x
    cmp #19
    beq @finished
    inx
    jsr a_enqueue
@finished:
    dec a_budget
    bne @next
@done:
    rts

; X candidate cell. Every cell is enqueued at most once in a generation, so
; the linear 200-byte queue cannot overflow even when the whole map is open.
a_enqueue:
    lda ai_visit,x
    cmp ai_generation
    beq @done
    lda arena_tiles,x
    beq @done
    cmp #4
    beq @done
    lda ai_generation
    sta ai_visit,x
    lda a_next_distance
    sta ai_distance,x
    ldy a_queue_tail
    txa
    sta ai_queue,y
    inc a_queue_tail
    inc ai_queue_count
@done:
    rts

a_steer:
    lda #0
    sta a_best_control
    sta a_field_usable
    lda #$FF
    sta a_best_distance
    sta a_best_penalty
    lda ai_plan_valid
    beq @greedy
    ldx a_bot_index
    lda ai_visit,x
    cmp ai_generation
    bne @greedy
    lda #1
    sta a_field_usable
    lda a_bot_index
    cmp #20
    bcc @field_down
    sec
    sbc #20
    tax
    lda #1
    jsr a_candidate
@field_down:
    lda a_bot_index
    cmp #180
    bcs @field_left
    clc
    adc #20
    tax
    lda #2
    jsr a_candidate
@field_left:
    lda p_tilex+1
    beq @field_right
    ldx a_bot_index
    dex
    lda #4
    jsr a_candidate
@field_right:
    lda p_tilex+1
    cmp #19
    beq @done
    ldx a_bot_index
    inx
    lda #8
    jmp a_candidate
@greedy:
    ; Prefer the seed-selected axis when legal approaches have the same cost.
    lda duel_seed
    and #1
    beq @horizontal_first
    jsr a_greedy_y
    jmp a_greedy_x
@horizontal_first:
    jsr a_greedy_x
    jmp a_greedy_y
@done:
    rts

a_greedy_x:
    lda p_tilex+1
    cmp a_goal_x
    beq @done
    ldx a_bot_index
    bcs @left
    inx
    lda #8
    jmp a_candidate
@left:
    dex
    lda #4
    jmp a_candidate
@done:
    rts

a_greedy_y:
    lda p_tiley+1
    cmp a_goal_y
    beq @done
    lda a_bot_index
    bcs @up
    clc
    adc #20
    tax
    lda #2
    jmp a_candidate
@up:
    sec
    sbc #20
    tax
    lda #1
    jmp a_candidate
@done:
    rts

; X neighbor, A normalized direction. Choose a decreasing valid field distance,
; with terrain as the tie-break. Greedy mode considers only goal-facing cells.
a_candidate:
    sta a_candidate_control
    lda arena_tiles,x
    beq @done
    cmp #4
    beq @done
    tay
    lda a_penalty,y
    sta a_candidate_penalty
    lda #0
    sta a_candidate_distance
    lda a_field_usable
    beq @rank
    lda ai_visit,x
    cmp ai_generation
    bne @done
    lda ai_distance,x
    sta a_candidate_distance
    ldy a_bot_index
    cmp ai_distance,y
    bcs @done
@rank:
    lda a_candidate_distance
    cmp a_best_distance
    bcc @choose
    bne @done
    lda a_candidate_penalty
    cmp a_best_penalty
    bcs @done
@choose:
    lda a_candidate_distance
    sta a_best_distance
    lda a_candidate_penalty
    sta a_best_penalty
    lda a_candidate_control
    sta a_best_control
@done:
    rts

a_aim:
    lda respawn
    ora invulnerable
    ora b_active+1
    ora b_cooldown+1
    jne @done
    lda p_xlo
    sec
    sbc p_xlo+1
    sta a_dxlo
    lda p_xhi
    sbc p_xhi+1
    sta a_dxhi
    bmi @human_left
    lda #8
    sta a_xdirection
    jmp @y_distance
@human_left:
    lda #4
    sta a_xdirection
    lda a_dxlo
    eor #$FF
    clc
    adc #1
    sta a_dxlo
    lda a_dxhi
    eor #$FF
    adc #0
    sta a_dxhi
@y_distance:
    lda p_y
    sec
    sbc p_y+1
    bcc @human_up
    sta a_dy
    lda #2
    sta a_ydirection
    jmp @horizontal
@human_up:
    lda p_y+1
    sec
    sbc p_y
    sta a_dy
    lda #1
    sta a_ydirection
@horizontal:
    lda a_dxhi
    jne @done
    lda a_dy
    cmp #8
    bcs @vertical
    lda a_dxlo
    cmp #6
    bcc @vertical
    cmp #181
    jcs @done
    lda a_xdirection
    sta a_shot_direction
    jsr a_centres
    ldy a_bot_row
    lda a_rows,y
    clc
    adc a_human_col
    sta a_ray_end
    lda a_xdirection
    cmp #4
    beq @ray_left
    lda #1
    bne @ray_ready
@ray_left:
    lda #$FF
    bne @ray_ready
@vertical:
    lda a_dxlo
    cmp #8
    jcs @done
    lda a_dy
    cmp #6
    jcc @done
    lda a_ydirection
    sta a_shot_direction
    jsr a_centres
    ldy a_human_row
    lda a_rows,y
    clc
    adc a_bot_col
    sta a_ray_end
    lda a_ydirection
    cmp #1
    beq @ray_up
    lda #20
    bne @ray_ready
@ray_up:
    lda #256-20
@ray_ready:
    sta a_ray_step
    ldy a_bot_row
    lda a_rows,y
    clc
    adc a_bot_col
    sta a_ray
@ray:
    lda a_ray
    cmp a_ray_end
    beq @fire
    clc
    adc a_ray_step
    sta a_ray
    tax
    lda arena_tiles,x
    cmp #4
    beq @done
    jmp @ray
@fire:
    ; A fresh aim during a tile crossing cannot change that stable movement
    ; target. Avoid forcing a new movement toward the shot on its final pixels.
    lda p_progress+1
    beq @set_fire
    cmp #5
    bcs @set_fire
    ldy facing+1
    lda a_direction_bits,y
    cmp a_shot_direction
    bne @done
    lda #16
    sta dual_controls+1
    rts
@set_fire:
    lda a_shot_direction
    ora #16
    sta dual_controls+1
@done:
    rts

; Actual centres can be in a neighboring cell during movement. Build the ray
; along the shooter's row/column, ending at the target's column/row respectively,
; so near-aligned actors across a cell boundary never cause an unbounded ray.
a_centres:
    ldx #1
@army:
    lda p_xlo,x
    clc
    adc #8
    sta a_pxlo
    lda p_xhi,x
    adc #0
    asl
    asl
    asl
    asl
    sta a_pxhi
    lda a_pxlo
    lsr
    lsr
    lsr
    lsr
    ora a_pxhi
    sta a_human_col,x                 ; x0 human, x1 stored immediately after
    lda p_y,x
    clc
    adc #8
    lsr
    lsr
    lsr
    lsr
    sta a_human_row,x
    dex
    bpl @army
    rts

.segment "RODATA"
a_rows: .byte 0,20,40,60,80,100,120,140,160,180
a_columns:
    .repeat 10
        .byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    .endrepeat
a_penalty: .byte 255,2,4,4,255,8,1,0,0
a_direction_bits: .byte 1,2,4,8

.assert a_scalar_end-a_scalar_begin < 128, error, "AI scalar reset exceeds byte loop"

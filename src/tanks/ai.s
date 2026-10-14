; IRONVEIL computer tank. Uses only viewer-1 sense contacts for its opponent;
; never reads concealed tank-0 coordinates. Writes dual_controls+1 only.
; One expensive block per tick: goal/clear work, fresh steering, exact firing
; alignment, or one reverse-flood node. HUD ticks defer the last three blocks.
; Distances and queue counters are WORDs; the 512-cell work arrays live in WORK.
; ai_init clears scalars only. Eight visit stamps per tick initialize/recover
; generation wrap without a long clear in an IRQ. Normal hull/turret controls
; obey the exact same movement, armor, shell, cooldown and stun rules as humans.
.setcpu "6502"
.macpack longbranch
.import computer_player2, ai_difficulty, world_seed, ticks, hud_clock, dual_controls
.import world_tiles, tank_xlo, tank_xhi, tank_y, hull, turret
.import respawn, stun, shell_active, shell_cooldown
.import enemy_visible, contact_known, contact_xlo, contact_xhi, contact_y
.import contact_hull, bearing
.import sense_ping_countdown
.export ai_init, ai_tick, ai_level, ai_goal, ai_objective, ai_generation
.export ai_queue_count, ai_queue_head, ai_clear_remaining, ai_plan_valid
.export ai_distlo, ai_disthi, ai_visit, ai_queuelo, ai_queuehi
.export ai_aim_wait, ai_pending_aim, ai_shot_spacing, ai_nav_heading
.export ai_work_class
.export a_waypoint_x, a_waypoint_y

.segment "WORK"
ai_distlo: .res 512
ai_disthi: .res 512
ai_visit: .res 512
ai_queuelo: .res 512
ai_queuehi: .res 512

.segment "BSS"
a_start:
ai_level: .res 1
ai_goal: .res 2
ai_objective: .res 1             ; 0 patrol,1 hunt,2 direct,3 side,4 rear,5 space
ai_generation: .res 1
ai_queue_count: .res 2
ai_queue_head: .res 2
a_tail: .res 2
ai_clear_remaining: .res 2
a_clear_index: .res 2
ai_plan_valid: .res 1
a_last_plan: .res 1
a_steer_wait: .res 1
ai_shot_spacing: .res 1
ai_aim_wait: .res 1
ai_pending_aim: .res 1
ai_nav_heading: .res 1
a_wanted: .res 2
a_goal_x: .res 1
a_goal_y: .res 1
a_new_mode: .res 1
a_raw_x: .res 1
a_raw_y: .res 1
a_cached_x: .res 1
a_cached_y: .res 1
a_cache_valid: .res 1
a_goal_work: .res 1
ai_work_class: .res 1            ; 0 cheap/aim,1 fresh steering,2 flood slice
a_aim_retry_wait: .res 1        ; ensure a poor firing angle cannot starve paths
a_probe: .res 1
a_probe_pending: .res 1
a_bot: .res 2
a_bot_x: .res 1
a_bot_y: .res 1
a_node: .res 2
a_current: .res 2
a_next_dist: .res 2
a_current_dist: .res 2
a_best_dist: .res 2
a_best_node: .res 2
a_waypoint_x: .res 2
a_waypoint_y: .res 1
a_cand_dist: .res 2
a_budget: .res 1
a_field: .res 1
a_best_heading: .res 1
a_best_penalty: .res 1
a_cand_heading: .res 1
a_cand_penalty: .res 1
a_tmp: .res 1
a_target_heading: .res 1
a_block_valid: .res 1
a_block_base: .res 2
a_block_wide: .res 1
a_block_tall: .res 1
a_flank_valid: .res 1
a_flank_x: .res 1
a_flank_y: .res 1
a_flank_hull: .res 1
a_flank_level: .res 1
a_flank_heading: .res 1
a_flank_initial: .res 1
a_flank_attempt: .res 1
a_ray_x: .res 1
a_ray_y: .res 1
a_dx: .res 2
a_dy: .res 1
a_end:

.segment "CODE"
ai_init:
    lda #0
    ldx #a_end-a_start-1
@clear:
    sta a_start,x
    dex
    bpl @clear
    lda #2
    sta ai_clear_remaining+1
    lda #$FF
    sta ai_goal
    sta ai_goal+1
    sta ai_objective
    sta ai_nav_heading
    sta ai_pending_aim
    rts

ai_tick:
    lda computer_player2
    bne :+
    rts
:
    lda #0
    sta dual_controls+1
    ldx ai_difficulty
    cpx #3
    bcc :+
    ldx #2
:
    stx ai_level
    lda a_steer_wait
    beq :+
    dec a_steer_wait
:
    lda ai_shot_spacing
    beq :+
    dec ai_shot_spacing
:
    lda ai_aim_wait
    beq :+
    dec ai_aim_wait
:
    lda a_aim_retry_wait
    beq :+
    dec a_aim_retry_wait
:
    lda #0
    sta a_goal_work
    sta ai_work_class
    lda hud_clock
    cmp #4
    jeq @drive
    lda sense_ping_countdown
    cmp #1
    bne :+
    lda #1
    sta a_goal_work            ; coarse-ping work reserves this interrupt
    jmp @drive
:
    jsr a_bot_cell
    jsr a_select_goal
    lda a_probe_pending
    jne @drive
    lda ai_clear_remaining
    ora ai_clear_remaining+1
    beq @plan
    lda #8
    sta a_budget
    lda #1
    sta a_goal_work            ; a clear slice owns this tick's expensive work
@clear_cell:
    ldx a_clear_index
    lda #0
    ldy a_clear_index+1
    bne :+
    sta ai_visit,x
    jmp @cleared
:
    sta ai_visit+256,x
@cleared:
    inc a_clear_index
    bne :+
    inc a_clear_index+1
:
    lda ai_clear_remaining
    bne :+
    dec ai_clear_remaining+1
:
    dec ai_clear_remaining
    lda ai_clear_remaining
    ora ai_clear_remaining+1
    beq @clear_done
    dec a_budget
    bne @clear_cell
    jmp @drive
@clear_done:
    ; Finishing staged initialization already consumed its bounded clear work.
    ; Start the field, but leave expansion and a fresh steering choice to the
    ; next tick; a committed waypoint still gets its normal arrival gate.
    lda #1
    sta a_goal_work
    jsr a_begin_plan
    jmp @expand
@plan:
    lda ai_plan_valid
    beq @new
    lda a_new_mode
    cmp ai_objective
    bne @new
    lda a_wanted
    cmp ai_goal
    bne @changed
    lda a_wanted+1
    cmp ai_goal+1
    beq @expand
@changed:
    lda ticks
    sec
    sbc a_last_plan
    ldx ai_level
    cmp a_refresh,x
    bcc @expand
    lda ai_queue_count
    ora ai_queue_count+1
    beq @new
    lda a_bot
    sta a_node
    lda a_bot+1
    sta a_node+1
    jsr a_read_visit
    cmp ai_generation
    bne @expand
@new:
    jsr a_begin_plan
@expand:
    ; Select one expensive operation below. Goal/ray/probe and clear work
    ; already reserve their ticks; flood, fresh steering and exact fire
    ; alignment must never accumulate in the same interrupt.
@drive:
    lda respawn+1
    beq :+
    ; Respawn teleports the tank to its base. A waypoint committed before the
    ; knockout is no longer adjacent and must not become a long terrain-blind
    ; throttle command from that new position.
    lda #$FF
    sta ai_nav_heading
    lda #0
    sta a_steer_wait
    jmp a_reset_aim
:
    lda a_goal_work
    bne @heading
    lda hud_clock
    cmp #4
    beq @heading
    lda a_steer_wait
    bne @reserve_aim
    lda ai_nav_heading
    cmp #$FF
    beq @fresh_steer
    jsr a_waypoint_reached
    bcc @reserve_aim
@fresh_steer:
    lda #1
    sta ai_work_class
    jsr a_steer
    ldx ai_level
    lda a_steer_interval,x
    sta a_steer_wait
    lda ai_nav_heading
    cmp #$FF
    bne @heading
    ; An unfinished field can offer no legal waypoint yet. Three ticks leave
    ; room for both an exact-aim retry and flood: two-tick steering and aim
    ; retries can otherwise alternate forever without expanding the field.
    lda a_steer_wait
    cmp #3
    bcs @heading
    lda #3
    sta a_steer_wait
    jmp @heading
@reserve_aim:
    ; These cheap guards identify a possible exact firing calculation. The
    ; calculation itself remains in a_aim and uses sensed contacts only.
    lda contact_known+1
    beq @flood
    lda enemy_visible+1
    beq @flood
    lda shell_active+1
    ora shell_cooldown+1
    ora stun+1
    bne @flood
    lda bearing+1
    and #7
    cmp turret+1
    bne @flood
    lda a_aim_retry_wait
    bne @flood
    ; An octant bearing can be aligned while the exact shell ray misses.
    ; Reserve the next tick for planning rather than retrying that ray forever.
    lda #2
    sta a_aim_retry_wait
    jmp @heading
@flood:
    lda ai_plan_valid
    beq @heading
    lda #2
    sta ai_work_class
    jsr a_expand
@heading:
    jsr a_drive_heading
    jmp a_aim

; Army-1 actual centre identifies the local path cell.
a_bot_cell:
    lda tank_xlo+1
    clc
    adc #8
    sta a_tmp
    lda tank_xhi+1
    adc #0
    asl
    asl
    asl
    asl
    sta a_bot_x
    lda a_tmp
    lsr
    lsr
    lsr
    lsr
    ora a_bot_x
    sta a_bot_x
    lda tank_y+1
    clc
    adc #8
    lsr
    lsr
    lsr
    lsr
    sta a_bot_y
    tay
    lda a_rowslo,y
    clc
    adc a_bot_x
    sta a_bot
    lda a_rowshi,y
    sta a_bot+1
    rts

a_select_goal:
    lda #0
    sta a_block_valid
    lda contact_known+1
    bne @contact
    lda #0
    sta a_new_mode
    lda ticks
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    tax
    lda a_patrol_x,x
    sta a_raw_x
    lda a_patrol_y,x
    sta a_raw_y
    jmp @sanitize
@contact:
    lda contact_xlo+1
    clc
    adc #8
    sta a_tmp
    lda contact_xhi+1
    adc #0
    asl
    asl
    asl
    asl
    sta a_raw_x
    lda a_tmp
    lsr
    lsr
    lsr
    lsr
    ora a_raw_x
    sta a_raw_x
    lda contact_y+1
    clc
    adc #8
    lsr
    lsr
    lsr
    lsr
    sta a_raw_y
    lda enemy_visible+1
    bne @visible
    lda #1
    sta a_new_mode
    ; Search adjacent cells within the coarse sector after approaching its
    ; centre. Offsets vary on a public clock, not concealed enemy coordinates.
    lda a_bot_x
    sec
    sbc a_raw_x
    clc
    adc #2
    cmp #5
    jcs @sanitize
    lda a_bot_y
    sec
    sbc a_raw_y
    clc
    adc #2
    cmp #5
    jcs @sanitize
    lda ticks
    lsr
    lsr
    lsr
    lsr
    lsr
    and #3
    tax
    lda a_raw_x
    clc
    adc a_search_x,x
    sta a_raw_x
    lda a_raw_y
    clc
    adc a_search_y,x
    sta a_raw_y
    jmp @clamp
@visible:
    jsr a_contact_too_close
    bcc @normal_approach
    ; Existing overlap is allowed to separate by normal tank physics. Give a
    ; respawned neighbor room rather than parking on its point and firing past
    ; it with a muzzle already beyond the opponent's body.
    lda #5
    sta a_new_mode
    lda #2
    sta a_budget
    lda hull+1
    clc
    adc #4
    and #7
    tax
    jmp @offset
@normal_approach:
    lda #2
    sta a_new_mode
    lda ai_level
    beq @sanitize
    ; The observed tank occupies one to four cells according to its offset.
    ; This is a private planning obstacle, never a world or actor mutation.
    jsr a_observed_block
    lda contact_hull+1
    cmp #8
    bcs @sanitize
    jsr a_choose_flank
@offset:
    lda a_raw_x
    clc
    adc a_vec_x,x
    sta a_raw_x
    lda a_raw_y
    clc
    adc a_vec_y,x
    sta a_raw_y
    dec a_budget
    bne @offset
@clamp:
    lda a_raw_x
    cmp #32
    bcc :+
    lda #31
    bit a_raw_x
    bpl :+
    lda #0
:
    sta a_raw_x
    lda a_raw_y
    cmp #16
    bcc :+
    lda #15
    bit a_raw_y
    bpl :+
    lda #0
:
    sta a_raw_y
@sanitize:
    ; A coarse contact may land in a solid region. Probe four candidates per
    ; tick while retaining the last completed goal/waypoint, rather than
    ; combining all seventeen candidates with game/sensor/HUD work in one IRQ.
    lda a_probe_pending
    beq @check_cache
    lda a_raw_x
    cmp a_cached_x
    bne @probe_start
    lda a_raw_y
    cmp a_cached_y
    bne @probe_start
    jmp @probe_resume
@check_cache:
    lda a_cache_valid
    beq @probe_start
    lda a_raw_x
    cmp a_cached_x
    bne @probe_start
    lda a_raw_y
    cmp a_cached_y
    jeq @done
@probe_start:
    lda #1
    sta a_probe_pending
    lda a_raw_x
    sta a_cached_x
    lda a_raw_y
    sta a_cached_y
    lda #0
    sta a_probe
@probe_resume:
    ; A new flank-ray test already used this tick's expensive work allowance.
    ; Start/resume sanitation on a later tick instead of combining both costs.
    lda a_goal_work
    bne @done
    lda #1
    sta a_goal_work
    lda #4
    sta a_budget
@probe:
    ldx a_probe
    lda a_raw_x
    clc
    adc a_probe_x,x
    cmp #32
    bcs @next_probe
    sta a_goal_x
    lda a_raw_y
    clc
    adc a_probe_y,x
    cmp #16
    bcs @next_probe
    sta a_goal_y
    ; Sanitation must not move a visible flank onto an impossible gun angle.
    ; Hidden/coarse search and close-contact backoff have no firing constraint.
    lda a_new_mode
    cmp #3
    bcc @candidate
    cmp #5
    bcs @candidate
    jsr a_firing_lane
    bcs @next_probe
@candidate:
    jsr a_goal_node
    jsr a_read_tile
    beq @next_probe
    cmp #4
    beq @next_probe
    jsr a_blocked
    bcc @found
@next_probe:
    inc a_probe
    lda a_probe
    cmp #17
    beq @fallback_goal
    dec a_budget
    bne @probe
    rts
@fallback_goal:
    ; Guaranteed bridge centre is a safe fallback if a coarse sector's tested
    ; neighborhood is completely solid; never use hidden exact coordinates.
    lda #15
    sta a_goal_x
    lda #8
    sta a_goal_y
    jsr a_goal_node
@found:
    lda #0
    sta a_probe_pending
    lda a_node
    sta a_wanted
    lda a_node+1
    sta a_wanted+1
    lda #1
    sta a_cache_valid
@done:
    rts

a_goal_node:
    ldy a_goal_y
    lda a_rowslo,y
    clc
    adc a_goal_x
    sta a_node
    lda a_rowshi,y
    sta a_node+1
    rts

; C clear iff a proposed visible flank is cardinal/diagonal from the sensed
; contact tile. Called only for a current visible approach; a_choose_flank has
; refreshed a_flank_x/y from that sensed contact. Bounded constant work within
; the existing sanitation slice, with no concealed opponent coordinates read.
a_firing_lane:
    lda a_goal_x
    sec
    sbc a_flank_x
    bcs :+
    eor #$ff
    clc
    adc #1
:
    sta a_tmp
    lda a_goal_y
    sec
    sbc a_flank_y
    bcs :+
    eor #$ff
    clc
    adc #1
:
    beq @lane
    cmp a_tmp
    beq @lane
    lda a_tmp
    beq @lane
    sec
    rts
@lane:
    clc
    rts

a_begin_plan:
    lda a_new_mode
    sta ai_objective
    lda a_wanted
    sta ai_goal
    sta a_node
    lda a_wanted+1
    sta ai_goal+1
    sta a_node+1
    lda ticks
    sta a_last_plan
    inc ai_generation
    bne @ready
    lda #0
    sta ai_plan_valid
    sta a_clear_index
    sta a_clear_index+1
    sta ai_queue_count
    sta ai_queue_count+1
    sta ai_clear_remaining
    lda #2
    sta ai_clear_remaining+1
    rts
@ready:
    lda #0
    sta a_next_dist
    sta a_next_dist+1
    jsr a_write_visit_dist
    lda ai_goal
    sta ai_queuelo
    lda ai_goal+1
    sta ai_queuehi
    lda #0
    sta ai_queue_head
    sta ai_queue_head+1
    sta a_tail+1
    sta ai_queue_count+1
    lda #1
    sta a_tail
    sta ai_queue_count
    sta ai_plan_valid
    rts

a_expand:
    ; Every fifth tick also publishes the dynamic HUD. Reserve that tick for
    ; the renderer; difficulty varies tactics and reactions, not IRQ work.
    lda hud_clock
    cmp #4
    bne :+
    rts
:
    lda #1
    sta a_budget
@node:
    lda ai_queue_count
    ora ai_queue_count+1
    jeq @done
    ldx ai_queue_head
    lda ai_queue_head+1
    bne @second
    lda ai_queuelo,x
    sta a_current
    lda ai_queuehi,x
    jmp @got
@second:
    lda ai_queuelo+256,x
    sta a_current
    lda ai_queuehi+256,x
@got:
    sta a_current+1
    sta a_node+1
    lda a_current
    sta a_node
    inc ai_queue_head
    bne :+
    inc ai_queue_head+1
:
    lda ai_queue_count
    bne :+
    dec ai_queue_count+1
:
    dec ai_queue_count
    jsr a_read_dist
    clc
    adc #1
    sta a_next_dist
    tya
    adc #0
    sta a_next_dist+1
    lda a_current+1
    bne @up
    lda a_current
    cmp #32
    bcc @down
@up:
    lda a_current
    sec
    sbc #32
    sta a_node
    lda a_current+1
    sbc #0
    sta a_node+1
    jsr a_enqueue
@down:
    lda a_current+1
    beq @down_ok
    lda a_current
    cmp #224
    bcs @left
@down_ok:
    lda a_current
    clc
    adc #32
    sta a_node
    lda a_current+1
    adc #0
    sta a_node+1
    jsr a_enqueue
@left:
    lda a_current
    and #31
    beq @right
    lda a_current
    sec
    sbc #1
    sta a_node
    lda a_current+1
    sta a_node+1
    jsr a_enqueue
@right:
    lda a_current
    and #31
    cmp #31
    beq @finished
    lda a_current
    clc
    adc #1
    sta a_node
    lda a_current+1
    sta a_node+1
    jsr a_enqueue
@finished:
    dec a_budget
    jne @node
@done:
    rts

a_enqueue:
    jsr a_read_visit
    cmp ai_generation
    beq @done
    jsr a_read_tile
    beq @done
    cmp #4
    beq @done
    jsr a_blocked
    bcs @done
    jsr a_write_visit_dist
    ldx a_tail
    lda a_tail+1
    bne @second
    lda a_node
    sta ai_queuelo,x
    lda a_node+1
    sta ai_queuehi,x
    jmp @added
@second:
    lda a_node
    sta ai_queuelo+256,x
    lda a_node+1
    sta ai_queuehi+256,x
@added:
    inc a_tail
    bne :+
    inc a_tail+1
:
    inc ai_queue_count
    bne :+
    inc ai_queue_count+1
:
@done:
    rts

a_read_visit:
    ldx a_node
    lda a_node+1
    beq :+
    lda ai_visit+256,x
    rts
:
    lda ai_visit,x
    rts

a_read_tile:
    ldx a_node
    lda a_node+1
    beq :+
    lda world_tiles+256,x
    rts
:
    lda world_tiles,x
    rts

a_read_dist:
    ldx a_node
    lda a_node+1
    beq :+
    lda ai_disthi+256,x
    tay
    lda ai_distlo+256,x
    rts
:
    lda ai_disthi,x
    tay
    lda ai_distlo,x
    rts

a_write_visit_dist:
    ldx a_node
    lda a_node+1
    beq @first
    lda ai_generation
    sta ai_visit+256,x
    lda a_next_dist
    sta ai_distlo+256,x
    lda a_next_dist+1
    sta ai_disthi+256,x
    rts
@first:
    lda ai_generation
    sta ai_visit,x
    lda a_next_dist
    sta ai_distlo,x
    lda a_next_dist+1
    sta ai_disthi,x
    rts

a_steer:
    ; Retain a committed waypoint until arrival. The per-tick throttle gate
    ; stops at it even if a slower difficulty's path decision skips that pixel.
    lda ai_nav_heading
    cmp #$FF
    beq @choose
    jsr a_waypoint_reached
    bcs @choose
    rts
@choose:
    lda #$FF
    sta a_best_heading
    sta a_best_dist
    sta a_best_dist+1
    sta a_best_penalty
    lda #0
    sta a_field
    lda a_bot
    sta a_node
    lda a_bot+1
    sta a_node+1
    lda ai_plan_valid
    beq @greedy
    jsr a_read_visit
    cmp ai_generation
    bne @greedy
    lda #1
    sta a_field
    jsr a_read_dist
    sta a_current_dist
    sty a_current_dist+1
    lda a_bot_y
    beq @down
    jsr a_up_node
    lda #0
    jsr a_candidate
@down:
    lda a_bot_y
    cmp #15
    beq @left
    jsr a_down_node
    lda #4
    jsr a_candidate
@left:
    lda a_bot_x
    beq @right
    jsr a_left_node
    lda #6
    jsr a_candidate
@right:
    lda a_bot_x
    cmp #31
    beq @selected
    jsr a_right_node
    lda #2
    jsr a_candidate
    jmp @selected
@greedy:
    lda a_bot_x
    cmp a_goal_x
    beq @greedy_y
    bcs @greedy_left
    jsr a_right_node
    lda #2
    jsr a_candidate
    jmp @greedy_y
@greedy_left:
    jsr a_left_node
    lda #6
    jsr a_candidate
@greedy_y:
    lda a_bot_y
    cmp a_goal_y
    beq @selected
    bcs @greedy_up
    jsr a_down_node
    lda #4
    jsr a_candidate
    jmp @selected
@greedy_up:
    jsr a_up_node
    lda #0
    jsr a_candidate
@selected:
    lda a_best_heading
    sta ai_nav_heading
    cmp #$FF
    beq @done
    lda a_best_node
    and #31
    sta a_tmp
    lsr
    lsr
    lsr
    lsr
    sta a_waypoint_x+1
    lda a_tmp
    asl
    asl
    asl
    asl
    sta a_waypoint_x
    lda a_best_node+1
    asl
    asl
    asl
    sta a_tmp
    lda a_best_node
    lsr
    lsr
    lsr
    lsr
    lsr
    ora a_tmp
    asl
    asl
    asl
    asl
    sta a_waypoint_y
@done:
    rts

a_up_node:
    lda a_bot
    sec
    sbc #32
    sta a_node
    lda a_bot+1
    sbc #0
    sta a_node+1
    rts

a_down_node:
    lda a_bot
    clc
    adc #32
    sta a_node
    lda a_bot+1
    adc #0
    sta a_node+1
    rts

a_left_node:
    lda a_bot
    sec
    sbc #1
    sta a_node
    lda a_bot+1
    sta a_node+1
    rts

a_right_node:
    lda a_bot
    clc
    adc #1
    sta a_node
    lda a_bot+1
    sta a_node+1
    rts

a_candidate:
    sta a_cand_heading
    jsr a_read_tile
    jeq @done
    cmp #4
    jeq @done
    pha
    jsr a_blocked
    pla
    bcs @done
    tay
    lda a_penalty,y
    sta a_cand_penalty
    lda #0
    sta a_cand_dist
    sta a_cand_dist+1
    lda a_field
    beq @rank
    jsr a_read_visit
    cmp ai_generation
    bne @done
    jsr a_read_dist
    sta a_cand_dist
    sty a_cand_dist+1
    tya
    cmp a_current_dist+1
    bcc @rank
    bne @done
    lda a_cand_dist
    cmp a_current_dist
    bcs @done
@rank:
    lda a_cand_dist+1
    cmp a_best_dist+1
    bcc @choose
    bne @done
    lda a_cand_dist
    cmp a_best_dist
    bcc @choose
    bne @done
    lda a_cand_penalty
    cmp a_best_penalty
    bcs @done
@choose:
    lda a_cand_dist
    sta a_best_dist
    lda a_cand_dist+1
    sta a_best_dist+1
    lda a_cand_penalty
    sta a_best_penalty
    lda a_cand_heading
    sta a_best_heading
    lda a_node
    sta a_best_node
    lda a_node+1
    sta a_best_node+1
@done:
    rts

a_drive_heading:
    lda ai_nav_heading
    cmp #$FF
    beq @done
    jsr a_waypoint_reached
    bcc @continue
    lda #$FF
    sta ai_nav_heading
    lda #0
    sta a_steer_wait
    rts
@continue:
    lda ai_nav_heading
    sec
    sbc hull+1
    and #7
    beq @forward
    cmp #4
    beq @reverse_or_turn
    bcc @right
    lda #4
    sta dual_controls+1
    rts
@reverse_or_turn:
    lda enemy_visible+1
    beq @right
    lda hull+1
    sec
    sbc bearing+1
    and #7
    cmp #2
    bcc @reverse
    cmp #7
    bne @right
@reverse:
    ; Reversing keeps front armor toward a visible opponent while withdrawing.
    lda #2
    sta dual_controls+1
    rts
@right:
    lda #8
    sta dual_controls+1
    rts
@forward:
    lda #1
    sta dual_controls+1
@done:
    rts

; C set once the requested destination is reached or crossed along the travel
; axis. All selected navigation headings are cardinal; fractions need no
; equality comparison, and x255/256 uses an unsigned WORD comparison.
a_waypoint_reached:
    lda ai_nav_heading
    beq @north
    cmp #4
    beq @south
    cmp #2
    beq @east
@west:
    lda a_waypoint_x
    sec
    sbc tank_xlo+1
    lda a_waypoint_x+1
    sbc tank_xhi+1
    rts
@east:
    lda tank_xlo+1
    sec
    sbc a_waypoint_x
    lda tank_xhi+1
    sbc a_waypoint_x+1
    rts
@north:
    lda a_waypoint_y
    cmp tank_y+1
    rts
@south:
    lda tank_y+1
    cmp a_waypoint_y
    rts

a_aim:
    lda contact_known+1
    jeq a_reset_aim
    lda bearing+1
    and #7
    sta a_target_heading
    sec
    sbc turret+1
    and #7
    beq @aligned
    cmp #4
    bcc @right
    lda dual_controls+1
    ora #32
    sta dual_controls+1
    jmp a_reset_aim
@right:
    lda dual_controls+1
    ora #64
    sta dual_controls+1
    jmp a_reset_aim
@aligned:
    lda enemy_visible+1
    jeq a_reset_aim
    ; Coarse turret steering remains responsive on HUD ticks, but new firing
    ; alignment/position work waits for the next ordinary tick. Never cache or
    ; repeat a FIRE command; ordinary game cooldowns and shells still own it.
    lda hud_clock
    cmp #4
    jeq @done
    lda a_goal_work
    jne @done
    lda ai_work_class
    jne @done
    lda shell_active+1
    ora shell_cooldown+1
    ora stun+1
    jne @done
    ; A visible sensed contact already has canonical mountain line of sight.
    ; Pixel alignment still matters: an octant bearing alone is not a hit ray.
    lda contact_xlo+1
    sec
    sbc tank_xlo+1
    sta a_dx
    lda contact_xhi+1
    sbc tank_xhi+1
    sta a_dx+1
    bpl :+
    lda a_dx
    eor #$FF
    clc
    adc #1
    sta a_dx
    lda a_dx+1
    eor #$FF
    adc #0
    sta a_dx+1
:
    lda a_dx+1
    jne a_reset_aim
    lda contact_y+1
    sec
    sbc tank_y+1
    bcs :+
    lda tank_y+1
    sec
    sbc contact_y+1
:
    sta a_dy
    lda a_dx
    cmp #6
    bcs :+
    lda a_dy
    cmp #6
    jcc a_reset_aim
:
    lda a_dy
    ldx ai_level
    cmp a_range,x
    bcs a_reset_aim
    lda a_dx
    cmp a_range,x
    bcs a_reset_aim
    lda a_target_heading
    and #1
    bne @diagonal
    lda a_target_heading
    and #2
    bne @horizontal
    lda a_dx
    cmp #7
    bcs a_reset_aim
    jmp @patient
@horizontal:
    lda a_dy
    cmp #7
    bcs a_reset_aim
    jmp @patient
@diagonal:
    lda a_dx
    sec
    sbc a_dy
    bcs :+
    lda a_dy
    sec
    sbc a_dx
:
    cmp #11
    bcs a_reset_aim
@patient:
    lda a_target_heading
    cmp ai_pending_aim
    beq @waiting
    sta ai_pending_aim
    ldx ai_level
    lda a_reaction,x
    sta ai_aim_wait
@waiting:
    lda ai_aim_wait
    beq @ready
@done:
    rts
@ready:
    lda ai_shot_spacing
    bne @done
    lda dual_controls+1
    ora #16
    sta dual_controls+1
    ldx ai_level
    lda a_spacing,x
    sta ai_shot_spacing
    lda #$FF
    sta ai_pending_aim
    lda #0
    sta ai_aim_wait
    rts

a_reset_aim:
    lda #$FF
    sta ai_pending_aim
    lda #0
    sta ai_aim_wait
    rts

; C set for visible contact within the 12px body-clearance square. Only viewer
; 1's exact visible contact and the computer's own coordinates are inspected.
a_contact_too_close:
    lda contact_xlo+1
    sec
    sbc tank_xlo+1
    sta a_dx
    lda contact_xhi+1
    sbc tank_xhi+1
    bpl :+
    eor #$FF
    sta a_dx+1
    lda a_dx
    eor #$FF
    clc
    adc #1
    sta a_dx
    lda a_dx+1
    adc #0
:
    bne @far
    lda a_dx
    cmp #12
    bcs @far
    lda contact_y+1
    sec
    sbc tank_y+1
    bcs :+
    lda tank_y+1
    sec
    sbc contact_y+1
:
    cmp #12
    bcs @far
    sec
    rts
@far:
    clc
    rts

a_observed_block:
    lda contact_xlo+1
    and #15
    sta a_block_wide
    lda contact_y+1
    and #15
    sta a_block_tall
    lda contact_xhi+1
    asl
    asl
    asl
    asl
    sta a_tmp
    lda contact_xlo+1
    lsr
    lsr
    lsr
    lsr
    ora a_tmp
    sta a_tmp
    lda contact_y+1
    lsr
    lsr
    lsr
    lsr
    tay
    lda a_rowslo,y
    clc
    adc a_tmp
    sta a_block_base
    lda a_rowshi,y
    sta a_block_base+1
    lda #1
    sta a_block_valid
    rts

; Test the short intended gun ray from a sensed, visible tank to its proposed
; flank. A mountain on a rear ray chooses a neighboring rear angle; Medium can
; switch side. Results are cached by observed tile/hull/level, so this bounded
; (at most nine tile reads) work is not repeated every simulation tick.
a_choose_flank:
    lda a_flank_valid
    beq @new
    lda a_raw_x
    cmp a_flank_x
    bne @new
    lda a_raw_y
    cmp a_flank_y
    bne @new
    lda contact_hull+1
    cmp a_flank_hull
    bne @new
    lda ai_level
    cmp a_flank_level
    jeq @selected
@new:
    lda #1
    sta a_goal_work
    lda a_raw_x
    sta a_flank_x
    lda a_raw_y
    sta a_flank_y
    lda contact_hull+1
    sta a_flank_hull
    clc
    adc #2
    ldx ai_level
    cpx #2
    bne :+
    clc
    adc #2
:
    and #7
    sta a_flank_initial
    lda ai_level
    sta a_flank_level
    lda #0
    sta a_flank_attempt
@attempt:
    ldx a_flank_attempt
    lda a_rear_angles,x
    ldy ai_level
    cpy #2
    beq :+
    lda #0
    cpx #0
    beq :+
    lda #4
:
    clc
    adc a_flank_initial
    and #7
    sta a_flank_heading
    lda a_flank_x
    sta a_ray_x
    lda a_flank_y
    sta a_ray_y
    lda #2
    ldy ai_level
    cpy #2
    bne :+
    lda #3
:
    sta a_budget
@ray_step:
    ldx a_flank_heading
    lda a_ray_x
    clc
    adc a_vec_x,x
    cmp #32
    bcs @blocked_ray
    sta a_ray_x
    lda a_ray_y
    clc
    adc a_vec_y,x
    cmp #16
    bcs @blocked_ray
    sta a_ray_y
    tay
    lda a_rowslo,y
    clc
    adc a_ray_x
    sta a_node
    lda a_rowshi,y
    sta a_node+1
    jsr a_read_tile
    cmp #4
    beq @blocked_ray
    dec a_budget
    bne @ray_step
    jmp @cache
@blocked_ray:
    inc a_flank_attempt
    lda a_flank_attempt
    ldy ai_level
    cpy #2
    bne @medium_limit
    cmp #3
    jcc @attempt
    jmp @fallback
@medium_limit:
    cmp #2
    jcc @attempt
@fallback:
    ; All preferred rear/side rays can leave a corner of the map. Clamping
    ; such an offset bends its firing lane (for example SW from tile1,1
    ; becomes0,3), leaving a visible opponent impossible to aim at. Approach
    ; horizontally toward the map interior instead: the normal2/3-cell
    ; offset is always in bounds and remains on a straight sensed-contact ray.
    lda a_flank_x
    cmp #16
    lda #2
    bcc :+
    lda #6
:
    sta a_flank_heading
@cache:
    lda #1
    sta a_flank_valid
@selected:
    ldx a_flank_heading
    lda #3
    sta a_new_mode
    lda #2
    ldy ai_level
    cpy #2
    bne :+
    lda #4
    sta a_new_mode
    lda #3
:
    sta a_budget
    rts

; C set iff a_node is in the visible obstacle. Full WORD subtraction handles
; boxes crossing node255/256. A column31 box never wraps into the next row.
a_blocked:
    lda a_block_valid
    beq @free
    lda a_node
    sec
    sbc a_block_base
    sta a_tmp
    lda a_node+1
    sbc a_block_base+1
    bne @free
    lda a_tmp
    and #$FE
    beq @box
    cmp #32
    bne @free
    lda a_block_tall
    beq @free
@box:
    lda a_tmp
    and #1
    beq @blocked
    lda a_block_wide
    beq @free
    lda a_block_base
    and #31
    cmp #31
    beq @free
@blocked:
    sec
    rts
@free:
    clc
    rts

.segment "RODATA"
a_rowslo: .byte 0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224
a_rowshi: .byte 0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1
a_refresh: .byte 64,40,24
a_steer_interval: .byte 8,4,1
a_reaction: .byte 16,8,0
a_spacing: .byte 48,24,0
a_range: .byte 97,145,181
a_penalty: .byte 255,2,4,4,255,8,0,0
a_vec_x: .byte 0,1,1,1,0,255,255,255
a_vec_y: .byte 255,255,0,1,1,1,0,255
a_patrol_x: .byte 16,10,8,5
a_patrol_y: .byte 8,4,12,8
a_search_x: .byte 255,1,1,255
a_search_y: .byte 255,255,1,1
a_probe_x: .byte 0,255,1,0,0,255,1,255,1,254,2,0,0,254,2,254,2
a_probe_y: .byte 0,0,0,255,1,255,255,1,1,0,0,254,2,255,255,1,1
a_rear_angles: .byte 0,7,1
.assert a_end-a_start < 128, error, "AI scalar initialization exceeds byte loop"

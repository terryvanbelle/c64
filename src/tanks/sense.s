; IRONVEIL shared observation rules. IRQ-only, no zero page or hardware access.
; All arrays are indexed by VIEWER: viewer0 observes tank1 and vice versa.
;
; sense_init resets this module and makes one initial observation/ping.
; sense_tick runs after game_tick at 50Hz. camera_x/y are desired 9x12-tile
; origins: centre tile minus4/minus6, clamped x0..23/y0..4 respectively.
; terrain_here is the viewer's centre terrain ID.
;
; enemy_visible requires an alive enemy inside that desired viewport, terrain
; range and unobstructed mountain LOS. Cover uses max(|dx|,|dy|): grass160,
; forest48, desert112, reeds64 pixels. Roads/bridges and reveal bypass range,
; but never viewport/LOS. One canonical tile ray is shared by both viewers;
; this avoids asymmetric Bresenham ties and visits at most eleven entered cells.
;
; contact coordinates are enemy TOP-LEFT world pixels. Visible contacts and
; hull are exact. Hidden contacts are always the last ping's 64px-sector centre
; minus8: zone*64+24; hidden hull=$FF. On concealment, cached coarse coordinates
; replace an exact contact immediately, without obtaining new hidden position.
; Contact_known=0 means unavailable; a respawning enemy is never visible/known.
;
; Pings happen immediately on init, then every50ticks. zone_x0..7/zone_y0..3,
; bearing0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW; range0=NEAR<=96px,
; 1=MID<=224px,2=FAR. These rough fields update only on a ping, independent of
; visual cover. AI must use exported contacts, never concealed tank positions.
; Every public routine clobbers A/X/Y/flags; caller serializes ownership.

.setcpu "6502"
.macpack longbranch
.import world_tiles, tank_xlo, tank_xhi, tank_y, hull, reveal, respawn
.export sense_init, sense_tick, sense_tick_done
.export camera_x, camera_y, terrain_here, enemy_visible
.export contact_xlo, contact_xhi, contact_y, contact_hull, contact_known
.export bearing, range_band, zone_x, zone_y
.export sense_ping_countdown

.segment "BSS"
s_state_begin:
camera_x: .res 2
camera_y: .res 2
terrain_here: .res 2
enemy_visible: .res 2
contact_xlo: .res 2
contact_xhi: .res 2
contact_y: .res 2
contact_hull: .res 2
contact_known: .res 2
bearing: .res 2
range_band: .res 2
zone_x: .res 2
zone_y: .res 2
s_coarse_xlo: .res 2
s_coarse_xhi: .res 2
s_coarse_y: .res 2
s_ping_known: .res 2
s_centre_xlo: .res 2
s_centre_xhi: .res 2
s_centre_y: .res 2
s_tile_x: .res 2
s_tile_y: .res 2
s_ping_timer: .res 1
sense_ping_countdown = s_ping_timer ; public read-only clock, no position data
s_ping_now: .res 1
s_viewer: .res 1
s_dxlo: .res 1
s_dxhi: .res 1
s_dy: .res 1
s_xsign: .res 1
s_ysign: .res 1
s_read_x: .res 1
s_radius: .res 1
s_los_clear: .res 1
s_los_x: .res 1
s_los_y: .res 1
s_los_dx: .res 1
s_los_dy: .res 1
s_los_sx: .res 1
s_los_sy: .res 1
s_los_error: .res 1
s_los_e2: .res 1
s_los_negdy: .res 1
s_los_posdx: .res 1
s_los_remaining: .res 1
s_two_ylo: .res 1
s_two_yhi: .res 1
s_state_end:

.segment "CODE"
sense_init:
    lda #0
    ldx #s_state_end-s_state_begin-1
@clear:
    sta s_state_begin,x
    dex
    bpl @clear
    lda #1
    sta s_ping_timer
    jmp sense_tick

sense_tick:
    lda #0
    sta s_ping_now
    dec s_ping_timer
    bne :+
    lda #50
    sta s_ping_timer
    lda #1
    sta s_ping_now
:
    ldx #1
@cameras:
    stx s_viewer
    lda tank_xlo,x
    clc
    adc #8
    sta s_centre_xlo,x
    lda tank_xhi,x
    adc #0
    sta s_centre_xhi,x
    asl
    asl
    asl
    asl
    sta s_tile_x,x
    lda s_centre_xlo,x
    lsr
    lsr
    lsr
    lsr
    ora s_tile_x,x
    sta s_tile_x,x
    cmp #4
    bcc @left_edge
    sbc #4
    cmp #23
    bcc @camera_x
    lda #23
    bne @camera_x
@left_edge:
    lda #0
@camera_x:
    sta camera_x,x
    lda tank_y,x
    clc
    adc #8
    sta s_centre_y,x
    lsr
    lsr
    lsr
    lsr
    sta s_tile_y,x
    cmp #6
    bcc @top_edge
    sbc #6
    cmp #4
    bcc @camera_y
    lda #4
    bne @camera_y
@top_edge:
    lda #0
@camera_y:
    sta camera_y,x
    ldy s_tile_y,x
    lda s_tile_x,x
    jsr s_terrain
    ldx s_viewer
    sta terrain_here,x
    dex
    jpl @cameras
    jsr s_distance
    ldx #1
@visibility:
    stx s_viewer
    lda #0
    sta enemy_visible,x
    txa
    eor #1
    tay
    lda respawn,y
    jne @next_visible
    lda s_tile_x,y
    sec
    sbc camera_x,x
    cmp #9
    bcs @next_visible
    lda s_tile_y,y
    sec
    sbc camera_y,x
    cmp #12
    bcs @next_visible
    lda reveal,y
    bne @visible_candidate
    lda terrain_here,y
    cmp #6
    bcs @visible_candidate
    tay
    lda s_cover_radius,y
    sta s_radius
    lda s_dxhi
    bne @next_visible
    lda s_radius
    cmp s_dxlo
    bcc @next_visible
    cmp s_dy
    bcc @next_visible
@visible_candidate:
    lda #1
    sta enemy_visible,x
@next_visible:
    dex
    bpl @visibility
    lda enemy_visible
    ora enemy_visible+1
    beq @contacts
    jsr s_line_of_sight
    lda s_los_clear
    bne @contacts
    sta enemy_visible
    sta enemy_visible+1
@contacts:
    lda s_ping_now
    beq :+
    jsr s_ping
:
    ldx #1
@contact:
    txa
    eor #1
    tay
    lda enemy_visible,x
    beq @hidden
    lda tank_xlo,y
    sta contact_xlo,x
    lda tank_xhi,y
    sta contact_xhi,x
    lda tank_y,y
    sta contact_y,x
    lda hull,y
    sta contact_hull,x
    lda #1
    sta contact_known,x
    bne @next_contact
@hidden:
    lda s_coarse_xlo,x
    sta contact_xlo,x
    lda s_coarse_xhi,x
    sta contact_xhi,x
    lda s_coarse_y,x
    sta contact_y,x
    lda #$ff
    sta contact_hull,x
    lda s_ping_known,x
    sta contact_known,x
    lda respawn,y
    beq @next_contact
    lda #0
    sta contact_known,x
@next_contact:
    dex
    bpl @contact
sense_tick_done:
    rts

; A=tileX0..31,Y=tileY0..15. Preserve Y; clobber X/A. No pointer scratch.
s_terrain:
    sta s_read_x
    tya
    and #7
    asl
    asl
    asl
    asl
    asl
    ora s_read_x
    tax
    tya
    and #8
    beq :+
    lda world_tiles+$100,x
    rts
:
    lda world_tiles,x
    rts

; Absolute top-left separation. Signs describe tank1 relative to tank0.
s_distance:
    lda #0
    sta s_xsign
    sta s_ysign
    lda tank_xlo+1
    sec
    sbc tank_xlo
    sta s_dxlo
    lda tank_xhi+1
    sbc tank_xhi
    sta s_dxhi
    bpl @y
    inc s_xsign
    lda s_dxlo
    eor #$ff
    clc
    adc #1
    sta s_dxlo
    lda s_dxhi
    eor #$ff
    adc #0
    sta s_dxhi
@y:
    lda tank_y+1
    sec
    sbc tank_y
    bcs :+
    inc s_ysign
    lda tank_y
    sec
    sbc tank_y+1
:
    sta s_dy
    rts

; Canonical ray uses 32-biased signed error, so comparisons are unsigned.
; Visibility candidates guarantee |tileDX|<=8 and |tileDY|<=11.
s_line_of_sight:
    lda #1
    sta s_los_clear
    sta s_los_sx
    sta s_los_sy
    lda #12
    sta s_los_remaining
    lda s_tile_x
    sta s_los_x
    lda s_tile_y
    sta s_los_y
    lda s_tile_x+1
    sec
    sbc s_tile_x
    bcs :+
    lda #$ff
    sta s_los_sx
    lda s_tile_x
    sec
    sbc s_tile_x+1
:
    sta s_los_dx
    clc
    adc #32
    sta s_los_posdx
    lda s_tile_y+1
    sec
    sbc s_tile_y
    bcs :+
    lda #$ff
    sta s_los_sy
    lda s_tile_y
    sec
    sbc s_tile_y+1
:
    sta s_los_dy
    lda #32
    sec
    sbc s_los_dy
    sta s_los_negdy
    clc
    adc s_los_dx
    sta s_los_error
@ray:
    lda s_los_x
    cmp s_tile_x+1
    bne @step
    lda s_los_y
    cmp s_tile_y+1
    beq @done
@step:
    dec s_los_remaining
    beq @blocked
    lda s_los_error
    asl
    sec
    sbc #32
    sta s_los_e2
    cmp s_los_negdy
    bcc @skip_x
    beq @skip_x
    lda s_los_error
    sec
    sbc s_los_dy
    sta s_los_error
    lda s_los_x
    clc
    adc s_los_sx
    sta s_los_x
@skip_x:
    lda s_los_e2
    cmp s_los_posdx
    bcs @skip_y
    lda s_los_error
    clc
    adc s_los_dx
    sta s_los_error
    lda s_los_y
    clc
    adc s_los_sy
    sta s_los_y
@skip_y:
    lda s_los_x
    ldy s_los_y
    jsr s_terrain
    cmp #4
    beq @blocked
    jmp @ray
@blocked:
    lda #0
    sta s_los_clear
@done:
    rts

s_ping:
    jsr s_bearing
    lda s_dxhi
    bne @far
    lda s_dxlo
    cmp s_dy
    bcs :+
    lda s_dy
:
    cmp #97
    bcc @near
    cmp #225
    bcc @mid
@far:
    lda #2
    bne @range
@near:
    lda #0
    beq @range
@mid:
    lda #1
@range:
    sta range_band
    sta range_band+1
    ldx #1
@viewer:
    txa
    eor #1
    tay
    lda respawn,y
    beq @alive
    lda #0
    sta s_ping_known,x
    jmp @next
@alive:
    lda #1
    sta s_ping_known,x
    lda s_centre_xlo,y
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta zone_x,x
    lda s_centre_xhi,y
    asl
    asl
    ora zone_x,x
    sta zone_x,x
    and #3
    asl
    asl
    asl
    asl
    asl
    asl
    clc
    adc #24
    sta s_coarse_xlo,x
    lda zone_x,x
    lsr
    lsr
    sta s_coarse_xhi,x
    lda s_centre_y,y
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta zone_y,x
    asl
    asl
    asl
    asl
    asl
    asl
    clc
    adc #24
    sta s_coarse_y,x
@next:
    dex
    bpl @viewer
    rts

; Axis-dominance sectors: horizontal if DX>=2DY, vertical if DY>=2DX.
s_bearing:
    lda s_dy
    asl
    sta s_two_ylo
    lda #0
    rol
    sta s_two_yhi
    lda s_dxhi
    cmp s_two_yhi
    bcc @vertical_check
    bne @horizontal
    lda s_dxlo
    cmp s_two_ylo
    bcs @horizontal
@vertical_check:
    lda s_dxhi
    bne @diagonal
    lda s_dxlo
    asl
    bcs @diagonal
    cmp s_dy
    bcc @vertical
    beq @vertical
@diagonal:
    lda s_ysign
    asl
    ora s_xsign
    tax
    lda s_diagonal_bearing,x
    jmp @save
@horizontal:
    lda #2
    ldx s_xsign
    beq @save
    lda #6
    bne @save
@vertical:
    lda #4
    ldx s_ysign
    beq @save
    lda #0
@save:
    sta bearing
    clc
    adc #4
    and #7
    sta bearing+1
    rts

.segment "RODATA"
s_cover_radius: .byte 0,160,48,112,0,64,255,255
s_diagonal_bearing: .byte 3,5,1,7
.assert s_state_end-s_state_begin < 128,error,"Sensor reset exceeds byte loop"

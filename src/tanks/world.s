; IRONVEIL: asymmetric geography generated on an unexpanded C64.
; world_generate preserves world_seed and fills world_tiles[512], row-major
; 32x16. Main/startup only: A/X/Y/flags and private scratch are clobbered.
; IDs: 0 water, 1 grass, 2 forest, 3 desert, 4 mountain, 5 reeds/ford,
; 6 road, 7 bridge. Three independently bent road routes cross a river at
; rows 3/8/12; slower fords add routes at 5/10/14. Clear spawn aprons at
; (3,8)/(28,8) join the roads. No mirror is applied.
.setcpu "6502"
.macpack longbranch
.import world_seed
.export world_generate, world_tiles, arena_tiles

.segment "WORK"
world_tiles: .res 512
arena_tiles = world_tiles

.segment "BSS"
w_random: .res 2
w_terrain: .res 1
w_column: .res 1
w_feature: .res 1
w_center_x: .res 1
w_center_y: .res 1
w_shape: .res 1
w_path: .res 1
w_side: .res 1
w_base_row: .res 1
w_bend_row: .res 1
w_turn: .res 1
w_end: .res 1
w_finish: .res 1

.segment "CODE"
world_generate:
    lda world_seed
    sta w_random
    lda world_seed+1
    sta w_random+1
    ora w_random
    bne :+
    lda #$E1
    sta w_random
    lda #$AC
    sta w_random+1
:
    jsr w_random_byte
    lda #1
    ldx #0
@clear:
    sta world_tiles,x
    sta world_tiles+256,x
    inx
    bne @clear
    lda #0
    sta w_feature
@feature:
    jsr w_random_byte
    and #31
    cmp #28
    bcc :+
    sec
    sbc #28
:
    clc
    adc #2
    sta w_center_x
    jsr w_random_byte
    and #15
    bne :+
    lda #1
:
    cmp #15
    bne :+
    lda #14
:
    sta w_center_y
    jsr w_random_byte
    sta w_shape
    ldx w_feature
    lda w_features,x
    sta w_terrain
    jsr w_stamp
    inc w_feature
    lda w_feature
    cmp #24
    bne @feature
    ldy #0
@river:
    ldx #15
    lda #0
    jsr w_put
    inx
    jsr w_put
    iny
    cpy #16
    bne @river
    ldy #5
    jsr w_ford
    ldy #10
    jsr w_ford
    ldy #14
    jsr w_ford
    ; Continuous wetland banks connect every ford to the bridge approaches,
    ; even if overlapping random mountains/ponds surround a particular ford.
    ; Later road carving restores fast crossings through these slow flanks.
    ldy #3
@reed_banks:
    ldx #14
    lda #5
    jsr w_put
    ldx #17
    jsr w_put
    iny
    cpy #15
    bne @reed_banks
    ldy #2
@spines:
    ldx #3
    lda #6
    jsr w_put
    ldx #28
    jsr w_put
    iny
    cpy #14
    bne @spines
    lda #0
    sta w_path
@crossing:
    ldx w_path
    lda w_crossings,x
    sta w_base_row
    lda #0
    sta w_side
@half:
    jsr w_random_byte
    and #1
    beq @bend_up
    lda w_base_row
    clc
    adc #1
    bne @bend_ready
@bend_up:
    lda w_base_row
    sec
    sbc #1
@bend_ready:
    sta w_bend_row
    lda w_side
    bne @east
    jsr w_random_byte
    and #3
    clc
    adc #6
    sta w_turn
    lda #12
    sta w_end
    lda #14
    sta w_finish
    ldx #3
    bne @approach
@east:
    jsr w_random_byte
    and #1
    clc
    adc #20
    sta w_turn
    lda #25
    sta w_end
    lda #28
    sta w_finish
    ldx #17
@approach:
    ldy w_base_row
    lda #6
    jsr w_put
    cpx w_turn
    beq @detour
    inx
    bne @approach
@detour:
    ldy w_bend_row
    lda #6
    jsr w_put
    cpx w_end
    beq @return_row
    inx
    bne @detour
@return_row:
    ldy w_base_row
    lda #6
    jsr w_put
    cpx w_finish
    beq @half_done
    inx
    bne @return_row
@half_done:
    inc w_side
    lda w_side
    cmp #2
    jne @half
    ldy w_base_row
    ldx #15
    lda #7
    jsr w_put
    inx
    jsr w_put
    inc w_path
    lda w_path
    cmp #3
    jne @crossing
    ; Each base has a clear apron, with the central spawn column a road.
    ldy #7
@apron_row:
    ldx #2
@west_apron:
    lda #1
    cpx #3
    bne :+
    lda #6
:
    jsr w_put
    inx
    cpx #5
    bne @west_apron
    ldx #27
@east_apron:
    lda #1
    cpx #28
    bne :+
    lda #6
:
    jsr w_put
    inx
    cpx #30
    bne @east_apron
    iny
    cpy #10
    bne @apron_row
    ; Edge representatives survive all road/spawn overwrites.
    jsr w_random_byte
    and #1
    clc
    adc #2
    tax
    ldy #0
    lda #0
    jsr w_put
    ldx #5
    lda #4
    jsr w_put
    ldx #25
    ldy #15
    lda #2
    jsr w_put
    ldx #28
    lda #3
    jsr w_put
    rts

w_ford:
    ldx #14
    lda #5
@cell:
    jsr w_put
    inx
    cpx #18
    bne @cell
    rts

; X column0..31, Y row0..15, A terrain; preserve A/X/Y. Main-owned store.
w_put:
    sta w_terrain
    stx w_column
    lda w_rowlo,y
    clc
    adc w_column
    clc
    adc #<world_tiles
    sta w_store+1
    lda w_rowhi,y
    adc #>world_tiles
    sta w_store+2
    lda w_terrain
w_store:
    sta $FFFF
    ldx w_column
    rts

w_stamp:
    ldx w_center_x
    ldy w_center_y
    lda w_terrain
    jsr w_put
    dex
    jsr w_put
    inx
    inx
    jsr w_put
    dex
    dey
    jsr w_put
    iny
    iny
    jsr w_put
    lda w_shape
    and #1
    beq :+
    dex
    lda w_terrain
    jsr w_put
:
    ldx w_center_x
    lda w_shape
    and #2
    beq :+
    inx
    lda w_terrain
    jsr w_put
:
    ldx w_center_x
    ldy w_center_y
    dey
    lda w_shape
    and #4
    beq :+
    dex
    lda w_terrain
    jsr w_put
:
    ldx w_center_x
    lda w_shape
    and #8
    beq :+
    inx
    lda w_terrain
    jsr w_put
:
    rts

w_random_byte:
    ldx #8
@step:
    lsr w_random+1
    ror w_random
    bcc :+
    lda w_random+1
    eor #$B4
    sta w_random+1
:
    dex
    bne @step
    lda w_random
    rts

.segment "RODATA"
w_features: .byte 2,2,3,4,0,2,3,4,0,2,2,3,4,0,2,3,4,0,2,2,3,2,0,4
w_crossings: .byte 3,8,12
w_rowlo: .byte 0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224
w_rowhi: .byte 0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1

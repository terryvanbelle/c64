; CROSSING: a fresh, fair arena generated on the stock C64.
;
; arena_generate reads the engine's 16-bit duel_seed without changing it.
; arena_tiles is a row-major 20 by 10 map, reflected horizontally. All random
; changes happen on its left half and are mirrored, so neither player receives
; a geographic advantage. This is main-loop-only code; A/X/Y/flags are clobbered.
;
; Terrain IDs match the original Atlas graphics: 0 water, 1 grass, 2 forest,
; 3 desert, 4 mountain, 5 river ford, 6 city, 7 road, 8 bridge. The engine owns
; movement/collision policy. Water and mountains are solid; river fords are
; deliberately traversable so bridges are fast routes rather than the sole
; routes. Three curved roads join the bases to bridges at rows 2, 5 and 8.
;
; The private right-shifting Galois LFSR uses polynomial $B400. Each random byte
; advances eight steps. A zero seed substitutes $ACE1, and eight initial steps
; mix the seed before geography is chosen. No host-generated map is shipped.

.setcpu "6502"
.import duel_seed
.export arena_generate, arena_tiles

ARENA_WIDTH = 20
ARENA_HEIGHT = 10

.segment "BSS"
arena_tiles:    .res ARENA_WIDTH * ARENA_HEIGHT
ar_random:      .res 2
ar_terrain:     .res 1
ar_column:      .res 1
ar_feature:     .res 1
ar_center_x:    .res 1
ar_center_y:    .res 1
ar_shape:       .res 1
ar_path:        .res 1
ar_base_row:    .res 1
ar_bend_row:    .res 1
ar_bend_column: .res 1
ar_guarantee:   .res 1

.segment "CODE"
arena_generate:
    lda duel_seed
    sta ar_random
    lda duel_seed+1
    sta ar_random+1
    ora ar_random
    bne :+
    lda #$E1
    sta ar_random
    lda #$AC
    sta ar_random+1
:
    jsr ar_random_byte
    lda #1
    ldx #0
@clear:
    sta arena_tiles,x
    inx
    cpx #200
    bne @clear

    ; The central river remains a ford between the bridge crossings. Wider
    ; water at its mouths gives the otherwise bounded map a natural shoreline.
    ldy #0
@river:
    ldx #9
    lda #5
    jsr ar_put
    iny
    cpy #10
    bne @river
    ldx #8
    ldy #0
    lda #0
    jsr ar_put
    ldy #9
    jsr ar_put

    ; Overlapping rounded 3x3 features yield clustered biomes and obstacles.
    lda #0
    sta ar_feature
@feature:
    jsr ar_random_byte
    and #3
    clc
    adc #3
    sta ar_center_x
    jsr ar_random_byte
    and #7
    clc
    adc #1
    sta ar_center_y
    jsr ar_random_byte
    sta ar_shape
    ldx ar_feature
    lda ar_features,x
    sta ar_terrain
    jsr ar_stamp
    inc ar_feature
    lda ar_feature
    cmp #12
    bne @feature

    ; A vertical spine allows a player to change routes quickly near home.
    ldy #1
@spine:
    ldx #1
    lda #7
    jsr ar_put
    iny
    cpy #9
    bne @spine

    ; Each route bends around a seed-selected row on its approach. Both halves
    ; have the same turn; the centre bridges always retain rows 2, 5 and 8.
    lda #0
    sta ar_path
@path:
    ldx ar_path
    lda ar_crossings,x
    sta ar_base_row
    jsr ar_random_byte
    and #1
    beq @bend_up
    lda ar_base_row
    cmp #8
    beq @bend_up
    clc
    adc #1
    bne @bend_ready
@bend_up:
    lda ar_base_row
    sec
    sbc #1
@bend_ready:
    sta ar_bend_row
    jsr ar_random_byte
    and #1
    clc
    adc #3
    sta ar_bend_column

    ; From the home spine to the first turn.
    ldx #1
@approach:
    ldy ar_base_row
    lda #7
    jsr ar_put
    cpx ar_bend_column
    beq @detour_start
    inx
    bne @approach
@detour_start:
    ; Crossing the two adjacent rows at both ends makes four-way connectivity
    ; explicit rather than relying on diagonal tile adjacency.
    ldy ar_bend_row
    lda #7
    jsr ar_put
@detour:
    ldy ar_bend_row
    lda #7
    jsr ar_put
    cpx #6
    beq @detour_end
    inx
    bne @detour
@detour_end:
    ldy ar_base_row
    lda #7
    jsr ar_put
@bridge_approach:
    inx
    ldy ar_base_row
    lda #7
    jsr ar_put
    cpx #8
    bne @bridge_approach
    ldx #9
    lda #8
    jsr ar_put
    inc ar_path
    lda ar_path
    cmp #3
    bne @path

    ; Leave a clear apron around each base. Roads retain their speed bonus.
    ldy #4
@apron_row:
    ldx #0
@apron_column:
    lda #1
    cpx #1
    bne :+
    lda #7
:
    jsr ar_put
    inx
    cpx #3
    bne @apron_column
    iny
    cpy #7
    bne @apron_row
    ldx #1
    ldy #5
    lda #6
    jsr ar_put

    ; Settlements at the two outside crossings provide recognizable landmarks.
    ldx #8
    ldy #2
    lda #6
    jsr ar_put
    ldy #8
    jsr ar_put

    ; Guaranteed representative tiles at the map edges survive road carving.
    ; The random column jitter gives them different neighbors on every map.
    lda #0
    sta ar_guarantee
@guarantee:
    jsr ar_random_byte
    and #1
    ldx ar_guarantee
    clc
    adc ar_edge_columns,x
    pha
    lda ar_edge_rows,x
    tay
    lda ar_edge_terrains,x
    sta ar_terrain
    pla
    tax
    lda ar_terrain
    jsr ar_put
    inc ar_guarantee
    lda ar_guarantee
    cmp #4
    bne @guarantee
    rts

; Store A at left-half X, Y and its horizontally reflected tile. Preserve X/Y/A.
; X must be 0..9; Y must be 0..9. Private scratch is separate from engine state.
ar_put:
    sta ar_terrain
    stx ar_column
    lda ar_row_offsets,y
    clc
    adc ar_column
    tax
    lda ar_terrain
    sta arena_tiles,x
    lda #19
    sec
    sbc ar_column
    clc
    adc ar_row_offsets,y
    tax
    lda ar_terrain
    sta arena_tiles,x
    ldx ar_column
    rts

; Draw a plus and zero to four corners. The centre never exceeds x6/y8, so the
; radius-one footprint stays in the map and does not overwrite the river.
ar_stamp:
    ldx ar_center_x
    ldy ar_center_y
    lda ar_terrain
    jsr ar_put
    dex
    jsr ar_put
    inx
    inx
    jsr ar_put
    dex
    dey
    jsr ar_put
    iny
    iny
    jsr ar_put

    lda ar_shape
    and #1
    beq :+
    dex
    lda ar_terrain
    jsr ar_put
:
    ldx ar_center_x
    lda ar_shape
    and #2
    beq :+
    inx
    lda ar_terrain
    jsr ar_put
:
    ldy ar_center_y
    dey
    ldx ar_center_x
    lda ar_shape
    and #4
    beq :+
    dex
    lda ar_terrain
    jsr ar_put
:
    ldx ar_center_x
    lda ar_shape
    and #8
    beq :+
    inx
    lda ar_terrain
    jsr ar_put
:
    rts

; Eight ordinary NMOS 6502 steps, returning a well-mixed low byte in A.
ar_random_byte:
    ldx #8
@step:
    lsr ar_random+1
    ror ar_random
    bcc :+
    lda ar_random+1
    eor #$B4
    sta ar_random+1
:
    dex
    bne @step
    lda ar_random
    rts

.segment "RODATA"
ar_row_offsets:   .byte 0,20,40,60,80,100,120,140,160,180
ar_features:      .byte 2,2,3,3,4,4,0,0,2,2,3,0
ar_crossings:     .byte 2,5,8
ar_edge_columns:  .byte 3,5,3,5
ar_edge_rows:     .byte 0,0,9,9
ar_edge_terrains: .byte 0,4,2,3

.assert ARENA_WIDTH * ARENA_HEIGHT = 200, error, "Arena size contract changed"

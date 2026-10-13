; ATLAS: stateless geography for an unexpanded Commodore 64.
;
; Public contract
;   world_init: call after changing world_seed; initializes the permutation and
;               invalidates the field cache. Does not change coordinates/seed.
;   world_tile: input unsigned 16-bit tile_x, tile_y; output A terrain ID.
;               Preserves input coordinates and seed; clobbers A/X/Y and flags.
;   world_overview_tile: display-only level of detail; same coordinates and
;               terrain IDs, with imported 16-bit sample_step selecting scale.
;               Movement/collision must continue to call exact world_tile.
;   Terrain: 0 sea, 1 grass, 2 forest, 3 desert, 4 mountain, 5 river,
;            6 city, 7 road, 8 bridge.
;   Main-loop only: the scratch/cache are deliberately not reentrant.
;
; The 65,536 by 65,536 tile world is a torus. A tile is regenerated from its
; coordinates and the 16-bit seed; the entire 4,294,967,296-tile world is never
; stored. All geography, including the permutation, is generated on the C64.
; Two bilinear value-noise fields describe 256-tile continental masses and
; 64-tile moisture/height contours. Thirty-two cached 4x4 samples make a nearby
; viewport much cheaper than evaluating the fields at every tile. Coastline
; pixels receive a small deterministic detail threshold to soften the sample
; grid. Mountains form contour ridges rather than isolated random tiles.
;
; The settlement lattice has a city at each naturally dry (128,128) regional
; center. Curved north/south and east/west roads meet at those centers, stop at
; sea, and bridge rivers. River/road joins include the previous curve position
; so even a one-tile bend remains connected by four-way adjacency.
;
; The seed-selected region is the capital. A small graded land halo guarantees
; a passable start at ($seedlow80,$seedhigh80), even for an ocean-heavy seed.
; It lifts existing height only; ordinary land/biomes remain unchanged.
;
; Memory: 489 bytes BSS, 27 bytes private zero page, 104 bytes constant tables.
; Work: a bounded 6- or 4-step interpolation, no division/multiplication loop
; dependent on coordinate magnitudes; cached tiles avoid all interpolation.

.setcpu "6502"

.importzp tile_x, tile_y
.import world_seed, sample_step
.export world_init, world_tile, world_overview_tile

T_SEA      = 0
T_GRASS    = 1
T_FOREST   = 2
T_DESERT   = 3
T_MOUNTAIN = 4
T_RIVER    = 5
T_CITY     = 6
T_ROAD     = 7
T_BRIDGE   = 8

.segment "ZEROPAGE"
w_cache_index:   .res 1
w_height:        .res 1
w_biome:         .res 1
w_hx:            .res 2
w_hy:            .res 2
w_fx:            .res 1
w_fy:            .res 1
w_bits:          .res 1
w_hash:          .res 1
w_c00:           .res 1
w_c10:           .res 1
w_c01:           .res 1
w_c11:           .res 1
w_top:           .res 1
w_lerp_base:     .res 1
w_lerp_other:    .res 1
w_lerp_fraction: .res 1
w_lerp_mag:      .res 1
w_lerp_down:     .res 1
w_terrain:       .res 1
w_road:          .res 1
w_curve_base:    .res 1
w_fold_mask:     .res 1
w_dx:            .res 1
w_dy:            .res 1

.segment "BSS"
world_perm:          .res 256
world_cache_valid:   .res 32
world_cache_xlo:     .res 32
world_cache_xhi:     .res 32
world_cache_ylo:     .res 32
world_cache_yhi:     .res 32
world_cache_height:  .res 32
world_cache_biome:   .res 32
world_rng:           .res 2
world_road_phase:    .res 1
; Only the display LOD routine uses these bytes. Gameplay always calls the
; exact one-tile query above.
world_lod_x:         .res 1
world_lod_y:         .res 1
world_lod_base:      .res 1
world_lod_half:      .res 1
world_lod_width:     .res 1
world_lod_road:      .res 1

.segment "CODE"

.proc world_init
    lda world_seed
    eor #$a5
    sta world_rng
    lda world_seed+1
    eor #$5a
    sta world_rng+1
    ora world_rng
    bne rng_ready
    lda #1
    sta world_rng
rng_ready:
    ldx #0
fill_permutation:
    txa
    sta world_perm,x
    inx
    bne fill_permutation
    ; A full, bounded shuffle. A permutation is required for coherent hashing;
    ; a uniform statistical shuffle is unnecessary for a landscape.
    ldx #0
shuffle:
    jsr world_random
    tay
    lda world_perm,x
    pha
    lda world_perm,y
    sta world_perm,x
    pla
    sta world_perm,y
    inx
    bne shuffle
    lda world_seed
    and #1
    asl
    asl
    asl
    asl
    sta world_road_phase
    lda #0
    ldx #31
invalidate:
    sta world_cache_valid,x
    dex
    bpl invalidate
    rts
.endproc

.proc world_random
    ; Right-shift 16-bit maximal-period LFSR, polynomial $b400. This private
    ; setup state never consumes or modifies the user's world seed.
    lsr world_rng+1
    ror world_rng
    bcc done
    lda world_rng+1
    eor #$b4
    sta world_rng+1
done:
    lda world_rng
    eor world_rng+1
    rts
.endproc

.proc world_overview_tile
    ; Display-only representative of a sample_step-wide square centered on
    ; tile_x/y. Sizes4/16/64 retain narrow cities and connected transport/water
    ; lines, which point sampling would miss as the army/camera moves. At256
    ; and above show natural geography: there can be hundreds of settlements
    ; inside one cell, so rendering every cell as a city would hide the world.
    lda sample_step+1
    bne regional_scale
    lda sample_step
    cmp #2
    bcc exact
    lsr
    sta world_lod_half
    asl
    clc
    adc #1
    sta world_lod_width
    jsr world_tile
    cmp #0
    beq store_base
    lda w_terrain
store_base:
    sta world_lod_base
    ; A regional-center city is retained if its exact tile falls inside the
    ; coarse square, including coastline squares centered just off shore.
    lda #128
    sta w_curve_base
    lda tile_x
    jsr overview_near
    bcs no_city
    lda tile_y
    jsr overview_near
    bcs no_city
    lda tile_x
    sta world_lod_x
    lda tile_y
    sta world_lod_y
    lda #128
    sta tile_x
    sta tile_y
    jsr world_tile
    tax
    lda world_lod_x
    sta tile_x
    lda world_lod_y
    sta tile_y
    cpx #T_CITY
    bne no_city
    lda #T_CITY
    rts
no_city:
    lda world_lod_base
    beq done
    jsr overview_road
    jsr overview_river
    bcs dry
    lda world_lod_road
    beq water_line
    lda #T_BRIDGE
    rts
water_line:
    lda #T_RIVER
    rts
dry:
    lda world_lod_road
    beq natural
    lda #T_ROAD
    rts
natural:
    lda world_lod_base
done:
    rts
exact:
    jmp world_tile
regional_scale:
    jsr world_tile
    cmp #T_RIVER
    bcc done
    lda w_terrain
    rts
.endproc

.proc overview_near
    ; Carry clear iff unsigned wrapped distance is within the display half-
    ; width. Centers stay well inside256-tile regions; modulo subtraction
    ; handles either sign without signed comparisons or changing coordinates.
    sec
    sbc w_curve_base
    clc
    adc world_lod_half
    cmp world_lod_width
    rts
.endproc

.proc overview_road
    lda #0
    sta world_lod_road
    lda tile_x
    jsr road_curve
    sta w_curve_base
    lda tile_y
    jsr overview_near
    bcc yes
    lda tile_x
    sec
    sbc #1
    jsr road_curve
    sta w_curve_base
    lda tile_y
    jsr overview_near
    bcc yes
    lda tile_y
    jsr road_curve
    sta w_curve_base
    lda tile_x
    jsr overview_near
    bcc yes
    lda tile_y
    sec
    sbc #1
    jsr road_curve
    sta w_curve_base
    lda tile_x
    jsr overview_near
    bcs done
yes:
    inc world_lod_road
done:
    rts
.endproc

.proc overview_river
    lda tile_x+1
    eor world_seed
    tax
    lda world_perm,x
    and #31
    clc
    adc #116
    sta w_curve_base
    lda tile_y
    jsr river_curve
    sta w_dx
    ; river_curve needs the column base for its second sample, so retain it
    ; until both current/previous centerlines have been obtained.
    lda tile_y
    sec
    sbc #1
    jsr river_curve
    sta w_dy
    lda w_dx
    sta w_curve_base
    lda tile_x
    jsr overview_near
    bcc done
    lda w_dy
    sta w_curve_base
    lda tile_x
    jmp overview_near
done:
    rts
.endproc

.proc world_tile
    ; Index: x-block plus eight times the low two y-block bits. A 20x10-tile
    ; close viewport occupies only a few dozen entries in this 32-slot cache.
    lda tile_y
    and #$0c
    asl
    sta w_cache_index
    lda tile_x
    lsr
    lsr
    clc
    adc w_cache_index
    and #31
    tax
    stx w_cache_index
    lda world_cache_valid,x
    beq cache_miss
    lda tile_x
    and #$fc
    cmp world_cache_xlo,x
    bne cache_miss
    lda tile_x+1
    cmp world_cache_xhi,x
    bne cache_miss
    lda tile_y
    and #$fc
    cmp world_cache_ylo,x
    bne cache_miss
    lda tile_y+1
    cmp world_cache_yhi,x
    bne cache_miss
    lda world_cache_height,x
    sta w_height
    lda world_cache_biome,x
    sta w_biome
    jmp fields_ready
cache_miss:
    jsr continental_field
    sta w_height
    jsr biome_field
    sta w_biome
    ldx w_cache_index
    lda w_height
    sta world_cache_height,x
    lda w_biome
    sta world_cache_biome,x
    lda tile_x
    and #$fc
    sta world_cache_xlo,x
    lda tile_x+1
    sta world_cache_xhi,x
    lda tile_y
    and #$fc
    sta world_cache_ylo,x
    lda tile_y+1
    sta world_cache_yhi,x
    lda #$ff
    sta world_cache_valid,x
fields_ready:
    jsr capital_halo
    ; Three units of coastal detail break perfectly rectangular sample edges.
    lda tile_x
    eor tile_y
    tax
    lda world_perm,x
    and #3
    clc
    adc #106
    cmp w_height
    bcc land
    beq land
    lda #T_SEA
    rts
land:
    lda #T_GRASS
    sta w_terrain
    lda w_height
    cmp #192
    bcs mountain
    lda w_biome
    cmp #101
    bcc forest
    cmp #155
    bcs desert
    lda w_height
    cmp #146
    bcc terrain_ready
    lda w_biome
    cmp #120
    bcc terrain_ready
    cmp #136
    bcs terrain_ready
mountain:
    lda #T_MOUNTAIN
    bne set_terrain
forest:
    lda #T_FOREST
    bne set_terrain
desert:
    lda #T_DESERT
set_terrain:
    sta w_terrain
terrain_ready:
    lda tile_x
    cmp #128
    bne not_city
    lda tile_y
    cmp #128
    bne not_city
    lda #T_CITY
    rts
not_city:
    jsr road_here
    jsr river_here
    bcc not_river
    lda w_road
    beq river
    lda #T_BRIDGE
    rts
river:
    lda #T_RIVER
    rts
not_river:
    lda w_road
    beq ordinary
    lda #T_ROAD
    rts
ordinary:
    lda w_terrain
    rts
.endproc

.proc capital_halo
    lda tile_x+1
    cmp world_seed
    bne done
    lda tile_y+1
    cmp world_seed+1
    bne done
    lda tile_x
    sec
    sbc #128
    bcs x_positive
    eor #$ff
    clc
    adc #1
x_positive:
    cmp #21
    bcs done
    sta w_dx
    lda tile_y
    sec
    sbc #128
    bcs y_positive
    eor #$ff
    clc
    adc #1
y_positive:
    clc
    adc w_dx
    cmp #21
    bcs done
    ; floor = 140 - Manhattan distance, fading to 120 at the outer edge.
    sta w_dy
    lda #140
    sec
    sbc w_dy
    cmp w_height
    bcc done
    sta w_height
done:
    rts
.endproc

.proc road_here
    lda #0
    sta w_road
    ; Most tiles are far from either centerline; reject them without curves.
    lda tile_y
    cmp #120
    bcc north_south
    cmp #137
    bcs north_south
    lda tile_x
    jsr road_curve
    cmp tile_y
    beq yes
    lda tile_x
    sec
    sbc #1
    jsr road_curve
    cmp tile_y
    beq yes
north_south:
    lda tile_x
    cmp #120
    bcc done
    cmp #137
    bcs done
    lda tile_y
    jsr road_curve
    cmp tile_x
    beq yes
    lda tile_y
    sec
    sbc #1
    jsr road_curve
    cmp tile_x
    bne done
yes:
    inc w_road
done:
    rts
.endproc

.proc road_curve
    lsr
    lsr
    lsr
    eor world_road_phase
    tax
    lda road_wave,x
    clc
    adc #128
    rts
.endproc

.proc river_here
    lda tile_x
    cmp #100
    bcc no
    cmp #164
    bcs no
    lda tile_x+1
    eor world_seed
    tax
    lda world_perm,x
    and #31
    clc
    adc #116
    sta w_curve_base
    lda tile_y
    jsr river_curve
    cmp tile_x
    beq yes
    lda tile_y
    sec
    sbc #1
    jsr river_curve
    cmp tile_x
    beq yes
no:
    clc
    rts
yes:
    sec
    rts
.endproc

.proc river_curve
    lsr
    lsr
    tax
    lda river_wave,x
    clc
    adc w_curve_base
    rts
.endproc

.proc continental_field
    lda tile_x+1
    sta w_hx
    lda tile_y+1
    sta w_hy
    lda #0
    sta w_hx+1
    sta w_hy+1
    sta w_fold_mask
    lda tile_x
    lsr
    lsr
    sta w_fx
    lda tile_y
    lsr
    lsr
    sta w_fy
    lda #6
    sta w_bits
    jmp value_noise
.endproc

.proc biome_field
    ; Coordinates >> 6 retain ten bits. The two upper bits are folded into
    ; each hash, avoiding the short 16,384-tile repetition of an 8-bit hash.
    lda #3
    sta w_fold_mask
    lda tile_x
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta w_hx
    lda tile_x+1
    asl
    asl
    ora w_hx
    sta w_hx
    lda tile_x+1
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta w_hx+1
    lda tile_y
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta w_hy
    lda tile_y+1
    asl
    asl
    ora w_hy
    sta w_hy
    lda tile_y+1
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta w_hy+1
    lda tile_x
    and #$3f
    lsr
    lsr
    sta w_fx
    lda tile_y
    and #$3f
    lsr
    lsr
    sta w_fy
    lda #4
    sta w_bits
    jmp value_noise
.endproc

.proc value_noise
    jsr corner_hash
    sta w_c00
    inc w_hx
    bne x_advanced
    inc w_hx+1
x_advanced:
    jsr corner_hash
    sta w_c10
    inc w_hy
    bne y_advanced
    inc w_hy+1
y_advanced:
    jsr corner_hash
    sta w_c11
    lda w_hx
    bne x_low_nonzero
    dec w_hx+1
x_low_nonzero:
    dec w_hx
    jsr corner_hash
    sta w_c01
    lda w_c00
    ldx w_c10
    ldy w_fx
    jsr lerp
    sta w_top
    lda w_c01
    ldx w_c11
    ldy w_fx
    jsr lerp
    tax
    lda w_top
    ldy w_fy
    jmp lerp
.endproc

.proc corner_hash
    ; Mask the upper coordinate folds: the +1 corner at the edge wraps to
    ; zero, matching both toroidal geography and 16-bit army coordinates.
    lda w_hx+1
    and w_fold_mask
    tay
    lda fold_x,y
    eor w_hx
    eor world_seed
    tax
    lda world_perm,x
    sta w_hash
    lda w_hy+1
    and w_fold_mask
    tay
    lda fold_y,y
    eor w_hy
    eor world_seed+1
    eor w_hash
    tax
    lda world_perm,x
    rts
.endproc

.proc lerp
    ; A = first endpoint, X = second endpoint, Y = fraction; w_bits is 4/6.
    ; Evaluate |b-a| * fraction / 2^bits with a fixed-length binary fractional
    ; multiply. ROR uses ADC's ninth carry bit, so endpoints up to 255 are safe.
    sta w_lerp_base
    stx w_lerp_other
    sty w_lerp_fraction
    lda #0
    sta w_lerp_down
    lda w_lerp_base
    cmp w_lerp_other
    bcc ascending
    sec
    sbc w_lerp_other
    inc w_lerp_down
    bne magnitude_ready
ascending:
    lda w_lerp_other
    sec
    sbc w_lerp_base
magnitude_ready:
    sta w_lerp_mag
    ldx w_bits
    lda #0
fraction_bit:
    lsr w_lerp_fraction
    bcc halve
    clc
    adc w_lerp_mag
halve:
    ror
    dex
    bne fraction_bit
    ldy w_lerp_down
    beq add_offset
    sta w_lerp_mag
    lda w_lerp_base
    sec
    sbc w_lerp_mag
    rts
add_offset:
    clc
    adc w_lerp_base
    rts
.endproc

.segment "RODATA"
fold_x:
    .byte 0,71,142,213
fold_y:
    .byte 0,103,206,53
road_wave:
    .byte 0,1,2,3,4,5,6,7,8,7,6,5,4,3,2,1
    .byte 0,255,254,253,252,251,250,249,248,249,250,251,252,253,254,255
river_wave:
    .byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    .byte 16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1
    .byte 0,255,254,253,252,251,250,249,248,247,246,245,244,243,242,241
    .byte 240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255

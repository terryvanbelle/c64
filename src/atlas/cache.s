; Close-view viewport cache for Atlas. Main-loop only; IRQ never uses this state.
;
; cache_update:
;   If the seed and zoom still match a remembered close view (zoom=0), and
;   its new origin differs by exactly one cardinal tile modulo65536, shift
;   the 22x12 viewport and query world_tile only for its newly exposed edge.
;   Return carry set when the viewport is ready. All other cases return carry
;   clear, leaving viewport unchanged, so the caller can generate a full view.
;   Clobbers A/X/Y, flags and tile_x/y. Origin, seed and zoom are preserved.
; cache_remember:
;   Call only after a complete viewport has been generated or updated. Saves
;   its metadata for the next cache_update; clobbers A and flags.
;
; Startup must clear BSS (the engine already owns and clears$0200-$07FF).
; Uses13 private BSS bytes,2 private zero-page bytes; no IRQ scratch.

.setcpu "6502"
.macpack longbranch

.import viewport, origin_x, origin_y, zoom, world_seed, world_tile
.importzp tile_x, tile_y
.export cache_update, cache_remember

VIEW_WIDTH = 22
VIEW_HEIGHT = 12
VIEW_SIZE = VIEW_WIDTH * VIEW_HEIGHT

.segment "ZEROPAGE"
c_dest: .res 2

.segment "BSS"
c_valid: .res 1
c_zoom: .res 1
c_seed: .res 2
c_origin_x: .res 2
c_origin_y: .res 2
c_dx: .res 2
c_dy: .res 2
c_count: .res 1
c_state_end:
.assert c_state_end-c_valid <= 20, error, "Viewport cache state budget"

.segment "CODE"

.proc cache_remember
    lda origin_x
    sta c_origin_x
    lda origin_x+1
    sta c_origin_x+1
    lda origin_y
    sta c_origin_y
    lda origin_y+1
    sta c_origin_y+1
    lda world_seed
    sta c_seed
    lda world_seed+1
    sta c_seed+1
    lda zoom
    sta c_zoom
    lda #1
    sta c_valid
    rts
.endproc

.proc cache_update
    lda c_valid
    jeq miss
    lda zoom
    ora c_zoom
    jne miss
    lda world_seed
    cmp c_seed
    jne miss
    lda world_seed+1
    cmp c_seed+1
    jne miss
    ; Unsigned subtraction naturally handles a step across either world edge.
    sec
    lda origin_x
    sbc c_origin_x
    sta c_dx
    lda origin_x+1
    sbc c_origin_x+1
    sta c_dx+1
    sec
    lda origin_y
    sbc c_origin_y
    sta c_dy
    lda origin_y+1
    sbc c_origin_y+1
    sta c_dy+1
    lda c_dx
    ora c_dx+1
    beq vertical
    lda c_dy
    ora c_dy+1
    bne miss
    lda c_dx
    cmp #1
    bne west_test
    lda c_dx+1
    bne miss
    jmp shift_east
west_test:
    lda c_dx
    and c_dx+1
    cmp #$ff
    bne miss
    jmp shift_west
vertical:
    lda c_dy
    cmp #1
    bne north_test
    lda c_dy+1
    bne miss
    jmp shift_south
north_test:
    lda c_dy
    and c_dy+1
    cmp #$ff
    bne miss
    jmp shift_north
miss:
    clc
    rts
.endproc

.proc load_origin
    lda origin_x
    sta tile_x
    lda origin_x+1
    sta tile_x+1
    lda origin_y
    sta tile_y
    lda origin_y+1
    sta tile_y+1
    rts
.endproc

.proc shift_east
    ; source1..263 -> destination0..262, forward to avoid overwriting source.
    ldx #0
page:
    lda viewport+1,x
    sta viewport,x
    inx
    bne page
    ldx #0
tail:
    lda viewport+257,x
    sta viewport+256,x
    inx
    cpx #7
    bne tail
    ; Linear shifts temporarily mix row boundaries; overwrite every final
    ; column before the viewport can be consumed by the renderer.
    jsr load_origin
    clc
    lda tile_x
    adc #VIEW_WIDTH-1
    sta tile_x
    bcc x_ready
    inc tile_x+1
x_ready:
    lda #<(viewport+VIEW_WIDTH-1)
    sta c_dest
    lda #>(viewport+VIEW_WIDTH-1)
    sta c_dest+1
    jmp fill_column
.endproc

.proc shift_west
    ; source0..262 -> destination1..263, backward to preserve overlap.
    ldx #6
tail:
    lda viewport+256,x
    sta viewport+257,x
    dex
    bpl tail
    ldx #0
page:
    dex
    lda viewport,x
    sta viewport+1,x
    cpx #0
    bne page
    jsr load_origin
    lda #<viewport
    sta c_dest
    lda #>viewport
    sta c_dest+1
    jmp fill_column
.endproc

.proc shift_south
    ; source22..263 -> destination0..241, forward.
    ldx #0
copy:
    lda viewport+VIEW_WIDTH,x
    sta viewport,x
    inx
    cpx #VIEW_SIZE-VIEW_WIDTH
    bne copy
    jsr load_origin
    clc
    lda tile_y
    adc #VIEW_HEIGHT-1
    sta tile_y
    bcc y_ready
    inc tile_y+1
y_ready:
    lda #<(viewport+VIEW_SIZE-VIEW_WIDTH)
    sta c_dest
    lda #>(viewport+VIEW_SIZE-VIEW_WIDTH)
    sta c_dest+1
    jmp fill_row
.endproc

.proc shift_north
    ; source0..241 -> destination22..263, backward.
    ldx #VIEW_SIZE-VIEW_WIDTH
copy:
    dex
    lda viewport,x
    sta viewport+VIEW_WIDTH,x
    cpx #0
    bne copy
    jsr load_origin
    lda #<viewport
    sta c_dest
    lda #>viewport
    sta c_dest+1
    jmp fill_row
.endproc

.proc fill_column
    lda #VIEW_HEIGHT
    sta c_count
next:
    jsr world_tile
    ldy #0
    sta (c_dest),y
    inc tile_y
    bne y_ready
    inc tile_y+1
y_ready:
    clc
    lda c_dest
    adc #VIEW_WIDTH
    sta c_dest
    bcc dest_ready
    inc c_dest+1
dest_ready:
    dec c_count
    bne next
    sec
    rts
.endproc

.proc fill_row
    lda #VIEW_WIDTH
    sta c_count
next:
    jsr world_tile
    ldy #0
    sta (c_dest),y
    inc tile_x
    bne x_ready
    inc tile_x+1
x_ready:
    inc c_dest
    bne dest_ready
    inc c_dest+1
dest_ready:
    dec c_count
    bne next
    sec
    rts
.endproc

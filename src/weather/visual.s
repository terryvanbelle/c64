; A MOUTHFUL OF WEATHER: a minimal copper profile speaking blue breath.
; Ordinary hires characters at screen $4000 / charset $4800. No sprites.
; Main-thread-only scratch. No SID, timer, CPU mapping, or interrupt changes.
; visual_tick is bounded direct writes: six mouth cells and 37 breath cells.
.setcpu "6502"

.export visual_init, visual_tick
.import play_tick, mouth_open, voice_shape, phrase_index, song_done

.segment "ZEROPAGE"
vis_source: .res 2
vis_dest:   .res 2

.segment "BSS"
vis_phase:  .res 1
vis_open:   .res 1

.segment "RODATA"
.include "art.inc"

breath_palette:
    .byte 6,6,6,14,14,3,3,15,3,14,14,6,6,6,6,6

.segment "CODE"
.proc visual_init
    lda #0
    sta $d011
    sta $d015
    sta $d020
    sta $d021
    sta $d022
    sta $d023
    sta vis_phase
    sta vis_open
    ldx #0
@clear_charset:
    .repeat 8, page
        sta $4800+page*$100,x
    .endrepeat
    inx
    bne @clear_charset

    ; Bank select while preserving unrelated serial-port state and direction.
    lda $dd02
    ora #3
    sta $dd02
    lda $dd00
    and #$fc
    ora #2
    sta $dd00
    lda #$02
    sta $d018
    lda #$08
    sta $d016
    ldx #0
@font_pages:
    .repeat ::ART_CHAR_BYTES / 256, page
        lda art_charset+page*$100,x
        sta $4800+page*$100,x
    .endrepeat
    inx
    bne @font_pages
    .if ::ART_CHAR_BYTES .mod 256
@font_tail:
        lda art_charset+(::ART_CHAR_BYTES/256)*256,x
        sta $4800+(::ART_CHAR_BYTES/256)*256,x
        inx
        cpx #(::ART_CHAR_BYTES .mod 256)
        bne @font_tail
    .endif

    lda #<art_screen_rle
    sta vis_source
    lda #>art_screen_rle
    sta vis_source+1
    lda #<$4000
    sta vis_dest
    lda #>$4000
    sta vis_dest+1
    jsr unpack
    lda #<art_colors_rle
    sta vis_source
    lda #>art_colors_rle
    sta vis_source+1
    lda #<$d800
    sta vis_dest
    lda #>$d800
    sta vis_dest+1
    jsr unpack
    lda #$1b
    sta $d011
    rts
.endproc

; Init only: (count,value) runs followed by a zero count, exactly 1,000 cells.
.proc unpack
    ldy #0
@next:
    jsr read_byte
    beq @done
    tax
    jsr read_byte
@run:
    sta (vis_dest),y
    inc vis_dest
    bne :+
    inc vis_dest+1
:
    dex
    bne @run
    beq @next
@done:
    rts
.endproc

.proc read_byte
    lda (vis_source),y
    inc vis_source
    bne :+
    inc vis_source+1
:
    cmp #0
    rts
.endproc

.proc visual_tick
    lda song_done
    beq :+
    jmp @rest
:
    lda mouth_open
    and #15
    lsr
    sta vis_open
    lda voice_shape
    and #7
    asl
    asl
    asl
    ora vis_open
    tax
    DRAW_MOUTH
    lda vis_open
    bne :+
    jmp @quiet
:
    ; Only the low clock byte is needed: 16 phases wrap exactly every 128 ticks.
    lda play_tick
    lsr
    lsr
    lsr
    clc
    adc phrase_index
    and #15
    sta vis_phase
    PAINT_BREATH
    rts
@rest:
    ldx #0
    DRAW_MOUTH
@quiet:
    QUIET_BREATH
    rts
.endproc

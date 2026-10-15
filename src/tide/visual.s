; TESSELLATED TIDE - geometric, hires character accompaniment.
; Main-thread only; the SID IRQ owns no state or scratch in this module.
; Screen $4000, charset $4800, hires black background, no sprites/raster tricks.
; Call visual_tick at approximately 25 Hz. It does bounded direct color stores
; to 200 ribbon cells; title and footer never change. Input energy is 0..15.
; Current generated art: under 1,500 CPU cycles per tick (excluding IRQ/DMA),
; 2,658 bytes CODE+RODATA, 3 bytes BSS, 4 bytes main-owned ZP.
.setcpu "6502"

.export visual_init, visual_tick
.import play_tick, voice_energy, section_index, song_done

.segment "ZEROPAGE"
vis_source: .res 2
vis_dest:   .res 2

.segment "BSS"
vis_phase:  .res 1
vis_energy: .res 1
vis_tick_hi:.res 1

.segment "RODATA"
.include "art.inc"

strand_palette:
    .byte 9,9,8,8,7,7,1,1
    .byte 6,6,14,14,3,3,1,1
    .byte 11,11,12,12,15,15,1,1

.segment "CODE"
.proc visual_init
    lda #0
    sta $d011                    ; prepare with display off
    sta $d015                    ; no sprites or inherited sprite state
    sta $d020
    sta $d021
    sta $d022
    sta $d023
    sta vis_phase
    sta vis_energy
    sta vis_tick_hi
    ldx #0
@clear_charset:
    .repeat 8, page
        sta $4800+page*$100,x
    .endrepeat
    inx
    bne @clear_charset

    ; Preserve serial-port pins and their data direction.
    lda $dd02
    ora #3
    sta $dd02
    lda $dd00
    and #$fc
    ora #2
    sta $dd00
    lda #$02
    sta $d018                    ; bank + $0000 screen, bank + $0800 font
    lda #$08
    sta $d016                    ; 40 columns, ordinary hires characters

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
    lda #$1b                    ; 25 rows, display enabled, ordinary text
    sta $d011
    rts
.endproc

; (count,value) runs, with zero count terminator. Init only, exact 1000 cells.
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
    ; INC modifies N/Z; unpack branches on the returned byte.
    cmp #0
    rts
.endproc

.proc visual_tick
    ; Stable 16-bit music clock snapshot; phase advances once per 8 ticks.
@clock:
    lda play_tick+1
    sta vis_tick_hi
    lda play_tick
    lsr
    lsr
    lsr
    sta vis_phase
    lda play_tick+1
    cmp vis_tick_hi
    bne @clock
    lda vis_tick_hi
    and #1
    .repeat 5
        asl
    .endrepeat
    ora vis_phase
    sta vis_phase
    lda section_index
    asl
    asl
    asl
    clc
    adc vis_phase
    and #63
    sta vis_phase

    ldx #0
    jsr energy
    PAINT_STRAND_0
    ldx #1
    jsr energy
    PAINT_STRAND_1
    ldx #2
    jsr energy
    PAINT_STRAND_2
    rts
.endproc

.proc energy
    lda song_done
    bne @quiet
    lda voice_energy,x
    lsr
    lsr
    sta vis_energy
    rts
@quiet:
    lda #0
    sta vis_energy
    rts
.endproc

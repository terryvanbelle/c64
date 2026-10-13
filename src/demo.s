.setcpu "6502"

message_ptr = $02
screen_ptr  = $04
color_ptr   = $06
line_color  = $08

.segment "BASIC"
    .word basic_end
    .word 10
    .byte $9e
    .byte "2061", 0
basic_end:
    .word 0

.segment "CODE"
start:
    sei
    cld

    ; Clear the screen and color RAM, four pages at a time.
    ldx #$00
    lda #$20
clear_screen:
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    inx
    bne clear_screen

    ldx #$00
    lda #$01
clear_colors:
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    inx
    bne clear_colors

    lda #$06
    sta $d021
    sta $d020

    lda #<title_text
    sta message_ptr
    lda #>title_text
    sta message_ptr+1
    lda #<$0574
    sta screen_ptr
    lda #>$0574
    sta screen_ptr+1
    lda #<$d974
    sta color_ptr
    lda #>$d974
    sta color_ptr+1
    lda #$0e
    sta line_color
    jsr draw_line

    lda #<tool_text
    sta message_ptr
    lda #>tool_text
    sta message_ptr+1
    lda #<$05c6
    sta screen_ptr
    lda #>$05c6
    sta screen_ptr+1
    lda #<$d9c6
    sta color_ptr
    lda #>$d9c6
    sta color_ptr+1
    lda #$07
    sta line_color
    jsr draw_line

    lda #<footer_text
    sta message_ptr
    lda #>footer_text
    sta message_ptr+1
    lda #<$0614
    sta screen_ptr
    lda #>$0614
    sta screen_ptr+1
    lda #<$da14
    sta color_ptr
    lda #>$da14
    sta color_ptr+1
    lda #$0d
    sta line_color
    jsr draw_line

    lda #$00
    sta border_index

border_loop:
    ldx border_index
    lda border_colors,x
    sta $d020
    inx
    txa
    and #$0f
    sta border_index
    jsr frame_delay
    jmp border_loop

draw_line:
    ldy #$00
draw_line_loop:
    lda (message_ptr),y
    beq draw_line_done
    sta (screen_ptr),y
    lda line_color
    sta (color_ptr),y
    iny
    bne draw_line_loop
draw_line_done:
    rts

frame_delay:
    ldx #$00
frame_delay_outer:
    ldy #$00
frame_delay_inner:
    dey
    bne frame_delay_inner
    dex
    bne frame_delay_outer
    rts

.segment "RODATA"
title_text:
    .byte $03, $36, $34, $20, $03, $0c, $0f, $15, $04, $20, $02, $15, $09, $0c, $04, 0
tool_text:
    .byte $03, $01, $36, $35, $20, $2b, $20, $16, $09, $03, $05, 0
footer_text:
    .byte $0c, $09, $16, $05, $20, $0f, $0e, $20, $19, $0f, $15, $12, $20, $0d, $01, $03, 0

border_index:
    .byte $00
border_colors:
    .byte $06, $0e, $03, $0b, $01, $0f, $08, $0a
    .byte $02, $0d, $05, $0c, $07, $04, $09, $0e

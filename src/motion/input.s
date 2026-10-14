; BORROWED MOTION: stock C64 keyboard and joystick port 2.
; Main-thread ABI; A/X/flags clobbered, Y preserved, no zero page or KERNAL.
; input_init owns CIA1 ports, disables timer PB6/PB7 output and primes edges.
; input_poll returns held input in A; exports held and newly pressed bytes.
; Controls: W/up=1, S/down=2, A/left=4, D/right=8, Space/fire=16.
; Menu: Return=1, R=2, H=4, RUN/STOP (VICE Escape)=8, M=16, Q=32.
; Both real cursor keys work; either Shift reverses their direction.
; Opposing directions cancel. Menus require raw controls released: WASD chords
; can otherwise ghost R through the physical keyboard matrix.
; Both ports finish as inputs with $FF latches. Selected keyboard columns only
; drive LOW, so a joystick contact never opposes a driven-high CIA output.
; Port-1 grounded rows are excluded before keyboard decoding. Mixed keyboard /
; joystick chords cannot all be distinguished by stock C64 hardware.
; CIA1 ports must not be accessed concurrently. BSS: 16 bytes, initialized here.
.setcpu "6502"
.export input_init,input_poll,input_controls,input_pressed,menu_keys,menu_pressed

PA=$dc00
PB=$dc01
DDRA=$dc02
DDRB=$dc03

.segment "BSS"
input_controls: .res 1
input_pressed: .res 1
menu_keys: .res 1
menu_pressed: .res 1
previous_controls: .res 1
previous_menu: .res 1
input_baseline: .res 1
input_matrix: .res 8
raw_controls: .res 1

.segment "RODATA"
input_columns: .byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

.macro KEY column,mask,destination,value
    lda input_matrix+column
    and #mask
    beq :+
    lda destination
    ora #value
    sta destination
:
.endmacro

.segment "CODE"
.proc input_init
    lda $dc0e
    and #$fd
    sta $dc0e
    lda $dc0f
    and #$fd
    sta $dc0f
    lda #0
    sta previous_controls
    sta previous_menu
    jsr input_poll
    lda #0
    sta input_pressed
    sta menu_pressed
    rts
.endproc

.proc input_poll
    lda #0
    sta DDRA
    sta DDRB
    sta menu_keys
    lda #$ff
    sta PA
    sta PB
    lda PA
    eor #$ff
    and #$1f
    sta input_controls
    lda PB
    sta input_baseline
    ldx #0
scan:
    lda input_columns,x
    sta PA
    eor #$ff
    sta DDRA
    lda PB
    eor #$ff
    and input_baseline
    sta input_matrix,x
    lda #0
    sta DDRA
    inx
    cpx #8
    bne scan
    lda #$ff
    sta PA
    KEY 1,$02,input_controls,1
    KEY 1,$20,input_controls,2
    KEY 1,$04,input_controls,4
    KEY 2,$04,input_controls,8
    KEY 7,$10,input_controls,16
    lda input_matrix+1
    and #$80
    bne shifted
    lda input_matrix+6
    and #$10
    bne shifted
    KEY 0,$80,input_controls,2
    KEY 0,$04,input_controls,8
    jmp directions
shifted:
    KEY 0,$80,input_controls,1
    KEY 0,$04,input_controls,4
directions:
    lda input_controls
    sta raw_controls
    and #3
    cmp #3
    bne horizontal
    lda input_controls
    and #$fc
    sta input_controls
horizontal:
    lda input_controls
    and #12
    cmp #12
    bne menus
    lda input_controls
    and #$f3
    sta input_controls
menus:
    lda raw_controls
    bne edges
    KEY 0,$02,menu_keys,1
    KEY 2,$02,menu_keys,2
    KEY 3,$20,menu_keys,4
    KEY 7,$80,menu_keys,8
    KEY 4,$10,menu_keys,16
    KEY 7,$40,menu_keys,32
edges:
    lda previous_controls
    eor #$ff
    and input_controls
    sta input_pressed
    lda input_controls
    sta previous_controls
    lda previous_menu
    eor #$ff
    and menu_keys
    sta menu_pressed
    lda menu_keys
    sta previous_menu
    lda input_controls
    rts
.endproc

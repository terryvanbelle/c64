; Atlas input, using the stock C64 keyboard matrix and joystick port 2.
;
; ABI: input_poll returns the current held controls in A:
;   bit 0 up, bit 1 down, bit 2 left, bit 3 right,
;   bit 4 Space/joystick fire, bit 5 N (new world).
; Caller derives single presses as held & ~previous for the two actions.
; Clobbers A/X and flags; preserves Y. No zero page, no KERNAL service.
; Call only from main, with I/O visible and CIA1 port ownership held by Atlas.
; Leaves DC00=$FF, DC01=$FF, DC02=$00, DC03=$00. CIA IRQ state is untouched.
;
; Only a selected Port A line becomes an output, always driving low. All other
; lines remain inputs, so held joystick contacts never fight an output high.
; The baseline Port B levels exclude rows grounded through joystick contacts
; before a column is selected; this suppresses false keyboard controls caused
; by the shared wiring. Some simultaneous keyboard/joystick chords cannot be
; distinguished electrically; joystick directions themselves remain sampled.
;
; Matrix coordinates and shared joystick wiring checked against:
; https://c64os.com/post/howthekeyboardworks
; CIA DDR semantics: MOS 6526 datasheet, as linked in TIPS_AND_TRICKS.md.

.setcpu "6502"
.export input_poll

CIA1_PA = $dc00
CIA1_PB = $dc01
CIA1_DDRA = $dc02
CIA1_DDRB = $dc03

UP = $01
DOWN = $02
LEFT = $04
RIGHT = $08
ACTION = $10
NEW_WORLD = $20

.segment "BSS"
input_held:     .res 1
input_baseline: .res 1
input_matrix:   .res 8

.segment "RODATA"
input_columns:
    .byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

.macro ADD_KEY column, rowbit, control
    lda input_matrix+column
    and #rowbit
    beq :+
    lda input_held
    ora #control
    sta input_held
:
.endmacro

.segment "CODE"
.proc input_poll
    ; Read port 2 with both ports as inputs and both output latches high.
    ; State is established on every call; no BSS initialization is required.
    lda #0
    sta CIA1_DDRA
    sta CIA1_DDRB
    lda #$ff
    sta CIA1_PA
    sta CIA1_PB
    lda CIA1_PA
    eor #$ff
    and #$1f
    sta input_held
    lda CIA1_PB
    sta input_baseline

    ldx #0
scan_column:
    ; Change the latch while all pins are inputs, then enable the sole low
    ; output. The intervening CPU cycles also allow the matrix lines to settle.
    lda input_columns,x
    sta CIA1_PA
    eor #$ff
    sta CIA1_DDRA
    lda CIA1_PB
    eor #$ff
    and input_baseline
    sta input_matrix,x
    lda #0
    sta CIA1_DDRA
    inx
    cpx #8
    bne scan_column

    ; W/A/S in column 1; D in column 2.
    ADD_KEY 1, $02, UP
    ADD_KEY 1, $04, LEFT
    ADD_KEY 1, $20, DOWN
    ADD_KEY 2, $04, RIGHT
    ; I/J/K in column 4; L in column 5.
    ADD_KEY 4, $02, UP
    ADD_KEY 4, $04, LEFT
    ADD_KEY 4, $20, DOWN
    ADD_KEY 5, $04, RIGHT
    ADD_KEY 7, $10, ACTION
    ADD_KEY 4, $80, NEW_WORLD

    ; The real C64 has two cursor keys. Shift reverses down/right to up/left.
    ; Shift Lock is electrically identical to Left Shift.
    lda input_matrix+1
    and #$80
    bne shifted_cursors
    lda input_matrix+6
    and #$10
    bne shifted_cursors
    ADD_KEY 0, $80, DOWN
    ADD_KEY 0, $04, RIGHT
    jmp finish
shifted_cursors:
    ADD_KEY 0, $80, UP
    ADD_KEY 0, $04, LEFT
finish:
    lda #$ff
    sta CIA1_PA
    lda input_held
    rts
.endproc

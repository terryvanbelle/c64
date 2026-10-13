; Dual-player input for an unexpanded C64. Game IRQ ownership only.
;
; ABI:
;   input_mode = 0: shared keyboard, 1: two joysticks.
;   duel_input_poll updates dual_controls[0..1] with held directions/fire.
;     P1 = joystick port 2 OR W/A/S/D + X, according to input_mode.
;     P2 = joystick port 1 OR U/B/N/M + period, according to input_mode.
;       U = up, B = left, N = down, M = right.
;     bits: up $01, down $02, left $04, right $08, fire $10.
;   menu_controls = Return or RUN/STOP $01 during keyboard play; RUN/STOP $01
;     during joystick play. The game uses this bit for start/pause/resume/replay.
;   duel_menu_poll scans the title/results keyboard regardless of input_mode:
;     Return or RUN/STOP $01, F1 $02, K $08, J $10, C $20, H $40.
;     C selects a computer gold army; H selects a human gold army.
;     Returns menu_controls in A. The engine accepts F1/K/J/C/H only with
;     gameplay controls released, because their matrix paths may ghost.
;     It leaves the previous dual_controls unchanged; use duel_input_poll to
;     sample fire when a joystick-driven menu should accept fire as well. Save
;     the returned menu byte before duel_input_poll, which replaces it with
;     the live-play menu controls. This permits menu-first sampling in the IRQ.
;   Both routines clobber A/X/flags and preserve Y. No zero-page scratch.
;   Caller derives presses as held AND NOT previous. Initialize input_mode
;   explicitly at startup; other working state is reset by every poll.
;
; Live joystick mode snapshots both sticks while both CIA ports are inputs,
; then scans only column 7 for RUN/STOP. That bit is unrelated to joystick
; Port A bits 0..4, and RUN/STOP's Port B row 7 is unrelated to the second
; stick's bits 0..4. The scan cannot change the already sampled stick bytes.
; Keyboard mode is a separate choice, not ORed together with joystick values.
; Release joystick contacts while using keyboard mode.
;
; Only the selected keyboard column is an output and is always low. There is
; never a driven-high pin opposing a held joystick contact. The baseline masks
; row pins already low before scanning. The physical C64 keyboard has no matrix
; diodes, so arbitrary multi-key chords can ghost. These ten control switches
; form a tree in the matrix wiring, so no combination of only these controls
; can produce a phantom mapped control. Other keys held at the same time may
; introduce ghost paths. Return/F1 use a separate column from the controls,
; and RUN/STOP adds a leaf at column 7 to the keyboard controls' matrix tree.
; Controls are deliberately held-state controls, without KERNAL repeat delays.
;
; I/O must be visible and CIA1 port ownership must belong to the game. Both
; routines leave DC00/DC01=$FF and DC02/DC03=$00. CIA IRQ state is untouched.
; Main and other handlers must not scan or modify these four ports. These
; routines are not reentrant; the normal IRQ registers must be saved by caller.
;
; Matrix and shared joystick wiring checked against the firsthand circuit
; investigation linked by TIPS_AND_TRICKS.md:
; https://c64os.com/post/howthekeyboardworks
; DDR semantics: MOS 6526 datasheet, also linked by that reference.

.setcpu "6502"
.export duel_input_poll, duel_menu_poll
.export dual_controls, duel_controls, input_mode, menu_controls

CIA1_PA   = $dc00
CIA1_PB   = $dc01
CIA1_DDRA = $dc02
CIA1_DDRB = $dc03

UP    = $01
DOWN  = $02
LEFT  = $04
RIGHT = $08
FIRE  = $10

MENU_START    = $01
MENU_NEW      = $02
MENU_KEYBOARD = $08
MENU_JOYSTICK = $10
MENU_COMPUTER = $20
MENU_HUMAN    = $40

.segment "BSS"
dual_controls:  .res 2
duel_controls = dual_controls
input_mode:     .res 1
menu_controls:  .res 1
input_baseline: .res 1
input_matrix:   .res 8

.segment "RODATA"
input_columns:
    .byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

.macro ADD_KEY column, rowbit, destination, control
    lda input_matrix+column
    and #rowbit
    beq :+
    lda destination
    ora #control
    sta destination
:
.endmacro

.segment "CODE"
.proc ports_to_inputs
    ; Change DDRs before changing latches: no high output is ever driven.
    lda #0
    sta CIA1_DDRA
    sta CIA1_DDRB
    lda #$ff
    sta CIA1_PA
    sta CIA1_PB
    rts
.endproc

.proc scan_keyboard
    jsr ports_to_inputs
    lda CIA1_PB
    sta input_baseline
    ldx #0
column_loop:
    ; Set the latch with all pins still inputs, then enable only the low bit.
    ; The EOR/STA plus read cycles give the lines time to settle.
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
    bne column_loop
    lda #$ff
    sta CIA1_PA
    rts
.endproc

.proc decode_common_menu
    ADD_KEY 0, $02, menu_controls, MENU_START
    ADD_KEY 7, $80, menu_controls, MENU_START
    ADD_KEY 0, $10, menu_controls, MENU_NEW
    rts
.endproc

.proc duel_input_poll
    lda #0
    sta dual_controls
    sta dual_controls+1
    sta menu_controls
    lda input_mode
    beq keyboard

    jsr ports_to_inputs
    ; Joystick bits are active low. Sample both before the RUN/STOP-only scan.
    lda CIA1_PA
    eor #$ff
    and #$1f
    sta dual_controls
    lda CIA1_PB
    eor #$ff
    and #$1f
    sta dual_controls+1

    ; Both ports are still inputs with high latches. A grounded joystick pin
    ; cannot reach PB7 without an additional closed key switch. Exclude PB7
    ; if it is already low through such a switch before selecting RUN/STOP.
    lda CIA1_PB
    sta input_baseline
    lda #$7f
    sta CIA1_PA
    lda #$80
    sta CIA1_DDRA
    lda CIA1_PB
    eor #$ff
    and input_baseline
    and #$80
    beq no_runstop
    lda #MENU_START
    sta menu_controls
no_runstop:
    lda #0
    sta CIA1_DDRA
    lda #$ff
    sta CIA1_PA
    rts

keyboard:
    jsr scan_keyboard
    ADD_KEY 1, $02, dual_controls,   UP       ; W
    ADD_KEY 1, $20, dual_controls,   DOWN     ; S
    ADD_KEY 1, $04, dual_controls,   LEFT     ; A
    ADD_KEY 2, $04, dual_controls,   RIGHT    ; D
    ADD_KEY 2, $80, dual_controls,   FIRE     ; X
    ADD_KEY 3, $40, dual_controls+1, UP       ; U
    ADD_KEY 4, $80, dual_controls+1, DOWN     ; N
    ADD_KEY 3, $10, dual_controls+1, LEFT     ; B
    ADD_KEY 4, $10, dual_controls+1, RIGHT    ; M
    ADD_KEY 5, $10, dual_controls+1, FIRE     ; period
    ADD_KEY 0, $02, menu_controls, MENU_START
    ADD_KEY 7, $80, menu_controls, MENU_START
    rts
.endproc

.proc duel_menu_poll
    lda #0
    sta menu_controls
    jsr scan_keyboard
    jsr decode_common_menu
    ADD_KEY 4, $20, menu_controls, MENU_KEYBOARD  ; K
    ADD_KEY 4, $04, menu_controls, MENU_JOYSTICK  ; J
    ADD_KEY 2, $10, menu_controls, MENU_COMPUTER  ; C
    ADD_KEY 3, $20, menu_controls, MENU_HUMAN     ; H
    lda menu_controls
    rts
.endproc

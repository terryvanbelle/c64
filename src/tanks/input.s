; IRONVEIL: stock-C64 keyboard and one-button joystick controls.
;
; IRQ-only ABI, A/X/flags clobbered, Y preserved, no zero-page scratch:
; input_mode 0 = keyboard, 1 = two physical joysticks.
; duel_input_poll updates dual_controls[2]: forward1, reverse2, hull-left4,
; hull-right8, fire16, turret-left32, turret-right64.
;
; Keyboard P1: WASD = map north/west/south/east, Q/2 turret, X fire.
; Keyboard P2: UBNM = map north/west/south/east, semicolon/Return turret,
; period fire. Opposing directions cancel on each axis; two remaining axes
; select a diagonal. Turn the hull along the shortest route, then drive forward
; once aligned. An exact half-turn chooses clockwise. The game still owns its
; ordinary hull-turn gate, physical speed, terrain and collision rules.
; Fully canceled movement emits neutral forward+reverse (3): the game rejects
; that throttle pair, while menus still see that gameplay keys are being held.
; These fourteen gameplay switches form a matrix tree. Key 1 adds its final
; leaf, providing an unambiguous common keyboard pause without mapped ghosts.
; Use VICE's default symbolic map: its semicolon is physical C64 PA6/PB2.
;
; Joysticks: P1 port2, P2 port1. Button released: stick controls throttle/hull.
; Hold button: left/right rotate the turret, throttle/hull are zero. Releasing
; button emits one FIRE pulse; movement may resume on that same sample. Only
; the actual button transition creates this pulse. Keyboard polls clear joystick
; button history, preventing stale release pulses after a control-mode switch.
;
; menu_controls: live keyboard key1=$01 pause; live joystick RUN/STOP=$01 pause.
; duel_menu_poll scans title/results regardless of mode and returns menu_controls
; in A: Return/RUNSTOP=$01, F1=$02, K=$08, J=$10, C=$20, H=$40.
; It separately updates menu_difficulty: key1=$01, key2=$02, key3=$04.
; Snapshot menu bytes before live poll, which replaces menu_controls only.
; The engine gates admin keys while gameplay controls are held. Title key2 is
; also P1 turret-right: exempt that matching bit only when choosing difficulty2.
;
; Both ports return to inputs, latches $FF. Only a selected low column is ever
; driven; never fight a joystick contact with a driven-high output. Joystick
; sampling precedes the RUN/STOP-only scan; PB7 is outside stick bits0..4.
; Main/other handlers must not touch CIA1 ports or reenter these routines.
; Matrix checked against official installed VICE keymaps and the circuit study:
; https://c64os.com/post/howthekeyboardworks

.setcpu "6502"
.export duel_input_poll, duel_menu_poll
.export dual_controls, duel_controls, tank_controls
.export input_mode, menu_controls, menu_difficulty
.import hull

CIA1_PA=$dc00
CIA1_PB=$dc01
CIA1_DDRA=$dc02
CIA1_DDRB=$dc03

.segment "BSS"
dual_controls: .res 2
duel_controls = dual_controls
tank_controls = dual_controls
input_mode: .res 1
menu_controls: .res 1
menu_difficulty: .res 1
input_baseline: .res 1
input_matrix: .res 8
joy_raw: .res 1
joy_button_previous: .res 2

.segment "RODATA"
input_columns: .byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
; Index: raw map-direction nibble N1/S2/W4/E8. Opposite axes cancel.
keyboard_headings:
    .byte $ff,0,4,$ff,6,7,5,6,2,1,3,2,$ff,0,4,$ff
; Index: (desired heading - current hull) & 7. Forward only when aligned.
keyboard_turns:
    .byte 1,8,8,8,8,4,4,4

.macro ADD_KEY column, rowbit, destination, control
    lda input_matrix+column
    and #rowbit
    beq :+
    lda destination
    ora #control
    sta destination
:
.endmacro

; Preserve turret/fire, convert only the map-direction nibble. No extra state:
; every poll responds to the current hull, including the first resumed tick.
; Neutral opposing throttle keeps the engine's held-control admin gate intact.
.macro MAP_DIRECTION player
    .local idle, done
    lda dual_controls+player
    and #15
    tax
    lda dual_controls+player
    and #$70
    sta dual_controls+player
    lda keyboard_headings,x
    bmi idle
    sec
    sbc hull+player
    and #7
    tax
    lda keyboard_turns,x
    ora dual_controls+player
    sta dual_controls+player
    jmp done
idle:
    cpx #0
    beq done
    lda dual_controls+player
    ora #3
    sta dual_controls+player
done:
.endmacro

.segment "CODE"
.proc ports_to_inputs
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
@column:
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
    bne @column
    lda #$ff
    sta CIA1_PA
    rts
.endproc

; A=normalized physical stick bits0..4, X=player. Preserve X/Y.
.proc decode_joystick
    sta joy_raw
    and #16
    beq @released
    sta joy_button_previous,x
    lda joy_raw
    and #12
    asl
    asl
    asl
    sta dual_controls,x
    rts
@released:
    lda joy_raw
    and #15
    sta dual_controls,x
    lda joy_button_previous,x
    beq @done
    lda dual_controls,x
    ora #16
    sta dual_controls,x
    lda #0
    sta joy_button_previous,x
@done:
    rts
.endproc

.proc duel_input_poll
    lda #0
    sta dual_controls
    sta dual_controls+1
    sta menu_controls
    lda input_mode
    beq @keyboard
    jsr ports_to_inputs
    ldx #0
    lda CIA1_PA
    eor #$ff
    and #31
    jsr decode_joystick
    inx
    lda CIA1_PB
    eor #$ff
    and #31
    jsr decode_joystick
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
    beq :+
    lda #1
    sta menu_controls
:
    lda #0
    sta CIA1_DDRA
    lda #$ff
    sta CIA1_PA
    rts
@keyboard:
    lda #0
    sta joy_button_previous
    sta joy_button_previous+1
    jsr scan_keyboard
    ADD_KEY 1,$02,dual_controls,1       ; W
    ADD_KEY 1,$20,dual_controls,2       ; S
    ADD_KEY 1,$04,dual_controls,4       ; A
    ADD_KEY 2,$04,dual_controls,8       ; D
    ADD_KEY 2,$80,dual_controls,16      ; X
    ADD_KEY 7,$40,dual_controls,32      ; Q
    ADD_KEY 7,$08,dual_controls,64      ; 2
    ADD_KEY 3,$40,dual_controls+1,1     ; U
    ADD_KEY 4,$80,dual_controls+1,2     ; N
    ADD_KEY 3,$10,dual_controls+1,4     ; B
    ADD_KEY 4,$10,dual_controls+1,8     ; M
    ADD_KEY 5,$10,dual_controls+1,16    ; period
    ADD_KEY 6,$04,dual_controls+1,32    ; semicolon
    ADD_KEY 0,$02,dual_controls+1,64    ; Return
    ADD_KEY 7,$01,menu_controls,1       ; common keyboard pause: 1
    MAP_DIRECTION 0
    MAP_DIRECTION 1
    rts
.endproc

.proc duel_menu_poll
    lda #0
    sta menu_controls
    sta menu_difficulty
    jsr scan_keyboard
    ADD_KEY 0,$02,menu_controls,$01    ; Return
    ADD_KEY 7,$80,menu_controls,$01    ; RUN/STOP
    ADD_KEY 0,$10,menu_controls,$02    ; F1
    ADD_KEY 4,$20,menu_controls,$08    ; K
    ADD_KEY 4,$04,menu_controls,$10    ; J
    ADD_KEY 2,$10,menu_controls,$20    ; C
    ADD_KEY 3,$20,menu_controls,$40    ; H
    ADD_KEY 7,$01,menu_difficulty,$01  ; 1: Easy
    ADD_KEY 7,$08,menu_difficulty,$02  ; 2: Medium
    ADD_KEY 1,$01,menu_difficulty,$04  ; 3: Hard
    lda menu_controls
    rts
.endproc

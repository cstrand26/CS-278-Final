; compile with:
; gavrasm.exe -b main.asm
; 
; upload with:
; avrdude -c arduino -p atmega328p -P COM4 -U main.hex
;
.DEVICE ATmega328p ;Define the correct device
.EQU STACK_SRAM = $08FF ; Starting location of stack
.EQU BUZZER_1 = $0100 ; Temp value for buzzer 1
.EQU BUZZER_2 = $0101 ; Temp value for buzzer 2
.EQU SCALE = $0102 ; For carrying the value of the current scale
.EQU COUNTER_1 = $0103 ; For keeping offset for buzzer_1
.EQU COUNTER_2 = $0104 ; For keeping offset for buzzer_2
.EQU TICK_NEEDED = $0105 ; For keeping track of the preset tick amount before ending note
.EQU TICK_CURRENT_1 = $0106 ; For keeping track of current tick count for buzzer 1
.EQU TICK_CURRENT_2 = $107 ; For keeping track of current tick count for buzzer 2
.EQU TIMER_OFFSET = $0108 ; The current offset for
.EQU BUZZER_2_SIZE = $0109 ; Stores the size of Buzzer 2, for looping
.EQU BUZZER_2_CURRENT = $010A ; Stores the current position in the loop for Buzzer 2
.EQU BUZZER_2_OFFSETS = $010B ; Starting location for list of offsets for Buzzer 2
.cseg
.org 000000
	rjmp begin ; Reset vector
	nop
	reti ; INT0
	nop
	reti ; INT1
	nop
	reti ; PCI0
	nop
	reti ; PCI1
	nop
	reti ; PCI2
	nop
	reti ; WDT
	nop
	reti ; OC2A
	nop
	reti ; OC2B
	nop
	reti ; OVF2
	nop
	reti ; ICP1
	nop
	reti ; OC1A
	nop
	reti ; OC1B
	nop
	reti ; OVF1
	nop
	reti ; OC0A
	nop
	reti ; OC0B
	nop
	reti ; OVF0
	nop
	reti ; SPI
	nop
	rjmp intr_urx ; URXC
	nop
	reti ; UDRE
	nop
	reti ; UTXC
	nop
	reti ; ADCC
	nop
	reti ; ERDY
	nop
	reti ; ACI
	nop
	reti ; TWI
	nop
	reti ; SPMR
	nop
intr_urx: ; interupt for receiving data through usart
    push r16 ; store register
	lds r16, UDR0 ; Load data received
	call interpret_ascii ; loads counter or scale based on ascii value
	call serial_send ; Send it back through USART
    pop r16 ; restore register
    reti ;
begin: ; the beginning
    ; Setting stack pointer
	ldi r20, HIGH(STACK_SRAM) ; Set high part of stack pointer
    out SPH, r20 ;
    ldi r20, LOW(STACK_SRAM) ; Set low part of stack pointer
    out SPL, r20 ;
	;
	; PortD, PortC and PortB set up
	ldi r20, (1<<PD6) ; DDRD - data direction (PIN 6 output, PINS 7 and 0-5 input) OC0A is PORTD:6
	out DDRD, r20 ; Send configuration
	ldi r20, (1<<PB3) ; DDRB - data direction (PIN 3 output, PINS 4-7 and 0-2 input) OC2A is PORTB:3
	out DDRB, r20 ; Send configuration
	ldi r20, $00 ; DDRC - data direction (all PINS input)
	out DDRC, r20 ; Send configuration
	;
	; set up counter 0
	; set up change toggle on compare match COM0A1 and COM0A0
	; set up clear timer on compare match WGM01 and WGM00
	ldi r20, (0<<COM0A1)|(1<<COM0A0)|(1<<WGM01)|(0<<WGM00) 
	out TCCR0A, r20 ; for counter 0
	; set up clock select for prescaler CS02, CS01, and CS00 to /256
	ldi r20, (1<<CS02)|(0<<CS01)|(0<<CS00)
	out TCCR0B, r20
	;
	; set up counter 2
	; set up change toggle on compare match COM2A1 and COM2A0
	; set up clear timer on compare match WGM21 and WGM20
	ldi r20, (0<<COM2A1)|(1<<COM2A0)|(1<<WGM21)|(0<<WGM20) 
	sts TCCR2A, r20 ; for counter 2
	; set up clock select for prescaler CS22, CS21, and CS20 to /256
	ldi r20, (1<<CS22)|(1<<CS21)|(0<<CS20)
	sts TCCR2B, r20
	;
	; set up counter 1
	ldi r20, $03 | (1<<WGM12); Setting clock select to clk/128 from IO clock (16MHz >> ~16Khz) + WGM12 set high
	sts TCCR1B, r20 ; write to Timer/Counter1 Control Register B
	; speed for the opener
	ldi r20, $7D ; upper part of 16bit number
	sts OCR1AH, r20 ; write upper first
	ldi r20, $00 ; lower part of 16bit number
	sts OCR1AL, r20 ; write lower (and temp) second
	; calls fun opening music
	call zelda_unlock_start
	; sets number of ticks needed to call the metronome function
	ldi r20, $7F ; should call the needed function every 64 ticks
	sts TICK_NEEDED, r20
	; change length of notes for actual keyboard
	ldi ZL, LOW(TIMER_SPEED*2) ; load in address into Z
	ldi ZH, HIGH(TIMER_SPEED*2)
	lpm r20, Z+ ; upper part of 16bit number
	sts OCR1AH, r20 ; write upper first
	lpm r20, Z ; lower part of 16bit number
	sts OCR1AL, r20 ; write lower (and temp) second

	; clear counters and scale at reboot cause they save for some reason
	clr r20
	sts COUNTER_1, r20
	sts COUNTER_2, r20
	sts SCALE, r20
	sts TICK_CURRENT_1, r20
	sts TICK_CURRENT_2, r20
	sts BUZZER_2_SIZE, r20
	sts BUZZER_2_CURRENT, r20
	sts TIMER_OFFSET, r20
	;
    call usart_init ; initialize usart communication
	;
    sei ; turn on global interrupts
motherloop: ; the loop where everything happens. Leave r19, r20, and r21 alone for note_check
	; note check
	call note_check ; compares r19, r20, and r21 to Scale, Counter 1, and Counter 2, changes notes and resets ticks if necessary
	; output to buzzer 1
	lds r16, BUZZER_1 ; load stored buzzer freq
	out OCR0A, r16 ; send it
	; output to buzzer 2
	lds r16, BUZZER_2 ; load stored buzzer freq
	sts OCR2A, r16 ; send it
	sbis TIFR1, OCF1A ; skip if bit in Timer/Counter Interrupt Flag register is clear
	rjmp motherloop
	sbi TIFR1, OCF1A ; Set timer compare bit (should clear it)
	lds r16, TICK_CURRENT_1 ; load tick for ending buzzer 1
	lds r17, TICK_NEEDED ; load in metronome 
	cp r16, r17 ; if we've reached enough ticks
	breq metronome_1 ; jump to clear counter_1
motherloop_next:
	lds r16, TICK_CURRENT_2 ; load tick for transitioning buzzer 2
	cp r16, r17 ; if we've reached enough ticks
	breq metronome_2 ; jump to transition counter_2
motherloop_end:	
	call next_tick ; moves the ticks of both counters forward 1
	rjmp motherloop ; heads back to begining
;
metronome_1: ; called if the predetermined number of ticks have occurred
	push r16 ; store
	clr r16 ; insures it's cleared
	sts COUNTER_1, r16 ; sets offset for buzzer 1 to $00
	pop r16 ; restore
	rjmp motherloop_next ; head to next check
;
metronome_2:
	call buzzer_2_loop ; moves counter 2 to next note in loop
	rjmp motherloop_end ; jumps back to end
next_tick: ; checks how many ticks have happened
	push r16 ; store
	push r17
	lds r16, TICK_CURRENT_1 ; how many ticks have occurred
	lds r17, TICK_NEEDED ; how many ticks before reset
	inc r16 ; increase
	cp r17, r16 
	brlo reset_tick_1 ; if we've reached the point to reset TICK_CURRENT_1 to 0
	sts TICK_CURRENT_1, r16 ; store value increased by 1
next_tick_2:
	lds r16, TICK_CURRENT_2 ; how many ticks have occurred
	inc r16 ; increase
	cp r17, r16
	brlo reset_tick_2 ; if we've reached the point to reset TICK_CURRENT_2 to 0
	sts TICK_CURRENT_2, r16 ; store value increased by 1
end_tick:
	pop r17
	pop r16 ; restore
	ret
reset_tick_1: 
	clr r16
	sts TICK_CURRENT_1, r16 ; reset to 0
	rjmp next_tick_2
reset_tick_2: 
	clr r16
	sts TICK_CURRENT_2, r16 ; reset to 0
	rjmp end_tick
;
usart_init: ; initializes contact with usart
    push r16 ; store registers
    push r17 ;
    ; Set baud rate
    ldi r17, $00 ; High baud (aiming for 9600bps)
    ldi r16, $67 ; Low baud
    sts UBRR0H, r17
    sts UBRR0L, r16
    ; Enable receiver and transmitter
    ldi r16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
    sts UCSR0B, r16
    ; Set frame format: 8data, 2stop bit
    ldi r16, (1<<USBS0)|(3<<UCSZ00)
    sts UCSR0C, r16
    pop r17 ; restore register
    pop r16
    ret ;
; initializes sending the data back
serial_send: ; passes in r16, sends it through USART
	push r17 ; store register
; loop that continues until the data is sent back
serial_send_loop: ;
    lds r17, UCSR0A ; pulls in status
    sbrs r17, UDRE0 ; checks flag
    rjmp serial_send_loop ; loop
	sts UDR0, r16; sends data in r16
    pop r17 ; restore register
    ret
;	
; interprets ascii value received
increase_length: ; increases length of each note
	lds r18, TIMER_OFFSET ; load in current offset value
	inc r18 ; increase by 2
	inc r18
	andi r18, $0F ; clear up nibble
	sts TIMER_OFFSET, r18 ; load in
	call change_speed ; call function that changes speed
	rjmp interpret_ascii_done ; finished
decrease_length: ; decreases legnth of each note
	lds r18, TIMER_OFFSET ; load in current offset value
	dec r18 ; decrease by 2
	dec r18
	andi r18, $0F ; clear up nibble
	sts TIMER_OFFSET, r18 ; load in
	call change_speed ; call function that changes speed
	rjmp interpret_ascii_done ; finished
space_bar:
	clr r18 ; set it to $00
	call buzzer_2_storage ; stores cleared value in buzzer_2_loop of offsets
	rjmp interpret_ascii_done	
interpret_ascii: ; pass in r16 and compare against expected ascii values
	push r17 ; store
	push ZL
	push ZH
	push r18
	push r19
	clr r19
	mov r17, r16 ; copy so r16 is not effected
	cpi r17, '+'
	breq increase_length ; for increasing timer 1 compare
	cpi r17, '-'
	breq decrease_length ; for decreasing timer 1 compare
	cpi r17, $20
	breq space_bar ; for adding cleared offset to buzzer 2 loop
	cpi r17, 'z' +1
	brsh outside_range
	cpi r17, '0'
	brlo outside_range
	cpi r17, $60
	brsh lower_case_ascii ; for buzzer 1 values and clear
	cpi r17, 'Z'+1
	brsh outside_range
	cpi r17, 'A'
	brsh upper_case_ascii ; for buzzer 2 values
	cpi r17, '9' +1
	brsh outside_range 
	subi r17, '0' ; so that r17 is 0-9
	sts SCALE, r17 ; stores that value in current scale
	rjmp interpret_ascii_done
outside_range: ; if a value outside of the expected range was given
	ldi r16, $00 
interpret_ascii_done: ; when complete
	pop r19
	pop r18
	pop ZH
	pop ZL
	pop r17 ; restore
	ret
lower_case_ascii: ; clear or buzzer 1
	cpi r17, $60 ; if the value is '`'
	breq special_clear_ascii
	subi r17, 'a' ; so that 'a' is 0 and 'z' is 25
	ldi ZL, LOW(OFFSET_LETTER_VALUE*2) ; load in address into Z
	ldi ZH, HIGH(OFFSET_LETTER_VALUE*2)
	add ZL, r17 ; move z pointer to offset
	adc ZH, r19 ; deal with overflow if memory is on an 8 bit edge
	lpm r18, Z ; load value of offset for counter from library
	sts COUNTER_1, r18
	rjmp interpret_ascii_done
special_clear_ascii: ; clears both counters, silencing both buzzers
	call clear_buzzers
	rjmp interpret_ascii_done	
upper_case_ascii: ; effects only buzzer 2
	subi r17, 'A' ; so that 'A' is 0 and 'Z' is 25
	ldi ZL, LOW(OFFSET_LETTER_VALUE*2) ; load in address into Z
	ldi ZH, HIGH(OFFSET_LETTER_VALUE*2)
	add ZL, r17 ; move z pointer to offset
	adc ZH, r19 ; deal with overflow if memory is on an 8 bit edge
	LPM r18, Z ; load value of offset for counter from library
	call buzzer_2_storage ; stores the value in a SRAM location for a loop for Buzzer 2
	rjmp interpret_ascii_done
;
note_check: ; pass in r19 (last scale), r20 (last counter_1), and r21 (last counter_2)
	push r16 ; store
	push r17
	push r18
	lds r16, SCALE ; loads scale position
	lds r17, COUNTER_1 ; loads buzzer 1 value
	lds r18, COUNTER_2 ; loads buzzer 2 value
	cpse r17, r20 ; compares previous buzzer 1 to current
	call note_change_1
	cpse r18, r21 ; compares previous buzzer 2 to current
	call note_change
	cpse r16, r19 ; compares previous scale position to current
	call note_change
	pop r18
	pop r17
	pop r16 ; restore
	ret
note_change_1:
	push r16 ; store
	clr r16 ; make sure it's clear
	sts TICK_CURRENT_1, r16 ; reset buzzer 1 tick counter
	pop r16
	rjmp note_change ; continue
note_change:
	push r22 ; store
	sts TCNT1H, r22 ; resets counter for timer 1
	sts TCNT1L, r22
	mov r19, r16 ; loads new positions into old
	mov r20, r17
	mov r21, r18
	cpse r16, r22; begin checking scales
	rjmp change_1 ; jump to the next
	call scale_0 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_1:
	inc r22
	cpse r16, r22 ;
	rjmp change_2 ; jump to the next
	call scale_1 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_2:
	inc r22
	cpse r16, r22 ;
	rjmp change_3 ; jump to the next
	call scale_2 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_3:
	inc r22
	cpse r16, r22 ;
	rjmp change_4 ; jump to the next
	call scale_3 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_4:
	inc r22
	cpse r16, r22 ;
	rjmp change_5 ; jump to the next
	call scale_4 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_5:
	inc r22
	cpse r16, r22 ;
	rjmp change_6 ; jump to the next
	call scale_5 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_6:
	inc r22
	cpse r16, r22 ;
	rjmp change_7 ; jump to the next
	call scale_6 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_7:
	inc r22
	cpse r16, r22 ;
	rjmp change_8 ; jump to the next
	call scale_7 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_8:
	inc r22
	cpse r16, r22 ;
	rjmp change_9 ; jump to the next
	call scale_8 ; change the notes according to this scale
	rjmp note_change_done ; jump to the end
change_9:
	call scale_9 ; change the notes according to this scale
note_change_done: ; complete changes
	pop r22
	ret
scale_0: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call major_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call major_c_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_6: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call pentatonic_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call pentatonic_c_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_7: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call pentatonic_b_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call pentatonic_b_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_8: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call blues_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call blues_c_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_2: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call minor_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call minor_c_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_1: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call harmonic_minor_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call  harmonic_minor_c_notes;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_5: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call major_bebop_c_notes; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call major_bebop_c_notes;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_3: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call aeolian_dominant_c_notes; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call aeolian_dominant_c_notes;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_4: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call phyrgian_dominant_c_notes ; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call phyrgian_dominant_c_notes ;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
scale_9: ; carry in r20 (counter_1) and r21 (counter_2)
	push r19
	mov r19, r20 ; load counter in
	call chromatic_notes; 
	sts BUZZER_1, r19 ; store new note
	mov r19, r21 ; load counter in
	call chromatic_notes;
	sts BUZZER_2, r19 ; store new note
	pop r19
	ret
blues_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(BLUES_SCALE_C*2) ; Load in address into Z
	ldi ZH, HIGH(BLUES_SCALE_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
major_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(MAJOR_SCALE_C*2) ; Load in address into Z
	ldi ZH, HIGH(MAJOR_SCALE_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
minor_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(MINOR_SCALE_C*2) ; Load in address into Z
	ldi ZH, HIGH(MINOR_SCALE_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
pentatonic_b_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(PENTATONIC_SCALE_B*2) ; Load in address into Z
	ldi ZH, HIGH(PENTATONIC_SCALE_B*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
pentatonic_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(PENTATONIC_SCALE_C*2) ; Load in address into Z
	ldi ZH, HIGH(PENTATONIC_SCALE_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
harmonic_minor_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(HARMONIC_MINOR_SCALE_C*2) ; Load in address into Z
	ldi ZH, HIGH(HARMONIC_MINOR_SCALE_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
chromatic_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(CHROMATIC_SCALE*2) ; Load in address into Z
	ldi ZH, HIGH(CHROMATIC_SCALE*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
major_bebop_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(MAJOR_BEBOP_C*2) ; Load in address into Z
	ldi ZH, HIGH(MAJOR_BEBOP_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
aeolian_dominant_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(AEOLIAN_DOMINANT_C*2) ; Load in address into Z
	ldi ZH, HIGH(AEOLIAN_DOMINANT_C*2)
	add ZL, r19 ; Move Z pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
phyrgian_dominant_c_notes: ; carry in r19, which should hold counter_1 or counter_2 value
	push ZL ; Store registers
	push ZH
	push r17
	clr r17
	ldi ZL, LOW(PHRYGIAN_DOMINANT_C*2) ; Load in address into X
	ldi ZH, HIGH(PHRYGIAN_DOMINANT_C*2)
	add ZL, r19 ; Move X pointer to offset
	adc ZH, r17 ; Deal with overflow if memory is on an 8 bit edge
	lpm r19, Z ; Load value from SRAM and carry out through r19
	pop r17
	pop ZH ; Restore registers
	pop ZL
	ret ; Return
zelda_unlock_start:
	push ZL ; Store registers
	push ZH
	push r16
	push r17
	push r18
	push r19
	push r20
	ldi r20, $09 ; for jumping the octave
	clr r17 ; for adc
	clr r16 ; cleared for counter
zelda_unlock:
	nop ; No op, pause / wait
	sbis TIFR1, OCF1A ; skip if bit in Timer/Counter Interrupt Flag register is set
	; TIFR1 - Timer/Counter1 Interrupt Flag Register
	; OCF1A - Timer/Counter1, Output Compare A Match Flag
	rjmp zelda_unlock ; loop back up continuously
	nop ; OCF1A Bit is set (this means counter has reached compare value)
	sbi TIFR1, OCF1A ; Set timer compare bit (should clear it)
	cpi r16, $08 ; if the final note has played
	breq zelda_unlock_end
	ldi ZL, LOW(ZELDA_UNLOCK_NOTES*2) ; load in address into Z
	ldi ZH, HIGH(ZELDA_UNLOCK_NOTES*2)
	add ZL, r16
	adc ZH, r17
	inc r16
	lpm r18, Z
	add ZL, r20 ; jump the octave
	adc ZH, r17
	lpm r19, Z ; Load value from SRAM
	out OCR0A, r18
	sts OCR2A, r19
	rjmp zelda_unlock
zelda_unlock_end:
	pop r20
	pop r19
	pop r18
	pop r17
	pop r16
	pop ZH ; Restore registers
	pop ZL
	ret
change_speed:
	push r16 ; store
	push r17
	push r18
	push r19
	push ZL
	push ZH
	clr r19 ; make sure it's actually clear
	ldi ZL, LOW(TIMER_SPEED*2) ; Load in address into Z
	ldi ZH, HIGH(TIMER_SPEED*2)
	lds r16, TIMER_OFFSET ; load offset for speed
	add ZL, r16 ; move pointer of Z
	adc ZH, r19
	lpm r17, Z+ ; load first half of speed
	lpm r18, Z ; load second half of speed
	sts OCR1AH, r17
	sts OCR1AL, r18
	pop ZH
	pop ZL
	pop r19
	pop r18
	pop r17
	pop r16 ; restore
	ret
buzzer_2_storage: ; carry in r18 from upper_case_ascii
	push r16 ; store
	push r17
	push XL
	push XH
	clr r17 ; verify is clear
	lds r16, BUZZER_2_SIZE ; load in size of loop
	cpi r16, $FF ; doesn't load if buzzer if its full
	breq buzzer_2_end ; jump to end
	ldi XL, LOW(BUZZER_2_OFFSETS)
	ldi XH, HIGH(BUZZER_2_OFFSETS)
	add XL, r16
	adc XH, r17 ; move to the next open space for SRAM storage
	st X, r18 ; stores the passed in offset into the SRAM location
	inc r16
	sts BUZZER_2_SIZE, r16 ; increase the loop by 1 for the new note
buzzer_2_end:	
	pop XH
	pop XL
	pop r17
	pop r16 ; restore
	ret
clear_buzzers: ; for killing buzzer 1 and clearing buzzer 2 loop
	push r17 ; store
	push r18
	push XH
	push XL
	clr r17 ; insure it's actually clear
	sts COUNTER_1, r17 ; kill buzzer_1
	sts COUNTER_2, r17
	sts BUZZER_2_CURRENT, r17 ; reset position for Buzzer_2_loop
clear_buzzer_2_loop: ; while loop for clearing buzzer 2 offsets and resetting size of loop to 0
	lds r18, BUZZER_2_SIZE ; loads current size
	cpi r18, $00 ; if buzzer 2 size was already zero then it's already cleared
	breq clear_buzzer_2_done
	ldi XL, LOW(BUZZER_2_OFFSETS) ; loads location of buzzer_2_offsets
	ldi XH, HIGH(BUZZER_2_OFFSETS)
	dec r18 ; decreases because size should always be 1 more than actual size
	add XL, r18 ; moves to end of loop of offsets
	add XH, r17
	st X, r17 ; clears the last note
	sts BUZZER_2_SIZE, r18 ; set the new size
	rjmp clear_buzzer_2_loop
clear_buzzer_2_done: ; time to finish	
	pop XL
	pop XH
	pop r18
	pop r17 ; restore
	ret
buzzer_2_loop: ; the loop for setting the offset for Counter_2
	push r16 ; store
	push r17
	push r18
	push r19
	push XL
	push XH
	clr r18 ; insure it's actually cleared
	lds r16, BUZZER_2_SIZE ; loads in size of loop
	cp r16, r18 ; if the size of the loop is $00, skip to end
	breq buzzer_2_loop_end
	lds r17, BUZZER_2_CURRENT ; loads in current position in loop
	ldi XL, LOW(BUZZER_2_OFFSETS)
	ldi XH, HIGH(BUZZER_2_OFFSETS)
	add XL, r17 ; add current offset to X
	adc XH, r18
	ld r19, X ; load offset value stored in X
	sts COUNTER_2, r19 ; store it in counter_2
	inc r17 ; increment the counter
	cp r17, r16 ; check to see if we've reached the end of the loop
	breq buzzer_2_loop_reset
	sts BUZZER_2_CURRENT, r17 ; store the counter
buzzer_2_loop_end:	
	pop XH
	pop XL
	pop r19
	pop r18
	pop r17
	pop r16 ; restore
	ret
buzzer_2_loop_reset: ; resets counter to $00 to start loop from beginning
	clr r17
	sts BUZZER_2_CURRENT, r17 
	rjmp buzzer_2_loop_end	
; for simplifying assigning ascii values to the counters
; offset sent to counter a  b  c  d   e   f   g   h   i   j   k   l   m  n  o   p   q   r   s  t   u   v  w   x  y   z
OFFSET_LETTER_VALUE: .db 8, 5, 3, 10, 19, 11, 12, 13, 24, 14, 15, 16, 7, 6, 25, 26, 17, 20, 9, 21, 23, 4, 18, 2, 22, 1
;
; for speed of timer 1   64/sec    32/sec    16/sec    8/sec     4/sec     2/sec     256/sec   128/sec
TIMER_SPEED: .db         $00, $FA, $01, $F4, $03, $E8, $07, $D0, $0F, $A0, $1F, $40, $00, $3E, $00, $7D
;
; library of pitches
; b2   c3   c#3  d3   d#3  e3   f3   f#3  g3   g#3  a3   a#3  b3   c4   c#4  d4   d#4  e4   f4   f#4  g4   g#4  a4   a#4  b4   c5
; $FD, $EE, $E1, $D4, $C8, $BD, $B2, $A8, $9F, $96, $8E, $86, $7E, $77, $70, $6A, $64, $5E, $59, $54, $4F, $4B, $47, $43, $3F, $3B
;
; c#5  d5   d#5  e5   f5   f#5  g5   g#5  a5   a#5  b5   c6   c#6  d6   d#6  e6   f6   f#6  g6   g#6  a6   a#6  b6   c7
; $38, $35, $32, $2F, $2C, $2A, $27, $25, $23, $21, $1F, $1D, $1C, $1A, $19, $17, $16, $15, $13, $12, $11, $10, $0F, $0E
;
;                       g4   f#4  d#4  a3   g#3  e4   g#4  c5   clr  g5   f#5  d#5  a4   g#4  e5   g#5  c6   clr
ZELDA_UNLOCK_NOTES: .db $4F, $54, $64, $8E, $96, $5E, $4B, $3B, $00, $27, $2A, $32, $47, $4B, $2F, $25, $1D, $00
;
;                       clr  b2   c#3  d#3  f#3  g#3  b3   c#4  d#4  f#4  g#4  b4   c#5  d#5  f#5  g#5  b5   c#6  d#6  f#6  g#6  b6   clr  clr  clr  clr  clr  clr
PENTATONIC_SCALE_B: .db $00, $FD, $E1, $C8, $A8, $96, $7E, $70, $64, $54, $4B, $3F, $38, $32, $2A, $25, $1F, $1C, $19, $15, $12, $0F, $00, $00, $00, $00, $00, $00
;
;                       clr  c3   d3   e3   g3   a3   c4   d4   e4   g4   a4   c7   d7   e7   g6   a6   c7   d7   e7   g7   a7   c8   clr  clr  clr  clr  clr  clr
PENTATONIC_SCALE_C: .db $00, $EE, $D4, $BD, $9F, $8E, $77, $6A, $5E, $4F, $47, $3B, $35, $2F, $27, $23, $1D, $1A, $17, $13, $11, $0E, $00, $00, $00, $00, $00, $00
;
;                       clr  c3   d3   e3   f3   g3   a3   b3   c4   d4   e4   f4   g4   a4   b4   c5   d5   e5   f5   g5   a5   b5   c6   d6   e6   f6   g6   clr
MAJOR_SCALE_C: .db      $00, $EE, $D4, $BD, $B2, $9F, $8E, $7E, $77, $6A, $5E, $59, $4F, $47, $3F, $3B, $35, $2F, $2C, $27, $23, $1F, $1D, $1A, $17, $16, $13, $00
;
;                       clr  c3   d3   d#3  f3   g3   g#3  a#3  c4   d4   d#4  f4   g4   g#4  a#4  c5   d5   d#5  f5   g5   g#5  a#5  c6   d6   d#6  f6   g6   clr
MINOR_SCALE_C: .db      $00, $EE, $D4, $C8, $B2, $9F, $96, $86, $77, $6A, $64, $59, $4F, $4B, $43, $3B, $35, $32, $2C, $27, $25, $21, $1D, $1A, $19, $16, $13, $00
;
;                       clr  c3   d3   d#3  e3   g3   a3   c4   d4   d#4  e4   g4   a4   c5   d5   d#5  e5   g5   a5   c6   d6   d#6  e6   g6   a6   c7   clr  clr
BLUES_SCALE_C: .db      $00, $EE, $D4, $C8, $BD, $9F, $8E, $77, $6A, $64, $5E, $4F, $47, $3B, $35, $32, $2F, $27, $23, $1D, $1A, $19, $17, $13, $11, $0E, $00, $00
;
;                            clr  c3   d3   d#3  f3   g3   g#3  b3   c4   d4   d#4  f4   g4   g#4  b4   c5   d5   d#5  f5   g5   g#5  b5   c6   d6   d#6  f6   g6   clr
HARMONIC_MINOR_SCALE_C: .db  $00, $EE, $D4, $C8, $B2, $9F, $96, $7E, $77, $6A, $64, $59, $4F, $4B, $3F, $3B, $35, $32, $2C, $27, $25, $1F, $1D, $1A, $19, $16, $13, $00
;
;                       clr  b2   c3   c#3  d3   d#3  e3   f3   f#3  g3   g#3  a3   a#3  b3   c4   c#4  d4   d#4  e4   f4   f#4  g4   g#4  a4   a#4  b4   c5   clr
CHROMATIC_SCALE: .db    $00, $FD, $EE, $E1, $D4, $C8, $BD, $B2, $A8, $9F, $96, $8E, $86, $7E, $77, $70, $6A, $64, $5E, $59, $54, $4F, $4B, $47, $43, $3F, $3B, $00
;
;						clr  c3   d3   e3   f3   g3   g#3  a3   b3   c4   d4   e4   f4   g4   g#4  a4   b4   c5   d5   e5   f5   g5   g#5  a5   b5   c6   d6   clr
MAJOR_BEBOP_C: .db      $00, $EE, $D4, $BD, $B2, $9F, $96, $8E, $7E, $77, $6A, $5E, $59, $4F, $4B, $47, $3F, $3B, $35, $2F, $2C, $27, $25, $23, $1F, $1D, $1A, $00
;
;                       clr  c3   d3   e3   f3   g3   g#3  a#3  c4   d4   e4   f4   g4   g#4  a#4  c5   d5   e5   f5   g5   g#5  a#5  c6   d6   e6   f6   g6   clr
AEOLIAN_DOMINANT_C: .db $00, $EE, $D4, $BD, $B2, $9F, $96, $86, $77, $6A, $5E, $59, $4F, $4B, $43, $3B, $35, $2F, $2C, $27, $25, $21, $1D, $1A, $17, $16, $13, $00
;
;                            clr  c3   c#3  e3   f3   g3   g#3  a#3  c4   c#4  e4   f4   g4   g#4  a#4  c5   c#5  e5   f5   g5   g#5  a#5  c6   c#6  e6   f6   g6   clr
PHRYGIAN_DOMINANT_C: .db     $00, $EE, $E1, $BD, $B2, $9F, $96, $86, $77, $70, $5E, $59, $4F, $4B, $43, $3B, $38, $2F, $2C, $27, $25, $21, $1D, $1C, $17, $16, $13, $00


; store Counter_2 values on a loop based of timer 1 that changes on regular intervals
; have some ascii values adjust OCR1AH and OCR1AL to change length of notes for Buzzer_1
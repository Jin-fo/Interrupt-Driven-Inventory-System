;
; AssemblerApplication2.asm
;
; Created: 11/20/2025 7:53:02 PM
; Author : jinyc
;
; Replace with your application code
.dseg 
page_1_buff		: .byte 80
page_2_buff		: .byte 80 
scan_buff		: .byte 20
keypad_in		: .byte 4

wireless_buff	: .byte 10

.cseg
.def page2_state = r20	; 0x10 : page1, 0x2A: page2A, 0x2B :page2B
	
rjmp start

;keypad pressed pin interrupt,
.org PORTE_PORT_vect
	rjmp keypad_process_isr

;scanner recieving interrupt, bit 7 of status is set
.org USART1_RXC_vect
	rjmp scanner_to_buffer_isr

.org USART2_DRE_vect
	rjmp wireless_send_isr

;LCD transmiting interrupt
.org USART3_DRE_vect
	rjmp LCD_home_isr

enable_keypad:
	lds r16, PORTE_PIN1CTRL
	ori r16, 0x02
	sts PORTE_PIN1CTRL, r16
	ret

disable_keypad:
	lds r16, PORTE_PIN1CTRL
	andi r16, 0xFD
	sts PORTE_PIN1CTRL, r16
	ret

keypad_process_isr:
	cli
	lds r16, PORTE_INTFLAGS
	sbrc r16, 1
	rcall process

	ldi r16, PORT_INT1_bm
	sts PORTE_INTFLAGS, r16
	sei 
	reti

process:
	cpi page2_state, 0x2A
	breq enter_count
	cpi page2_state, 0x2B			
	breq scan_barcode

	enter_count:
	rcall num_enter
	rjmp done_process
	scan_barcode:
	rcall scan_enter
	done_process:
	ret 

num_enter:
	cpi r17, 0x03
	brne no_rest
	ldi r17, 0x00 
	ldi YL, low(keypad_in)
	ldi YH, high(keypad_in)
	rcall line2_LCD

	no_rest:
	rcall process_key_state
	cpi page2_state, 0x2B
	breq just_ENTER1
	ld r16, Y+
	rcall start_TX
	inc r17
	rjmp pass

	just_ENTER1:
	ldi YL, low(keypad_in+3)
	ldi YH, high(keypad_in+3)
	ldi r16, '\r'
	st Y, r16
	pass:
	ret
	
scan_enter:
	rcall process_key_state
	ret 

process_key_state:
	lds r16, VPORTC_IN
	swap r16
	andi r16, 0x0f
	ldi ZL, low(keypad_map << 1)
	ldi ZH, high(keypad_map << 1)
	clr r0

	add ZL, r16
	adc ZH, r0

	lpm r16, Z
	cpi r16, 'C'
	brne not_enter
	cpi page2_state, 0x2A
	breq to_state2B
	cpi page2_state, 0x2B
	breq to_state2A

	to_state2B:
	ldi page2_state, 0x2B
	rjmp done_keypad
	to_state2A:
	ldi page2_state, 0x2A
	rjmp done_keypad

	not_enter:
	cpi r16, '0'
	brlo done_keypad        
	cpi r16, '9'+1   
	brlo store   
	rjmp done_keypad  
	
	store:
	st Y, r16
	done_keypad:
	ret

enable_scanner:
    lds r16, USART1_CTRLA
    ori r16, 0x80              ; enable RXCIE
    sts USART1_CTRLA, r16
	nop
    ret

disable_scanner:
	lds r16, USART1_CTRLA
	andi r16, 0x00
	sts USART1_CTRLA, r16
	ret

scanner_to_buffer_isr:
	cli 
	lds r16, USART1_RXDATAL
    st Y+, r16
	nop
	cpi r16, '\r'
	brne continue_scan
	
	done_scan:
	rcall disable_scanner
	rcall enable_keypad
	ldi YL, low(scan_buff)
	ldi YH, high(scan_buff)
	rcall enable_LCD
	continue_scan: 
	sei
	reti

enable_LCD:						; Enable interrupt to trigger on TX register DREIF | STATUS[5] is set
    lds r16, USART3_CTRLA
    ori r16, 0x20
    sts USART3_CTRLA, r16
    ret				; immediately triggering ISR 

disable_LCD:
	lds r16, USART3_CTRLA
	andi r16, 0x00
	sts USART3_CTRLA, r16
	ret

LCD_home_isr:
	cli 
		ld r16, Y+
		cpi r16, '\r'
		breq done1
		sts USART3_TXDATAL, r16
		rjmp continue1

	done1: ;disable LCD interrupt i.e. prevent LCD from displaying completely
	rcall disable_LCD
	
	continue1:
	sei 
	reti

enable_wireless:						; Enable interrupt to trigger on TX register DREIF | STATUS[5] is set
    lds r16, USART2_CTRLA
    ori r16, 0x20
    sts USART2_CTRLA, r16
    ret		

disable_wireless:
	lds r16, USART2_CTRLA
	andi r16, 0x00
	sts USART2_CTRLA, r16
	ret

wireless_send_isr:
	cli
		ld r16, Y+
		cpi r16, '\r'
		breq done2
		sts USART2_TXDATAL, r16
		rjmp continue2

	done2: ;disable LCD interrupt i.e. prevent LCD from displaying completely
	rcall disable_wireless
	
	continue2:
	sei
	reti
	
start:
	;transmit rate
	ldi r16, low(1667)
	sts USART3_BAUDL, r16
	ldi r16, high(1667)
	sts USART3_BAUDH, r16

	;transmit rate
	ldi r16, 0x10
	sts PORTMUX_USARTROUTEA, r16
	ldi r16, low(1667)
	sts USART2_BAUDL, r16
	ldi r16, high(1667)
	sts USART2_BAUDH, r16

	;received rate
	ldi r16, low(139)
	sts USART1_BAUDL, r16
	ldi r16, high(139)
	sts USART1_BAUDH, r16

	;formate
	ldi r16, 0x03
	sts USART3_CTRLC, r16
	sts USART2_CTRLC, r16
	sts USART1_CTRLC, r16

	;enable transmit
	ldi r16, 0x40
	sts USART3_CTRLB, r16
	sts USART2_CTRLB, r16

	;enable receive
	ldi r16, 0x80
	sts USART1_CTRLB, r16

	;I/O
	sbi VPORTF_DIR, 4
	sbi VPORTB_DIR, 0	;Transmit to LCD 
	cbi VPORTC_DIR, 1	;Receive from Scanner
	ldi r16, 0x0D
	out VPORTC_DIR, r16	;input from Keypad
	sei
	
home:
	ldi page2_state, 0x10
	rcall clear_LCD
	rcall disable_keypad
	rcall load_page1
	ldi YL, low(page_1_buff)
	ldi YH, high(page_1_buff)

	rcall enable_LCD		;disabled_LCD isr after
	rcall delay_1sec
	
page2A: ;main loop
	rcall clear_LCD
	;rjmp test
	;disabled
	rcall disable_scanner

	rcall load_page2
	ldi page2_state, 0x2A

	rcall line1_LCD
	
	ldi YL, low(page_2_buff)
	ldi YH, high(page_2_buff)
	rcall buffer_to_LCD
	push YL						
	push YH
	rcall line2_LCD

	ldi r17, 0x00
	ldi YL, low(keypad_in)
	ldi YH, high(keypad_in) 
	;enabled
	rcall enable_keypad

wait_enterA:
	cpi page2_state, 0x2B
	breq page2B
	rjmp wait_enterA

page2B:
	rcall disable_keypad

	ldi page2_state, 0x2B
	rcall line3_LCD
	pop YH
	pop YL
	rcall buffer_to_LCD

	rcall line4_LCD

	ldi YL, low(scan_buff)
	ldi YH, high(scan_buff)
	rcall enable_scanner	;keypad enable in scanned isr
	rcall enable_keypad

wait_enterB:
	cpi page2_state, 0x2A
	breq wireless_send

	rjmp wait_enterB

wireless_send:
	;test:
	rcall load_wireless_cmd
	ldi YL, low(wireless_buff)
	ldi YH, high(wireless_buff)
	rcall buffer_to_wireless
	push YL
	push YH

	ldi YL, low(scan_buff)
	ldi YH, high(scan_buff)
	rcall buffer_to_wireless

	pop YH
	pop YL
	rcall buffer_to_wireless

	ldi YL, low(keypad_in)
	ldi YH, high(keypad_in)
	rcall buffer_to_wireless

	ldi r16, '\r'
	rcall wireless_TX
	ldi r16, '\n'
	rcall wireless_TX

	rjmp page2A

;--------------subroutines---------
load_page1:
	ldi YL, low(page_1_buff)
	ldi YH, high(page_1_buff)
	
	ldi ZL, low(home_message << 1)
	ldi ZH, high(home_message <<1)

	rcall page_to_buffer
	ret 

load_page2:
	ldi YL, low(page_2_buff)
	ldi YH, high(page_2_buff)

	ldi ZL, low(main_message << 1)
	ldi ZH, high(main_message << 1)

	rcall page_to_buffer
	ret

load_wireless_cmd:
	ldi YL, low(wireless_buff)
	ldi YH, high(wireless_buff)

	ldi ZL, low(wireless_cmd << 1)
	ldi ZH, high(wireless_cmd << 1)

	rcall page_to_buffer
	ret

page_to_buffer:
	lpm r16, Z+
	st Y+, r16
	cpi r16, '\0'
	brne page_to_buffer
	ret 

buffer_to_LCD:
	ld r16, Y+
	cpi r16, '\r'
	breq doneA
	rcall start_TX
	rjmp buffer_to_LCD

	doneA:
	ret

buffer_to_wireless:
	ld r16, Y+
	cpi r16, '\r'
	breq doneB
	rcall wireless_TX
	rjmp buffer_to_wireless

	doneB:
	ret 

clear_LCD:
	ldi r16, '|'
	rcall start_TX
	ldi r16, '-'
	rcall start_TX
	ret 

line1_LCD:						;move LCD cursor to beginning of line 1
	ldi r16, 0xFE				
	rcall start_TX
	ldi r16, 0x80
	rcall start_TX
	ret

line2_LCD:						;move LCD cursor to beginning of line 2
	ldi r16, 0xFE				
	rcall start_TX
	ldi r16, 0xC0
	rcall start_TX
	ret

line3_LCD:						;move LCD cursor to beginning of line 3
	ldi r16, 0xFE				
	rcall start_TX
	ldi r16, 0x94
	rcall start_TX
	ret
		
line4_LCD:						;move LCD cursor to beginning of line 3
    ldi r16, 0xFE				
    rcall start_TX
    ldi r16, 0xD4     
	rcall start_TX 
    ret

wireless_TX:
	lds r19, USART2_STATUS
	sbrs r19, 5
	rjmp wireless_TX
	sts USART2_TXDATAL, r16
	ret

start_TX:
	lds r19, USART3_STATUS	
	sbrs r19, 5				; check USART1 Data register Empty flag is set
	rjmp start_TX
	sts USART3_TXDATAL, r16 
	nop
	ret 

delay_1sec:
	ldi r24, low(5234)
	ldi r25, high(5234)
	outer_loop:
		ldi r23, $ff
		inner_loop:
		dec r23
		brne inner_loop
		sbiw  r25:r24, 1
		brne outer_loop
	ret 

home_message:
    .db "                    "
    .db "Inventory Systems I "
	.db "  ESE280 Fall 2025  "
	.db "    Jin Y. Chen   ", '\r', '\0'

main_message:
	.db "Enter item count:", '\r'
	.db "Scan barcode:   ", '\r', '\0'

keypad_map:
	.db "123F456E789DA0BC"

wireless_cmd:
	.db "AT+SEND=100, 28, ID: ", '\r'
	.db ", COUNT= ", '\r', '\0' 

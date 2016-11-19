	errorlevel  -302


	#include "config.inc" 
	
	__CONFIG       _CP_OFF & _CPD_OFF & _WDT_OFF & _BOR_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT  & _MCLRE_OFF & _FCMEN_OFF & _IESO_OFF
	
	
MainData	udata	0x20 ; 
d1			res	1
d2			res 1
d3			res	1
temp		res 1
STATUS_TEMP	res	1
W_TEMP		res	1


	; imported from the rf_protocol_rx module
	extern	RF_RX_Init			; method
	extern	RF_RX_ReceiveMsg	; method
	extern	RfRxMsgBuffer  		; variable
	extern	RfRxMsgLen			; variable
	extern	RfRxReceiveResult	; variable
	; imported from the rf_protocol_tx module
	extern	RF_TX_Init			; method
	extern	RF_TX_SendMsg		; method
	extern	TXMsgAddr			; variable
	extern	TXMsgLen			; variable	
	extern	TXDstAddr			; variable
	; imported from the crc16 module:
	extern	REG_CRC16_HI	; variable
	extern	REG_CRC16_LO	; variable
	extern	CRC16			; method
	; imported from the RS232 module
	extern	RS232_Init		; method
	extern	RS232_Send_W	; method
	extern	RS232_receive_W ; method
	extern	RS232ReceiveBuf	; variable

Interrupt	CODE	0x4
	pagesel	_interrupt
	goto	_interrupt
	
	
Reset		CODE	0x0
	pagesel	_init
	goto	_init
	code
	
_init
	; set the requested clockspeed
	banksel	OSCCON
	if CLOCKSPEED == .8000000
		movlw	b'01110000'
	else
		if CLOCKSPEED == .4000000
			movlw	b'01100000'
		else
			error	"Unsupported clockspeed"
		endif
	endif
	movwf	OSCCON
	
	; setup option register
	banksel	OPTION_REG
	movlw	b'00001000'	
		;	  ||||||||---- PS0 - Timer 0: 
		;	  |||||||----- PS1
		;	  ||||||------ PS2
		;	  |||||------- PSA -  Assign prescaler to WDT
		;	  ||||-------- TOSE - LtoH edge
		;	  |||--------- TOCS - Timer0 uses IntClk
		;	  ||---------- INTEDG - falling edge RB0
		;	  |----------- NOT_RABPU - pull-ups enabled
	movwf	OPTION_REG
	
	; Select the clock for our A/D conversations
	BANKSEL	ADCON1
	MOVLW 	B'01010000'	; ADC Fosc/16
	MOVWF 	ADCON1

	; all ports to digital
	banksel	ANSEL
	clrf	ANSEL
	clrf	ANSELH
	
	; Configure PortA as output
	BANKSEL TRISA
	clrf	TRISA
	
	; Set entire portB as output
	BANKSEL	TRISB
	clrf	TRISB
	BSF		TRISB, 5	; input for rs232 port
	
	; Set entire portC as output
	BANKSEL	TRISC
	clrf	TRISC	
	
	; set all output ports to 0
	banksel	PORTA
	clrf	PORTA
	clrf	PORTB
	clrf	PORTC
	
	; set the OSCTUNE value now
	banksel	OSCTUNE
	movlw	OSCTUNE_VALUE
	movwf	OSCTUNE
	
	banksel	PORTA

	; init the rf_protocol_tx.asm module
	call	RF_RX_Init
	call	RS232_Init
	call	RF_TX_Init

	; configure interrupt
	movfw	PORTB		; read port to get current status
	banksel	IOCB
	bsf		IOCB, 5
	; enable interrupt
	bsf		INTCON, RABIE
	bsf		INTCON, GIE
	banksel	PORTA

	goto	_main

_interrupt
	; save context
	MOVWF 	W_TEMP 		;Copy W to TEMP register
	SWAPF 	STATUS,W 	;Swap status to be saved into W
	CLRF 	STATUS 		;bank 0, regardless of current bank, Clears IRP,RP1,RP0
	MOVWF 	STATUS_TEMP ;Save status to bank zero STATUS_TEMP register
	
	; temp disable interrupt
	bcf		INTCON, GIE
	movfw	PORTB
	bcf		INTCON, RABIF
	
	; execute interrupt code
	bsf		PORTC, 3
	call	ReadAndHandleRs232
	bcf		PORTC, 3

	;trigger reset now
	; configure the watch-dog timer now
	CLRWDT
	banksel	WDTCON
	movlw	b'00000001' ; 0 + enable
	movwf	WDTCON
	banksel	PORTA

	; re-enable interrupt
	bsf		INTCON, GIE

	; restore context
	SWAPF 	STATUS_TEMP,W 	;Swap STATUS_TEMP register into W
	MOVWF 	STATUS 			;Move W into STATUS register
	SWAPF 	W_TEMP,F 		;Swap W_TEMP
	SWAPF 	W_TEMP,W 		;Swap W_TEMP into W
	RETFIE
	

ReadAndHandleRs232
	call	RS232_receive_W
	movwf	temp

	; only proceed if we received at least 2 bytes
	sublw	.1
	btfsc	STATUS, C
	goto	ReadAndHandleRs232_done

	; send the received msg over RF now:
	; the fist byte is poped off from the buffer and used as the dst addr
	movfw	RS232ReceiveBuf	; first byte in buffer into W
	movwf	TXDstAddr		; save byte into dst-addr
	; point TX buffer to the receive buffer, but one byte forward to skip the dst addr
	movlw	HIGH	RS232ReceiveBuf
	movwf	TXMsgAddr
	movlw	LOW		RS232ReceiveBuf
	movwf	TXMsgAddr+1
	incf	TXMsgAddr+1, F	; step addr one byte forward
	decf	temp, F	; the first byte contains the dst addr, not part of the msg
	movfw	temp
	movwf	TXMsgLen
	; and transmit the data now
	call	RF_TX_SendMsg

ReadAndHandleRs232_done
	return
	
_main
	; read something from the air
	bsf		PORTC, 4
	call	RF_RX_ReceiveMsg
	bcf		PORTC, 4

	movfw	RfRxReceiveResult
	sublw	.1
	btfss	STATUS, Z
	goto	RfError
	
	; SEND over RS232
	; send error code 0 to rs232
	movlw	0x00
	call	RS232_Send_W
	; send the entire msg
	movfw	RfRxMsgLen
	movwf	temp
	decf	temp, F ; skip the crc
	decf	temp, F ; skip the crc
	; configure the address to which we write the current byte
	movlw	RfRxMsgBuffer
	movwf	FSR
	bcf		STATUS, IRP
_send_to_rs232_loop
	movfw	INDF
	call	RS232_Send_W
	incf	FSR, F
	decfsz	temp, F
	goto	_send_to_rs232_loop

	CLRWDT	; reset watch-dog timer because we received a valid msg

RfError
	movfw	RfRxReceiveResult
	call	RS232_Send_W
	call	Delay_50ms

_main_loop_cnt
	goto	_main


BlinkShort
	bsf		PORTC, 5
	bsf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	bcf		PORTC, 5
	bcf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	return
BlinkLong
	bsf		PORTC, 5
	bsf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	bcf		PORTC, 5
	bcf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	return


Delay_100ms
			;199993 cycles
	movlw	0x3E
	movwf	d1
	movlw	0x9D
	movwf	d2
Delay_100ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay_100ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return

Delay_50ms
			;99993 cycles
	movlw	0x1E
	movwf	d1
	movlw	0x4F
	movwf	d2
Delay_50ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay_50ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return

	end
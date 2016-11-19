;**********************************************
; Module for a wireless data transmission
;
; Based on manchester encoding
;
;**********************************************

#include "config.inc"

#ifndef CLOCKSPEED
	error	"CLOCKSPEED must be defined, for example: .8000000"
#endif
#ifndef	RF_TX_PORT
	error	"RF_TX_PORT must be defined, for example: PORTA, 0"
#endif
#ifndef	RF_SRC_ADDR
	error	"RF_DST_ADDR must be defined, for example: .2"
#endif


TxData	udata 0x2a
Temp			res	1
Temp2			res	1
Counter			res	1
DelayCounter1	res	1
DelayCounter2	res	1
TXMsgAddr		res	2
TXMsgLen		res	1
TXDstAddr		res	1
	global	TXMsgAddr
	global	TXMsgLen
	global	TXDstAddr


	; From the crc16.asm module
	extern	REG_CRC16_LO
	extern	REG_CRC16_HI
	extern	CRC16

	code
	
RF_TX_Init
	global	RF_TX_Init
	call	RF_TX_End
	return
	
RF_TX_SendMsg
	global	RF_TX_SendMsg

	; ensure msgLen is != 0
	movfw	TXMsgLen
	sublw	0x00
	btfsc	STATUS, Z
	goto	RF_TX_SendMsg_return

	
	; calculate the CRC16
	call	RF_Calc_CRC16	
	
	; send the start-bit
	call	RF_TX_Start

	; send the dst
	movfw	TXDstAddr
	call	RF_TX_SendW
	; send the src
	movlw	RF_SRC_ADDR
	call	RF_TX_SendW
	; send the len
	movfw	TXMsgLen
	call	RF_TX_SendW
	; send the content

	movfw	TXMsgAddr+1
	movwf	FSR
	bcf		STATUS, IRP
	btfsc	TXMsgAddr, 0
	bsf		STATUS, IRP
RF_TX_SendMsg_Loop
	movfw	INDF
	call	RF_TX_SendW
	incf	FSR, F
	decfsz	TXMsgLen, F
	goto	RF_TX_SendMsg_Loop

	
	; transmit the crc1
	movfw	REG_CRC16_LO
	call	RF_TX_SendW
	; transmit the crc2
	movfw	REG_CRC16_HI
	call	RF_TX_SendW

	; send the stop-bit
	call	RF_TX_End


	call	BitDelay
	call	BitDelay
	call	BitDelay
RF_TX_SendMsg_return
	return
	
RF_Calc_CRC16
	clrf	REG_CRC16_LO
	clrf	REG_CRC16_HI
	
	movfw	TXDstAddr
	call	CRC16
	movlw	RF_SRC_ADDR
	call	CRC16
	movfw	TXMsgLen
	call	CRC16
	
	; the msg itself
	movfw	TXMsgLen  ; copy the len
	movwf	Temp
	movfw	TXMsgAddr+1
	movwf	FSR
	bcf		STATUS, IRP
	btfsc	TXMsgAddr, 0
	bsf		STATUS, IRP
RF_Calc_CRC16_Loop
	movfw	INDF	; pick up the value at specified addr
	call	CRC16
	incf	FSR, F
	decfsz	Temp, F
	goto	RF_Calc_CRC16_Loop

	; done
	return

RF_TX_Start
	bsf		RF_TX_PORT
	call 	BitDelay
	return
	
RF_TX_SendW
	movwf	Temp
	movlw	.8 			; transmit 8 bits
	movwf	Counter
_f_transmit_w_next
	rrf		Temp, F
	btfsc	STATUS, C
	goto	_f_transmit_w_hi
_f_transmit_w_lo
	bsf		RF_TX_PORT
	call	BitDelay
	bcf		RF_TX_PORT
	call	BitDelay
	goto	_f_transmit_w_done
_f_transmit_w_hi
	bcf		RF_TX_PORT
	call	BitDelay
	bsf		RF_TX_PORT
	call	BitDelay
	goto	_f_transmit_w_done
_f_transmit_w_done
	decfsz	Counter, F
	goto 	_f_transmit_w_next
	return
	
RF_TX_End
	bcf		RF_TX_PORT
	call 	BitDelay
	return

_f_transmit_w
	return
	
BitDelay ; 0.0005 s
	if CLOCKSPEED == .4000000
		movlw	0xA5
		movwf	DelayCounter1
	else
		if CLOCKSPEED == .8000000
			movlw	0xC6
			movwf	DelayCounter1
			movlw	0x01
			movwf	DelayCounter2
		else
			error "Unsupported clockspeed"
		endif
	endif
BitDelay_loop
	if CLOCKSPEED == .4000000
		decfsz	DelayCounter1, f
		goto	BitDelay_loop
	else
		if CLOCKSPEED == .8000000
			decfsz	DelayCounter1, f
			goto	$+2
			decfsz	DelayCounter2, f
			goto	BitDelay_loop
			goto	$+1
			nop
		else
			error "Unsupported clockspeed"
		endif
	endif
	return
	
	end
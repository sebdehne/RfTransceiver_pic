;--------------------------
; config.inc
;--------------------------

	list	p=16f690
#include    <p16f690.inc>

;**********************************************
; Port config:
; * PortC  : Out - display-data
; * RA4    : Out - display-RS
; * RA5    : Out - display-E
;
; * RA0    : IN  - RSSI 
; * RA1    : IN  - RSSI reference
;
; * RB4    : OUT - LED
; * RB5    : OUT - RS232 output
; * RB6    : IN  - RS232 input
;**********************************************
#define CLOCKSPEED      		.8000000	; 8 MHz Osc
;#define CLOCKSPEED       		.4000000	; 4 MHz Osc
#define	OSCTUNE_VALUE			.0

;
; Mem
; main  : 5 0x20 - 0x25
; crc   : 4 0x26 - 0x29
; tx    : 9 0x2a - 0x32
; rs323 : 21 0x33 - 
; rx    : 24 0x50
; 

;***************************************
; Values required by rf_protocol.asm
;***************************************
#define	RF_RX_PORT_RSSI			PORTA, 0    ; C1IN+
#define	RF_RX_PORT_RSSI_REF		PORTA, 1    ; C12IN0-
#define	RF_TX_PORT				PORTB, 4    ; PORTB, 4
#define	RF_SRC_ADDR				.1


;***************************************
; Values required by rs232.asm
;***************************************
#define	RS232_RX_PORT			PORTB, 5
#define	RS232_TX_PORT			PORTB, 6
#define	RS232_BAUD				.9600


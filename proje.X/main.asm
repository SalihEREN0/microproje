; PIC16F877A Temperature Control with 7-Segment Display
; Adapted to circuit: Segments on PORTD, Digits on PORTB
; Target: 27 degrees Celsius
PROCESSOR 16F877A
#include <xc.inc>

; Configuration
CONFIG FOSC = HS
CONFIG WDTE = OFF
CONFIG PWRTE = ON
CONFIG BOREN = ON
CONFIG LVP = OFF
CONFIG CPD = OFF
CONFIG WRT = OFF
CONFIG CP = OFF

; Constants
#define TARGET_TEMP 27
#define HEATER_PIN 0    ; RC0 (changed from RD0)
#define COOLER_PIN 1    ; RC1 (changed from RD1)
#define HEATER_PORT PORTC
#define COOLER_PORT PORTC

; Variables
PSECT udata_bank0
AMBIENT_TEMP: DS 1
FRAC_TEMP: DS 1
TEMP_HIGH: DS 1
TEMP_LOW: DS 1
DELAY_COUNT: DS 1
DELAY_COUNT2: DS 1
TENS_DIGIT: DS 1
ONES_DIGIT: DS 1
TENTHS_DIGIT: DS 1
HUNDREDTHS_DIGIT: DS 1
DISPLAY_COUNT: DS 1
; Math Variables
RES_0: DS 1
RES_1: DS 1
RES_2: DS 1
MATH_A_L: DS 1
MATH_A_H: DS 1
MATH_COUNT: DS 1
MATH_TEMP: DS 1

; Reset Vector
PSECT resetVec,class=CODE,delta=2
GOTO MAIN

; Main Code
PSECT code

MAIN:
    CALL INIT_SYSTEM

MAIN_LOOP:
    ; Read real temperature
    CALL READ_TEMPERATURE
    
    ; Control heater/cooler based on temperature
    CALL CONTROL_TEMP
    
    ; Display temperature
    CALL CONVERT_TO_DIGITS
    CALL DISPLAY_TEMPERATURE
    ; CALL DELAY (Removed to prevent flicker)
    GOTO MAIN_LOOP

; Initialize System
INIT_SYSTEM:
    BANKSEL TRISA
    MOVLW 0xFF          ; PORTA as input for ADC
    MOVWF TRISA
    CLRF TRISB          ; PORTB as output for digit select
    CLRF TRISC          ; PORTC as output for heater/cooler
    CLRF TRISD          ; PORTD as output for segments
    
    ; ADC Configuration
    MOVLW 0x8E
    MOVWF ADCON1
    
    BANKSEL PORTA
    CLRF PORTA
    CLRF PORTB          ; All digits OFF initially
    CLRF PORTC          ; Heater/Cooler OFF initially
    CLRF PORTD          ; All segments OFF initially
    CLRF AMBIENT_TEMP
    
    ; ADC on, channel 0, FOSC/32
    MOVLW 0x81
    MOVWF ADCON0
    
    CALL DELAY
    
    ; Ensure all unused digits are OFF
    BANKSEL PORTB
    CLRF PORTB
    
    ; Ensure heater/cooler OFF
    BANKSEL PORTC
    BCF PORTC, HEATER_PIN
    BCF PORTC, COOLER_PIN
    
    RETURN

; Read Temperature from ADC
READ_TEMPERATURE:
    BANKSEL ADCON0
    MOVLW 0x81
    MOVWF ADCON0
    
    CALL SHORT_DELAY
    CALL SHORT_DELAY
    
    BSF ADCON0, 2
    
WAIT_ADC:
    BTFSC ADCON0, 2
    GOTO WAIT_ADC
    
    ; Get ADC Result
    BANKSEL ADRESL
    MOVF ADRESL, W
    BANKSEL MATH_A_L
    MOVWF MATH_A_L
    
    BANKSEL ADRESH
    MOVF ADRESH, W
    BANKSEL MATH_A_H
    MOVWF MATH_A_H
    
    ; Calculate (ADC * 125)
    MOVLW 125
    CALL MULTIPLY_16x8
    
    ; Integer Part = RES_2:RES_1 (Result / 256)
    ; Store Integer Part in AMBIENT_TEMP (Low byte is enough for < 255)
    BANKSEL RES_1
    MOVF RES_1, W
    BANKSEL AMBIENT_TEMP
    MOVWF AMBIENT_TEMP
    
    ; Fractional Part Calculation
    ; Remainder is in RES_0
    ; Calculate (RES_0 * 100) / 256
    BANKSEL RES_0
    MOVF RES_0, W
    BANKSEL MATH_A_L
    MOVWF MATH_A_L
    CLRF MATH_A_H
    
    MOVLW 100
    CALL MULTIPLY_16x8
    
    ; Result / 256 is in RES_1
    BANKSEL RES_1
    MOVF RES_1, W
    BANKSEL FRAC_TEMP
    MOVWF FRAC_TEMP
    
    RETURN

; Multiply 16x8 Routine
; Inputs: MATH_A_H:MATH_A_L (Multiplicand), W (Multiplier)
; Output: RES_2:RES_1:RES_0
MULTIPLY_16x8:
    BANKSEL MATH_COUNT
    MOVWF MATH_COUNT
    CLRF RES_0
    CLRF RES_1
    CLRF RES_2
    
    MOVLW 8
    MOVWF MATH_TEMP ; Loop counter
    
MULT_LOOP:
    ; Shift Result Left (RES << 1)
    BCF STATUS, 0
    RLF RES_0, F
    RLF RES_1, F
    RLF RES_2, F
    
    ; Check MSB of Multiplier
    BCF STATUS, 0
    RLF MATH_COUNT, F
    BTFSS STATUS, 0
    GOTO SKIP_ADD
    
    ; Add Multiplicand to RES
    MOVF MATH_A_L, W
    ADDWF RES_0, F
    BTFSC STATUS, 0
    CALL INC_RES_1
    
    MOVF MATH_A_H, W
    ADDWF RES_1, F
    BTFSC STATUS, 0
    INCF RES_2, F

SKIP_ADD:
    DECFSZ MATH_TEMP, F
    GOTO MULT_LOOP
    RETURN

INC_RES_1:
    INCF RES_1, F
    BTFSC STATUS, 2 ; If wrapped to 0
    INCF RES_2, F
    RETURN

; Control Temperature (Heater/Cooler)
CONTROL_TEMP:
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    SUBLW TARGET_TEMP      ; W = TARGET - AMBIENT
    
    BTFSC STATUS, 2        ; Check Z flag (Equal)
    GOTO TEMP_OK
    
    BTFSS STATUS, 0        ; Check C flag (If C=0, Result is negative -> TARGET < AMBIENT)
    GOTO TOO_HOT
    
    ; If here, TARGET > AMBIENT (Too Cold)
    GOTO TOO_COLD

TOO_COLD:
    BANKSEL PORTC
    BSF PORTC, HEATER_PIN
    BCF PORTC, COOLER_PIN
    RETURN

TOO_HOT:
    BANKSEL PORTC
    BCF PORTC, HEATER_PIN
    BSF PORTC, COOLER_PIN
    RETURN

TEMP_OK:
    BANKSEL PORTC
    BCF PORTC, HEATER_PIN
    BCF PORTC, COOLER_PIN
    RETURN

; Convert Temperature to Digits
CONVERT_TO_DIGITS:
    ; 1. Convert Integer Part
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    CALL GET_DIGITS
    MOVWF ONES_DIGIT
    ; TENS_DIGIT is set correctly.
    
    ; 2. Convert Fractional Part
    ; We need to save TENS_DIGIT because GET_DIGITS uses it.
    MOVF TENS_DIGIT, W
    MOVWF MATH_TEMP ; Save Integer Tens
    
    BANKSEL FRAC_TEMP
    MOVF FRAC_TEMP, W
    CALL GET_DIGITS
    MOVWF HUNDREDTHS_DIGIT
    MOVF TENS_DIGIT, W
    MOVWF TENTHS_DIGIT
    
    ; Restore Integer Tens
    MOVF MATH_TEMP, W
    MOVWF TENS_DIGIT
    
    RETURN

; Helper: Converts W to TENS_DIGIT and returns ONES in W
GET_DIGITS:
    CLRF TENS_DIGIT
    MOVWF MATH_A_L ; Use MATH_A_L as temp
DIV_LOOP:
    MOVLW 10
    SUBWF MATH_A_L, W
    BTFSS STATUS, 0
    GOTO DIV_DONE
    MOVWF MATH_A_L
    INCF TENS_DIGIT, F
    GOTO DIV_LOOP
DIV_DONE:
    MOVF MATH_A_L, W
    RETURN

; Display Temperature on 7-Segment
; D1 (RB7): Tens
; D2 (RB6): Ones + DP
; D3 (RB5): Tenths
; D4 (RB4): Hundredths
DISPLAY_TEMPERATURE:
    BANKSEL DISPLAY_COUNT
    MOVLW 0xC8
    MOVWF DISPLAY_COUNT
    
DISPLAY_LOOP:
    ; --- Digit 1: Tens (RB7) ---
    CALL OFF_ALL
    BANKSEL TENS_DIGIT
    MOVF TENS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTB
    MOVLW 0x80          ; RB7
    MOVWF PORTB
    CALL SHORT_DELAY
    
    ; --- Digit 2: Ones (RB6) + DP ---
    CALL OFF_ALL
    BANKSEL ONES_DIGIT
    MOVF ONES_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    ; Add Decimal Point (RD0)
    BANKSEL PORTD
    BSF PORTD, 0
    BANKSEL PORTB
    MOVLW 0x40          ; RB6
    MOVWF PORTB
    CALL SHORT_DELAY
    
    ; --- Digit 3: Tenths (RB5) ---
    CALL OFF_ALL
    BANKSEL TENTHS_DIGIT
    MOVF TENTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTB
    MOVLW 0x20          ; RB5
    MOVWF PORTB
    CALL SHORT_DELAY
    
    ; --- Digit 4: Hundredths (RB4) ---
    CALL OFF_ALL
    BANKSEL HUNDREDTHS_DIGIT
    MOVF HUNDREDTHS_DIGIT, W
    CALL GET_SEGMENT_CODE
    CALL SEND_TO_PORTD
    BANKSEL PORTB
    MOVLW 0x10          ; RB4
    MOVWF PORTB
    CALL SHORT_DELAY
    
    BANKSEL DISPLAY_COUNT
    DECFSZ DISPLAY_COUNT, F
    GOTO DISPLAY_LOOP
    
    CALL OFF_ALL
    RETURN

OFF_ALL:
    BANKSEL PORTB
    CLRF PORTB
    BANKSEL PORTD
    CLRF PORTD
    RETURN

SEND_TO_PORTD:
    ; Shift left by 1 (segments on RD7-RD1)
    BANKSEL TEMP_LOW
    MOVWF TEMP_LOW
    BCF STATUS, 0
    RLF TEMP_LOW, F
    MOVF TEMP_LOW, W
    BANKSEL PORTD
    MOVWF PORTD
    RETURN

; Get 7-Segment Code from Table
GET_SEGMENT_CODE:
    BANKSEL TEMP_LOW
    MOVWF TEMP_LOW
    MOVLW HIGH(SEGMENT_TABLE)
    MOVWF PCLATH
    MOVF TEMP_LOW, W
    CALL SEGMENT_TABLE
    RETURN

; 7-Segment Lookup Table (Common Cathode)
; Standard codes (shifted by 1 in display routine)
SEGMENT_TABLE:
    ADDWF PCL, F
    RETLW 0x3F  ; 0
    RETLW 0x06  ; 1
    RETLW 0x5B  ; 2
    RETLW 0x4F  ; 3
    RETLW 0x66  ; 4
    RETLW 0x6D  ; 5
    RETLW 0x7D  ; 6
    RETLW 0x07  ; 7
    RETLW 0x7F  ; 8
    RETLW 0x6F  ; 9

; Short Delay
SHORT_DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0x50
    MOVWF DELAY_COUNT
SHORT_DELAY_LOOP:
    NOP
    NOP
    NOP
    NOP
    DECFSZ DELAY_COUNT, F
    GOTO SHORT_DELAY_LOOP
    RETURN

; Main Delay
DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0x32
    MOVWF DELAY_COUNT
DELAY_OUTER:
    MOVLW 0xFF
    MOVWF DELAY_COUNT2
DELAY_INNER:
    DECFSZ DELAY_COUNT2, F
    GOTO DELAY_INNER
    DECFSZ DELAY_COUNT, F
    GOTO DELAY_OUTER
    RETURN

END
; PIC16F877A Temperature Control with 7-Segment Display
; Target: 27 degrees Celsius
; Displays current temperature on 2-digit 7-segment display
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
#define HEATER_PIN 0
#define COOLER_PIN 1

; Variables
PSECT udata_bank0
AMBIENT_TEMP: DS 1
TEMP_HIGH: DS 1
TEMP_LOW: DS 1
DELAY_COUNT: DS 1
TENS_DIGIT: DS 1
ONES_DIGIT: DS 1
DIGIT_SELECT: DS 1
DISPLAY_COUNT: DS 1

; Reset Vector
PSECT resetVec,class=CODE,delta=2
GOTO MAIN

; Main Code
PSECT code

; 7-Segment Lookup Table (Common Cathode)
; Segments: GFEDCBA (bit 6-0), DP not used
SEGMENT_TABLE:
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

MAIN:
    CALL INIT_SYSTEM

MAIN_LOOP:
    CALL READ_TEMPERATURE
    CALL CONTROL_TEMP
    CALL CONVERT_TO_DIGITS
    CALL DISPLAY_TEMPERATURE
    CALL DELAY
    GOTO MAIN_LOOP

; Initialize System
INIT_SYSTEM:
    BANKSEL TRISA
    MOVLW 0x01          ; RA0 as input for ADC
    MOVWF TRISA
    MOVLW 0x03          ; RD0, RD1 as output (heater/cooler), RD2+ as input
    MOVWF TRISD
    CLRF TRISB          ; PORTB as output for 7-segment data
    CLRF TRISC          ; PORTC as output (RC0, RC1 for digit select)
    
    MOVLW 0x8E          ; Right justified, AN0 analog
    MOVWF ADCON1
    
    BANKSEL PORTA
    MOVLW 0x81          ; ADC on, channel 0, FOSC/32
    MOVWF ADCON0
    
    CLRF PORTA
    CLRF PORTD
    CLRF PORTB
    CLRF PORTC
    
    BCF PORTD, HEATER_PIN
    BCF PORTD, COOLER_PIN
    BCF PORTC, 0        ; D1 off
    BCF PORTC, 1        ; D2 off
    
    CLRF DIGIT_SELECT
    RETURN

; Read Temperature from ADC (ORIGINAL WORKING VERSION)
READ_TEMPERATURE:
    ; 1. Start Conversion
    BANKSEL ADCON0      ; Select Bank 0
    BSF     ADCON0, 2   ; Set GO/DONE bit to start conversion
WAIT_ADC:
    BTFSC   ADCON0, 2   ; Check if GO/DONE is clear
    GOTO    WAIT_ADC    ; If not, keep waiting
    ; 2. Read Low Byte (Must switch to BANK 1)
    BANKSEL ADRESL      ; SWITCH TO BANK 1
    MOVF    ADRESL, W   ; Read the low byte into W
    ; 3. Save Low Byte (Must switch BACK to BANK 0)
    BANKSEL TEMP_LOW    ; SWITCH BACK TO BANK 0
    MOVWF   TEMP_LOW    ; Now store W into the variable
    ; 4. Read High Byte (Already in Bank 0, but good practice to ensure)
    ; ADRESH is in Bank 0
    MOVF    ADRESH, W
    MOVWF   TEMP_HIGH
    ; 5. Convert Raw ADC to Celsius
    ; LM35 + 10-bit ADC formula approx: Temp = ADC / 2
    MOVF    TEMP_LOW, W
    MOVWF   AMBIENT_TEMP
    BCF     STATUS, 0       ; Clear Carry bit (C) to prevent rotation errors
    RRF     AMBIENT_TEMP, F ; Rotate Right = Divide by 2
    RETURN

; Control Temperature (WORKING VERSION)
CONTROL_TEMP:
    BANKSEL AMBIENT_TEMP
    MOVF AMBIENT_TEMP, W
    SUBLW TARGET_TEMP       ; TARGET - AMBIENT
    BTFSS STATUS, 0         ; If result positive (Temp < Target)
    GOTO COOL_MODE          ; Temp >= Target, cool down
    GOTO HEAT_MODE          ; Temp < Target, heat up

HEAT_MODE:
    BANKSEL PORTD
    BSF PORTD, HEATER_PIN
    BCF PORTD, COOLER_PIN
    RETURN

COOL_MODE:
    BANKSEL PORTD
    BCF PORTD, HEATER_PIN
    BSF PORTD, COOLER_PIN
    RETURN

; Convert Temperature to Tens and Ones Digits
CONVERT_TO_DIGITS:
    BANKSEL AMBIENT_TEMP
    CLRF TENS_DIGIT
    MOVF AMBIENT_TEMP, W
    MOVWF ONES_DIGIT    ; Start with full value in ones
    
DIVIDE_BY_10:
    MOVLW 0x0A          ; Check if >= 10
    SUBWF ONES_DIGIT, W
    BTFSS STATUS, 0     ; Skip if result is positive (>= 10)
    GOTO DIVISION_DONE
    
    MOVWF ONES_DIGIT    ; Save remainder
    INCF TENS_DIGIT, F  ; Increment tens
    GOTO DIVIDE_BY_10
    
DIVISION_DONE:
    RETURN

; Display Temperature on 7-Segment
DISPLAY_TEMPERATURE:
    BANKSEL DISPLAY_COUNT
    MOVLW 0x32          ; Display refresh count
    MOVWF DISPLAY_COUNT
    
DISPLAY_LOOP:
    ; Display Tens Digit (D1 = RC0)
    MOVF TENS_DIGIT, W
    CALL GET_SEGMENT_CODE
    MOVWF PORTB
    
    BANKSEL PORTC
    BSF PORTC, 0        ; Enable tens digit (D1 = RC0)
    BCF PORTC, 1
    CALL SHORT_DELAY
    
    ; Display Ones Digit (D2 = RC1)
    BANKSEL ONES_DIGIT
    MOVF ONES_DIGIT, W
    CALL GET_SEGMENT_CODE
    MOVWF PORTB
    
    BANKSEL PORTC
    BCF PORTC, 0
    BSF PORTC, 1        ; Enable ones digit (D2 = RC1)
    CALL SHORT_DELAY
    
    BANKSEL DISPLAY_COUNT
    DECFSZ DISPLAY_COUNT, F
    GOTO DISPLAY_LOOP
    
    ; Turn off all digits
    BANKSEL PORTC
    BCF PORTC, 0
    BCF PORTC, 1
    RETURN

; Get 7-Segment Code from Table
GET_SEGMENT_CODE:
    ADDWF PCL, F
    GOTO SEGMENT_TABLE

; Short Delay for Display Multiplexing
SHORT_DELAY:
    MOVLW 0x05
    MOVWF DELAY_COUNT
SHORT_DELAY_LOOP:
    DECFSZ DELAY_COUNT, F
    GOTO SHORT_DELAY_LOOP
    RETURN

; Main Delay Function
DELAY:
    BANKSEL DELAY_COUNT
    MOVLW 0xFF
    MOVWF DELAY_COUNT
DELAY_LOOP:
    DECFSZ DELAY_COUNT, F
    GOTO DELAY_LOOP
    RETURN

END
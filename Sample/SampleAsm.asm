;--------------------------------------------------
; Vector
	.org	$FFFA
	.dw	NMI
	.dw	Reset
	.dw	Interrupt

	.org	$FFF0
NMI:
Interrupt:
	BRK
	RTI

	.org	$8000
Reset:
	LDA	#$42
	STA	<Argument_A
	LDA	#42
	STA	<Argument_B
	JSR	Multiply
	NOP
	BRK

;--------------------------------------------------
; Calculation

Argument	= $00
Argument_A	= Argument
Argument_B	= Argument + 1
Result		= $02
Result_Low	= Result
Result_High	= Result + 1

Multiply:
		DEC	<Argument_B
		LDA	<Argument_A
		LSR	A
		STA	<Result_Low
		LDA	#$00
		LDY	#$08
.Loop		BCC	+
		ADC	<Argument_B
+		ROR	A
		ROR	<Result_Low
		DEY
		BNE	.Loop
		STA	<Result_High
		RTS

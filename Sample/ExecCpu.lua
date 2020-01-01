local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")

-- memory
memory	= L6502Memory.new()

-- vector
memory:Upload(0xFFFA, {
	0x00, 0x80, 0x00, 0x90, 0x00, 0xA0,
})

-- program
--[[	; $02-$03 = $00 * $01
	LDA #$42	; $9000 : A9 42
	STA <$00	; $9002 : 85 00
	LDA #$2A	; $9004 : A9 2A
	STA <$01	; $9006 : 85 01
	JSR $900D	; $9008 : 20 0D 90
	NOP		; $900B : EA
	BRK		; $900C : 00
	DEC <$01	; $900D : C6 01
	LDA <$00	; $900F : A5 00
	LSR A		; $9011 : 4A
	STA <$02	; $9012 : 85 02
	LDA #$00	; $9014 : A9 00
	LDY #$08	; $9016 : A0 08
	BCC $901C	; $9018 : 90 02
	ADC <$01	; $901A : 65 01
	ROR A		; $901C : 6A
	ROR <$02	; $901D : 66 02
	DEY		; $901F : 88
	BNE $9018	; $9020 : D0 F6
	STA <$03	; $9022 : 85 03
	RTS		; $9024 : 60
]]
memory:Upload(0x9000, {
	0xA9, 0x42, 0x85, 0x00, 0xA9, 0x2A, 0x85, 0x01,
	0x20, 0x0D, 0x90, 0xEA, 0x00, 0xC6, 0x01, 0xA5,
	0x00, 0x4A, 0x85, 0x02, 0xA9, 0x00, 0xA0, 0x08,
	0x90, 0x02, 0x65, 0x01, 0x6A, 0x66, 0x02, 0x88,
	0xD0, 0xF6, 0x85, 0x03, 0x60
})

-- execute
cpu	= L6502.new(memory, print)
cpu:Reset()
repeat
	cpu:Clock()
until(cpu.Registers.PC >= 0xA000)

memory:WriteToFile("memory.bin")

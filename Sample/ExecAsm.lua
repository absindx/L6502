local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")
local L6502Assembler	= require("L6502Assembler")
local L6502Disassembler	= require("L6502Disassembler")

code	= [[
	IOPort	= $2000		; define named address
	VFlag	= %10000000	; define named value
	.org	$8000		; set origin
Routine:			; define global label
	LDA	<$00		; instruction(zeropage, hex)
	BEQ	.skip		; jump to named local label
	SEC			; instrcution(implied)
-				; define - label
	SBC	#1		; instruction(immediate, dec)
	BNE	+		; jump to recent + label
	BEQ	-		; jump to recent - label
+				; define + label
.skip				; define named local label
	ORA	#VFlag		; use the named value as operand(immediate, bin)
	STA	IOPort		; use the named address as operand(absolute, hex)
	LDA	.Data, X	; use the named address as operand(absolute,x)
	LDX	IOPort + 2	; use expression
	RTS			; 
.Data	.db	$AA, $BB, $CC	; define data byte array
]]

-- assemble code
bin	= L6502Assembler.Assemble(code, 0x8000, print)
if(not bin)then
	print("Failed to assemble code.")
	return
end

-- write to memory
memory	= L6502Memory.new()
memory:Upload(0xFFFA, {
	0x00, 0x90, 0x00, 0x80, 0x00, 0xA0,
})
L6502Assembler.UploadToMemory(memory, bin)

-- disassemble and check
local dis	= L6502Disassembler.new(memory)
local address	= 0x8000
repeat
	local disasm, length	= dis:DisassembleAddress(address)
	if(disasm == "BRK")then
		break
	end
	print(string.format("$%04X : %s", address, disasm))
	address	= address + length
until(address >= 0x8100)

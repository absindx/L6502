local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")
local L6502Disassembler	= require("L6502Disassembler")

-- disassemble from memory
memory	= L6502Memory.new()
memory:Upload(0xFFFA, {
	0x00, 0x80, 0x00, 0x90, 0x00, 0xA0,
})
local prg	= {
	0xA9, 0x42, 0x85, 0x00, 0xA9, 0x2A, 0x85, 0x01,
	0x20, 0x0D, 0x90, 0xEA, 0x00, 0xC6, 0x01, 0xA5,
	0x00, 0x4A, 0x85, 0x02, 0xA9, 0x00, 0xA0, 0x08,
	0x90, 0x02, 0x65, 0x01, 0x6A, 0x66, 0x02, 0x88,
	0xD0, 0xF6, 0x85, 0x03, 0x60
}
memory:Upload(0x9000, prg)

local dis	= L6502Disassembler.new(memory)
local address	= 0x9000
repeat
	local disasm, length	= dis:DisassembleAddress(address)
	print(string.format("$%04X : %s", address, disasm))
	address	= address + length
until(address >= (0x9000 + #prg))

-- disassemble from byte array
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x09, 0x40}	))	-- ORA #$40
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x30, 0x80}	))	-- BMI $C060
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x30, 0xFE}	))	-- BMI $C0DE
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x30, 0xFF}	))	-- BMI $C0DF
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x10, 0x00}	))	-- BPL $C0E0
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x10, 0x01}	))	-- BPL $C0E1
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0xA}		))	-- NOP
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0xA}		))	-- ROL A
print(L6502Disassembler.DisassembleBinary(0xC0DE, {0x2}		))	-- .db $02 (undefined opcode)

-- disassemble all opcodes
if(true)then
	for i=0x00,0xFF do
		print(string.format("$%02X	%s", i, L6502Disassembler.DisassembleBinary(0x0000, {i, 0xAA, 0xBB})))
	end
end

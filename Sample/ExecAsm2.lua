local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")
local L6502Assembler	= require("L6502Assembler")

-- memory
memory	= L6502Memory.new()

-- assemble file
bin, lines	= L6502Assembler.AssembleFromFile("SampleAsm.asm", 0x8000, print)
if(not bin)then
	print("Failed to assemble code.")
	return
end
lineNumbers	= L6502Assembler.UploadToMemory(memory, bin)

-- execute
cpu	= L6502.new(memory, print)
cpu:Reset()
cpu.CycleCounter	= -6	-- JSR abs
repeat
	-- print line number
	lineNumber	= lineNumbers:GetLineNumber(cpu)
	if(lineNumber ~= nil)then
		print(string.format("[%-7d] %s", lineNumber, lines[lineNumber]))
	end

	cpu:Step()
until(cpu.Registers.PC >= 0xFFF0)

-- check calculation result
local argA	= cpu.MemoryProvider:ReadBypass(0x0000)
local argB	= cpu.MemoryProvider:ReadBypass(0x0001) + 1
local resultA	= cpu.MemoryProvider:ReadBypass(0x0002)
local resultB	= cpu.MemoryProvider:ReadBypass(0x0003)
local result	= resultB * 256 + resultA
print(string.format("Exec : 0x%02X * 0x%02X = 0x%04X", argA, argB, result))
print(string.format("True : 0x%04X", argA * argB))

----------------------------------------------------------------------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########                    ##########        ############    ########      --
--  ####            ####          ####              ##    ####    ####      ####                  ####    ####          ####      ####    ####    --
--  ####          ####            ############    ####      ####          ######                  ####      ####        ####      ####            --
--  ####          ############              ####  ####      ####      ########      ############  ####      ####        ####        ##########    --
--  ####          ####      ####            ####  ####      ####    ########        ############  ####      ####        ####                ####  --
--  ####          ####      ####  ####      ####    ####    ##    ######                          ####    ####          ####      ####      ####  --
--  ############    ##########      ##########        ######      ##############                  ##########        ############    ##########    --
--                                                                                                                                                --
----------------------------------------------------------------------------------------------------------------------------------------------------

local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")

--------------------------------------------------

local L6502Disassembler	= {}
function L6502Disassembler.new(MemoryProvider)
	local disasm	= {}

	local memory	= MemoryProvider	or L6502Memory.new()

	-- intercept trace
	local traceString
	disasm.cpu	= L6502.new(memory, function(trace)
		traceString	= trace
	end)

	local function internalDisassemble(address)
		-- initialize cpu
		disasm.cpu.Registers.PC		= address
		disasm.cpu.WaitCycleCounter	= 0
		disasm.cpu.PendingReset		= false
		disasm.cpu.PendingIrq		= false
		disasm.cpu.PendingBrk		= false
		disasm.cpu.PendingNmi		= false
		disasm.cpu.Halt			= false

		-- get trace
		local opcode			= disasm.cpu.MemoryProvider:ReadBypass(address)
		traceString			= nil
		disasm.cpu:Clock()
		if((not traceString) or (string.find(traceString, "undefined")))then
			return string.format(".db $%02X", opcode), 1
		end

		-- split instruction
		traceString	= string.match(traceString, "(.-)%s*;")

		return traceString, disasm.cpu.InstructionLength
	end

	function disasm:DisassembleAddress(address)
		if(not address)then
			return nil
		end
		return internalDisassemble(address)
	end

	return disasm
end

local disasmMemory, disasmObject
function L6502Disassembler.DisassembleBinary(address, binary)
	if(not address)then
		return nil
	end
	if(not disasmObject)then
		disasmMemory	= L6502Memory.new()
		disasmObject	= L6502Disassembler.new(disasmMemory)
	end

	-- set binary
	disasmMemory:Upload(address, binary)

	-- disassemble
	return disasmObject:DisassembleAddress(address)
end

return L6502Disassembler

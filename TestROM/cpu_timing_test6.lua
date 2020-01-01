local L6502		= require("L6502")
local L6502Memory_NES	= require("L6502Memory_NES")
local L6502Disassembler	= require("L6502Disassembler")

local baseDir	= [[cpu_timing_test6\]]

function ExecuteTest(romFile)
	memory	= L6502Memory_NES.ReadFromNesRomFile(baseDir .. romFile)
	if(not memory)then
		print("Failed to read the rom file")
		return
	end

	memory:WriteBypass(0x2002, 0x80)	-- PPU Status : V-Blank on
	memory:WriteBypass(0x4015, 0x40)	-- APU Status : Frame interrupt

	local executing	= 0

	local fp	= io.open(romFile .. ".log", "w")
	if(not fp)then
		print("Failed to create the result file")
		return
	end
	local enableLog	= true
	function fputs(str)
		if(enableLog)then
			fp:write(str .. "\n")
		end
	end
	function LogMessage(format, ...)
		local str	= string.format(format, ...)
		print(str)
		fputs(str)
	end

	print("Testing " .. romFile .. " ...")

	cpu	= L6502.new(memory, fputs)
	cpu.DisableDecimalMode	= true
	dis	= L6502Disassembler.new(memory)
	cpu:Reset()

	local waitVBlank	= 0
	while(true)do
		cpu:Clock()

		if(cpu.Halt)then
			LogMessage("CPU halt")
			break
		end

		if((cpu.Registers.PC == 0xE9EC) or (cpu.Registers.PC == 0xE9EF))then
			waitVBlank	= waitVBlank + 1
			enableLog	= (waitVBlank <= 12)
		else
			waitVBlank	= 0
			enableLog	= true
		end

		if(cpu.Registers.PC == 0xEA5A)then
			break
		end
		if(cpu.WaitCycleCounter == 0)then
			if(cpu.Registers.PC == 0xE6CE)then
				local indAddr	= memory:ReadBypass(0x0001)*0x100 + memory:ReadBypass(0x0000)
				local msg	= ""
				local char
				while(true)do
					char	= memory:ReadBypass(indAddr)
					if(char == 0x00)then
						break
					end
					msg	= msg .. string.char(char)
					indAddr	= indAddr + 1
				end
				LogMessage("; Message : %s", msg)
			elseif(cpu.Registers.PC == 0xE0BF)then
				local opcode	= memory:ReadBypass(0x0013)
				LogMessage("; Message : FAIL OP : $%02X [%s]", opcode, dis:DisassembleBinary({opcode, 0xAA, 0xBB}, 0x0000))
			elseif(cpu.Registers.PC == 0xE12B)then
				local v0	= memory:ReadBypass(0x0010)
				local v1	= memory:ReadBypass(0x0011)
				LogMessage("; Message : UNKNOWN ERROR $%02X%02X", v1, v0)
			end
		end

		-- V-Blank
		if(((cpu.CycleCounter * 3 + 30 + 241 * 262) % (341 * 262)) < 3)then	-- 89342 ppu cycles
			fputs(string.format("; NMI Cycle=%d", cpu.CycleCounter))
			cpu.TraceLogProvider	= fputs
			waitVBlank		= 0
			cpu:NMI()
		end
	end

	fp:close()
	memory:WriteToFile(romFile .. ".bin")
end

ExecuteTest("cpu_timing_test.nes")
print("Test finished")

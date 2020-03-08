local L6502		= require("L6502")
local L6502Memory_NES	= require("L6502Memory_NES")

local baseDir		= [[branch_timing_tests\]]
local enableTrace	= false

function ExecuteTest(romFile)
	memory	= L6502Memory_NES.ReadFromNesRomFile(baseDir .. romFile)
	if(not memory)then
		print("Failed to read the rom file")
		return
	end

	memory:WriteBypass(0x2002, 0x80)	-- PPU Status : V-Blank on
	memory:WriteBypass(0x4015, 0x40)	-- APU Status : Frame interrupt

	local fp
	local enableLog	= true
	if(enableTrace)then
		fp	= io.open(romFile .. ".log", "w")
		if(not fp)then
			print("Failed to create the result file")
			return
		end
		function fputs(str)
			if(enableLog)then
				fp:write(str .. "\n")
			end
		end
	else
		function fputs()
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
	cpu:Reset()
	local waitVBlank	= 0
	while(true)do
		cpu:Clock()

		if(cpu.Halt)then
			print("CPU halt")
			break
		end

		if((cpu.Registers.PC == 0xE0D6) or (cpu.Registers.PC == 0xE0D8))then
			waitVBlank	= waitVBlank + 1
			enableLog	= (waitVBlank <= 12)
		else
			waitVBlank	= 0
			enableLog	= true
		end

		if(cpu.Registers.PC == 0xE076)then
			LogMessage("; PASSED")
			break
		elseif(cpu.Registers.PC == 0xE051)then
			LogMessage("; FAILED")
			break
		elseif(cpu.Registers.PC == 0xE043)then
			LogMessage("; INTERNAL ERROR")
			break
		end

		-- V-Blank
		if(((cpu.CycleCounter * 3 + 30 + 241 * 262) % (341 * 262 - 0.5)) < 3)then	-- 89341.5 ppu cycles
			fputs(string.format("; NMI Cycle=%d", cpu.CycleCounter))
			cpu.TraceLogProvider	= fputs
			waitVBlank		= 0
			cpu:NMI()
		end
	end

	if(enableTrace)then
		fp:close()
		memory:WriteToFile(romFile .. ".bin")
	end
end

ExecuteTest("1.Branch_Basics.nes")
ExecuteTest("2.Backward_Branch.nes")
ExecuteTest("3.Forward_Branch.nes")
print("Test finished")

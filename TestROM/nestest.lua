local L6502		= require("L6502")
local L6502Memory_NES	= require("L6502Memory_NES")

local baseDir		= [[kevtris\]]
local enableTrace	= false

function ExecuteTest(romFile)
	memory	= L6502Memory_NES.ReadFromNesRomFile(baseDir .. romFile)
	if(not memory)then
		print("Failed to read the rom file")
		return
	end

	memory:WriteBypass(0x2002, 0x80)	-- PPU Status : V-Blank on
	memory:WriteBypass(0x4015, 0x40)	-- APU Status : Frame interrupt

	local executing	= 0

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

	function memory:Read(address)
		local value	= memory:ReadBypass(address)
		if(address == 0x00D5)then		-- controller 1
			value		= 0x10		-- ...S....	run test
		end
		return value
	end

	local ppuAddr		= 0x0000
	local ppuAddrTwice	= false
	local ppuAddrHold	= 0x00
	local resultString
	function memory:Write(address, value)
		local isMainRam	= (0x0000 <= address) and (address < 0x0800)
		local isExRam	= (0x6000 <= address) and (address < 0x8000)
		if(isMainRam or (self.HasSram and isExRam))then
			memory:WriteBypass(address, value or 0)
		end
		if(address == 0x2006)then
			if(ppuAddrTwice)then
				ppuAddr		= ppuAddrHold * 0x100 + value
				ppuAddrTwice	= false
			else
				ppuAddrHold	= value
				ppuAddrTwice	= true
			end
		elseif(address == 0x2007)then
			if((0x20 <= value) and (value < 0x80))then
				--fputs(string.format("; PPU data = %02X (%c), $%04X", value, value, ppuAddr))

				-- tile
				if((executing > 0) and (0x2000 <= ppuAddr) and (ppuAddr < 0x2400) and (math.floor(ppuAddr / 0x10)%2 == 0))then
					-- result area
					if((ppuAddr % 0x10) == 4)then
						resultString	= string.char(value)
					elseif((ppuAddr % 0x10) == 5)then
						local testNames	= {
							"Run all tests",
							"Branch tests",
							"Flag tests",
							"Immediate tests",
							"Implied tests",
							"Stack tests",
							"Accumulator tests",
							"(Indirect,X) tests",
							"Zeropage tests",
							"Absolute tests",
							"(Indirect),Y tests",
							"Absolute,Y tests",
							"Zeropage,X tests",
							"Absolute,X tests",
						}
						local testNamesIndex	= math.floor((ppuAddr - 0x2060) / 0x20)
						if((0 < testNamesIndex) and (testNamesIndex < #testNames))then
							LogMessage("; Result : %s%s %s", resultString, string.char(value), testNames[testNamesIndex])
						end
					end
				end
			else
				--fputs(string.format("; PPU data = %02X, $%04X", value, ppuAddr))
			end
			ppuAddr	= ppuAddr + 1
		end
	end


	print("Testing " .. romFile .. " ...")

	cpu	= L6502.new(memory, fputs)
	cpu.DisableDecimalMode	= true
	cpu:Reset()
	while(true)do
		cpu:Clock()

		if(cpu.Halt)then
			print("CPU halt")
			break
		end

		if(cpu.Registers.PC == 0xC089)then
			executing	= executing + 1
			if(executing >= 8)then
				break
			end
		end

		-- V-Blank
		if(((cpu.CycleCounter * 3 + 30 + 241 * 262) % (341 * 262 - 0.5)) < 3)then	-- 89341.5 ppu cycles
			fputs(string.format("; NMI Cycle=%d", cpu.CycleCounter))
			cpu:NMI()
		end
	end

	if(enableTrace)then
		fp:close()
		memory:WriteToFile(romFile .. ".bin")
	end
end

ExecuteTest("nestest.nes")
print("Test finished")

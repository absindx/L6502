----------------------------------------------------------------------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########                      ############  ####      ####    ############  --
--  ####            ####          ####              ##    ####    ####      ####                        ####      ######    ####        ####      --
--  ####          ####            ############    ####      ####          ######                        ####      ########  ####        ####      --
--  ####          ############              ####  ####      ####      ########      ############        ####      ##############        ####      --
--  ####          ####      ####            ####  ####      ####    ########        ############        ####      ####  ########        ####      --
--  ####          ####      ####  ####      ####    ####    ##    ######                                ####      ####      ####        ####      --
--  ############    ##########      ##########        ######      ##############                    ############  ####      ####        ####      --
--                                                                                                                                                --
----------------------------------------------------------------------------------------------------------------------------------------------------

--[[ Usage
L6502Interpreter.Prompt()
> LDA #$00	; Interpret code
> save		; Save history to file
> exit		; Exit prompt mode

]]

--------------------------------------------------

local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")
local L6502Assembler	= require("L6502Assembler")

--------------------------------------------------

local function split(str, delimiter, isSkipBlank)
	local match	= string.match
	local s	= {}
	local p	= string.format("([^%s]*)%s(.*)", delimiter, delimiter)
	repeat
		local v, r	= match(str, p)
		if(v)then
			if((not isSkipBlank) or (#v > 0))then
				s[#s + 1]	= v
			end
		else
			s[#s + 1]	= str
		end
		str	= r
	until(str == nil)
	return s
end

--------------------------------------------------

local L6502Interpreter	= {}

function L6502Interpreter.new()
	local interpreter	= {}

	local function addCodeHistory(interpreter, code)
		interpreter.code[#interpreter.code + 1]	= string.match(code, ".*[^\n]")
	end
	local function setOriginToHistory(interpreter, address)
		address	= address	or interpreter:GetProgramCounter()
		addCodeHistory(interpreter, string.format("	.org $%04X", address))
	end
	local function assemble(interpreter, code, origin)
		origin		= origin	or interpreter:GetProgramCounter()
		local bin	= L6502Assembler.Assemble(code, origin)
		if(not bin)then
			print("[Error] Failed to assemble.")
			return
		end
		if(#bin > 1)then
			print("[Warning] Program is divided.")
		end

		L6502Assembler.UploadToMemory(interpreter.memory, bin)

		return bin
	end

	interpreter.memory		= L6502Memory.new()
	interpreter.cpu			= L6502.new(interpreter.memory, print)
	interpreter.cpu.BeforeTracelog	= false
	interpreter.cpu.AfterTracelog	= true
	interpreter.code		= {}

	interpreter.memory:Upload(0xFFFC, {0x00, 0x80})	-- $FFFC(RESET)	= .dw $8000

	function interpreter:GetProgramCounter()
		return self.cpu.Registers.PC
	end

	function interpreter:Reset()
		self.LastExecutedAddress	= -1
		self.cpu:Reset()
	end
	function interpreter:Interpret(code)
		local origin	= self:GetProgramCounter()
		local bin	= assemble(self, code)
		if(not bin)then
			return
		end

		if(origin ~= self.LastExecutedAddress)then
			setOriginToHistory(self)
		end
		addCodeHistory(self, code)

		if(#bin[1].Data > 0)then
			local nextOrigin	= origin + #bin[1].Data
			self.cpu:Step()

			if(nextOrigin ~= self:GetProgramCounter())then
				setOriginToHistory(self)
			end
		end

		self.LastExecutedAddress	= self:GetProgramCounter()
	end

	function interpreter:GetHistory()
		return table.concat(self.code, "\n")
	end
	function interpreter:LoadAsmFromFile(file, address)
		address	= address	or self:GetProgramCounter()
		local fp	= io.open(file, "r")
		if(not fp)then
			print("[Error] Failed to open the file.")
			return
		end

		local code	= fp:read("*a")
		fp:close()

		local bin	= assemble(self, code, address)
		if(not bin)then
			return
		end

		addCodeHistory(self, ";--------------------------------------------------")
		addCodeHistory(self, "; loadasm " .. file)
		if(address ~= self.LastExecutedAddress)then
			setOriginToHistory(self, address)
		end
		addCodeHistory(self, code)
		addCodeHistory(self, ";--------------------------------------------------")

		self.LastExecutedAddress	= -1
	end
	function interpreter:LoadBinaryFromFile(file, address)
		address	= address	or self:GetProgramCounter()

		local fp	= io.open(file, "rb")
		if(not fp)then
			print("[Error] Failed to open the file.")
			return
		end

		local data	= fp:read("*a")
		fp:close()

		local bin	= {string.byte(data, 1, #data)}
		local code	= ""
		local binLength	= #bin
		local format	= string.format

		if((address + binLength) > 0x10000)then
			print("[Warning] Address range exceeded 0x10000, stop writing at 0xFFFF.")
			binLength	= 0x10000 - address
		end

		self.memory:Upload(address, bin)

		for i=1,binLength,16 do
			local line	= "\n	.db "
			local length	= binLength - (i - 1)
			if(length > 16)then
				length	= 16
			end

			if(length > 0)then
				for j=1,length do
					line	= format("%s$%02X, ", line, bin[i + j - 1])
				end

				code	= code .. string.sub(line, 1, #line - 2)
			end
		end

		code	= string.sub(code, 2)	-- remove first newline

		addCodeHistory(self, ";--------------------------------------------------")
		addCodeHistory(self, "; loadbin " .. file)
		if(address ~= self.LastExecutedAddress)then
			setOriginToHistory(self, address)
		end
		addCodeHistory(self, code)
		addCodeHistory(self, ";--------------------------------------------------")

		self.LastExecutedAddress	= -1
	end
	function interpreter:WriteHistoryToFile(file)
		local fp	= io.open(file, "w")
		if(not fp)then
			print("[Error] Failed to open the file.")
			return
		end
		fp:write(self:GetHistory())
		fp:write("\n")
		fp:close()
	end

	interpreter:Reset()
	return interpreter
end

function L6502Interpreter.Prompt()
	local interpreter	= L6502Interpreter.new()
	local commands		= {}

	local isExit		= false

	function commands.dump(args)
		local dumpRows	= 16
		local address	= tonumber(args[1] or "", 16)

		if(not address)then
			io.write("address (hex)	> ")
			address	= tonumber(io.read() or "", 16)
		end
		if(not address)then
			print("[Error] Invalid address.")
			return
		end

		address	= (address - address % 16) % 0x10000

		local a, s
		for i=0,dumpRows-1 do
			a	= address + i * 16
			s	= ""
			for j=0,15 do
				s	= string.format("%s %02X", s, interpreter.memory:ReadBypass(a + j))
			end
			print(string.format("%08X |%s", a, s))
		end
	end
	function commands.step(args)
		local count	= tonumber(args[1] or "") or 1
		for i=1,count do
			interpreter.cpu:Step()
		end
	end
	function commands.reset(args)
		interpreter:Reset()
	end
	function commands.loadasm(args)
		local file	= args[1]
		local address	= tonumber(args[2] or "", 16)
		if(not file)then
			io.write("file	> ")
			file	= io.read()
		end
		interpreter:LoadAsmFromFile(file, address)
	end
	function commands.loadbin(args)
		local file	= args[1]
		local address	= tonumber(args[2] or "", 16)
		if(not file)then
			io.write("file	> ")
			file	= io.read()
		end

		interpreter:LoadBinaryFromFile(file, address)
	end
	function commands.save(args)
		local file	= args[1]
		if(not file)then
			io.write("file	> ")
			file	= io.read()
		end
		interpreter:WriteHistoryToFile(file)
	end
	function commands.exit(args)
		isExit		= true
	end
	function commands.help(args)
		local function description(name, text)
			print(string.format("  %-36s: %s", name, text))
		end
		print("Command format")
		print("  command [argument, ...]")
		print("Commands")
		description("dump <address (hex)>",			"Display memory dump")
		description("step [count=1]",				"Step instruction")
		description("reset",					"Reset CPU")
		description("loadasm <file>",				"Load asm source from file")
		description("loadbin <file> [address (hex)=pc]",	"Load binary data from file")
		description("save <file>",				"Save history to file")
		description("exit",					"Exit prompt mode")
		description("help",					"Show help")
	end

	while(not isExit)do
		interpreter.cpu:InterruptBypass()
		io.write(string.format("$%04X	> ", interpreter:GetProgramCounter()))
		local code	= io.read()
		local args	= split(code, " ", true)

		local command	= commands[string.lower(args[1])]
		if(command)then
			table.remove(args, 1)
			command(args)
		else
			interpreter:Interpret(code)
		end
	end
end

return L6502Interpreter

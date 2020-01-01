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
		addCodeHistory(interpreter, "	.org $8000")
		interpreter.cpu:Reset()
	end
	function interpreter:Interpret(code)
		local origin	= self:GetProgramCounter()
		local bin	= L6502Assembler.Assemble(code, origin)
		if(not bin)then
			print("[Error] Failed to assemble.")
			return
		end
		if(#bin > 1)then
			print("[Warning] Program is divided.")
		end

		addCodeHistory(self, code)

		if(#bin[1].Data > 0)then
			local nextOrigin	= origin + #bin[1].Data
			L6502Assembler.UploadToMemory(self.memory, bin)
			self.cpu:Step()

			if(nextOrigin ~= self:GetProgramCounter())then
				addCodeHistory(self, string.format("	.org $%04X", self:GetProgramCounter()))
			end
		end
	end

	function interpreter:GetHistory()
		return table.concat(self.code, "\n")
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
			print(string.format("  %-24s: %s", name, text))
		end
		print("Command format")
		print("  command [argument, ...]")
		print("Commands")
		description("dump [address (hex)]",	"Display memory dump")
		description("step [count=1]",		"Step instruction")
		description("save [file]",		"Save history to file")
		description("exit",			"Exit prompt mode")
		description("help",			"Show help")
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

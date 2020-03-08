------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########    --
--  ####            ####          ####              ##    ####    ####      ####  --
--  ####          ####            ############    ####      ####          ######  --
--  ####          ############              ####  ####      ####      ########    --
--  ####          ####      ####            ####  ####      ####    ########      --
--  ####          ####      ####  ####      ####    ####    ##    ######          --
--  ############    ##########      ##########        ######      ##############  --
--                                                                                --
------------------------------------------------------------------------------------

local L6502Memory	= require("L6502Memory")

--------------------------------------------------
-- Bit operation
--------------------------------------------------

local function bitCalc(a, b, f)
	local v	= 0
	local m = 2
	local p = 1
	local ma, mb
	while((a>0) or (b>0))do
		ma	= a % m
		mb	= b % m
		if(f(ma~=0, mb~=0))then
			v	= v + p
		end
		a	= a - ma
		b	= b - mb
		p	= m
		m	= m * 2
	end
	return v
end

local function BitAnd(a, b)
	return bitCalc(a, b, function(ba, bb) return ba and bb end)
end
local function BitOr(a, b)
	return bitCalc(a, b, function(ba, bb) return ba or bb end)
end
local function BitXor(a, b)
	return bitCalc(a, b, function(ba, bb) return ba ~= bb end)
end

local function ToChar(v)
	return math.fmod(math.floor(v) + 2^7, 2^8) - 2^7
end
local function ToByte(v)
	return math.floor(v) % (2^8)
end
local function ToWord(v)
	return math.floor(v) % (2^16)
end

--------------------------------------------------

local function GetBit(value, p)
	return (math.floor(value / (2^p)) % 2) ~= 0
end
local function SetBit(value, p, bit)
	local b		= not GetBit(value, p)
	local mask	= 2^p
	if((not bit) or (bit == 0))then
		-- clear
		if(b)then
			return value
		else
			return value - mask
		end
	else
		-- set
		if(b)then
			return value + mask
		else
			return value
		end
	end
end

local function SplitWord(value)
	local low	= value % 0x100
	local high	= value - low
	return high, low
end
local function GetHighByte(value)
	return math.floor(value / 0x100) % 0x100
end
local function GetLowByte(value)
	return math.floor(value) % 0x100
end

--------------------------------------------------
-- Utility
--------------------------------------------------

local function StatusFlagToTable(preg)
	return {
		N	= GetBit(preg, 7);
		V	= GetBit(preg, 6);
		R	= GetBit(preg, 5);
		B	= GetBit(preg, 4);
		D	= GetBit(preg, 3);
		I	= GetBit(preg, 2);
		Z	= GetBit(preg, 1);
		C	= GetBit(preg, 0);
	}
end
local function StatusFlagTableToValue(preg)
	local function bton(b, n)
		if(b)then
			return n
		else
			return 0
		end
	end
	return	bton(preg.N, 2^7) +
		bton(preg.V, 2^6) +
		bton(preg.R, 2^5) +
		bton(preg.B, 2^4) +
		bton(preg.D, 2^3) +
		bton(preg.I, 2^2) +
		bton(preg.Z, 2^1) +
		bton(preg.C, 2^0)
end
local function StatusFlagToString(preg)
	local function btos(i, a, b)
		if(GetBit(preg, i))then
			return a
		else
			return b
		end
	end
	return	btos(7, "N", "n") ..
		btos(6, "V", "v") ..
		btos(5, "R", "r") ..
		btos(4, "B", "b") ..
		btos(3, "D", "d") ..
		btos(2, "I", "i") ..
		btos(1, "Z", "z") ..
		btos(0, "C", "c")
end

--------------------------------------------------

local function ReadByte(status, address)
	return status.MemoryProvider:Read(address)
end
local function ReadBypassByte(status, address)
	return status.MemoryProvider:ReadBypass(address)
end
local function ReadWord(status, address)
	local low		= status.MemoryProvider:Read(address)
	local high		= status.MemoryProvider:Read(address + 1)
	return high * 256 + low
end
local function ReadPagedWord(status, address)
	local highAddr, lowAddr	= SplitWord(address)
	local nextHigh, nextLow	= SplitWord(lowAddr + 1)
	local nextAddr		= highAddr + nextLow
	local low		= status.MemoryProvider:Read(address)
	local high		= status.MemoryProvider:Read(nextAddr)
	return high * 256 + low
end

local function ReadProgramByte(status)
	local value		= ReadByte(status, status.Registers.PC)
	status.Registers.PC	= status.Registers.PC + 1
	return value
end

--------------------------------------------------

local function PushStack(status, value)
	status.MemoryProvider:Write(0x0100 + status.Registers.S, value)
	status.Registers.S	= (status.Registers.S - 1) % 0x0100
end
local function PopStack(status)
	status.Registers.S	= (status.Registers.S + 1) % 0x0100
	return status.MemoryProvider:Read(0x0100 + status.Registers.S)
end

--------------------------------------------------

local function TraceFormat(status)
	status.TraceLogProvider(string.format("%-16s; PC=%04X, A=%02X, X=%02X, Y=%02X, S=%02X, P=%02X %s, Cycle=%d", status.InstructionString,
		status.InstructionAddress, status.Registers.A, status.Registers.X, status.Registers.Y, status.Registers.S, status.Registers.P,
		StatusFlagToString(status.Registers.P), status.CycleCounter
	))
end

local function TraceLogBefore(status, format, operand)
	status.InstructionString	= string.format(format, operand)
	if(status.BeforeTracelog)then
		TraceFormat(status)
	end
end
local function TraceLogAfter(status)
	if(status.AfterTracelog)then
		TraceFormat(status)
	end
end

--------------------------------------------------
-- Instruction table
--------------------------------------------------

local function Addressing_Implied(status, instName)
	TraceLogBefore(status, instName)
	status.NextInstructionAddress	= status.Registers.PC
end
local function Addressing_Accumulator(status, instName)
	TraceLogBefore(status, instName .. " A", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return status.Registers.A
end
local function Addressing_Immediate(status, instName)
	local operand		= ReadProgramByte(status)
	TraceLogBefore(status, instName .. " #$%02X", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return operand
end
local function Addressing_Zeropage(status, instName, read)
	local operand		= ReadProgramByte(status)
	TraceLogBefore(status, instName .. " $%02X", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, operand), operand
end
local function Addressing_ZeropageIndexedX(status, instName, read)
	local operand		= ReadProgramByte(status)
	local address		= GetLowByte(operand + status.Registers.X)
	TraceLogBefore(status, instName .. " $%02X, X", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, address), address
end
local function Addressing_ZeropageIndexedY(status, instName, read)
	local operand		= ReadProgramByte(status)
	local address		= GetLowByte(operand + status.Registers.Y)
	TraceLogBefore(status, instName .. " $%02X, Y", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, address), address
end
local function Addressing_Absolute(status, instName, read)
	local operand1		= ReadProgramByte(status)
	local operand2		= ReadProgramByte(status)
	local operand		= operand2 * 256 + operand1
	TraceLogBefore(status, instName .. " $%04X", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, operand), operand
end
local function Addressing_AbsoluteIndexedX(status, instName, read)
	local operand1		= ReadProgramByte(status)
	local operand2		= ReadProgramByte(status)
	local operand		= operand2 * 256 + operand1
	local address		= ToWord(operand + status.Registers.X)
	local addCycle		= 0
	if(GetHighByte(address) ~= operand2)then
		addCycle	= 1
	end
	TraceLogBefore(status, instName .. " $%04X, X", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, address), address, addCycle
end
local function Addressing_AbsoluteIndexedY(status, instName, read)
	local operand1		= ReadProgramByte(status)
	local operand2		= ReadProgramByte(status)
	local operand		= operand2 * 256 + operand1
	local address		= ToWord(operand + status.Registers.Y)
	local addCycle		= 0
	if(GetHighByte(address) ~= operand2)then
		addCycle	= 1
	end
	TraceLogBefore(status, instName .. " $%04X, Y", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, address), address, addCycle
end
local function Addressing_IndexedXIndirect(status, instName, read)
	local operand		= ReadProgramByte(status)
	local indAddr		= ReadPagedWord(status, ToByte(operand + status.Registers.X))
	TraceLogBefore(status, instName .. " ($%02X, X)", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, indAddr), indAddr
end
local function Addressing_IndirectIndexedY(status, instName, read)
	local operand		= ReadProgramByte(status)
	local indAddr		= ReadPagedWord(status, operand)
	local address		= ToWord(indAddr + status.Registers.Y)
	local addCycle		= 0
	if(GetHighByte(indAddr) ~= GetHighByte(address))then
		addCycle	= 1
	end
	TraceLogBefore(status, instName .. " ($%02X), Y", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadByte)(status, address), address, addCycle
end
local function Addressing_AbsoluteIndirect(status, instName, read)
	local operand1		= ReadProgramByte(status)
	local operand2		= ReadProgramByte(status)
	local operand		= operand2 * 256 + operand1
	local indAddr		= ReadPagedWord(status, operand)
	TraceLogBefore(status, instName .. " ($%04X)", operand)
	status.NextInstructionAddress	= status.Registers.PC
	return (read or ReadPagedWord)(status, indAddr), indAddr
end
local function Addressing_Relative(status, instName)
	local operand		= ReadProgramByte(status)
	local jmpAddr		= ToWord(ToChar(operand) + status.Registers.PC)
	TraceLogBefore(status, instName .. " $%04X", jmpAddr)
	status.NextInstructionAddress	= status.Registers.PC
	return jmpAddr
end

--------------------------------------------------

local function Instruction_ADC(status, value)
	local preg		= StatusFlagToTable(status.Registers.P)
	local carry		= 0
	if(preg.C)then
		carry		= 1
	end
	local preg		= StatusFlagToTable(status.Registers.P)
	local regA		= status.Registers.A
	local resHigh, resLow

	if(status.DisableDecimalMode or (not preg.D))then
		-- binary
		resHigh, resLow	= SplitWord(regA + value + carry)
	else
		-- decimal
		local lowNibble	= BitAnd(regA, 0x0F) + BitAnd(value, 0x0F) + carry
		local highNibble= BitAnd(regA, 0xF0) + BitAnd(value, 0xF0)
		if(lowNibble >= 0x0A)then
			lowNibble	= BitAnd(lowNibble - 0x0A, 0x0F)
			highNibble	= highNibble + 0x10
		end
		if(highNibble >= 0xA0)then
			highNibble	= highNibble - 0xA0
			resHigh		= 1
		else
			resHigh		= 0
		end
		resLow			= ToByte(highNibble + lowNibble)
	end

	status.Registers.A	= resLow

	local signA		= regA >= 0x80
	local signM		= value >= 0x80
	local signR		= resLow >= 0x80

	preg.C			= resHigh > 0
	preg.Z			= status.Registers.A == 0
	preg.V			= (signA == signM) and (signA ~= signR)
	preg.N			= status.Registers.A >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_AND(status, value)
	status.Registers.A	= BitAnd(status.Registers.A, value)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.A == 0
	preg.N			= status.Registers.A >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_ASL(status, value)
	local carry		= value >= 0x80
	value			= ToByte(value * 2)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.C			= carry
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_BIT(status, value)
	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= BitAnd(status.Registers.A, value) == 0
	preg.N			= value >= 0x80
	preg.V			= BitAnd(value, 0x40) ~= 0
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_DEC(status, value)
	value			= ToByte(value - 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_DEX(status)
	status.Registers.X	= ToByte(status.Registers.X - 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.X == 0
	preg.N			= status.Registers.X >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_DEY(status)
	status.Registers.Y	= ToByte(status.Registers.Y - 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.Y == 0
	preg.N			= status.Registers.Y >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_EOR(status, value)
	status.Registers.A	= BitXor(status.Registers.A, value)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.A == 0
	preg.N			= status.Registers.A >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_INC(status, value)
	value			= ToByte(value + 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_INX(status)
	status.Registers.X	= ToByte(status.Registers.X + 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.X == 0
	preg.N			= status.Registers.X >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_INY(status)
	status.Registers.Y	= ToByte(status.Registers.Y + 1)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.Y == 0
	preg.N			= status.Registers.Y >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_JMP(status, value)
	status.Registers.PC	= value
end
local function Instruction_LSR(status, value)
	local carry		= (value % 2) ~= 0
	value			= ToByte(value / 2)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.C			= carry
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_ORA(status, value)
	status.Registers.A	= BitOr(status.Registers.A, value)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= status.Registers.A == 0
	preg.N			= status.Registers.A >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_PLP(status)
	local stackPflag	= StatusFlagToTable(PopStack(status))
	local preg		= StatusFlagToTable(status.Registers.P)
	stackPflag.R		= preg.R
	stackPflag.B		= preg.B
	status.Registers.P	= StatusFlagTableToValue(stackPflag)
end
local function Instruction_ROL(status, value)
	local preg		= StatusFlagToTable(status.Registers.P)
	local beforeCarry	= 0
	if(preg.C)then
		beforeCarry	= 1
	end
	local afterCarry	= value >= 0x80
	value			= ToByte(value * 2 + beforeCarry)

	preg.C			= afterCarry
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_ROR(status, value)
	local preg		= StatusFlagToTable(status.Registers.P)
	local beforeCarry	= 0
	if(preg.C)then
		beforeCarry	= 0x80
	end
	local afterCarry	= (value % 2) ~= 0
	value			= ToByte(value / 2 + beforeCarry)

	preg.C			= afterCarry
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
	return value
end
local function Instruction_RTS(status)
	local lowAddr		= PopStack(status)
	local highAddr		= PopStack(status)
	status.Registers.PC	= highAddr * 256 + lowAddr
end
local function Instruction_SBC(status, value)
	local preg		= StatusFlagToTable(status.Registers.P)
	local carry		= 0
	if(not preg.C)then
		carry		= 1
	end
	local regA		= status.Registers.A
	local resHigh, resLow, result

	local binMode	= status.DisableDecimalMode or (not preg.D)
	if(binMode)then
		-- binary
		resHigh, resLow	= SplitWord(ToWord(regA - value - carry))
		result		= resLow
	else
		-- decimal
		-- TODO : check for accurate update of V flag
		local lowNibble	= BitAnd(regA, 0x0F) - BitAnd(value, 0x0F) - carry
		local highNibble= BitAnd(regA, 0xF0) - BitAnd(value, 0xF0)
		if(lowNibble < 0)then
			lowNibble	= BitAnd(lowNibble + 0x0A, 0x0F)
			highNibble	= highNibble - 0x10
		end
		if(highNibble < 0)then
			highNibble	= highNibble + 0xA0
			resHigh		= -1
		else
			resHigh		= 0
		end
		result			= ToByte(highNibble + lowNibble)
		resLow			= ToByte(regA - value - carry)
	end

	status.Registers.A	= result

	local signA		= regA >= 0x80
	local signM		= value >= 0x80
	local signR		= resLow >= 0x80

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.C			= resHigh == 0
	preg.Z			= status.Registers.A == 0
	preg.V			= (signA ~= signM) and (signM == signR)
	preg.N			= status.Registers.A >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end

local function Instruction_Branch(status, jmpAddr, flagName, flagSet)
	local preg		= StatusFlagToTable(status.Registers.P)
	local jump
	if(not flagSet)then	-- BxC
		jump		= not preg[flagName]
	else			-- BxS
		jump		= preg[flagName]
	end

	if(not jump)then
		return 0
	end

	local addCycle	= 0
	if(GetHighByte(status.Registers.PC) ~= GetHighByte(jmpAddr))then
		addCycle	= 1
	end

	status.Registers.PC	= jmpAddr

	return 1 + addCycle
end
local function Instruction_Compare(status, register, value)
	local result		= status.Registers[register] - value;
	local bResult		= ToByte(result)

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.C			= result >= 0
	preg.Z			= bResult == 0
	preg.N			= bResult >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_Load(status, register, value)
	status.Registers[register]	= value;
	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end
local function Instruction_Store(status, address, register)
	status.MemoryProvider:Write(address, status.Registers[register])
end
local function Instruction_TransferRegister(status, src, dst, protectStatus)
	local value		= status.Registers[src]
	status.Registers[dst]	= value
	if(protectStatus)then
		return
	end

	local preg		= StatusFlagToTable(status.Registers.P)
	preg.Z			= value == 0
	preg.N			= value >= 0x80
	status.Registers.P	= StatusFlagTableToValue(preg)
end

local function Instruction_Undefined(status)
	status.Halt		= true
	status.TraceLogProvider(string.format("Executed undefined instruction ; PC=%04X, A=%02X, X=%02X, Y=%02X, S=%02X, P=%02X %s, Cycle=%d",
		status.InstructionAddress, status.Registers.A, status.Registers.X, status.Registers.Y, status.Registers.S, status.Registers.P,
		StatusFlagToString(status.Registers.P), status.CycleCounter
	))
	status.NextInstructionAddress	= status.Registers.PC
	return 0
end

--------------------------------------------------

local instruction	= {
	[0x00]	= function(status)	-- BRK
		Addressing_Implied(status, "BRK")
		status:Break()
		return 7
	end;
	[0x01]	= function(status)	-- ORA (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "ORA")
		Instruction_ORA(status, value)
		return 6
	end;
	[0x02]	= Instruction_Undefined;
	[0x03]	= Instruction_Undefined;
	[0x04]	= Instruction_Undefined;
	[0x05]	= function(status)	-- ORA zp
		local value		= Addressing_Zeropage(status, "ORA")
		Instruction_ORA(status, value)
		return 3
	end;
	[0x06]	= function(status)	-- ASL zp
		local value, address	= Addressing_Zeropage(status, "ASL")
		value			= Instruction_ASL(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0x07]	= Instruction_Undefined;
	[0x08]	= function(status)	-- PHP
		Addressing_Implied(status, "PHP")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.R			= 1
		preg.B			= 1
		PushStack(status, StatusFlagTableToValue(preg))
		return 3
	end;
	[0x09]	= function(status)	-- ORA #imm
		local value		= Addressing_Immediate(status, "ORA")
		Instruction_ORA(status, value)
		return 2
	end;
	[0x0A]	= function(status)	-- ASL A
		local value		= Addressing_Accumulator(status, "ASL")
		status.Registers.A	= Instruction_ASL(status, value)
		return 2
	end;
	[0x0B]	= Instruction_Undefined;
	[0x0C]	= Instruction_Undefined;
	[0x0D]	= function(status)	-- ORA abs
		local value		= Addressing_Absolute(status, "ORA")
		Instruction_ORA(status, value)
		return 4
	end;
	[0x0E]	= function(status)	-- ASL abs
		local value, address	= Addressing_Absolute(status, "ASL")
		value			= Instruction_ASL(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x0F]	= Instruction_Undefined;
	[0x10]	= function(status)	-- BPL rel
		local jmpAddr		= Addressing_Relative(status, "BPL")
		local addCycle		= Instruction_Branch(status, jmpAddr, "N", false)
		return 2 + addCycle
	end;
	[0x11]	= function(status)	-- ORA abs, X
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "ORA")
		Instruction_ORA(status, value)
		return 5 + addCycle
	end;
	[0x12]	= Instruction_Undefined;
	[0x13]	= Instruction_Undefined;
	[0x14]	= Instruction_Undefined;
	[0x15]	= function(status)	-- ORA zp, X
		local value		= Addressing_ZeropageIndexedX(status, "ORA")
		Instruction_ORA(status, value)
		return 4
	end;
	[0x16]	= function(status)	-- ASL zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "ASL")
		value			= Instruction_ASL(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x17]	= Instruction_Undefined;
	[0x18]	= function(status)	-- CLC
		Addressing_Implied(status, "CLC")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.C			= false
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0x19]	= function(status)	-- ORA abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "ORA")
		Instruction_ORA(status, value)
		return 4 + addCycle
	end;
	[0x1A]	= Instruction_Undefined;
	[0x1B]	= Instruction_Undefined;
	[0x1C]	= Instruction_Undefined;
	[0x1D]	= function(status)	-- ORA abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "ORA")
		Instruction_ORA(status, value)
		return 4 + addCycle
	end;
	[0x1E]	= function(status)	-- ASL abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "ASL")
		value			= Instruction_ASL(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0x1F]	= Instruction_Undefined;
	[0x20]	= function(status)	-- JSR abs
		local value, address	= Addressing_Absolute(status, "JSR")
		local pushAddr		= status.Registers.PC - 1
		PushStack(status, GetHighByte(pushAddr))
		PushStack(status, GetLowByte(pushAddr))
		status.Registers.PC	= address
		return 6
	end;
	[0x21]	= function(status)	-- AND (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "AND")
		Instruction_AND(status, value)
		return 6
	end;
	[0x22]	= Instruction_Undefined;
	[0x23]	= Instruction_Undefined;
	[0x24]	= function(status)	-- BIT zp
		local value		= Addressing_Zeropage(status, "BIT")
		Instruction_BIT(status, value)
		return 3
	end;
	[0x25]	= function(status)	-- AND zp
		local value		= Addressing_Zeropage(status, "AND")
		Instruction_AND(status, value)
		return 3
	end;
	[0x26]	= function(status)	-- ROL zp
		local value, address	= Addressing_Zeropage(status, "ROL")
		value			= Instruction_ROL(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0x27]	= Instruction_Undefined;
	[0x28]	= function(status)	-- PLP
		Addressing_Implied(status, "PLP")
		Instruction_PLP(status)
		return 4
	end;
	[0x29]	= function(status)	-- AND #imm
		local value		= Addressing_Immediate(status, "AND")
		Instruction_AND(status, value)
		return 2
	end;
	[0x2A]	= function(status)	-- ROL A
		local value		= Addressing_Accumulator(status, "ROL")
		status.Registers.A	= Instruction_ROL(status, value)
		return 2
	end;
	[0x2B]	= Instruction_Undefined;
	[0x2C]	= function(status)	-- BIT abs
		local value		= Addressing_Absolute(status, "BIT")
		Instruction_BIT(status, value)
		return 4
	end;
	[0x2D]	= function(status)	-- AND abs
		local value		= Addressing_Absolute(status, "AND")
		Instruction_AND(status, value)
		return 4
	end;
	[0x2E]	= function(status)	-- ROL abs
		local value, address	= Addressing_Absolute(status, "ROL")
		value			= Instruction_ROL(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x2F]	= Instruction_Undefined;
	[0x30]	= function(status)	-- BMI rel
		local jmpAddr		= Addressing_Relative(status, "BMI")
		local addCycle		= Instruction_Branch(status, jmpAddr, "N", true)
		return 2 + addCycle
	end;
	[0x31]	= function(status)	-- AND abs, X
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "AND")
		Instruction_AND(status, value)
		return 5 + addCycle
	end;
	[0x32]	= Instruction_Undefined;
	[0x33]	= Instruction_Undefined;
	[0x34]	= Instruction_Undefined;
	[0x35]	= function(status)	-- AND zp, X
		local value		= Addressing_ZeropageIndexedX(status, "AND")
		Instruction_AND(status, value)
		return 4
	end;
	[0x36]	= function(status)	-- ROL zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "ROL")
		value			= Instruction_ROL(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x37]	= Instruction_Undefined;
	[0x38]	= function(status)	-- SEC
		Addressing_Implied(status, "SEC")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.C			= true
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0x39]	= function(status)	-- AND abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "AND")
		Instruction_AND(status, value)
		return 4 + addCycle
	end;
	[0x3A]	= Instruction_Undefined;
	[0x3B]	= Instruction_Undefined;
	[0x3C]	= Instruction_Undefined;
	[0x3D]	= function(status)	-- AND abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "AND")
		Instruction_AND(status, value)
		return 4 + addCycle
	end;
	[0x3E]	= function(status)	-- ROL abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "ROL")
		value			= Instruction_ROL(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0x3F]	= Instruction_Undefined;
	[0x40]	= function(status)	-- RTI
		Addressing_Implied(status, "RTI")
		Instruction_PLP(status)
		Instruction_RTS(status)
		return 6
	end;
	[0x41]	= function(status)	-- EOR (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "EOR")
		Instruction_EOR(status, value)
		return 6
	end;
	[0x42]	= Instruction_Undefined;
	[0x43]	= Instruction_Undefined;
	[0x44]	= Instruction_Undefined;
	[0x45]	= function(status)	-- EOR zp
		local value		= Addressing_Zeropage(status, "EOR")
		Instruction_EOR(status, value)
		return 3
	end;
	[0x46]	= function(status)	-- LSR zp
		local value, address	= Addressing_Zeropage(status, "LSR")
		value			= Instruction_LSR(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0x47]	= Instruction_Undefined;
	[0x48]	= function(status)	-- PHA
		Addressing_Implied(status, "PHA")
		PushStack(status, status.Registers.A)
		return 3
	end;
	[0x49]	= function(status)	-- EOR #imm
		local value		= Addressing_Immediate(status, "EOR")
		Instruction_EOR(status, value)
		return 2
	end;
	[0x4A]	= function(status)	-- LSR A
		local value		= Addressing_Accumulator(status, "LSR")
		status.Registers.A	= Instruction_LSR(status, value)
		return 2
	end;
	[0x4B]	= Instruction_Undefined;
	[0x4C]	= function(status)	-- JMP abs
		local value, address	= Addressing_Absolute(status, "JMP")
		Instruction_JMP(status, address)
		return 3
	end;
	[0x4D]	= function(status)	-- EOR abs
		local value		= Addressing_Absolute(status, "EOR")
		Instruction_EOR(status, value)
		return 4
	end;
	[0x4E]	= function(status)	-- LSR abs
		local value, address	= Addressing_Absolute(status, "LSR")
		value			= Instruction_LSR(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x4F]	= Instruction_Undefined;
	[0x50]	= function(status)	-- BVC rel
		local jmpAddr		= Addressing_Relative(status, "BVC")
		local addCycle		= Instruction_Branch(status, jmpAddr, "V", false)
		return 2 + addCycle
	end;
	[0x51]	= function(status)	-- EOR (zp), X
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "EOR")
		Instruction_EOR(status, value)
		return 5 + addCycle
	end;
	[0x52]	= Instruction_Undefined;
	[0x53]	= Instruction_Undefined;
	[0x54]	= Instruction_Undefined;
	[0x55]	= function(status)	-- EOR zp, X
		local value		= Addressing_ZeropageIndexedX(status, "EOR")
		Instruction_EOR(status, value)
		return 4
	end;
	[0x56]	= function(status)	-- LSR zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "LSR")
		value			= Instruction_LSR(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x57]	= Instruction_Undefined;
	[0x58]	= function(status)	-- CLI
		Addressing_Implied(status, "CLI")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.I			= false
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0x59]	= function(status)	-- EOR abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "EOR")
		Instruction_EOR(status, value)
		return 4 + addCycle
	end;
	[0x5A]	= Instruction_Undefined;
	[0x5B]	= Instruction_Undefined;
	[0x5C]	= Instruction_Undefined;
	[0x5D]	= function(status)	-- EOR abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "EOR")
		Instruction_EOR(status, value)
		return 4 + addCycle
	end;
	[0x5E]	= function(status)	-- LSR abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "LSR")
		value			= Instruction_LSR(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0x5F]	= Instruction_Undefined;
	[0x60]	= function(status)	-- RTS
		Addressing_Implied(status, "RTS")
		Instruction_RTS(status)
		status.Registers.PC	= status.Registers.PC + 1
		return 6
	end;
	[0x61]	= function(status)	-- ADC (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "ADC")
		Instruction_ADC(status, value)
		return 6
	end;
	[0x62]	= Instruction_Undefined;
	[0x63]	= Instruction_Undefined;
	[0x64]	= Instruction_Undefined;
	[0x65]	= function(status)	-- ADC zp
		local value		= Addressing_Zeropage(status, "ADC")
		Instruction_ADC(status, value)
		return 3
	end;
	[0x66]	= function(status)	-- ROR zp
		local value, address	= Addressing_Zeropage(status, "ROR")
		value			= Instruction_ROR(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0x67]	= Instruction_Undefined;
	[0x68]	= function(status)	-- PLA
		Addressing_Implied(status, "PLA")
		local value		= PopStack(status)
		status.Registers.A	= value
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.Z			= value == 0
		preg.N			= value >= 0x80
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 4
	end;
	[0x69]	= function(status)	-- ADC #imm
		local value		= Addressing_Immediate(status, "ADC")
		Instruction_ADC(status, value)
		return 2
	end;
	[0x6A]	= function(status)	-- ROR A
		local value		= Addressing_Accumulator(status, "ROR")
		status.Registers.A	= Instruction_ROR(status, value)
		return 2
	end;
	[0x6B]	= Instruction_Undefined;
	[0x6C]	= function(status)	-- JMP (zp)
		local value, address	= Addressing_AbsoluteIndirect(status, "JMP")
		Instruction_JMP(status, address)
		return 5
	end;
	[0x6D]	= function(status)	-- ADC abs
		local value		= Addressing_Absolute(status, "ADC")
		Instruction_ADC(status, value)
		return 4
	end;
	[0x6E]	= function(status)	-- ROR abs
		local value, address	= Addressing_Absolute(status, "ROR")
		value			= Instruction_ROR(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x6F]	= Instruction_Undefined;
	[0x70]	= function(status)	-- BVS rel
		local jmpAddr		= Addressing_Relative(status, "BVS")
		local addCycle		= Instruction_Branch(status, jmpAddr, "V", true)
		return 2 + addCycle
	end;
	[0x71]	= function(status)	-- ADC (zp), Y
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "ADC")
		Instruction_ADC(status, value)
		return 5 + addCycle
	end;
	[0x72]	= Instruction_Undefined;
	[0x73]	= Instruction_Undefined;
	[0x74]	= Instruction_Undefined;
	[0x75]	= function(status)	-- ADC zp, X
		local value		= Addressing_ZeropageIndexedX(status, "ADC")
		Instruction_ADC(status, value)
		return 4
	end;
	[0x76]	= function(status)	-- ROR zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "ROR")
		value			= Instruction_ROR(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0x77]	= Instruction_Undefined;
	[0x78]	= function(status)	-- SEI
		Addressing_Implied(status, "SEI")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.I			= true
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0x79]	= function(status)	-- ADC abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "ADC")
		Instruction_ADC(status, value)
		return 4 + addCycle
	end;
	[0x7A]	= Instruction_Undefined;
	[0x7B]	= Instruction_Undefined;
	[0x7C]	= Instruction_Undefined;
	[0x7D]	= function(status)	-- ADC abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "ADC")
		Instruction_ADC(status, value)
		return 4 + addCycle
	end;
	[0x7E]	= function(status)	-- ROR abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "ROR")
		value			= Instruction_ROR(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0x7F]	= Instruction_Undefined;
	[0x80]	= Instruction_Undefined;
	[0x81]	= function(status)	-- STA (zp, X)
		local value, address	= Addressing_IndexedXIndirect(status, "STA")
		Instruction_Store(status, address, "A")
		return 6
	end;
	[0x82]	= Instruction_Undefined;
	[0x83]	= Instruction_Undefined;
	[0x84]	= function(status)	-- STY zp
		local value, address	= Addressing_Zeropage(status, "STY")
		Instruction_Store(status, address, "Y")
		return 3
	end;
	[0x85]	= function(status)	-- STA zp
		local value, address	= Addressing_Zeropage(status, "STA")
		Instruction_Store(status, address, "A")
		return 3
	end;
	[0x86]	= function(status)	-- STX zp
		local value, address	= Addressing_Zeropage(status, "STX")
		Instruction_Store(status, address, "X")
		return 3
	end;
	[0x87]	= Instruction_Undefined;
	[0x88]	= function(status)	-- DEY
		Addressing_Implied(status, "DEY")
		Instruction_DEY(status)
		return 2
	end;
	[0x89]	= Instruction_Undefined;
	[0x8A]	= function(status)	-- TXA
		Addressing_Implied(status, "TXA")
		value			= Instruction_TransferRegister(status, "X", "A")
		return 2
	end;
	[0x8B]	= Instruction_Undefined;
	[0x8C]	= function(status)	-- STY abs
		local value, address	= Addressing_Absolute(status, "STY")
		Instruction_Store(status, address, "Y")
		return 4
	end;
	[0x8D]	= function(status)	-- STA abs
		local value, address	= Addressing_Absolute(status, "STA")
		Instruction_Store(status, address, "A")
		return 4
	end;
	[0x8E]	= function(status)	-- STX abs
		local value, address	= Addressing_Absolute(status, "STX")
		Instruction_Store(status, address, "X")
		return 4
	end;
	[0x8F]	= Instruction_Undefined;
	[0x90]	= function(status)	-- BCC rel
		local jmpAddr		= Addressing_Relative(status, "BCC")
		local addCycle		= Instruction_Branch(status, jmpAddr, "C", false)
		return 2 + addCycle
	end;
	[0x91]	= function(status)	-- STA (zp), Y
		local value, address	= Addressing_IndirectIndexedY(status, "STA")
		Instruction_Store(status, address, "A")
		return 6
	end;
	[0x92]	= Instruction_Undefined;
	[0x93]	= Instruction_Undefined;
	[0x94]	= function(status)	-- STY zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "STY")
		Instruction_Store(status, address, "Y")
		return 4
	end;
	[0x95]	= function(status)	-- STA zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "STA")
		Instruction_Store(status, address, "A")
		return 4
	end;
	[0x96]	= function(status)	-- STX zp, Y
		local value, address	= Addressing_ZeropageIndexedY(status, "STX")
		Instruction_Store(status, address, "X")
		return 4
	end;
	[0x97]	= Instruction_Undefined;
	[0x98]	= function(status)	-- TYA
		Addressing_Implied(status, "TYA")
		value			= Instruction_TransferRegister(status, "Y", "A")
		return 2
	end;
	[0x99]	= function(status)	-- STA abs, Y
		local value, address	= Addressing_AbsoluteIndexedY(status, "STA")
		Instruction_Store(status, address, "A")
		return 5
	end;
	[0x9A]	= function(status)	-- TXS
		Addressing_Implied(status, "TXS")
		value			= Instruction_TransferRegister(status, "X", "S", true)
		return 2
	end;
	[0x9B]	= Instruction_Undefined;
	[0x9C]	= Instruction_Undefined;
	[0x9D]	= function(status)	-- STA abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "STA")
		Instruction_Store(status, address, "A")
		return 5
	end;
	[0x9E]	= Instruction_Undefined;
	[0x9F]	= Instruction_Undefined;
	[0xA0]	= function(status)	-- LDY #imm
		local value		= Addressing_Immediate(status, "LDY")
		Instruction_Load(status, "Y", value)
		return 2
	end;
	[0xA1]	= function(status)	-- LDA (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "LDA")
		Instruction_Load(status, "A", value)
		return 6
	end;
	[0xA2]	= function(status)	-- LDX #imm
		local value		= Addressing_Immediate(status, "LDX")
		Instruction_Load(status, "X", value)
		return 2
	end;
	[0xA3]	= Instruction_Undefined;
	[0xA4]	= function(status)	-- LDY zp
		local value		= Addressing_Zeropage(status, "LDY")
		Instruction_Load(status, "Y", value)
		return 3
	end;
	[0xA5]	= function(status)	-- LDA zp
		local value		= Addressing_Zeropage(status, "LDA")
		Instruction_Load(status, "A", value)
		return 3
	end;
	[0xA6]	= function(status)	-- LDX zp
		local value		= Addressing_Zeropage(status, "LDX")
		Instruction_Load(status, "X", value)
		return 3
	end;
	[0xA7]	= Instruction_Undefined;
	[0xA8]	= function(status)	-- TAY
		Addressing_Implied(status, "TAY")
		value			= Instruction_TransferRegister(status, "A", "Y")
		return 2
	end;
	[0xA9]	= function(status)	-- LDA #imm
		local value		= Addressing_Immediate(status, "LDA")
		Instruction_Load(status, "A", value)
		return 2
	end;
	[0xAA]	= function(status)	-- TAX
		Addressing_Implied(status, "TAX")
		value			= Instruction_TransferRegister(status, "A", "X")
		return 2
	end;
	[0xAB]	= Instruction_Undefined;
	[0xAC]	= function(status)	-- LDY abs
		local value		= Addressing_Absolute(status, "LDY")
		Instruction_Load(status, "Y", value)
		return 4
	end;
	[0xAD]	= function(status)	-- LDA abs
		local value		= Addressing_Absolute(status, "LDA")
		Instruction_Load(status, "A", value)
		return 4
	end;
	[0xAE]	= function(status)	-- LDX abs
		local value		= Addressing_Absolute(status, "LDX")
		Instruction_Load(status, "X", value)
		return 4
	end;
	[0xAF]	= Instruction_Undefined;
	[0xB0]	= function(status)	-- BCS rel
		local jmpAddr		= Addressing_Relative(status, "BCS")
		local addCycle		= Instruction_Branch(status, jmpAddr, "C", true)
		return 2 + addCycle
	end;
	[0xB1]	= function(status)	-- LDA (zp), Y
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "LDA")
		Instruction_Load(status, "A", value)
		return 5 + addCycle
	end;
	[0xB2]	= Instruction_Undefined;
	[0xB3]	= Instruction_Undefined;
	[0xB4]	= function(status)	-- LDY zp, X
		local value		= Addressing_ZeropageIndexedX(status, "LDY")
		Instruction_Load(status, "Y", value)
		return 4
	end;
	[0xB5]	= function(status)	-- LDA zp, X
		local value		= Addressing_ZeropageIndexedX(status, "LDA")
		Instruction_Load(status, "A", value)
		return 4
	end;
	[0xB6]	= function(status)	-- LDX zp, Y
		local value		= Addressing_ZeropageIndexedY(status, "LDX")
		Instruction_Load(status, "X", value)
		return 4
	end;
	[0xB7]	= Instruction_Undefined;
	[0xB8]	= function(status)	-- CLV
		Addressing_Implied(status, "CLV")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.V			= false
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0xB9]	= function(status)	-- LDA abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "LDA")
		Instruction_Load(status, "A", value)
		return 4 + addCycle
	end;
	[0xBA]	= function(status)	-- TSX
		Addressing_Implied(status, "TSX")
		value			= Instruction_TransferRegister(status, "S", "X")
		return 2
	end;
	[0xBB]	= Instruction_Undefined;
	[0xBC]	= function(status)	-- LDY abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "LDY")
		Instruction_Load(status, "Y", value)
		return 4 + addCycle
	end;
	[0xBD]	= function(status)	-- LDA abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "LDA")
		Instruction_Load(status, "A", value)
		return 4 + addCycle
	end;
	[0xBE]	= function(status)	-- LDX abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "LDX")
		Instruction_Load(status, "X", value)
		return 4 + addCycle
	end;
	[0xBF]	= Instruction_Undefined;
	[0xC0]	= function(status)	-- CPY #imm
		local value		= Addressing_Immediate(status, "CPY")
		Instruction_Compare(status, "Y", value)
		return 2
	end;
	[0xC1]	= function(status)	-- CMP (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 6
	end;
	[0xC2]	= Instruction_Undefined;
	[0xC3]	= Instruction_Undefined;
	[0xC4]	= function(status)	-- CPY zp
		local value		= Addressing_Zeropage(status, "CPY")
		Instruction_Compare(status, "Y", value)
		return 3
	end;
	[0xC5]	= function(status)	-- CMP zp
		local value		= Addressing_Zeropage(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 3
	end;
	[0xC6]	= function(status)	-- DEC zp
		local value, address	= Addressing_Zeropage(status, "DEC")
		value			= Instruction_DEC(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0xC7]	= Instruction_Undefined;
	[0xC8]	= function(status)	-- INY
		Addressing_Implied(status, "INY")
		Instruction_INY(status)
		return 2
	end;
	[0xC9]	= function(status)	-- CMP #imm
		local value		= Addressing_Immediate(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 2
	end;
	[0xCA]	= function(status)	-- DEX
		Addressing_Implied(status, "DEX")
		Instruction_DEX(status)
		return 2
	end;
	[0xCB]	= Instruction_Undefined;
	[0xCC]	= function(status)	-- CPY abs
		local value		= Addressing_Absolute(status, "CPY")
		Instruction_Compare(status, "Y", value)
		return 4
	end;
	[0xCD]	= function(status)	-- CMP abs
		local value		= Addressing_Absolute(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 4
	end;
	[0xCE]	= function(status)	-- DEC abs
		local value, address	= Addressing_Absolute(status, "DEC")
		value			= Instruction_DEC(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0xCF]	= Instruction_Undefined;
	[0xD0]	= function(status)	-- BNE rel
		local jmpAddr		= Addressing_Relative(status, "BNE")
		local addCycle		= Instruction_Branch(status, jmpAddr, "Z", false)
		return 2 + addCycle
	end;
	[0xD1]	= function(status)	-- CMP (zp), Y
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 5 + addCycle
	end;
	[0xD2]	= Instruction_Undefined;
	[0xD3]	= Instruction_Undefined;
	[0xD4]	= Instruction_Undefined;
	[0xD5]	= function(status)	-- CMP zp, X
		local value		= Addressing_ZeropageIndexedX(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 4
	end;
	[0xD6]	= function(status)	-- DEC zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "DEC")
		value			= Instruction_DEC(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0xD7]	= Instruction_Undefined;
	[0xD8]	= function(status)	-- CLD
		Addressing_Implied(status, "CLD")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.D			= false
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0xD9]	= function(status)	-- CMP abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 4 + addCycle
	end;
	[0xDA]	= Instruction_Undefined;
	[0xDB]	= Instruction_Undefined;
	[0xDC]	= Instruction_Undefined;
	[0xDD]	= function(status)	-- CMP abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "CMP")
		Instruction_Compare(status, "A", value)
		return 4 + addCycle
	end;
	[0xDE]	= function(status)	-- DEC abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "DEC")
		value			= Instruction_DEC(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0xDF]	= Instruction_Undefined;
	[0xE0]	= function(status)	-- CPX #imm
		local value		= Addressing_Immediate(status, "CPX")
		Instruction_Compare(status, "X", value)
		return 2
	end;
	[0xE1]	= function(status)	-- SBC (zp, X)
		local value		= Addressing_IndexedXIndirect(status, "SBC")
		Instruction_SBC(status, value)
		return 6
	end;
	[0xE2]	= Instruction_Undefined;
	[0xE3]	= Instruction_Undefined;
	[0xE4]	= function(status)	-- CPX zp
		local value		= Addressing_Zeropage(status, "CPX")
		Instruction_Compare(status, "X", value)
		return 3
	end;
	[0xE5]	= function(status)	-- SBC zp
		local value		= Addressing_Zeropage(status, "SBC")
		Instruction_SBC(status, value)
		return 3
	end;
	[0xE6]	= function(status)	-- INC zp
		local value, address	= Addressing_Zeropage(status, "INC")
		value			= Instruction_INC(status, value)
		status.MemoryProvider:Write(address, value)
		return 5
	end;
	[0xE7]	= Instruction_Undefined;
	[0xE8]	= function(status)	-- INX
		Addressing_Implied(status, "INX")
		Instruction_INX(status)
		return 2
	end;
	[0xE9]	= function(status)	-- SBC #imm
		local value		= Addressing_Immediate(status, "SBC")
		Instruction_SBC(status, value)
		return 2
	end;
	[0xEA]	= function(status)	-- NOP
		Addressing_Implied(status, "NOP")
		return 2
	end;
	[0xEB]	= Instruction_Undefined;
	[0xEC]	= function(status)	-- CPX abs
		local value		= Addressing_Absolute(status, "CPX")
		Instruction_Compare(status, "X", value)
		return 4
	end;
	[0xED]	= function(status)	-- SBC abs
		local value		= Addressing_Absolute(status, "SBC")
		Instruction_SBC(status, value)
		return 4
	end;
	[0xEE]	= function(status)	-- INC abs
		local value, address	= Addressing_Absolute(status, "INC")
		value			= Instruction_INC(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0xEF]	= Instruction_Undefined;
	[0xF0]	= function(status)	-- BEQ rel
		local jmpAddr		= Addressing_Relative(status, "BEQ")
		local addCycle		= Instruction_Branch(status, jmpAddr, "Z", true)
		return 2 + addCycle
	end;
	[0xF1]	= function(status)	-- SBC (zp), Y
		local value, address, addCycle	= Addressing_IndirectIndexedY(status, "SBC")
		Instruction_SBC(status, value)
		return 5 + addCycle
	end;
	[0xF2]	= Instruction_Undefined;
	[0xF3]	= Instruction_Undefined;
	[0xF4]	= Instruction_Undefined;
	[0xF5]	= function(status)	-- SBC zp, X
		local value		= Addressing_ZeropageIndexedX(status, "SBC")
		Instruction_SBC(status, value)
		return 4
	end;
	[0xF6]	= function(status)	-- INC zp, X
		local value, address	= Addressing_ZeropageIndexedX(status, "INC")
		value			= Instruction_INC(status, value)
		status.MemoryProvider:Write(address, value)
		return 6
	end;
	[0xF7]	= Instruction_Undefined;
	[0xF8]	= function(status)	-- SED
		Addressing_Implied(status, "SED")
		local preg		= StatusFlagToTable(status.Registers.P)
		preg.D			= true
		status.Registers.P	= StatusFlagTableToValue(preg)
		return 2
	end;
	[0xF9]	= function(status)	-- SBC abs, Y
		local value, address, addCycle	= Addressing_AbsoluteIndexedY(status, "SBC")
		Instruction_SBC(status, value)
		return 4 + addCycle
	end;
	[0xFA]	= Instruction_Undefined;
	[0xFB]	= Instruction_Undefined;
	[0xFC]	= Instruction_Undefined;
	[0xFD]	= function(status)	-- SBC abs, X
		local value, address, addCycle	= Addressing_AbsoluteIndexedX(status, "SBC")
		Instruction_SBC(status, value)
		return 4 + addCycle
	end;
	[0xFE]	= function(status)	-- INC abs, X
		local value, address	= Addressing_AbsoluteIndexedX(status, "INC")
		value			= Instruction_INC(status, value)
		status.MemoryProvider:Write(address, value)
		return 7
	end;
	[0xFF]	= Instruction_Undefined;
}

--------------------------------------------------
-- Function
--------------------------------------------------

local function CheckStatus(status)
	return (not status.Halt) and (status.MemoryProvider ~= nil)
end

local function ExecuteInstruction(status)
	status.InstructionAddress	= status.Registers.PC
	status.NextInstructionAddress	= nil
	status.InstructionLength	= 1
	status.InstructionString	= ""

	local opcode	= ReadProgramByte(status)
	if(instruction[opcode])then
		status.WaitCycleCounter		= instruction[opcode](status)
		status.InstructionLength	= ToWord(status.NextInstructionAddress + 0x10000 - status.InstructionAddress)
		TraceLogAfter(status)
	end
end

--------------------------------------------------
-- Processor object
--------------------------------------------------

local L6502	= {}
function L6502.new(MemoryProvider, TraceLogProvider)
	local status		= {}
	status.Registers	= {
		A	= 0x00;
		X	= 0x00;
		Y	= 0x00;
		S	= 0x00;
		P	= 0x00;
		PC	= 0x0000;
	}
	status.MemoryProvider		= MemoryProvider	or L6502Memory.new()
	status.TraceLogProvider		= TraceLogProvider	or function() end
	status.CycleCounter		= 0
	status.WaitCycleCounter		= 0
	status.PendingReset		= false
	status.PendingIrq		= false
	status.PendingBrk		= false
	status.PendingNmi		= false
	status.Halt			= false

	-- User control
	status.DisableDecimalMode	= false
	status.BeforeTracelog		= true
	status.AfterTracelog		= false
	status.AfterInterruptCheck	= true

	function status:Reset()
		status.CycleCounter	= 0
		status.WaitCycleCounter	= 0
		self.Halt		= false
		self.PendingReset	= true
	end
	function status:Interrupt()
		self.PendingIrq		= not StatusFlagToTable(self.Registers.P).I
	end
	function status:Break()
		self.PendingBrk		= true
	end
	function status:NMI()
		self.PendingNmi		= true
	end
	function status:InterruptBypass()
		local function internalInterrupt(vectoraddr, flagB)
			-- push status
			PushStack(self, GetHighByte(self.Registers.PC))
			PushStack(self, GetLowByte(self.Registers.PC))
			PushStack(self, self.Registers.P)

			-- fetch interrupt address
			self.Registers.PC	= ReadWord(self, vectoraddr)

			-- set B,I flag
			local preg		= StatusFlagToTable(self.Registers.P)
			preg.B			= flagB
			preg.I			= true
			self.Registers.P	= StatusFlagTableToValue(preg)
		end

		-- Interrupt
		if(self.PendingReset)then
			-- fetch interrupt address
			self.Registers.PC	= ReadWord(self, 0xFFFC)

			-- set registers
			self.Registers.A	= 0
			self.Registers.X	= 0
			self.Registers.Y	= 0
			self.Registers.S	= 0xFD
			self.Registers.P	= 0x34	-- nvRBdIzc

			self.PendingReset	= false
		elseif(self.PendingIrq)then
			internalInterrupt(0xFFFE, false)
			self.PendingIrq		= false
		elseif(self.PendingBrk)then
			internalInterrupt(0xFFFE, true)
			self.PendingBrk		= false
		elseif(self.PendingNmi)then
			internalInterrupt(0xFFFA, false)
			self.PendingNmi		= false
		end
	end
	function status:Clock()
		-- Instruction waiting
		if(not CheckStatus(self))then
			self.CycleCounter	= self.CycleCounter + 1
			return
		end

		if(self.WaitCycleCounter <= 0)then
			self:InterruptBypass()

			-- Normal
			ExecuteInstruction(self)
		end
		self.CycleCounter	= self.CycleCounter + 1
		self.WaitCycleCounter	= self.WaitCycleCounter - 1

		if(self.AfterInterruptCheck and (self.WaitCycleCounter <= 0))then
			self:InterruptBypass()
		end
	end
	function status:Step()
		repeat
			status:Clock()
		until(status.WaitCycleCounter <= 0)
	end

	function status.Registers:GetStringStatus()
		return StatusFlagToString(self.Registers.P)
	end

	return status
end

return L6502

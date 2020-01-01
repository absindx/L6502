----------------------------------------------------------------------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########                        ######        ########      ####      ####  --
--  ####            ####          ####              ##    ####    ####      ####                    ####  ####    ####    ####    ######  ######  --
--  ####          ####            ############    ####      ####          ######                  ####      ####  ####            ##############  --
--  ####          ############              ####  ####      ####      ########      ############  ####      ####    ##########    ##############  --
--  ####          ####      ####            ####  ####      ####    ########        ############  ##############            ####  ####  ##  ####  --
--  ####          ####      ####  ####      ####    ####    ##    ######                          ####      ####  ####      ####  ####      ####  --
--  ############    ##########      ##########        ######      ##############                  ####      ####    ##########    ####      ####  --
--                                                                                                                                                --
----------------------------------------------------------------------------------------------------------------------------------------------------

--[[ Syntax
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
	LDX	IOPort+2	; use expression
	RTS			; 
.Data	.db	$AA, $BB, $CC	; define data byte array
]]
--[[ Expression
	+, -, *, /, %, <<, >>, &, |, ^
]]

--------------------------------------------------

--[[ Lexicon
directive			; .org
	(argument)		; $xxxx
label				; xxxx:
instruction			; LDA
	(operand)		; $xxxx
define = value			; def = $xxxx
]]

--[[ lex
lex
	Address	= Address
	Line	= Line number
	Label
		Address	= Address
		LocalLabel
			Name
				Address	= Address
	+
		Address, Address, ...
	-
		Address, Address, ...
	Define
		Name
	LocalScopeName	= "xxx"

]]

--------------------------------------------------
-- std functions
--------------------------------------------------

local find	= string.find
local sub	= string.sub
local gsub	= string.gsub
local match	= string.match

--------------------------------------------------
-- Utility
--------------------------------------------------

local function ToByte(v)
	return math.floor(v) % (2^8)
end
local function ToWord(v)
	return math.floor(v) % (2^16)
end
local function HighByte(value)
	return math.floor(value / 0x100) % 0x100
end
local function LowByte(value)
	return math.floor(value) % 0x100
end

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

--------------------------------------------------

local function split(str, delimiter)
	local list	= {}
	local i		= 1
	local pos	= 1
	while(true)do
		local s,e	= find(str, delimiter, pos)
		if(s)then
			list[i]	= sub(str, pos, s-1)
			pos	= e+1
		else
			list[i]	= sub(str, pos)
			break
		end
		i	= i+1
	end
	return list
end

local function trim(str)
	return match(str, "^%s*(.-)%s*$")
end
local function splitSpace(str)
	return match(str, "([^%s]+)%s*(.*)")
end
local function splitComma(str)
	return match(str, "([^%s,]*),%s*(.*)")
end
local function splitCommaOrSpace(str)
	return match(str, "([^%s,]*),?%s*(.*)")
end

--------------------------------------------------
-- Instruction
--------------------------------------------------

local addressingName	= {
	"Implied",		--  1;
	"Accumulator",		--  2;
	"Immediate",		--  3;
	"Zeropage",		--  4;
	"ZeropageIndexedX",	--  5;
	"ZeropageIndexedY",	--  6;
	"Absolute",		--  7;
	"AbsoluteIndexedX",	--  8;
	"AbsoluteIndexedY",	--  9;
	"IndexedXIndirect",	-- 10;
	"IndirectIndexedY",	-- 11;
	"AbsoluteIndirect",	-- 12;
	"Relative"		-- 13;
}
local addressingType	= {
	Implied			=  1;
	Accumulator		=  2;
	Immediate		=  3;
	Zeropage		=  4;
	ZeropageIndexedX	=  5;
	ZeropageIndexedY	=  6;
	Absolute		=  7;
	AbsoluteIndexedX	=  8;
	AbsoluteIndexedY	=  9;
	IndexedXIndirect	= 10;
	IndirectIndexedY	= 11;
	AbsoluteIndirect	= 12;
	Relative		= 13;
}
local instructionLength	= {
	1,	-- Implied
	1,	-- Accumulator
	2,	-- Immediate
	2,	-- Zeropage
	2,	-- ZeropageIndexedX
	2,	-- ZeropageIndexedY
	3,	-- Absolute
	3,	-- AbsoluteIndexedX
	3,	-- AbsoluteIndexedY
	2,	-- IndexedXIndirect
	2,	-- IndirectIndexedY
	3,	-- AbsoluteIndirect
	2,	-- Relative
}
local instructionTable	= {
	--	   impl  acc   imm   zp    zp,x  zp,y  abs   abs,x abs,y (zp,x)(zp),y(abs) rel
	ADC	= {nil,  nil,  0x69, 0x65, 0x75, nil,  0x6D, 0x7D, 0x79, 0x61, 0x71, nil,  nil };
	AND	= {nil,  nil,  0x29, 0x25, 0x35, nil,  0x2D, 0x3D, 0x39, 0x21, 0x31, nil,  nil };
	ASL	= {nil,  0x0A, nil,  0x06, 0x16, nil,  0x0E, 0x1E, nil,  nil,  nil,  nil,  nil };
	BCC	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0x90};
	BCS	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0xB0};
	BEQ	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0xF0};
	BIT	= {nil,  nil,  nil,  0x24, nil,  nil,  0x2C, nil,  nil,  nil,  nil,  nil,  nil };
	BMI	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0x30};
	BNE	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0xD0};
	BPL	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0x10};
	BRK	= {0x00, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	BVC	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0x50};
	BVS	= {nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  0x70};
	CLC	= {0x18, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	CLD	= {0xD8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	CLI	= {0x58, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	CLV	= {0xB8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	CMP	= {nil,  nil,  0xC9, 0xC5, 0xD5, nil,  0xCD, 0xDD, 0xD9, 0xC1, 0xD1, nil,  nil };
	CPX	= {nil,  nil,  0xE0, 0xE4, nil,  nil,  0xEC, nil,  nil,  nil,  nil,  nil,  nil };
	CPY	= {nil,  nil,  0xC0, 0xC4, nil,  nil,  0xCC, nil,  nil,  nil,  nil,  nil,  nil };
	DEC	= {nil,  nil,  nil,  0xC6, 0xD6, nil,  0xCE, 0xDE, nil,  nil,  nil,  nil,  nil };
	DEX	= {0xCA, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	DEY	= {0x88, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	EOR	= {nil,  nil,  0x49, 0x45, 0x55, nil,  0x4D, 0x5D, 0x59, 0x41, 0x51, nil,  nil };
	INC	= {nil,  nil,  nil,  0xE6, 0xF6, nil,  0xEE, 0xFE, nil,  nil,  nil,  nil,  nil };
	INX	= {0xE8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	INY	= {0xC8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	JMP	= {nil,  nil,  nil,  nil,  nil,  nil,  0x4C, nil,  nil,  nil,  nil,  0x6C, nil };
	JSR	= {nil,  nil,  nil,  nil,  nil,  nil,  0x20, nil,  nil,  nil,  nil,  nil,  nil };
	LDA	= {nil,  nil,  0xA9, 0xA5, 0xB5, nil,  0xAD, 0xBD, 0xB9, 0xA1, 0xB1, nil,  nil };
	LDX	= {nil,  nil,  0xA2, 0xA6, nil,  0xB6, 0xAE, nil,  0xBE, nil,  nil,  nil,  nil };
	LDY	= {nil,  nil,  0xA0, 0xA4, 0xB4, nil,  0xAC, 0xBC, nil,  nil,  nil,  nil,  nil };
	LSR	= {nil,  0x4A, nil,  0x46, 0x56, nil,  0x4E, 0x5E, nil,  nil,  nil,  nil,  nil };
	NOP	= {0xEA, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	ORA	= {nil,  nil,  0x09, 0x05, 0x15, nil,  0x0D, 0x1D, 0x19, 0x01, 0x11, nil,  nil };
	PHA	= {0x48, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	PHP	= {0x08, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	PLA	= {0x68, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	PLP	= {0x28, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	ROL	= {nil,  0x2A, nil,  0x26, 0x36, nil,  0x2E, 0x3E, nil,  nil,  nil,  nil,  nil };
	ROR	= {nil,  0x6A, nil,  0x66, 0x76, nil,  0x6E, 0x7E, nil,  nil,  nil,  nil,  nil };
	RTI	= {0x40, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	RTS	= {0x60, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	SBC	= {nil,  nil,  0xE9, 0xE5, 0xF5, nil,  0xED, 0xFD, 0xF9, 0xE1, 0xF1, nil,  nil };
	SEC	= {0x38, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	SED	= {0xF8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	SEI	= {0x78, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	STA	= {nil,  nil,  nil,  0x85, 0x95, nil,  0x8D, 0x9D, 0x99, 0x81, 0x91, nil,  nil };
	STX	= {nil,  nil,  nil,  0x86, nil,  0x96, 0x8E, nil,  nil,  nil,  nil,  nil,  nil };
	STY	= {nil,  nil,  nil,  0x84, 0x94, nil,  0x8C, nil,  nil,  nil,  nil,  nil,  nil };
	TAX	= {0xAA, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	TAY	= {0xA8, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	TSX	= {0xBA, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	TXA	= {0x8A, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	TXS	= {0x9A, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
	TYA	= {0x98, nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil,  nil };
}

--------------------------------------------------
-- Parser
--------------------------------------------------

local function incrementAddress(lex, token, incremental)
	if(lex.Address > 0xFFFF)then
		token.ErrorMessage	= "Address range exceeded."
		return false
	end
	lex.Address	= lex.Address + (incremental or 1)
	return true
end

--------------------------------------------------

local function formatString(line)
	-- remove comment
	line	= gsub(line, ";.*", "")

	-- remove contiguous space
	line	= gsub(line, "%s+", " ")

	-- remove first and last space
	line	= trim(line)

	return line
end

local function decodeValue(str)
	local m

	-- hex "$xx"
	m	= match(str, "%$([^%s]+)")
	if(m)then
		return tonumber(m, 16)
	end

	-- bin "%xxxxxxxx"
	m	= match(str, "%%([^%s]+)")
	if(m)then
		return tonumber(m, 2)
	end

	-- dec "xx"
	m	= match(str, "[^%s]+")
	if(m)then
		return tonumber(m, 10)
	end

	return nil
end

local function splitDataArray(str)
	local data	= {}
	local value

	while((str~=nil) and (#str>0))do
		value, str	= splitCommaOrSpace(str)
		data[#data+1]	= value
	end
	return data, str
end

--------------------------------------------------

local operators	= {
	["+"]	= function (a, b)
		return a + b
	end;
	["-"]	= function (a, b)
		return a - b
	end;
	["*"]	= function (a, b)
		return a * b
	end;
	["/"]	= function (a, b)
		return a / b
	end;
	["%"]	= function (a, b)
		return a % b
	end;
	["<<"]	= function (a, b)
		return a * (2^b)
	end;
	[">>"]	= function (a, b)
		return math.floor(a / (2^b))
	end;
	["&"]	= function (a, b)
		return BitAnd(a, b)
	end;
	["|"]	= function (a, b)
		return BitOr(a, b)
	end;
	["^"]	= function (a, b)
		return BitXor(a, b)
	end;
}

local function resolveValue(lex, name, depth)
	depth	= depth	or 1
	if(depth > 100)then
		return nil, "The definition is too deep."
	end

	local value

	-- define
	if(lex.Define[name])then
		return resolveValue(lex, lex.Define[name], depth+1)
	end

	-- +
	if(name == "+")then
		local plus	= lex["+"]
		local origin	= lex.Address
		local address
		for i=#plus,1,-1 do
			if(plus[i] < origin)then
				break
			end
			address	= plus[i]
		end
		if(address)then
			return address, "+ label"
		else
			return nil, "+ label resolution failed."
		end
	end
	-- -
	if(name == "-")then
		local minus	= lex["-"]
		local origin	= lex.Address
		local address
		for i=1,#minus do
			if(origin < minus[i])then
				break
			end
			address	= minus[i]
		end
		if(address)then
			return address, "- label"
		else
			return nil, "- label resolution failed."
		end
	end

	-- local label
	if(find(name, "%.") == 1)then
		local scope	= lex.Label[lex.LocalScopeName]
		if(not scope)then
			return nil, "Scope resolution failed."
		end
		if(not scope.LocalLabel[name])then
			return nil, "Local label resolution failed."
		end
		return scope.LocalLabel[name].Address, "local label"
	end

	-- global label
	if(lex.Label[name])then
		return lex.Label[name].Address, "global label"
	end

	-- expression
	local expLeft, expOperator, expRight	= match(name, "(.-)%s*([%+%-*/%%<>&|%^]+)%s*([^%s%+%-*/%%<>&|%^]+)$")
	if((expLeft~=nil) and (#expLeft > 0) and (operators[expOperator]~=nil))then
		expLeft		= resolveValue(lex, expLeft, depth+1)
		expRight	= resolveValue(lex, expRight, depth+1)
		if((expLeft==nil) or (expRight==nil))then
			return nil, "Expression resolution failed."
		end
		return operators[expOperator](expLeft, expRight)
	end

	-- number
	value	= decodeValue(name)
	if(value)then
		return value, "number"
	end

	return nil, "Value resolution failed."
end

--------------------------------------------------

local tokenType	= {
	DirectiveBank		= 101;	-- ".bank"
	DirectiveOrigin		= 102;	-- ".org"
	DirectiveDataByte	= 103;	-- ".db"
	DirectiveDataWord	= 104;	-- ".dw"
	DirectiveIncludeSource	= 105;	-- ".incldue"
	DirectiveIncludeBinary	= 106;	-- ".incbin"
	DirectiveMacroStart	= 107;	-- ".macro"
	DirectiveMacroEnd	= 108;	-- ".endm"
	DirectiveIf		= 109;	-- ".if"
	DirectiveIfDef		= 110;	-- ".ifdef"
	DirectiveIfNDef		= 111;	-- ".ifndef"
	DirectiveElse		= 112;	-- ".else"
	DirectiveEndif		= 113;	-- ".endif"
	DirectiveFail		= 114;	-- ".fail"

	LabelGlobal		= 201;	-- "Xxx:"
	LabelLocal		= 202;	-- ".xxx"
	LabelPlus		= 203;	-- "+"
	LabelMinus		= 204;	-- "-"

	Instruction		= 301;	-- "LDA"

	Define			= 401;	-- "Xxx=YY"
}

local function createToken(lex, token, ...)
	local unpack	= unpack	or table.unpack
	return {
		Line		= lex.Line;
		Bank		= lex.Bank;
		Address		= lex.Address;
		Token		= token;
		unpack({...})
	}
end
local function createErrorToken(lex, message)
	return {
		Line		= lex.Line;
		ErrorMessage	= message;
	}
end

--------------------------------------------------

local function checkDirective(lex, line)
	local directive, remain	= splitSpace(line)
	directive	= string.lower(directive)

	if(directive == ".bank")then
		local bank, remain	= splitSpace(remain)
		if(not bank)then
			return createErrorToken(lex, "There is no bank number.")
		end
		local resolvedBank	= resolveValue(lex, address)
		if(not resolvedBank)then
			return createErrorToken(lex, "There is no bank number.")
		end
		lex.Bank	= resolvedBank
		return createToken(lex, tokenType.DirectiveBank, bank), remain
	elseif(directive == ".org")then
		local address, remain	= splitSpace(remain)
		if(not address)then
			return createErrorToken(lex, "There is no address.")
		end
		local resolvedAddress	= resolveValue(lex, address)
		if(not resolvedAddress)then
			return createErrorToken(lex, "There is no address.")
		end
		lex.Address	= resolvedAddress
		return createToken(lex, tokenType.DirectiveOrigin, address), remain
	elseif(directive == ".db")then
		local data, remain	= splitDataArray(remain)
		local token		= createToken(lex, tokenType.DirectiveDataByte, data)
		incrementAddress(lex, token, #data)
		return token, remain
	elseif(directive == ".dw")then
		local data, remain	= splitDataArray(remain)
		local token		= createToken(lex, tokenType.DirectiveDataWord, data)
		incrementAddress(lex, token, #data * 2)
		return token, remain
--	no plan to implement it
--	elseif(directive == ".include")then
--	elseif(directive == ".incbin")then
--	elseif(directive == ".macro")then
--	elseif(directive == ".endm")then
--	elseif(directive == ".if")then
--	elseif(directive == ".ifdef")then
--	elseif(directive == ".ifndef")then
--	elseif(directive == ".else")then
--	elseif(directive == ".endif")then
--	elseif(directive == ".fail")then
	else
		return nil
	end
end
local function checkLabel(lex, line)
	local word, remain			= splitSpace(line)
	local globalLabel, globalLabelRemain	= match(line, "^([^%s]+):%s*(.*)")

	if(globalLabel)then
		if(find(globalLabel, "[%+-*/%%<>&|%^#%$%.]"))then
			return createErrorToken(lex, "Invalid label name.")
		elseif(lex.Label[globalLabel])then
			return createErrorToken(lex, "Global label name conflict.")
		end
		lex.LocalScopeName	= globalLabel
		lex.Label[globalLabel]	= {
			Address		= lex.Address;
			LocalLabel	= {};
		}
		return createToken(lex, tokenType.LabelGlobal, globalLabel), globalLabelRemain
	elseif(find(word, "%.") == 1)then
		if(find(word, "[%+-*/%%<>&|%^#%$]"))then
			return createErrorToken(lex, "Invalid label name.")
		elseif((lex.LocalScopeName==nil) or (lex.Label[lex.LocalScopeName]==nil))then
			return createErrorToken(lex, "Local label used in global scope.")
		elseif(lex.Label[lex.LocalScopeName].LocalLabel[word])then
			return createErrorToken(lex, "Local label name conflict.")
		end
		lex.Label[lex.LocalScopeName].LocalLabel[word]	= {
			Address		= lex.Address;
		}
		return createToken(lex, tokenType.LabelLocal, word), remain
	elseif(word == "+")then
		lex["+"][#lex["+"]+1]	= lex.Address
		return createToken(lex, tokenType.LabelPlus), remain
	elseif(word == "-")then
		lex["-"][#lex["-"]+1]	= lex.Address
		return createToken(lex, tokenType.LabelMinus), remain
	end
	return nil
end
local function checkInstruction(lex, line)
	local instruction, operand	= match(line, "([^%s]+)%s*(.*)")
	instruction			= string.upper(instruction)
	operand				= operand	or ""
	local opcodeTable		= instructionTable[instruction]
	if(not opcodeTable)then
		return nil
	end

	local addressingMatch	= {
--		"",				addressingType.Implied,			false,	--  1 ""
		"([Aa])",			addressingType.Accumulator,		false,	--  2 "A"
		"(#(.+))",			addressingType.Immediate,		false,	--  3 "#xx"
		"(%(([^,]+),%s*[Xx]%))",	addressingType.IndexedXIndirect,	false,	-- 10 "(xx, X)"
		"(%(([^,]+)%),%s*[Yy])",	addressingType.IndirectIndexedY,	false,	-- 11 "(xx), Y"
		"(%((.+)%))",			addressingType.AbsoluteIndirect,	false,	-- 12 "(xx)"
		"(<([^,]+),%s*[Xx])",		addressingType.ZeropageIndexedX,	false,	--  5 "<xx, X"
		"(<([^,]+),%s*[Yy])",		addressingType.ZeropageIndexedY,	false,	--  6 "<xx, Y"
		"(<(.+))",			addressingType.Zeropage,		false,	--  4 "<xx"
		"(([^,]+),%s*[Xx])",		addressingType.AbsoluteIndexedX,	false,	--  8 "xx, X"
		"((.+),%s*[Yy])",		addressingType.AbsoluteIndexedY,	false,	--  9 "xx, Y"
		"((.+))",			addressingType.Absolute,		true,	--  7 "xx"
		"((.+))",			addressingType.Relative,		true,	-- 13 "xx"
	}

	local addressing, matchedAll, argument
	if(operand ~= "")then
		for i=1,#addressingMatch,3 do
			matchedAll, argument, remain	= match(operand, addressingMatch[i] .. "%s*(.*)")
			if(matchedAll == operand)then
				if(opcodeTable[addressingMatch[i+1]] ~= nil)then
					addressing		= addressingMatch[i+1]
					break
				elseif(not addressingMatch[i+2])then
					return createErrorToken(lex, "This addressing can not be used with this instruction.")
				end
			end
		end
	elseif(opcodeTable[addressingType.Implied])then
		addressing	= addressingType.Implied
		argument	= ""
	end

	if(not addressing)then
		return createErrorToken(lex, "Unknown addressing.")
	end

	local token	= createToken(lex, tokenType.Instruction, instruction, addressing, argument, opcodeTable[addressing])
	incrementAddress(lex, token, instructionLength[addressing])
	return token, remain
end
local function checkDefine(lex, line)
	local def, val	= match(line, "([^%s]+)%s*=%s*(.*)")
	if((def~=nil) and (val~=nil))then
		if(find(def, "[%+-*/%%<>&|%^#%$]"))then
			return createErrorToken(lex, "Invalid label name.")
		elseif(lex.Define[def])then
			return createErrorToken(lex, "Define name conflict.")
		end
		lex.Define[def]	= val
		return createToken(lex, tokenType.Define, def, val), remain, nil
	end
	return nil
end

--------------------------------------------------

local L6502Assembler	= {}
function L6502Assembler.Assemble(code, origin, print)
	origin	= origin	or 0x0000
	print	= print		or function() end

	local tokens	= {}
	local lex	= {
		Address	= origin;
		Bank	= 0;
		Label	= {};
		["+"]	= {};
		["-"]	= {};
		Define	= {};
		LocalScopeName	= nil;
	}
	local lines	= split(code, "\n")
	local line, remain, token, bank, address, addressing, value, data, distance, errMsg
	local isError	= false

	local function errorMessage(token, message)
		print(string.format("\tLine %3d : %s", token.Line, message))
		isError	= true
	end

	--print("pass 1")
	local function pushToken(token)
		if(token and token.ErrorMessage)then
			errorMessage(token, token.ErrorMessage)
			return true
		elseif(token)then
			tokens[#tokens+1]	= token
			return true
		else
			return false
		end
	end
	for i=1,#lines do
		lex.Line	= i
		line	= formatString(lines[i])
		while((line~=nil) and (#line>0))do
			(function()
				token, remain	= checkDirective(lex, line)
				if(pushToken(token))then
					return	-- continue
				end

				token, remain	= checkLabel(lex, line)
				if(pushToken(token))then
					return	-- continue
				end

				token, remain	= checkInstruction(lex, line)
				if(pushToken(token))then
					return	-- continue
				end

				token, remain	= checkDefine(lex, line)
				if(pushToken(token))then
					return	-- continue
				end

				errorMessage(lex, "Detected unknown token.")
				return	-- continue
			end)()
			line		= remain
		end
	end
	if(isError)then
		return nil
	end

	table.sort(lex["+"])
	table.sort(lex["-"])

	--print("pass 2")
	lex.Address		= origin
	lex.Bank		= 0
	lex.LocalScopeName	= nil
	local bin		= {}
	local function newBinData(bank, origin)
		return {
			Bank	= bank		or 0;
			Origin	= origin	or 0;
			Data	= {};
			Line	= {};
		}
	end
	bin[#bin+1]		= newBinData(0, origin)
	for i=1,#tokens do
		local currentBin	= bin[#bin]
		local function pushValue(value)
			currentBin.Data[#currentBin.Data+1]	= ToByte(value)
			currentBin.Line[#currentBin.Line+1]	= lex.Line
			incrementAddress(lex, token, 1)
		end
		token		= tokens[i]
		lex.Line	= token.Line
		if(token.Token == tokenType.DirectiveBank)then
			bank, errMsg	= resolveValue(lex, token[1])
			if(not bank)then
				errorMessage(lex, errMsg)
			end
			lex.Bank	= bank
			bin[#bin+1]	= newBinData(bank, address)
		elseif(token.Token == tokenType.DirectiveOrigin)then
			address, errMsg	= resolveValue(lex, token[1])
			if(not address)then
				errorMessage(lex, errMsg)
			end
			lex.Address	= address
			bin[#bin+1]	= newBinData(bank, address)
		elseif(token.Token == tokenType.DirectiveDataByte)then
			data	= token[1]
			for i=1,#data do
				value, errMsg	= resolveValue(lex, data[i])
				if(value)then
					pushValue(value)
				else
					errorMessage(lex, errMsg)
				end
			end
		elseif(token.Token == tokenType.DirectiveDataWord)then
			data	= token[1]
			for i=1,#data do
				value, errMsg	= resolveValue(lex, data[i])
				if(value)then
					pushValue(LowByte(value))
					pushValue(HighByte(value))
				else
					errorMessage(lex, errMsg)
				end
			end
		elseif(token.Token == tokenType.LabelGlobal)then
			lex.LocalScopeName	= token[1]
		elseif(token.Token == tokenType.Instruction)then
			addressing	= token[2]
			data		= token[3]

			pushValue(token[4])

			if(
				(addressing == addressingType.Implied)		or	--  1
				(addressing == addressingType.Accumulator)		--  2
			)then
				-- nop
			elseif(
				(addressing == addressingType.Immediate)	or	--  3
				(addressing == addressingType.Zeropage)		or	--  4
				(addressing == addressingType.ZeropageIndexedX)	or	--  5
				(addressing == addressingType.ZeropageIndexedY)	or	--  6
				(addressing == addressingType.IndexedXIndirect)	or	-- 10
				(addressing == addressingType.IndirectIndexedY)		-- 11
			)then
				value, errMsg	= resolveValue(lex, data)
				if(value)then
					pushValue(value)
				else
					errorMessage(lex, errMsg)
				end
			elseif(
				(addressing == addressingType.Absolute)		or	--  7
				(addressing == addressingType.AbsoluteIndexedX)	or	--  8
				(addressing == addressingType.AbsoluteIndexedY)	or	--  9
				(addressing == addressingType.AbsoluteIndirect)		-- 12
			)then
				value, errMsg	= resolveValue(lex, data)
				if(value)then
					pushValue(LowByte(value))
					pushValue(HighByte(value))
				else
					errorMessage(lex, errMsg)
				end
			elseif(
				(addressing == addressingType.Relative)			-- 13
			)then
				value, errMsg	= resolveValue(lex, data)
				if(not value)then
					errorMessage(lex, errMsg)
				elseif(errMsg == "number")then
					pushValue(value)
				else
					distance	= value - (lex.Address + 1)
					pushValue(ToByte(distance))
					if((distance < -128) or (128 <= distance))then
						errorMessage(lex, "Out of range of relative access.")
					end
				end
			end
		end
	end

	if(isError)then
		return nil
	end

	return bin, lines
end
function L6502Assembler.AssembleFromFile(file, origin, print)
	local fp	= io.open(file, "r")
	if(not fp)then
		if(print)then
			print("Failed to open the file.")
		end
		return nil
	end

	local code	= fp:read("*a")
	fp:close()
	return L6502Assembler.Assemble(code, origin, print)
end
function L6502Assembler.UploadToMemory(memory, bin)
	local lineNumbers	= {}
	function lineNumbers:GetLineNumber(cpu)
		local bank	= cpu.MemoryProvider.BankNumber
		local pc	= cpu.Registers.PC
		if((self[bank] ~= nil) and (self[bank][pc] ~= nil))then
			return self[bank][pc]
		else
			return nil
		end
	end

	for i,v in ipairs(bin) do
		local origin	= v.Origin
		local bank	= v.Bank	or 0
		local line	= v.Line

		memory:Upload(origin, v.Data, bank)

		lineNumbers[bank]	= lineNumbers[bank]	or {}
		for i=1,#line do
			lineNumbers[bank][origin + i - 1]	= line[i]
		end
	end
	return lineNumbers
end

return L6502Assembler

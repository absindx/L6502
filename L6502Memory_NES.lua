----------------------------------------------------------------------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########                    ####      ####  ##############    ########      --
--  ####            ####          ####              ##    ####    ####      ####                  ######    ####  ####            ####    ####    --
--  ####          ####            ############    ####      ####          ######                  ########  ####  ####            ####            --
--  ####          ############              ####  ####      ####      ########      ############  ##############  ############      ##########    --
--  ####          ####      ####            ####  ####      ####    ########        ############  ####  ########  ####                      ####  --
--  ####          ####      ####  ####      ####    ####    ##    ######                          ####    ######  ####            ####      ####  --
--  ############    ##########      ##########        ######      ##############                  ####      ####  ##############    ##########    --
--                                                                                                                                                --
----------------------------------------------------------------------------------------------------------------------------------------------------

local L6502Memory	= require("L6502Memory")

--------------------------------------------------

local iNESHeaderSignature	= {0x4E, 0x45, 0x53, 0x1A}

local L6502Memory_NES	= {}

function L6502Memory_NES.new(mapper, hasSram)
	local memory		= L6502Memory.new()
	memory.Mapper		= mapper
	memory.HasSram		= hasSram

	memory.internalRomData	= {}
	memory.Registers	= {}

	-- memory access
	memory.InvokeWrite	= memory.WriteBypass
	memory.InvokeRead	= memory.ReadBypass

	function memory:ReadBypass(address)
		-- RAM mirroring
		if(address < 0x2000)then
			address	= address % 0x0800
		end

		if(self.Mapper == 4)then
			-- Bank = {
			-- 	CHR[$0000], CHR[$0400], CHR[$0800], CHR[$0C00],
			-- 	CHR[$1000], CHR[$1400], CHR[$1800], CHR[$1C00],
			-- 	PRG[$8000], PRG[$A000], PRG[$C000], PRG[$E000],
			--	PRG old[6], PRG old[7]
			-- }
			if(address < 0x8000)then
				return self:BaseRead(address, 0)
			end
			local bankRegister	= math.floor((address - 0x8000) / 0x2000)
			local bankOffset	= address % 0x2000
			local bankNumber	= self.Registers.Bank[bankRegister + 8]	or 0

			return self.internalRomData[bankNumber * 0x2000 + bankOffset]
		else
			-- mapper 0
			if(address < 0x8000)then
				return self:InvokeRead(address, 0)
			else
				return self.internalRomData[address - 0x8000]
			end
		end
	end
	function memory:WriteBypass(address, value)
		-- RAM mirroring
		if(address < 0x2000)then
			address	= address % 0x0800
		end

		local isMainRam	= (0x0000 <= address) and (address < 0x2000)
		local isPpuPort	= (0x2000 <= address) and (address < 0x4000)
		local isApuPort	= (0x4000 <= address) and (address < 0x6000)
		local isExRam	= (0x6000 <= address) and (address < 0x8000)
		if(isMainRam or (memory.HasSram and isExRam))then
			memory:InvokeWrite(address, value)
		end
		-- TODO : Implement
		if(isPpuPort or isApuPort)then
			memory:InvokeWrite(address, value)
		end
	end
	function memory:Write(address, value)
		if(self.Mapper == 4)then
			if(address < 0x8000)then
				self:WriteBypass(address, value)
				return
			end
			local lastBank	= math.floor(#self.internalRomData / 0x2000)
			local register	= math.floor((address - 0x8000) / 0x2000) * 2 + (address % 2)
			if(register == 0)then
				-- $8000 BankSelect
				--self.Registers.BankSelect_ChrSwap	= (value / 0x80) >= 1
				self.Registers.BankSelect_PrgSwap	= (math.floor(value / 0x40) % 2) >= 1
				self.Registers.BankSelect_Mapping	= value % 8
			elseif(register == 1)then
				-- $8001 BankData
				local floorValue	= value - value % 2
				local prgAdd		= 0
				if(self.Registers.BankSelect_PrgSwap)then
					prgAdd		= 4
				end
				if(self.Registers.BankSelect_Mapping == 0)then
					self.Registers.Bank[0 + prgAdd]	= floorValue
					self.Registers.Bank[1 + prgAdd]	= floorValue + 1
				elseif(self.Registers.BankSelect_Mapping == 1)then
					self.Registers.Bank[2 + prgAdd]	= floorValue
					self.Registers.Bank[3 + prgAdd]	= floorValue + 1
				elseif(self.Registers.BankSelect_Mapping == 2)then
					self.Registers.Bank[4 - prgAdd]	= value
				elseif(self.Registers.BankSelect_Mapping == 3)then
					self.Registers.Bank[5 - prgAdd]	= value
				elseif(self.Registers.BankSelect_Mapping == 4)then
					self.Registers.Bank[6 - prgAdd]	= value
				elseif(self.Registers.BankSelect_Mapping == 5)then
					self.Registers.Bank[7 - prgAdd]	= value
				elseif(self.Registers.BankSelect_Mapping == 6)then
					if(not self.Registers.BankSelect_PrgSwap)then
						self.Registers.Bank[ 8]	= value
						self.Registers.Bank[ 9]	= self.Registers.Bank[13]
						self.Registers.Bank[10]	= lastBank - 1
						self.Registers.Bank[11]	= lastBank
					else
						self.Registers.Bank[ 8]	= lastBank - 1
						self.Registers.Bank[ 9]	= self.Registers.Bank[13]
						self.Registers.Bank[10]	= value
						self.Registers.Bank[11]	= lastBank
					end
					self.Registers.Bank[12]	= value
				elseif(self.Registers.BankSelect_Mapping == 7)then
					if(not self.Registers.BankSelect_PrgSwap)then
						self.Registers.Bank[ 8]	= self.Registers.Bank[12]
						self.Registers.Bank[ 9]	= value
						self.Registers.Bank[10]	= lastBank - 1
						self.Registers.Bank[11]	= lastBank
					else
						self.Registers.Bank[ 8]	= lastBank - 1
						self.Registers.Bank[ 9]	= value
						self.Registers.Bank[10]	= self.Registers.Bank[12]
						self.Registers.Bank[11]	= lastBank
					end
					self.Registers.Bank[13]	= value
				end
			end
		else
			-- mapper 0
			self:WriteBypass(address, value)
		end
	end

	function memory:InitializeMapper()
		if(memory.Mapper == 4)then
			local lastBank			= math.floor(#memory.internalRomData / 0x2000)
			memory.Registers.Bank		= {}
			for i=0,9 do
				memory.Registers.Bank[i]	= 0
			end
			memory.Registers.Bank[10]	= lastBank - 1
			memory.Registers.Bank[11]	= lastBank
			memory.Registers.Bank[12]	= 0
			memory.Registers.Bank[13]	= 0

			memory.Registers.BankSelect_PrgSwap	= 0
			memory.Registers.BankSelect_Mapping	= 0
		end
	end

	memory:InitializeMapper()

	return memory
end
function L6502Memory_NES.ReadFromNesRomFile(file)
	local fp	= io.open(file, "rb")
	if(not fp)then
		return 0
	end

	local function readByte()
		local char	= fp:read(1)
		if(char)then
			return char:byte()
		else
			return nil
		end
	end

	local byte

	-- read header
	local header	= {}
	for i=1,0x10 do
		byte	= readByte()
		if(not byte)then
			return nil
		end
		header[i-1]	= byte
	end

	-- check iNES header format
	-- signature
	for i=1,#iNESHeaderSignature do
		if(header[i-1] ~= iNESHeaderSignature[i])then
			return nil
		end
	end

	header.PrgCount		= header[4]
	header.ChrCount		= header[5]
	header.Mirroring	= math.floor(header[6] / (2^0)) % 2
	header.Battery		= math.floor(header[6] / (2^1)) % 2
	header.Trainer		= math.floor(header[6] / (2^2)) % 2
	header.FourScreen	= math.floor(header[6] / (2^3)) % 2
	header.VsUnisystem	= math.floor(header[7] / (2^0)) % 2
	header.PlayChoice10	= math.floor(header[7] / (2^1)) % 2
	header.InesV2		= math.floor(header[7] / (2^2)) % 4
	header.Mapper		= (math.floor(header[7] / (2^4)) % 0x0F) * 0x10 + (math.floor(header[6] / (2^4)) % 0x0F)
	header.RamCount		= header[8]
	header.TvSystem		= math.floor(header[9] / (2^0)) % 2
	header.TvSystemEx	= math.floor(header[10] / (2^0)) % 4
	header.PrgRam		= math.floor(header[10] / (2^4)) % 2
	header.BusConflict	= math.floor(header[10] / (2^5)) % 2

	-- create instance
	local memory	= L6502Memory_NES.new(header.Mapper, header.PrgRam==0)
	memory.Header	= header
	memory.Mapper	= header.Mapper
	memory.HasSram	= header.RamCount > 0

	-- read body
	memory.internalRomData	= {}
	local read	= 0
	for i=0,header.PrgCount*0x4000 do
		byte	= readByte()
		if(not byte)then
			break
		end

		memory.internalRomData[read]	= byte
		read	= read + 1
	end

	fp:close()

	-- mapping
	if(read < 0x4000)then
		for i=0,0x1FFF do
			--memory.internalRomData[0x0000 + i]	= memory.internalRomData[i]
			memory.internalRomData[0x2000 + i]	= memory.internalRomData[i]
			memory.internalRomData[0x4000 + i]	= memory.internalRomData[i]
			memory.internalRomData[0x8000 + i]	= memory.internalRomData[i]
		end
	elseif(read < 0x8000)then
		for i=0,0x3FFF do
			--memory.internalRomData[0x0000 + i]	= memory.internalRomData[i]
			memory.internalRomData[0x4000 + i]	= memory.internalRomData[i]
		end
	else	-- 0x8000 <= read
		--for i=0,0x7FFF do
		--	memory[0x0000 + i]	= memory.internalRomData[i]
		--end
	end

	memory:InitializeMapper()

	return memory
end

return L6502Memory_NES

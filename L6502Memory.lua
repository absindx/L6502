----------------------------------------------------------------------------------------------------------------------------------------------------
--  ####              ########    ############        ######        ##########                    ####      ####  ##############  ####      ####  --
--  ####            ####          ####              ##    ####    ####      ####                  ######  ######  ####            ######  ######  --
--  ####          ####            ############    ####      ####          ######                  ##############  ####            ##############  --
--  ####          ############              ####  ####      ####      ########      ############  ##############  ############    ##############  --
--  ####          ####      ####            ####  ####      ####    ########        ############  ####  ##  ####  ####            ####  ##  ####  --
--  ####          ####      ####  ####      ####    ####    ##    ######                          ####      ####  ####            ####      ####  --
--  ############    ##########      ##########        ######      ##############                  ####      ####  ##############  ####      ####  --
--                                                                                                                                                --
----------------------------------------------------------------------------------------------------------------------------------------------------

local L6502Memory	= {}
function L6502Memory.new()
	local memory	= {}

	-- For expansion
	memory.Bank		= {}
	memory.Bank[0]		= {}
	memory.BankNumber	= 0

	function memory:ReadBypass(address, bank)
		bank	= bank	or self.BankNumber
		if((0 <= address) and (address < 0x10000))then
			local bankMemory	= self.Bank[bank]	or {}
			return bankMemory[address]	or 0
		else
			return 0
		end
	end
	function memory:Read(address)
		return self:ReadBypass(address)
	end

	function memory:WriteBypass(address, value, bank)
		bank	= bank	or self.BankNumber
		if((0 <= address) and (address < 0x10000))then
			self.Bank[bank]	= self.Bank[bank]	or {}
			self.Bank[bank][address]	= value	or 0
		end
	end
	function memory:Write(address, value)
		self:WriteBypass(address, value)
	end

	function memory:Upload(origin, data, bank)
		for i=1,#data do
			self:WriteBypass(origin + i - 1, data[i], bank)
		end
	end
	function memory:Download(origin, length, bank)
		local data	= {}
		for i=1,length do
			data[i]	= self:ReadBypass(origin + i - 1)
		end
		return data
	end

	function memory:ReadFromFile(file, origin, bank)
		bank		= bank	or 0
		local fp	= io.open(file, "rb")
		if(not fp)then
			return 0
		end

		local char, byte
		local offset	= origin
		repeat
			if(offset >= 0x10000)then
				bank	= bank + 1
				offset	= 0
			end

			char	= fp:read(1)
			byte	= nil
			if(char)then
				byte	= char:byte()
				if(byte)then
					self:WriteBypass(offset, byte, bank)
					offset	= offset + 1
				end
			end
		until(not byte)

		fp:close()

		return read
	end
	function memory:WriteToFile(file, memory)
		local fp	= io.open(file, "wb")
		if(not fp)then
			return false
		end

		local maxBank	= 0
		for k,v in pairs(self.Bank)do
			local bankNumber	= tonumber(k)
			if(bankNumber and maxBank < bankNumber)then
				maxBank	= bankNumber
			end
		end

		for b=0,maxBank do
			local bank	= self.Bank[b]
			if(bank)then
				for i=0,0xFFFF do
					fp:write(string.char(bank[i] or 0))
				end
			else
				local zeroChar	= string.char(0)
				for i=0,0xFFFF do
					fp:write(zeroChar)
				end
			end
		end

		fp:close()

		return true
	end

	-- Initialize
	for i=0,0xFFFF do
		memory:WriteBypass(i, 0, 0)
	end

	return memory
end

return L6502Memory

# L6502  

L6502 is a 6502 library implemented in Lua.  
Undefined instructions are not implemented. (Because the instructions differ from chip to chip)  

## Environment  
Supports Lua 5.1 to 5.4 and LuaJIT 2.0.  

## Including  
* [CPU Emulator](L6502.lua)  
* [Assembler](L6502Assembler.lua)  
* [Disassembler](L6502Disassembler.lua)  
* [Interpreter](L6502Interpreter.lua)  

## How to Run  

```lua
-- Load library
local L6502		= require("L6502")
local L6502Memory	= require("L6502Memory")

-- Create memory
memory	= L6502Memory.new()
memory:Upload(0xFFFA, {0x00, 0x80, 0x00, 0x90, 0x00, 0xA0})	-- Interrupt handler
memory:Upload(0x9000, {0xEA})	-- Program code (Reset: NOP)

-- Create cpu
cpu	= L6502.new(memory, print)	-- print is a function that displays the trace log

-- Execute cpu
cpu:Reset()	-- Go to Reset routine
cpu:Clock()	-- Execute instruction
		--   To execute the next instruction,
		--   need to call cpu:Clock() for the currently executing instruction cycle.
		--   cpu:Step() advances the clock to the next instruction in one call.

--[[ Output:
NOP             ; PC=9000, A=00, X=00, Y=00, S=FD, P=34 nvRBdIzc, Cycle=0
]]
```

See also [Sample](Sample/) directory.  

## For NES  
Set `cpu.DisableDecimalMode` to `true` to ignore the D flag.  
[L6502Memory_NES.lua](L6502Memory_NES.lua) provides .nes file reading and mapper. (currently only mapper 0, 4)  

## ToDo  
* CPU : Memory accurate access (RMWW, dummy read)  
* CPU : Cycle accurate (probably remake)  
* Assembler : `.include` directive  
* Assembler : `.if` directive  
* Interpreter : breakpoint commands  

## License  
[MIT License](LICENSE).  

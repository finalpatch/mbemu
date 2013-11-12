import std.stdio;
import std.bitmanip;
import mbemu.cpu;
import mbemu.mem;
import mbemu.elf;

void main(string[] args)
{
	if (args.length < 2)
	{
		writeln("Usage: mbemu xyz.elf");
		return;
	}

	auto mem = new MemorySpace(new Console(),
							   new InterruptController(),
							   new SDRAM(0, 65536*4));

	auto cpu = new CPU(mem, ()=>mem.readByte(0xfffffff0)!=0);
	
	cpu.pc = loadElf(args[1], mem);
	while(cpu.tick())
	{
		if (cpu.pc == 0x50)
		{
			mem.writeByte(0xfffffff0, 1);
		}
	}
}

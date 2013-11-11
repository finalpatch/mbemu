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
							   new SDRAM(0, 65536*4));
	auto cpu = new CPU(mem);
	
	cpu.pc = loadElf(args[1], mem);
	while(cpu.tick())
	{}
}

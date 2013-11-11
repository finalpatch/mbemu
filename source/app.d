import std.stdio;
import std.bitmanip;
import mbemu.cpu;
import mbemu.mem;
import mbemu.elf;

void main()
{
	auto mem = new MemorySpace(new Console(),
							   new SDRAM(0, 65536*4));
	auto cpu = new CPU(mem);
	
	cpu.pc = loadElf("test.elf", mem);
	while(cpu.tick())
	{}
}

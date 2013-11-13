import std.stdio;
import std.bitmanip;
import mbemu.cpu;
import mbemu.mem;
import mbemu.elf;
import mbemu.fpga;

void main(string[] args)
{
    if (args.length < 2)
    {
        writeln("Usage: mbemu xyz.elf");
        return;
    }

	auto fpga = new FPGA();
    auto mem = new MemorySpace(new Console(), fpga, new SDRAM(0, 65536*4));
    auto cpu = new CPU(mem, ()=>fpga.reg[FPGA.InterruptStatus]!=0);
    
    cpu.pc = loadElf(args[1], mem);
    while(cpu.tick())
    {
		fpga.tick();
    }
}

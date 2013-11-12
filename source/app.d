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
    auto mem = new MemorySpace(fpga, new Console(), new SDRAM(0, 65536*4));
    auto cpu = new CPU(mem, ()=>fpga.registers[FPGA.interruptStatus]!=0);
    
    cpu.pc = loadElf(args[1], mem);
    while(cpu.tick())
    {
        if (cpu.pc == 0x50)
        {
            fpga.registers[FPGA.interruptStatus] = 1;
        }
    }
}

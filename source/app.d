import std.stdio;
import std.getopt;
import mbemu.cpu;
import mbemu.mem;
import mbemu.elf;
import mbemu.fpga;
import mbemu.gdb;

void main(string[] args)
{
    bool dbg;
    getopt(args, "debug|d", &dbg);

    if (args.length < 2)
    {
        writeln("Usage: mbemu [--debug] xyz.elf");
        return;
    }

    auto sdram = new SDRAM(0, 1024*1024*2);
    auto fpga = new FPGA(sdram);
    auto mem = new MemorySpace(new Console(), fpga, sdram);
    auto cpu = new CPU(mem);

    cpu.interrupt = ()=>fpga.reg[FPGA.InterruptStatus]!=0;
    cpu.advclk = &fpga.advanceClock;
    
    cpu.pc = loadElf(args[1], mem);

    if (!dbg)
    {
        while(cpu.tick())
        {}
    }
    else
    {
        startGdbServer(1234);
        scope(exit) stopGdbServer();

        while(true)
            handleGdbCommands(cpu);
    }
}

// Local Variables:
// indent-tabs-mode: nil
// End:

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

    auto fpga = new FPGA();
    auto mem = new MemorySpace(new Console(), fpga, new SDRAM(0, 65536*4));
    auto cpu = new CPU(mem, ()=>fpga.reg[FPGA.InterruptStatus]!=0, &fpga.advanceClock);
    
    cpu.pc = loadElf(args[1], mem);

    if (!dbg)
    {
        while(cpu.tick())
        {}
    }
    else
    {
        startGdbServer(1234);
        scope(exit)
            stopGdbServer();

        while(true)
            handleGdbCommands(cpu);
    }
}

// Local Variables:
// indent-tabs-mode: nil
// End:

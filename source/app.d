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
    auto cpu = new CPU(mem, ()=>fpga.reg[FPGA.InterruptStatus]!=0);
    
    cpu.pc = loadElf(args[1], mem);

    auto tick = delegate bool()
        {
            bool running = cpu.tick();
            fpga.tick();
            return running;
        };
    
    if (!dbg)
    {
        while(tick())
        {}
    }
    else
    {
        startGdbServer(1234);
        scope(exit)
            stopGdbServer();

        while(true)
            handleGdbCommands(cpu, tick);
    }
}

// Local Variables:
// indent-tabs-mode: nil
// End:

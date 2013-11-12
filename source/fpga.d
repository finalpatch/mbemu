module mbemu.fpga;
import mbemu.mem;
import std.stdio;
import std.bitmanip;

class Console : MemoryRange
{
    uint base() { return 0xfffffffc; }
    uint size() { return 1; }
    
    uint readWord(uint addr) { return 0; }
    void writeWord(uint addr, uint data) {}
    ubyte readByte(uint addr)
    {
        char c;
        std.stdio.readf("%s", &c);
        return cast(ubyte)c;
    }
    void writeByte(uint addr, ubyte data)
    {
        std.stdio.writef("%s", cast(char)data);
    }
}

class FPGA : MemoryRange
{
public:
	uint base() { return 0xfffffff0; }
    uint size() { return 10; }

	enum {
		interruptStatus,
		timerCounter,
		timerSet,
		frameBuffer0,
		frameBuffer1,
		numOfRegisters,
	}
	uint[numOfRegisters] registers;

	// byte access disabled
    ubyte readByte(uint addr) {return 0;}
    void writeByte(uint addr, ubyte data) {}

	// The FPGA uses native endian because byte access is not allowed
    uint readWord(uint addr)
    {
		uint idx = addr - base();
		return registers[idx];
    }
    void writeWord(uint addr, uint data)
    {
		uint idx = addr - base();
		switch(idx)
		{
		case interruptStatus:
			registers[idx] &= ~data;
			break;
		case timerSet:
		case frameBuffer0:
		case frameBuffer1:
			registers[idx] = data;
			break;
		default:
			break;
		}
    }
}

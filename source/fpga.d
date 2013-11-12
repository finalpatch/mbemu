module mbemu.fpga;
import mbemu.mem;
import std.stdio;

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

class InterruptController : MemoryRange
{
    private bool interrupt = false;
    
    uint base() { return 0xfffffff0; }
    uint size() { return 1; }
    
    uint readWord(uint addr) {return 0;}
    void writeWord(uint addr, uint data) {}
    
    ubyte readByte(uint addr)
    {
        return interrupt ? 1 : 0;
    }
    void writeByte(uint addr, ubyte data)
    {
        interrupt = (data != 0);
    }
}

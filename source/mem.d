module mbemu.mem;
import std.array;
import std.algorithm;
import std.bitmanip;
import std.string;

class MemoryRange
{
    immutable uint base;
    immutable uint size;

    this(uint _base, uint _size)
    {
        base = _base;
        size = _size;
    }
    
    uint  readWord(uint addr) { return 0; }
    void  writeWord(uint addr, uint data) {}
    ubyte readByte(uint addr) { return 0; }
    void  writeByte(uint addr, ubyte data) {}
}

class MemorySpace
{
public:
    this(MemoryRange[] ranges ...)
    {
        mem = ranges;
    }
    final uint readWord(uint addr)
    {
        return findMemRange(addr).readWord(addr);
    }
    final void writeWord(uint addr, uint data)
    {
        findMemRange(addr).writeWord(addr, data);
    }
    final ubyte readByte(uint addr)
    {
        return findMemRange(addr).readByte(addr);
    }
    final void writeByte(uint addr, ubyte data)
    {
        findMemRange(addr).writeByte(addr, data);
    }
    final MemoryRange findMemRange(uint addr)
    {
        auto r = mem.find!(m=>(addr >= m.base && addr < m.base + m.size));
        if (r.empty) throw new Exception("invalid mem address %x".format(addr));
        return r[0];
    }
private:
    MemoryRange[] mem;
}

class SDRAM : MemoryRange
{
public:
    this(uint _base, uint _size)
    {
        super(_base, _size);
        m_words = new uint[size >> 2];
    }
    override uint readWord(uint addr)
    {
        version(BigEndianMicroBlaze)
            return swapEndian(m_words[(addr - base)>>2]);
        else
            return m_words[(addr - base)>>2];
    }
    override void writeWord(uint addr, uint data)
    {
        version(BigEndianMicroBlaze)
            m_words[(addr - base)>>2] = swapEndian(data);
        else
            m_words[(addr - base)>>2] = data;
    }
    override ubyte readByte(uint addr)
    {
        ubyte* bytes = cast(ubyte*)m_words.ptr;
        return bytes[addr];
    }
    override void writeByte(uint addr, ubyte data)
    {
        ubyte* bytes = cast(ubyte*)m_words.ptr;
        bytes[addr] = data;
    }
    T[] getBuffer(T)() { return cast(T[])m_words; }
private:
    uint[] m_words;
}

// Local Variables:
// indent-tabs-mode: nil
// End:

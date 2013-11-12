module mbemu.mem;
import std.bitmanip;
import std.string;

interface MemoryRange
{
    uint base();
    uint size();
    
    uint  readWord(uint addr);
    void  writeWord(uint addr, uint data);
    ubyte readByte(uint addr);
    void  writeByte(uint addr, ubyte data);
}

class MemorySpace
{
public:
    this(MemoryRange[] ranges ...)
    {
        mem = ranges;
    }
    uint readWord(uint addr)
    {
        return findMemRange(addr).readWord(addr);
    }
    void writeWord(uint addr, uint data)
    {
        findMemRange(addr).writeWord(addr, data);
    }
    ubyte readByte(uint addr)
    {
        return findMemRange(addr).readByte(addr);
    }
    void writeByte(uint addr, ubyte data)
    {
        findMemRange(addr).writeByte(addr, data);
    }
private:
    MemoryRange[] mem;
    
    MemoryRange findMemRange(uint addr)
    {
        foreach (m; mem)
        {
            if (addr >= m.base() && addr < m.base() + m.size())
                return m;
        }
        throw new Exception("invalid mem address %x".format(addr));
    }
}

class SDRAM : MemoryRange
{
public:
    this(uint base, uint size)
    {
        m_base = base;
        m_words = new uint[size / 4];
    }
    uint base() { return m_base; }
    uint size() { return cast(uint)m_words.length * 4; }
    uint readWord(uint addr)
    {
        version(BigEndianMicroBlaze)
            return swapEndian(m_words[(addr - m_base)/4]);
        else
            return m_words[(addr - m_base)/4];
    }
    void writeWord(uint addr, uint data)
    {
        version(BigEndianMicroBlaze)
            m_words[(addr - m_base)/4] = swapEndian(data);
        else
            m_words[(addr - m_base)/4] = data;
    }
    ubyte readByte(uint addr)
    {
        ubyte* bytes = cast(ubyte*)m_words.ptr;
        return bytes[addr];
    }
    void writeByte(uint addr, ubyte data)
    {
        ubyte* bytes = cast(ubyte*)m_words.ptr;
        bytes[addr] = data;
    }
private:
    uint   m_base;
    uint[] m_words;
}

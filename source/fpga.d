module mbemu.fpga;
import mbemu.mem;
import mbemu.lcd;
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
    final void writeByte(uint addr, ubyte data)
    {
        std.stdio.writef("%s", cast(char)data);
    }
}

class FPGA : MemoryRange
{
public:
    this(SDRAM sdram)
    {
        lcd = new LCD(sdram);
    }

    uint base() { return 0xffffff00; }
    uint size() { return NumOfRegisters * 4; }

    enum {
        TimerInterrupt,
    }

    enum {
        InterruptControl,
        InterruptStatus,
        TimerCounter,
        TimerSet,
        LCDEnable,
        LCDFrameBuffer,
        NumOfRegisters,
    }
    uint[NumOfRegisters] reg;

    // byte access disabled
    ubyte readByte(uint addr) {return 0;}
    void writeByte(uint addr, ubyte data) {}

    // The FPGA uses native endian because byte access is not allowed
    uint readWord(uint addr)
    {
        uint idx = (addr - base())/4;
        switch(idx)
        {
        case LCDEnable:
            return lcd.enabled ? 1 : 0;
        case LCDFrameBuffer:
            return lcd.frameBuffer;
        default:
            return reg[idx];
        }
    }
    void writeWord(uint addr, uint data)
    {
        uint idx = (addr - base())/4;
        switch(idx)
        {
        case InterruptStatus:
            reg[idx] &= ~data;
            break;
        case TimerCounter:
            // Timer cannot be assigned
            break;
        case LCDEnable:
            lcd.enabled = (data != 0);
            break;
        case LCDFrameBuffer:
            lcd.frameBuffer = data;
            break;
        default:
            reg[idx] = data;
            break;
        }
    }

    final void advanceClock(uint cycles)
    {
        while(cycles--)
        {
            if(++reg[TimerCounter] == reg[TimerSet])
            {
                // trigger timer interrupt
                reg[InterruptStatus] |= reg[InterruptControl] & (1 << TimerInterrupt);
            }
        }
        if ((reg[TimerCounter] & 0xffff) == 0)
            lcd.handleEvents();
    }

private:
    LCD lcd;
}

// Local Variables:
// indent-tabs-mode: nil
// End:

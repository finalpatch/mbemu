module mbemu.fpga;
import mbemu.mem;
import mbemu.lcd;
import std.stdio;
import std.bitmanip;

class Console : MemoryRange
{
    this()
    {
        super(0xfffffffc, 1);
    }
    
    override ubyte readByte(uint addr)
    {
        char c;
        std.stdio.readf("%s", &c);
        return cast(ubyte)c;
    }
    override void writeByte(uint addr, ubyte data)
    {
        std.stdio.writef("%s", cast(char)data);
    }
}

class FPGA : MemoryRange
{
public:
    this(SDRAM sdram)
    {
        super(0xffffff00, NumOfRegisters * 4);
        lcd = new LCD(sdram);
    }

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

    // The FPGA uses native endian because byte access is not allowed
    override uint readWord(uint addr)
    {
        uint idx = (addr - base)/4;
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
    override void writeWord(uint addr, uint data)
    {
        uint idx = (addr - base)/4;
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

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
        super(0xffff0000, NumOfRegisters * 4);
        lcd = new LCD(sdram, this);
    }

    enum {
        TimerInterrupt,
        ButtonInterrupt,
    }

    enum {
        InterruptControl,
        InterruptStatus,
        TimerCounter,
        TimerSet,
        LCDEnable,
        LCDLookupTable,
        LCDFrameBuffer = LCDLookupTable + 0x100,
        ButtonStatus,
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
        case LCDLookupTable: .. case LCDLookupTable + 0xff:
            return lcd.lut[idx - LCDLookupTable];
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
        case LCDLookupTable: .. case (LCDLookupTable + 0xff):
            lcd.lut[idx - LCDLookupTable] = data;
            break;
        case LCDFrameBuffer:
            lcd.frameBuffer = data;
            break;
        default:
            reg[idx] = data;
            break;
        }
    }

    final bool advanceClock(uint cycles)
    {
        while(cycles--)
        {
            if(++reg[TimerCounter] == reg[TimerSet])
            {
                // trigger timer interrupt
                reg[InterruptStatus] |= reg[InterruptControl] & (1 << TimerInterrupt);
            }
        }
        bool keepRunning = true;
        if ((reg[TimerCounter] & 0xffff) == 0)
            keepRunning = lcd.handleEvents();
        return keepRunning;
    }

private:
    LCD lcd;
}

// Local Variables:
// indent-tabs-mode: nil
// End:

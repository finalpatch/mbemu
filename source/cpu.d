module mbemu.cpu;

import std.stdio;
import std.bitmanip;
import std.algorithm;
import std.string;
import std.typecons;
import mbemu.mem;

// Versions:
// * BigEndianMicroBlaze
// * TraceInstructions
// * StackProtector

struct Instruction
{
    union
    {
        uint insword;
        mixin(bitfields!(uint, "filler1", 11,
                         uint, "Rb",       5,
                         uint, "Ra",       5,
                         uint, "Rd",       5,
                         uint, "Opcode",   6));
        mixin(bitfields!(uint, "Imm",     16,
                         uint, "filler2", 16));
    };
}

class CPU
{
public:
    uint[32] r;
    uint     pc;
    uint     slr = 0;               // stack low
    uint     shr = ~0;              // stack high
    union
    {
        uint msr;
        mixin(bitfields!(bool, "BE" , 1,
                         bool, "IE" , 1,
                         bool, "C"  , 1,
                         bool, "BIP", 1,
                         bool, "FSL", 1,
                         bool, "ICE", 1,
                         bool, "DZO", 1,
                         bool, "DCE", 1,
                         bool, "EE" , 1,
                         bool, "EIP", 1,
                         bool, "PVR", 1,
                         bool, "UM" , 1,
                         bool, "UMS", 1,
                         bool, "VM" , 1,
                         bool, "VMS", 1,
                         uint, "RESERVED", 16,
                         bool, "CC" , 1));
    }

    // the cpu calls this delegate to check for interrupt signal every
    // clock cycle
    bool delegate() interrupt;
    // the cpu calls this after every instruction with the instruction
    // latency in number of cycles
    bool delegate(uint cycles) advclk;
    // gets called after memory access
    void delegate(bool write, uint addr, uint size) memaccess;

    this(MemorySpace m)
    {
        mem = m;
    }

    final bool tick()
    {
        uint latency;
        if (delaySlot.isNull)
        {
            if (interrupt && interrupt() && immExt.isNull && IE && !BIP && !EIP)
            {
                r[14] = pc;
                IE = false;
                pc = 0x10;
                ++trace;
            }

            auto ins = cast(Instruction)mem.readWord(pc);
            trace(pc, ins);
            if (ins.insword == 0xb8000000) // bri 0
            {
                trace.halt();
                return false;
            }
            pc += 4;
            latency = execute(ins);
        }
        else
        {
            auto ins = cast(Instruction)mem.readWord(delaySlot);
            trace(delaySlot, ins);
            latency = execute(ins);
            delaySlot.nullify();
        }

        if (advclk)
            return advclk(latency);

        return true;
    }

    final uint execute(const Instruction ins)
    {
        scope(exit)
            r[0] = 0;           // make sure r0 is always zero
        
        bool typeB = (ins.Opcode & 0x8) != 0;
        uint op1 = r[ins.Ra];
        uint op2 = typeB ? getImm(ins) : r[ins.Rb];

        uint latency = 1;       // most instructions have latency of 1 cycle

        switch(ins.Opcode)
        {
        case 0b000000:          // ADD
        case 0b000010:          // ADDC
        case 0b000100:          // ADDK
        case 0b000110:          // ADDKC
        case 0b001000:          // ADDI
        case 0b001010:          // ADDIC
        case 0b001100:          // ADDIK
        case 0b001110:          // ADDIKC
            ulong sum = cast(ulong)op1 + cast(ulong)op2;
            r[ins.Rd] = cast(uint)sum;
            if (ins.Opcode & 0b010 && C) // C
                r[ins.Rd] += 1;
            if ((ins.Opcode & 0b100) == 0) // K
                C = (sum > 0xffffffff);
            break;
        case 0b000001:          // RSUB
        case 0b000011:          // RSUBC
        case 0b000111:          // RSUBKC
        case 0b001001:          // RSUBI
        case 0b001011:          // RSUBIC
        case 0b001101:          // RSUBIK
        case 0b001111:          // RSUBIKC
            if (ins.Opcode & 0b010) // C
                r[ins.Rd] = op2 + ~op1 + (C ? 1 : 0);
            else
                r[ins.Rd] = op2 + ~op1 + 1;
            if ((ins.Opcode & 0b100) == 0) // K
                C = cast(int)op2 < cast(int)op1;
            break;
        case 0b000101:          // CMP,CMPU,RSUBK
            {
                r[ins.Rd] = op2 + ~op1 + 1; // RSUBK
                if (ins.filler1 != 0)
                {
                    if ((ins.filler1 == 1) ?
                        (cast(int)op2 >= cast(int)op1) : // CMP
                        (op2 >= op1))                    // CMPU
                        r[ins.Rd] &= 0x7fffffff;
                    else
                        r[ins.Rd] |= 0x80000000;
                }
            }
            break;
        case 0b010000:          // MUL,MULH,MULHU,MULHSU
            switch(ins.filler1)
            {
            case 0:
                r[ins.Rd] = op1 * op2;
                break;
            case 1:
                r[ins.Rd] = cast(uint)((cast(long)cast(int)op1 * cast(long)cast(int)op2) >> 32);
                break;
            case 3:
                r[ins.Rd] = cast(uint)((cast(ulong)cast(uint)op1 * cast(ulong)cast(uint)op2) >>> 32);
                break;
            case 2:
                r[ins.Rd] = cast(uint)(cast(long)((cast(long)cast(int)op1 * cast(ulong)cast(uint)op2)) >> 32);
                break;
            default:
                unknownInstruction(ins);
            }
            version(AreaOptimizedMicroBlaze)
                latency = 3;
            break;
        case 0b011000:          // MULI
            r[ins.Rd] = op1 * op2;
            version(AreaOptimizedMicroBlaze)
                latency = 3;
            break;
        case 0b010001:          // BSRL,BSRA,BSLL
        case 0b011001:          // BSRLI,BSRAI,BSLLI
            {
                uint selector = (ins.Opcode == 0b010001) ? (ins.filler1 >> 5) : (op2 >> 5);
                uint shift = (ins.Opcode == 0b010001) ? op2 : (op2 & 0b11111);
                switch(selector)
                {
                case 0:             // BSRLI
                    r[ins.Rd] = op1 >>> shift;
                    break;
                case 0b10000:       // BSRAI
                    r[ins.Rd] = cast(int)op1 >> shift;
                    break;
                case 0b100000:      // BSLLI
                    r[ins.Rd] = op1 << shift;
                    break;
                default:
                    unknownInstruction(ins);
                }
            }
            version(AreaOptimizedMicroBlaze)
                latency = 2;
            break;
        case 0b101000:          // ORI
            r[ins.Rd] = op1 | op2;
            break;
        case 0b100000:          // OR,PCMPBF
            if (ins.filler1 == 0)   // OR
            {
                r[ins.Rd] = op1 | op2;
            }
            else                // PCMPBF
            {
                byte getByte(uint w, int n) { return 0xff & (w >> ((3 - n) * 8)); }
                if (getByte(op2, 0) == getByte(op1, 0))
                    r[ins.Rd] = 1;
                else if (getByte(op2, 1) == getByte(op1, 1))
                    r[ins.Rd] = 2;
                else if (getByte(op2, 2) == getByte(op1, 2))
                    r[ins.Rd] = 3;
                else if (getByte(op2, 3) == getByte(op1, 3))
                    r[ins.Rd] = 4;
                else
                    r[ins.Rd] = 0;
            }
            break;
        case 0b100010:          // PCMPEQ, XOR
            if (ins.filler1 == 0)
                r[ins.Rd] = op1 ^ op2;
            else
                r[ins.Rd] = (op2 == op1) ? 1 : 0;
            break;
        case 0b100001:          // AND
        case 0b101001:          // ANDI
            r[ins.Rd] = op1 & op2;
            break;
        case 0b101010:          // XORI
            r[ins.Rd] = op1 ^ op2;
            break;
        case 0b101100:          // IMM
            immExt = ins.Imm << 16;
            break;
        case 0b101101:          // RTSD,RTID,RTBD,RTED
            switch(ins.Rd)
            {
            case 0b10000:       // RTSD
                delaySlot = pc;
                pc = op1 + op2;
                --trace;
                break;
            case 0b10001:       // RTID
                delaySlot = pc;
                pc = op1 + op2;
                IE = true;
                --trace;
                break;
            case 0b10010:       // RTBD
                throw new Exception("unimplemented instruction RTBD");
            case 0b10100:       // RTED
                throw new Exception("unimplemented instruction RTED");
            default:
                unknownInstruction(ins);
            }
            latency = 2;
            break;
        case 0b100110:          // BR,BRD,BRLD,BRA,BRAD,BRALD,BRK
        case 0b101110:          // BRI,BRID,BRLID,BRAI,BRAID,BRALID,BRKI
            if (ins.Ra & 0b10000) // D
                delaySlot = pc;
            if (ins.Ra & 0b00100) // L
            {
                r[ins.Rd] = pc - 4;
                ++trace;
            }
            switch(ins.Ra)
            {
            case 0b00000:       // BRI
            case 0b10000:       // BRID
            case 0b10100:       // BRLID
                pc += op2 - 4;
                break;
            case 0b01000:       // BRAI
            case 0b11000:       // BRAID
            case 0b11100:       // BRALID
                pc = op2;
                break;
            case 0b01100:       // BRKI
                r[ins.Rd] = pc - 4;
                pc = op2;
                BIP = true;
                break;
            default:
                unknownInstruction(ins);
            }
            latency = delaySlot.isNull ? 3 : 2;
            break;
        case 0b101111:          // BEQI,BNEI,BLTI,BLEI,BGTI,BGEI,BEQID,BNEID,BLTID,BLEID,BGTID,BGEID
            {
                void doBranch()
                {
                    if (ins.Rd & 0b10000)
                        delaySlot = pc;
                    pc += op2 - 4;
                    latency = delaySlot.isNull ? 3 : 2;
                }
                switch(ins.Rd & 0b1111)
                {
                case 0b00000:       // BEQI
                    if (op1 == 0)
                        doBranch();
                    break;
                case 0b00001:       // BNEI
                    if (op1 != 0)
                        doBranch();
                    break;
                case 0b00010:       // BLTI
                    if (cast(int)op1 < 0)
                        doBranch();
                    break;
                case 0b00011:       // BLEI
                    if (cast(int)op1 <= 0)
                        doBranch();
                    break;
                case 0b00100:       // BGTI
                    if (cast(int)op1 > 0)
                        doBranch();
                    break;
                case 0b00101:       // BGEI
                    if (cast(int)op1 >= 0)
                        doBranch();
                    break;
                default:
                    unknownInstruction(ins);
                }
            }
            break;
        case 0b110000:          // LBU
        case 0b111000:          // LBUI
            {
                uint addr = op1 + op2;
                if (ins.Ra == 1)
                    checkStack(addr);
                r[ins.Rd] = mem.readByte(addr);
                if (memaccess)
                    memaccess(false, addr, 1);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b110001:          // LHU
        case 0b111001:          // LHUI
            {
                uint addr = op1 + op2;
                if (ins.Ra == 1)
                    checkStack(addr);
                auto b1 = mem.readByte(addr);
                auto b2 = mem.readByte(addr+1);
                version (BigEndianMicroBlaze)
                    r[ins.Rd] = (b1 << 8) | b2;
                else // Little endian
                    r[ins.Rd] = (b2 << 8) | b1;
                if (memaccess)
                    memaccess(false, addr, 2);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b110010:          // LW
        case 0b111010:          // LWI
            {
                uint addr = op1 + op2;
                if (ins.Ra == 1)
                    checkStack(addr);
                r[ins.Rd] = mem.readWord(addr);
                if (memaccess)
                    memaccess(false, addr, 4);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b110100:          // SB
        case 0b111100:          // SBI
            {
                uint addr = op1 + op2;
                if (ins.Ra == 1)
                    checkStack(addr);
                mem.writeByte(addr, cast(byte)r[ins.Rd]);
                if (memaccess)
                    memaccess(true, addr, 1);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b110101:          // SH
        case 0b111101:          // SHI
            {
                uint addr = op1 + op2;
                ushort word = r[ins.Rd] & 0xffff;
                version (BigEndianMicroBlaze)
                {
                    mem.writeByte(addr, word >> 8);
                    mem.writeByte(addr+1, word & 0xff);
                }
                else // Little endian
                {
                    mem.writeByte(addr, word & 0xff);
                    mem.writeByte(addr+1, word >> 8);
                }
                if (memaccess)
                    memaccess(true, addr, 2);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b110110:          // SW
        case 0b111110:          // SWI
            {
                uint addr = op1 + op2;
                if (ins.Ra == 1)
                    checkStack(addr);
                mem.writeWord(addr, r[ins.Rd]);
                if (memaccess)
                    memaccess(true, addr, 4);
                version(AreaOptimizedMicroBlaze)
                    latency = 2;
            }
            break;
        case 0b100011:          // PCMPNE
            r[ins.Rd] = (op1 == op2) ? 0 : 1;
            break;
        case 0b100100:          // SRA,SRC,SRL,SEXT8,SEXT16
            switch (ins.Imm)
            {
            case 0b0000000000000001: // SRA
                r[ins.Rd] = cast(int)op1 >> 1;
                C = op1 & 0x1;
                break;
            case 0b0000000000100001: // SRC
                r[ins.Rd] = (op1 >>> 1) | (C ? 0x80000000 : 0);
                C = op1 & 0x1;
                break;
            case 0b0000000001000001: // SRL
                r[ins.Rd] = op1 >>> 1;
                C = op1 & 0x1;
                break;
            case 0b0000000001100000: // SEXT8
                r[ins.Rd] = cast(int)(cast(byte)op1);
                break;
            case 0b0000000001100001: // SEXT16
                r[ins.Rd] = cast(int)(cast(short)op1);
                break;
            case 0b0000000011100000: // CLZ
                r[ins.Rd] = 0;
                for(int i = 0; i < 32; ++i)
                {
                    if ((op1 << i) & 0x80000000)
                        break;
                    r[ins.Rd]++;
                }
                break;
            default:
                // WDC, WIC are ignored because cache is not yet implemented
                break;
            }
            break;
        case 0b100101:          // MTS,MFS,MSRCLR,MSRSET
            {
                op2 = ins.Imm & 0x3fff;
                switch(ins.Imm >>> 14)
                {
                case 3:             // MTS
                    if (op2 == 1)
                        msr = op1;
                    else if (op2 == 2048)
                        slr = op1;
                    else if (op2 == 2050)
                        shr = op1;
                    else
                        // ignore unimplemented special registers
                    {}
                    break;
                case 2:             // MFS
                    if (op2 == 0)
                        r[ins.Rd] = pc - 4;
                    else if (op2 == 1)
                        r[ins.Rd] = msr;
                    else if (op2 == 2048)
                        r[ins.Rd] = slr;
                    else if (op2 == 2050)
                        r[ins.Rd] = shr;
                    else
                        unknownInstruction(ins);
                    break;
                case 0:
                    r[ins.Rd] = msr;
                    if (ins.Ra == 1) // MSRCLR
                        msr &= ~op2;
                    else            // MSRSET
                        msr |= op2;
                    break;
                default:
                    unknownInstruction(ins);
                    break;
                }
            }
            break;
        default:
            unknownInstruction(ins);
        }
        return latency;
    }

    // for debugger support
    final ubyte readMemByte(uint addr) { return mem.readByte(addr); }
    final void  writeMemByte(uint addr, ubyte data) { mem.writeByte(addr, data); }

private:
    Nullable!uint immExt;
    Nullable!uint delaySlot;
    MemorySpace mem;
    Tracer trace;

    final int getImm(Instruction ins)
    {
        if (immExt.isNull)
        {
            return cast(int)(cast(short)ins.Imm);
        }
        else
        {
            uint x = ins.Imm | immExt;
            immExt.nullify();
            return cast(int)x;
        }
    }

    final void unknownInstruction(Instruction ins)
    {
        throw new Exception(format("unknown instruction %x @%x", ins.insword, pc));
    }

    final void checkStack(uint addr)
    {
        version (StackProtector)
        {
            if (addr < slr || addr > shr)
                throw new Exception(format("stack violation [%x] @%x", addr, pc));
        }
    }
}

struct Tracer
{
    char[] indent;
    final void opUnary(string op)() if( op =="++")
    {
        version(TraceInstructions)
        {
            indent.length += 2;
            indent[$-2..$] = ' ';
        }
    }
    final void opUnary(string op)() if( op =="--")
    {
        version(TraceInstructions)
            indent = indent[0..$-2];
    }
    final void opCall(uint addr, Instruction ins)
    {
        version(TraceInstructions)
            writefln("%s%x: %x", indent, addr, ins.insword);
    }
    final void halt()
    {
        version(TraceInstructions)
            writeln("halt");
    }
}

// Local Variables:
// indent-tabs-mode: nil
// End:

module mbemu.cpu;

import std.stdio;
import std.bitmanip;
import std.algorithm;
import std.string;
import std.typecons;
import mbemu.mem;

struct Instruction
{
	union
	{
		uint insword;
		mixin(bitfields!(uint, "filler1", 11,
						 uint, "Rb", 5,
						 uint, "Ra", 5,
						 uint, "Rd", 5,
						 uint, "Opcode", 6));
		mixin(bitfields!(uint, "Imm", 16,
						 uint, "filler2", 16));
	};
}

class CPU
{
public:
	uint[32] r;
	uint     pc;
	union
	{
		uint msr;		
		mixin(bitfields!(bool, "CC" , 1,
						 uint, "RESERVED", 16,
						 bool, "VMS", 1,
						 bool, "VM" , 1,
						 bool, "UMS", 1,
						 bool, "UM" , 1,
						 bool, "PVR", 1,
						 bool, "EIP", 1,
						 bool, "EE" , 1,
						 bool, "DCE", 1,
						 bool, "DZO", 1,
						 bool, "ICE", 1,
						 bool, "FSL", 1,
						 bool, "BIP", 1,
						 bool, "C"  , 1,
						 bool, "IE" , 1,
						 bool, "BE" , 1));
	}

	Nullable!uint immExt;
	Nullable!Instruction delaySlot;

	this(MemorySpace m)
	{
		mem = m;
		delaySlot.nullify();
	}

	bool tick()
	{
		auto indentstr = new char[indent];
		indentstr[] = ' ';
		if (delaySlot.isNull)
		{
			immutable ins = cast(Instruction)mem.readWord(pc);
			version(TraceInstructions)
			{
				writefln("%s%x: %x", indentstr, pc, ins.insword);
			}
			if (ins.insword == 0xb8000000) // bri 0
			{
				
				version(TraceInstructions)
					writeln("halt");
				return false;
			}
			execute(ins);
		}
		else
		{
			version(TraceInstructions)
				writefln("%sdelayslot: %x", indentstr, delaySlot.insword);
			execute(delaySlot);
			delaySlot.nullify();
			pc -= 4;
		}
		return true;
	}

	void execute(const Instruction ins)
	{
		bool typeB = (ins.Opcode & 0x8) != 0;
		uint op1 = r[ins.Ra];
		uint op2 = typeB ? getImm(ins) : r[ins.Rb];

		switch(ins.Opcode)
		{
		case 0b000000:			// ADD
		case 0b000010:			// ADDC
		case 0b000100:			// ADDK
		case 0b000110:			// ADDKC
		case 0b001000:			// ADDI
		case 0b001010:			// ADDIC
		case 0b001100:			// ADDIK
		case 0b001110:			// ADDIKC
            ulong sum = cast(ulong)op1 + cast(ulong)op2;
			r[ins.Rd] = cast(uint)sum;
			if (ins.Opcode & 0b010 && C) // C
				r[ins.Rd] += 1;
			if ((ins.Opcode & 0b100) == 0) // K
                C = (sum > 0xffffffff);
			pc += 4;
			break;
		case 0b000001:			// RSUB
		case 0b000011:			// RSUBC
		case 0b000111:			// RSUBKC
		case 0b001001:			// RSUBI
		case 0b001011:			// RSUBIC
		case 0b001101:			// RSUBIK
		case 0b001111:			// RSUBIKC
			if (ins.Opcode & 0b010) // C
				r[ins.Rd] = op2 + ~op1 + C ? 1 : 0;
			else
				r[ins.Rd] = op2 + ~op1 + 1;
			if ((ins.Opcode & 0b100) == 0) // K
				C = op2 < op1;
			pc += 4;
			break;
			
		case 0b000101:			// CMP,CMPU,RSUBK
			{
				r[ins.Rd] = op2 + ~op1 + 1;
				switch(ins.filler1)
				{
				case 1:				// CMP
					if (cast(int)op2 >= cast(int)op1)
					    r[ins.Rd] &= 0x7fffffff;
					else
						r[ins.Rd] |= 0x80000000;
					break;
				case 3:				// CMPU
					if (op2 >= op1)
						r[ins.Rd] &= 0x7fffffff;
					else
						r[ins.Rd] |= 0x80000000;
					break;
				default:			// RSUBK
					break;
				}
			}
			pc += 4;
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
			pc += 4;
			break;
		case 0b011000:			// MULI
			r[ins.Rd] = op1 * op2;
			pc += 4;
			break;
        case 0b010001:          // BSRL,BSRA,BSLL
			switch(ins.filler1 >> 5)
			{
			case 0:				// BSRLI
				r[ins.Rd] = op1 >>> op2;
				break;
			case 0b10000:		// BSRAI
				r[ins.Rd] = cast(int)op1 >> op2;
				break;
			case 0b100000:		// BSLLI
				r[ins.Rd] = op1 << op2;
				break;
			default:
				unknownInstruction(ins);
			}
			pc += 4;
            break;
		case 0b100100:			// SRA,SRC,SRL
			switch (op2)
			{
			case 0b0000000000000001: // SRA
				r[ins.Rd] = cast(int)op1 >> 1;
				break;
			case 0b0000000000100001: // SRC
				r[ins.Rd] = (op1 >>> 1) | (C ? 0x80000000 : 0);
				break;
			case 0b0000000001000001: // SRL
				r[ins.Rd] = op1 >>> 1;
				break;
			}
			C = op1 & 0x1;
			pc += 4;
            break;
		case 0b011001:			// BSRLI,BSRAI,BSLLI
			switch(op2 >> 5)
			{
			case 0:				// BSRLI
				r[ins.Rd] = op1 >>> (op2 & 0b11111);
				break;
			case 0b10000:		// BSRAI
				r[ins.Rd] = cast(int)op1 >> (op2 & 0b11111);
				break;
			case 0b100000:		// BSLLI
				r[ins.Rd] = op1 << (op2 & 0b11111);
				break;
			default:
				unknownInstruction(ins);
			}
			pc += 4;
			break;
		case 0b101000:			// ORI
			r[ins.Rd] = op1 | op2;
			pc += 4;
			break;			
		case 0b100000:			// OR,PCMPBF
			if (ins.filler1 == 0)	// OR
			{
				r[ins.Rd] = op1 | op2;
			}
			else				// PCMPBF
			{
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
			pc += 4;
			break;
		case 0b100010:			// PCMPEQ, XOR
			if (ins.filler1 == 0)
            {
				r[ins.Rd] = op1 ^ op2;
            }
			else
            {
				r[ins.Rd] = (op2 == op1) ? 1 : 0;
            }
            pc += 4;
            break;
		case 0b100001:			// AND
		case 0b101001:			// ANDI
			r[ins.Rd] = op1 & op2;
			pc += 4;
			break;
		case 0b101010:			// XORI
			r[ins.Rd] = op1 ^ op2;
			pc += 4;
			break;
		case 0b101100:			// IMM
			immExt = ins.Imm << 16;
			pc += 4;
			break;
		case 0b101101:			// RTSD,RTID,RTBD,RTED
			switch(ins.Rd)
			{
			case 0b10000:		// RTSD
				delaySlot = cast(Instruction)mem.readWord(pc+4);
				indent-=2;
				pc = op1 + op2;
				break;
			case 0b10001:		// RTID
				throw new Exception("unimplemented instruction RTID");
			case 0b10010:		// RTBD
				throw new Exception("unimplemented instruction RTBD");
			case 0b10100:		// RTED
				throw new Exception("unimplemented instruction RTED");
			default:
				unknownInstruction(ins);
			}
			break;
		case 0b100110:			// BR,BRD,BRLD,BRA,BRAD,BRALD,BRK
		case 0b101110:			// BRI,BRID,BRLID,BRAI,BRAID,BRALID,BRKI
			switch(ins.Ra)
			{
			case 0b00000:		// BRI
				pc += op2;
				break;
			case 0b10000:		// BRID
				delaySlot = cast(Instruction)mem.readWord(pc+4);
				pc += op2;
				break;
			case 0b10100:		// BRLID
				r[ins.Rd] = pc;
				delaySlot = cast(Instruction)mem.readWord(pc+4);
				indent+=2;
				pc += op2;
				break;
			case 0b01000:		// BRAI
				pc = op2;
				break;
			case 0b11000:		// BRAID
				delaySlot = cast(Instruction)mem.readWord(pc+4);
				pc = op2;
				break;
			case 0b11100:		// BRALID
				r[ins.Rd] = pc;
				delaySlot = cast(Instruction)mem.readWord(pc+4);
				indent+=2;
				pc = op2;
				break;
			case 0b01100:		// BRKI
				r[ins.Rd] = pc;
				pc = op2;
				BIP = true;
				break;
			default:
				unknownInstruction(ins);
			}
			break;
		case 0b101111:			// BEQI,BNEI,BLTI,BLEI,BGTI,BGEI,BEQID,BNEID,BLTID,BLEID,BGTID,BGEID
			switch(ins.Rd & 0b1111)
			{
			case 0b00000:		// BEQI
				if (op1 == 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			case 0b00001:		// BNEI
				if (op1 != 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			case 0b00010:		// BLTI
				if (cast(int)op1 < 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			case 0b00011:		// BLEI
				if (cast(int)op1 <= 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			case 0b00100:		// BGTI
				if (cast(int)op1 > 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			case 0b00101:		// BGEI
				if (cast(int)op1 >= 0)
				{
					if (ins.Rd & 0b10000)
						delaySlot = cast(Instruction)mem.readWord(pc+4);
					pc += op2;
				}
				else
					pc += 4;
				break;
			default:
				unknownInstruction(ins);
			}
			break;
		case 0b110000:			// LBU
		case 0b111000:			// LBUI
			{
				uint addr = op1 + op2;
				r[ins.Rd] = mem.readByte(addr);
				// writefln("  read byte %x => %x", addr, r[ins.Rd]);
			}
			pc += 4;
			break;
		case 0b110010:			// LW
		case 0b111010:			// LWI
			{
				uint addr = op1 + op2;
				r[ins.Rd] = mem.readWord(addr);
				// writefln("  read word %x => %x", addr, r[ins.Rd]);
			}
			pc += 4;
			break;
		case 0b110100:			// SB
		case 0b111100:			// SBI
			{
				uint addr = op1 + op2;
				mem.writeByte(addr, cast(byte)r[ins.Rd]);
				// writefln("  write byte %x => %x", cast(byte)r[ins.Rd], addr);
			}
			pc += 4;
			break;
		case 0b110110:			// SW
		case 0b111110:			// SWI
			{
				uint addr = op1 + op2;
				mem.writeWord(addr, r[ins.Rd]);
				// writefln("  write word %x => %x", r[ins.Rd], addr);
			}
			pc += 4;
			break;
		case 0b110001:			// LHU
		case 0b111001:			// LHUI
			{
				uint addr = op1 + op2;
				auto b1 = mem.readByte(addr);
				auto b2 = mem.readByte(addr+1);
				version (BigEndianMicroBlaze)
					r[ins.Rd] = (b1 << 8) | b2;
				else // Little endian
					r[ins.Rd] = (b2 << 8) | b1;
			}
			pc += 4;
			break;
		case 0b110101:			// SH
		case 0b111101:			// SHI
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
			}
			pc += 4;
			break;
		case 0b100011:			// PCMPNE
			r[ins.Rd] = (op1 == op2) ? 0 : 1;
			pc += 4;
			break;
		case 0b100100:			// SEXT8, SEXT16
			if (op2 & 1)
				r[ins.Rd] = cast(int)(cast(short)op1);
			else 
				r[ins.Rd] = cast(int)(cast(byte)op1);
			pc += 4;
			break;
		case 0b100101:			// MTS
			switch(ins.Imm)
			{
			case 0x0001:
				msr = op1;
				break;
			default:
				version(TraceInstructions)
					writefln("unsupported MTS %x", ins.Imm);
				break;
			}
			pc += 4;
			break;
		default:
			unknownInstruction(ins);
		}
	}

private:
	MemorySpace mem;
	int indent = 0;

	final byte getByte(uint w, int n) pure { return 0xff & (w >> ((3 - n) * 8)); }

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

    void unknownInstruction(Instruction ins)
    {
        throw new Exception(format("unknown instruction %x @%x", ins.insword, pc));
    }
}

module mbemu.elf;

import std.mmfile;
import std.bitmanip;
import std.algorithm;
import std.conv;

import mbemu.mem;

// Elf data types
private alias uint      Elf32_Addr;
private alias uint      Elf32_Off;
private alias ushort    Elf32_Half;
private alias uint      Elf32_Word;
private alias int       Elf32_Sword;

// Elf constants
private enum EI_NIDENT = 16;
private enum EI_MAG0    = 0;
private enum EI_MAG1    = 1;
private enum EI_MAG2    = 2;
private enum EI_MAG3    = 3;

private enum ELFMAG0    = 0x7f; /* EI_MAG */
private enum ELFMAG1    = 'E';
private enum ELFMAG2    = 'L';
private enum ELFMAG3    = 'F';

private enum SHT_PROGBITS = 1;
private enum SHT_STRTAB = 3;

// Elf structs
private align(1)
struct Elf32_Ehdr {
    ubyte[EI_NIDENT] e_ident;      /* ident bytes */
    Elf32_Half       e_type;       /* file type */
    Elf32_Half       e_machine;    /* target machine */
    Elf32_Word       e_version;    /* file version */
    Elf32_Addr       e_entry;      /* start address */
    Elf32_Off        e_phoff;      /* phdr file offset */
    Elf32_Off        e_shoff;      /* shdr file offset */
    Elf32_Word       e_flags;      /* file flags */
    Elf32_Half       e_ehsize;     /* sizeof ehdr */
    Elf32_Half       e_phentsize;  /* sizeof phdr */
    Elf32_Half       e_phnum;      /* number phdrs */
    Elf32_Half       e_shentsize;  /* sizeof shdr */
    Elf32_Half       e_shnum;      /* number shdrs */
    Elf32_Half       e_shstrndx;   /* shdr string index */

    void fixEndian()
    {
        version(BigEndianMicroBlaze)
        {
            swapEndianInplace(e_type);
            swapEndianInplace(e_machine);
            swapEndianInplace(e_version);
            swapEndianInplace(e_entry);
            swapEndianInplace(e_phoff);
            swapEndianInplace(e_shoff);
            swapEndianInplace(e_flags);
            swapEndianInplace(e_ehsize);
            swapEndianInplace(e_phentsize);
            swapEndianInplace(e_phnum);
            swapEndianInplace(e_shentsize);
            swapEndianInplace(e_shnum);
            swapEndianInplace(e_shstrndx);
        }
    }
}

private align(1)
struct Elf32_Shdr {
    Elf32_Word  sh_name;
    Elf32_Word  sh_type;
    Elf32_Word  sh_flags;
    Elf32_Addr  sh_addr;
    Elf32_Off   sh_offset;
    Elf32_Word  sh_size;
    Elf32_Word  sh_link;
    Elf32_Word  sh_info;
    Elf32_Word  sh_addralign;
    Elf32_Word  sh_entsize;

    void fixEndian()
    {
        version(BigEndianMicroBlaze)
        {
            swapEndianInplace(sh_name);
            swapEndianInplace(sh_type);
            swapEndianInplace(sh_flags);
            swapEndianInplace(sh_addr);
            swapEndianInplace(sh_offset);
            swapEndianInplace(sh_size);
            swapEndianInplace(sh_link);
            swapEndianInplace(sh_info);
            swapEndianInplace(sh_addralign);
            swapEndianInplace(sh_entsize);
        }
    }
}

private void swapEndianInplace(T) (ref T v)
{
    v = swapEndian(v);
}

private T* getStruct(T, S, I)(S buf, I pos)
{
    auto bytes = cast(ubyte[])buf[pos..pos+T.sizeof];
    return cast(T*)bytes.ptr;
}

uint loadElf(string filename, MemorySpace mem)
{
    auto mmfile = new MmFile(filename);

    // read elf header
    auto ehdr = *mmfile.getStruct!Elf32_Ehdr(0);
    ehdr.fixEndian();

    if (ehdr.e_ident[EI_MAG0] != ELFMAG0 || ehdr.e_ident[EI_MAG1] != ELFMAG1 || ehdr.e_ident[EI_MAG2] != ELFMAG2 || ehdr.e_ident[EI_MAG3] != ELFMAG3)
        throw new Exception("Invalid ELF file");

    // read string table section
    auto stringTableHeader = *mmfile.getStruct!Elf32_Shdr(ehdr.e_shoff + Elf32_Shdr.sizeof * ehdr.e_shstrndx);
    stringTableHeader.fixEndian();

    if (stringTableHeader.sh_type != SHT_STRTAB)
        throw new Exception("Invalid ELF file");

    // go through all sections
    for (Elf32_Half i = 0; i < ehdr.e_shnum; ++i)
    {
        Elf32_Shdr shdr = *mmfile.getStruct!Elf32_Shdr(ehdr.e_shoff + Elf32_Shdr.sizeof * i);
        shdr.fixEndian();

        if (shdr.sh_type == SHT_PROGBITS)
        {
            string sectionName = mmfile[stringTableHeader.sh_offset + shdr.sh_name .. stringTableHeader.sh_offset + stringTableHeader.sh_size].to!string;

            if (sectionName.startsWith(".debug") || sectionName.startsWith(".comment"))
                continue;

            auto section = cast(ubyte[])mmfile[shdr.sh_offset .. shdr.sh_offset + shdr.sh_size];
            for(int offset = 0; offset < shdr.sh_size; ++offset)
                mem.writeByte(shdr.sh_addr + offset, section[offset]);
        }
    }

    return ehdr.e_entry;
}

// Local Variables:
// indent-tabs-mode: nil
// End:

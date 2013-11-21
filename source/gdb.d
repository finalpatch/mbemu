module mbemu.gdb;
import std.concurrency;
import std.socket;
import std.stdio;
import std.algorithm;
import std.string;
import std.bitmanip;
import std.regex;
import std.conv;
import mbemu.cpu;

private __gshared TcpSocket server;
private __gshared Tid serverTid;

void handleGdbCommands(CPU cpu)
{
    static uint[] breakpoints = [];

    struct DataBreakPoint
    {
        bool read;
        bool write;
        uint addr;
        uint size;
    }
    static DataBreakPoint[] dataBreakpoints = [];
    bool hitDataBreakpoint = false;
    cpu.memaccess = delegate(bool write, uint addr, uint size)
        {
            foreach(b; dataBreakpoints)
            {
                if (addr < (b.addr + b.size) && b.addr < (addr + size))
                {
                    if (!write && b.read)
                        hitDataBreakpoint = true;
                    if (write && b.write)
                        hitDataBreakpoint = true;
                }
            }
        };
    
    auto cmd = receiveOnly!string();
    version(TraceGdbPackets)
        writefln("gdb: %s", cmd);

    if (cmd == "?")
    {
        serverTid.send("S05");
    }
    else if (cmd.startsWith("qAttached"))
    {
        serverTid.send("1");
    }
    else if (cmd == "g")
    {
        string resp;
        foreach(r; cpu.r)
        {
            resp ~= dumpRegister(r);
        }
        resp ~= dumpRegister(cpu.pc);
        resp ~= dumpRegister(cpu.msr);
        serverTid.send(resp);
    }
    else if (cmd.startsWith("P"))
    {
        auto re = regex(r"P([0-9a-f]+)=([0-9a-f]+)");
        auto m = match(cmd, re);
        auto reg = m.captures[1].to!uint(16);
        auto val = m.captures[2].to!uint(16);
        switch(reg)
        {
        case 0x0: .. case 0x1f: cpu.r[reg] = val; break;
        case 0x20: cpu.pc = val; break;
        case 0x21: cpu.msr = val; break;
        default: break;
        }
        serverTid.send("OK");
    }
    else if (cmd == "c")
    {
        try
        {
            while (!breakpoints.canFind(cpu.pc))
            {
                if (!cpu.tick())
                {
                    serverTid.send("S03");
                    return;
                }
                if (hitDataBreakpoint)
                    break;
            }
        }
        catch(Exception) {}
        serverTid.send("S05");
    }
    else if (cmd == "k")
    {
        import std.c.stdlib;
        exit(0);
    }
    else if (cmd.startsWith("m"))
    {
        auto re = regex(r"m([0-9a-f]+),([0-9a-f]+)");
        auto m = match(cmd, re);
        auto addr = m.captures[1].to!uint(16);
        auto size = m.captures[2].to!uint(16);
        string resp;
        for (uint i = 0; i < size; ++i)
            resp ~= "%02x".format(cpu.readMemByte(addr + i));
        serverTid.send(resp);
    }
    else if (cmd.startsWith("M"))
    {
        auto re = regex(r"M([0-9a-f]+),([0-9a-f]+):([0-9a-f]+)");
        auto m = match(cmd, re);
        auto addr = m.captures[1].to!uint(16);
        auto size = m.captures[2].to!uint(16);
        string sdata = m.captures[3];
        for(uint i = 0; i < size; ++i)
        {
            ubyte data = sdata[0..2].to!ubyte(16);
            try
            {
                cpu.writeMemByte(addr + i, data);
            }
            catch(Exception)
            {}
            sdata = sdata[2..$];
        }
        serverTid.send("OK");
    }
    else if (cmd.startsWith("Z") || cmd.startsWith("z"))
    {
        auto re = regex(r"([zZ])([0-4]),([0-9a-f]+),([0-9a-f]+)");
        auto m = match(cmd, re);
        string z = m.captures[1];
        string kind = m.captures[2];
        auto addr = m.captures[3].to!uint(16);
        auto size = m.captures[4].to!uint(16);
        if ((kind == "0" || kind == "1")) // code breakpoint
        {
            if (z == "Z")
                breakpoints ~= addr;
            else
                breakpoints = partition!(x=>(x==addr))(breakpoints);
        }
        else
        {
            DataBreakPoint bp;
            bp.read = (kind == "3") || (kind == "4");
            bp.write = (kind == "2") || (kind == "4");
            bp.addr = addr;
            bp.size = size;
            if (z == "Z")
                dataBreakpoints ~= bp;
            else
                dataBreakpoints = partition!(x=>(x==bp))(dataBreakpoints);
        }
        serverTid.send("OK");
    }
    else
    {
        serverTid.send("");
    }
}

void startGdbServer(short port)
{
    serverTid = spawnLinked(&serverThread, thisTid, port);
}

void stopGdbServer()
{
    server.close();
}

private void serverThread(Tid owner, short port)
{
    server = new TcpSocket();
    server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    server.bind(new InternetAddress(port));
    server.listen(1);
    while(true)
    {
        try
        {
            Socket client = server.accept();
            handleGdbClient(owner, client);
        }
        catch(SocketAcceptException)
        {
            break;
        }
    }
}

private void handleGdbClient(Tid owner, Socket client)
{
    while (true)
    {
        char[1024] buf;
        auto received = client.receive(buf);
        if (received == 0)
            break;
        client.send("+");   // ack
        
        auto cmd = buf[0..received];
        
        if (cmd == "+")
            continue;

        cmd = cmd[1..$-3];
        if (cmd == "D")         // detach
        {
            client.rspSend("OK");
            break;
        }

        owner.send(cmd.idup);
        auto resp = receiveOnly!string();
        client.rspSend(resp);
    }
    client.close();
}

private void rspSend(Socket client, string resp)
{
    auto checksum = (reduce!"a+b"(0, resp)) % 256;
    auto packet = "$%s#%02x".format(resp, checksum);
    version(TraceGdbPackets)
        writefln("mb : %s", packet);
    while (true) {
        client.send(packet);
        char[1] ack;
        client.receive(ack);
        if (ack[0] != '-')
            break;
    }
}

private string dumpRegister(uint r)
{
    string s;
    version(BigEndianMicroBlaze)
        r = swapEndian(r);
    s ~= "%02x".format(r & 0xff); r >>= 8;
    s ~= "%02x".format(r & 0xff); r >>= 8;
    s ~= "%02x".format(r & 0xff); r >>= 8;
    s ~= "%02x".format(r & 0xff);
    return s;
}

// Local Variables:
// indent-tabs-mode: nil
// End:

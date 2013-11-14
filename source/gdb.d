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
    
    auto cmd = receiveOnly!string();
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
    else if (cmd == "c")
    {
        while (!breakpoints.canFind(cpu.pc))
            cpu.tick();
        serverTid.send("S05");
    }
    else if (cmd.startsWith("m"))
    {
        auto re = regex(r"m([0-9a-f]+),([0-9]+)");
        auto m = match(cmd, re);
        string saddr = m.captures[1];
        string ssize = m.captures[2];
        auto addr = parse!uint(saddr, 16);
        auto size = parse!uint(ssize, 16);
        string resp;
        for (uint i = 0; i < size; ++i)
            resp ~= "%02x".format(cpu.readMemByte(addr + i));
        serverTid.send(resp);
    }
    else if (cmd.startsWith("Z0") || cmd.startsWith("z0"))
    {
        auto re = regex(r"([zZ])0,([0-9a-f]+),([0-9]+)");
        auto m = match(cmd, re);
        string z = m.captures[1];
        string saddr = m.captures[2];
        auto addr = parse!uint(saddr, 16);
        if (z == "Z")
            breakpoints ~= addr;
        else
            breakpoints = partition!(x=>(x==addr))(breakpoints);
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

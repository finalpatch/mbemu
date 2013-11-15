mbemu
=====

A MicroBlaze emulator in D language

# Prepare a C/C++ program to run in the emulator

```
$ mb-g++ -mxl-barrel-shift -mxl-pattern-compare -mcpu=v8.20.a -mno-xl-soft-mul -mbig-endian
-fno-exceptions -Wl,-defsym -Wl,_STACK_SIZE=4096 -Wl, -defsym -Wl,_HEAP_SIZE=8192
-g -o test.elf test.cpp
```
It is important to change the stack size to at least 2kb because printf() alone uses 1.5kb of stack space.
Also make sure the emulator has the same endian as the program (define the 'BigEndianMicroBlaze' version
to compile a big endian emulator).

# Run the program in the emulator

```
$ ./mbemu test.elf
```
Or if you want to attach gdb to the emulator

```
$ ./mbemu --debug test.elf
```
This will load the program in the emulator paused, and start a GDB server listening on port 1234.

# Debugging with GDB

```
$ mb-gdb -ex "target remote localhost:1234" test.elf
GNU gdb (GDB) 7.4.50.20120403-cvs
Copyright (C) 2012 Free Software Foundation, Inc.
Reading symbols from C:\Users\fengli\code\mbemu\test.elf...done.
Remote debugging using localhost:1234
_start () at /gnu/mb_gnu/src/newlib/libgloss/microblaze/crt0.S:61
61      /gnu/mb_gnu/src/newlib/libgloss/microblaze/crt0.S: No such file or directory.
(gdb) b main
Breakpoint 1 at 0x248: file test.cpp, line 24.
(gdb) cont
Continuing.

Breakpoint 1, main () at test.cpp:24
24              asm("msrset r5, 0x2");
(gdb) info locals
x = 504
(gdb) n
26              fpga[InterruptControl] |= 1 << TimerInterrupt;
(gdb) n
28              fpga[TimerSet] = 2000;
(gdb) n
30              scanf("%d", &x);
(gdb) n
31              printf("%d\n", x);
(gdb) info locals
x = 30
(gdb) set x=40
(gdb) info locals
x = 40
(gdb)

```

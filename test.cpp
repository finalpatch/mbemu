#include <stdio.h>
#include <stdint.h>

volatile char* io = (char*)0xfffffffc;
volatile uint32_t* fpga = (uint32_t*)0xffffff00;

enum {
	InterruptControl,
	InterruptStatus,
	TimerCounter,
	TimerSet,
	FrameBuffer0,
	FrameBuffer1,
	NumOfRegisters,
};

enum {
	TimerInterrupt,
};

int main()
{
	// enable interrupt on cpu
	asm("msrset r5, 0x2");
	// enable timer interrupt on fpga
	fpga[InterruptControl] |= 1 << TimerInterrupt;
	// set timer
	fpga[TimerSet] = 2000;
	int x;
	scanf("%d", &x);
	printf("%d\n", x);
	return 0;
}

__attribute__ ((interrupt_handler))
void isr()
{
	fpga[InterruptStatus] = 1 << TimerInterrupt;
	const static char msg[] = "isr\n";
	for (const char* p = msg; *p; ++p)
		*io = *p;
}

extern "C"
void outbyte(char c)
{
	*io = c;
}

extern "C"
char inbyte()
{
	return *io;
}

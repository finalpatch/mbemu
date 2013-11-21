#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

volatile char* io = (char*)0xfffffffc;
volatile uint32_t* fpga = (uint32_t*)0xffff0000;

enum {
	InterruptControl,
	InterruptStatus,
	TimerCounter,
	TimerSet,
	LCDEnable,
	LCDLookupTable,
	LCDFrameBuffer = LCDLookupTable + 0x100,
	NumOfRegisters,
};

enum {
	TimerInterrupt,
};

const static uint32_t w = 320;
const static uint32_t h = 240;
static uint8_t fb[2][w*h];

void fillRect(uint8_t* fb, uint32_t x1, uint32_t y1, uint32_t x2, uint32_t y2, uint8_t clr)
{
	for(int y = y1; y < y2; ++y)
	{
		memset(&fb[w * y + x1], x2 - x1, clr);
	}
}

int main()
{
	// enable interrupt on cpu
	asm("msrset r5, 0x2");
	// enable timer interrupt on fpga
	fpga[InterruptControl] |= 1 << TimerInterrupt;
	// set timer
	fpga[TimerSet] = fpga[TimerCounter] + 2000;

	for(int i = 0; i < 250;)
	{
		fpga[LCDLookupTable + (i++)] = 0xff0000ff;
		fpga[LCDLookupTable + (i++)] = 0xff00ff00;
		fpga[LCDLookupTable + (i++)] = 0xffff0000;
		fpga[LCDLookupTable + (i++)] = 0xff00ffff;
		fpga[LCDLookupTable + (i++)] = 0xffffff00;
		fpga[LCDLookupTable + (i++)] = 0xffff00ff;
	}
	fpga[LCDEnable] = 1;
	
	while (true)
	{
		uint x1 = rand() % w;
		uint x2 = rand() % w;
		uint y1 = rand() % h;
		uint y2 = rand() % h;
		fillRect(fb[0], x1, y1, x2, y2, rand() & 0xff);
		fpga[LCDFrameBuffer] = (uint32_t)fb[0];
	}
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

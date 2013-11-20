#include <stdio.h>
#include <stdint.h>

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

int main()
{
	// enable interrupt on cpu
	asm("msrset r5, 0x2");
	// enable timer interrupt on fpga
	fpga[InterruptControl] |= 1 << TimerInterrupt;
	// set timer
	fpga[TimerSet] = fpga[TimerCounter] + 2000;

	// fill lut [argb]
	fpga[LCDLookupTable] = 0xffff00ff;
	fpga[LCDLookupTable+1] = 0xff0000ff;
	fpga[LCDEnable] = 1;
	uint32_t idx = 0;
	while (true)
	{
		for(int y = 0; y < h; ++y)
		{
			for(int x = 0; x < w; ++x)
			{
				fb[idx][w * y + x] = idx ? 0 : 1;
			}
		}
		fpga[LCDFrameBuffer] = (uint32_t)fb[idx];
		idx = (idx + 1) % 2;
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

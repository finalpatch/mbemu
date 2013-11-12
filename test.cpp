#include <stdio.h>
#include <stdint.h>

volatile char* io = (char*)0xfffffffc;
volatile char* intctl = (char*)0xfffffff0;

int main()
{
	asm("msrset r5, 0x2");
	int x;
	scanf("%d", &x);
	printf("%d\n", x);
	return 0;
}

__attribute__ ((interrupt_handler))
void isr()
{
	*intctl = 0;
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

#include <stdio.h>

volatile char* io = (char*)0xfffffffc;

const char hello[] = "Hello %s!\n";

int main()
{
	printf("You name: ");
	char name[20];
	scanf("%s", name);
	printf(hello, name);
	return 0;
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

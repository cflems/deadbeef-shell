all:
	nasm sh.s -f elf64 -o sh.o
	ld sh.o -o sh
clean:
	rm -f sh.o sh

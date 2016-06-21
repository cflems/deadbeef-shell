all:
	nasm sh.asm -f elf64 -o sh.o
	ld sh.o -o sh
clean:
	rm -f sh.o sh

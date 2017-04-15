all:
	nasm sh.asm -f elf64 -o sh.o
	ld sh.o -o sh
	strip sh
	rm sh.o
dbg:
	nasm sh.asm -f elf64 -o sh.o
	ld sh.o -o sh
	rm sh.o
	gdb -q --eval-command="layout asm" -tui sh
clean:
	rm -f sh.o sh

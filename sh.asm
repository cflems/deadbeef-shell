section .data
	sigs dd 0x2
	cpid dd 0x0
	eol db `\n`
	msg db "Welcome to deadbeef shell!", `\n`
	env_str db "/etc/environment", 0x0

  prompt_str db "[0xdeadbeef] "
  prompt_str_len equ $-prompt_str
  
	not_func_str db "Error: program not found.", `\n`
  not_func_str_len equ $-not_func_str

	boe_str db "Error: input overflows buffer.", `\n`
  boe_str_len equ $-boe_str

	no_dir_str db "cd: Unknown directory.",`\n`
	no_dir_str_len equ $-no_dir_str

	invalid_int_str db "exit: Invalid integer.",`\n`
	invalid_int_str_len equ $-invalid_int_str
	;Flag indicating ability to execute
	X_OK equ 0x1

	;Indicates that a file can be accessed in the way specified
	F_OK equ 0x0

	;option for waitid
	P_PGID equ 2

	;Special file descriptors
	fd_stdin equ 0x00
	fd_stdout equ 0x01
	fd_stderr equ 0x02

	;Syscall constants
	sys_read equ 0x00
	sys_write equ 0x01
	sys_open equ 0x02
	sys_close equ 0x03
	sys_access equ 0x15
	stub_fork equ 0x39
	stub_execve equ 0x3b
	sys_exit equ 0x3c
	sys_wait4 equ 0x3d
	sys_kill equ 0x3e
	sys_chdir equ 0x50
	sys_waitid equ 0xf7


section .text
	global _start

_start:
	; TODO: handle interrupt signal

	push rbp
	mov rbp, rsp
	sub rsp, 0x110
	mov r15, rsp
	sub rsp, 0x110
	mov r9, rsp
	sub rsp, 0x110
	mov rbx, rsp

	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, msg
	mov rdx, 0x1b
	syscall

	jmp _parse_path

_read_loop:
	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, prompt_str
	mov rdx, prompt_str_len
	syscall

	mov r8, -0x1
	mov r12, _read_loopr
	jmp _bzero

_read_loopr:
	mov rax, sys_read
	xor rdi, rdi ;stdin
	mov rsi, r15
	mov rdx, 0xff
	syscall

	; check for _quit
	mov r12, _quit
	cmp byte [r15], 0x0
	je _weol
	;Start using r12 to hold the number of args
	xor r12,r12

	; call _parse
	jmp _parse

_exec:
	; fork so we don't hurt ourselves
	mov rax, stub_fork
	syscall
	mov dword [cpid], eax
	test eax, eax ;checks if cpid is 0
	jne _wait_for_proc

	; now that we know what to execute, do so
	mov rax, stub_execve
	mov rdi, r13 ;Filename
	mov rsi, r14 ;argv
	xor rdx, rdx ;envp
	syscall

	; and now kill the child process
	jmp _quit

;waits for the process to close
_wait_for_proc:
	mov r12, r10 ;backup

	mov rsi, rax
	mov rax, sys_waitid
	xor rdi, rdi
	xor rdx, rdx
	mov r10, P_PGID
	xor r8, r8
	syscall

	mov r10, r12 ;restore

	mov dword [cpid], -0x1
	jmp _read_loop

; input: none
; output: r9 (path elements), r10 (length)
; clobbered: r8, r12
; other: r15 (buffer)
_parse_path:
	mov rax, sys_open
	mov rdi, env_str
	xor rsi, rsi
	syscall
	test rax, rax ;check if rax is 0
	jl _quit

	mov r8, -0x1
	mov r12, _parse_path2
	jmp _bzero

_parse_path2:
	mov rdi, rax
	mov rax, sys_read
	mov rsi, r9
	mov rdx, 0xff
	syscall
	test rax, rax
	jl _quit
	mov r8, r9
	dec r8
; Reads the PATH variable
_pathfinder:
	inc r8
	xor rax, rax
	mov byte al, [r8]
	cmp al, `P`
	jne _pathfinder
	mov byte al, [r8+1]
	cmp al, `A`
	jne _pathfinder
	mov byte al, [r8+2]
	cmp al, `T`
	jne _pathfinder
	mov byte al, [r8+3]
	cmp al, `H`
	jne _pathfinder
	mov byte al, [r8+4]
	cmp al, `=`
	jne _pathfinder
	mov byte al, [r8+5]
	cmp al, `"`
	jne _pathfinder
	test al, al ;checks for 0
	je _quit
	add r8, 0x6
	mov r10, 0x1
	push 0x0
	push r8
	dec r8

_pathender:
	inc r8
	mov al, [r8]
	cmp al, `:`
	je _pathender1
	cmp al, `"`
	jne _pathender
	mov byte [r8], 0x0
	mov r9, rsp
	jmp _read_loop

_pathender1:
	inc r10
	mov byte [r8], 0x0
	lea rcx, [r8+0x1]
	push rcx
	jmp _pathender

;Writes 0s in buffer r15 until r8 is 255
;input: r8 (iterator), r15 (buffer), r12 (return address)
;output: none
_bzero:
	inc r8
	mov byte [r8+r15], 0x0
	cmp r8, 0xff
	jle _bzero
	jmp r12

;input: r15 (buffer)
;output: r13 (path), r14 (arguments)
;clobbered: r8, rax, rbx, rcx
_parse:
	;syscall 80 is chdir, so do that first, it's easiest
	;It takes a path string.
	;also needs pipes (|, >, <)
	xor r13, r13 ;for _strlen
	push r13 ;push 0
	jmp _strlen

;r8 holds strlen so we start at the end and parse backwards
; go through and sub/push
_parse1:
	cmp byte [r15+r8], ` `
	je _subzp
	cmp byte [r15+r8], `\n`
	je _subz
	cmp byte [r15+r8], `/`
	je _sabsf
	cmp byte [r15+r8], `.`
	je _sabsf

;Controls the parsing of the directory, keeps parsing each bit of the dir until
;the end of the string or directory name
_parse1r:
	dec r8
	jl _parse2
	jmp _parse1

_sabsf:
	cmp r8, 0x1
	jg _parse1r
	mov r13, 0x1
	jmp _parse1r

_subz:
	mov byte [r8+r15], 0x0
	jmp _parse1

;Splits at the current position and puts the address of the argument on the stack
_subzp:
	mov byte [r8+r15], 0x0
	lea rax, [r8+r15+1]
	push rax
	inc r12
	jmp _parse1

_parse2:
	push rbx
	mov r14, rsp
	cmp r13, 0x0
	jg _parse7
	mov r8, -0x1

_parse3:
	inc r8
	cmp r8, r10
	je _parse4
  ; Builtins to add: export, eval
	;r15 holds the name that the user entered, so we'll use that for shell builtins
	mov rcx,`\0\0\0exit\0`
	mov r13, [r15]
	shl r13, 24 ;Remove the last character in r13, because it's an arg not the name of it
	cmp r13, rcx
	je _builtin_exit
	mov rcx,`\0\0\0\0\0cd\0`
	shl r13, 16 ;Remove the extra characters for cd, note how we're doing the
							;longest function names first then the shorter later
	cmp r13, rcx
	je _builtin_cd
	;END OF BUILTINS
	mov r13, r15
	mov rcx, [r9+r8*8]
	push r8
	jmp _concat

_parse4: ; Function not found
	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, not_func_str
	mov rdx, not_func_str_len
	syscall
	jmp _read_loop

; Checks that the program rbx can be executed
_parse5:
	mov rax, sys_access
	mov rdi, rbx
	mov rsi, X_OK
	syscall

	pop r8
	;Check if it can be executed
	cmp rax, F_OK
	jl _parse3

; We'll fall through to here if the file is accessible, therefore we should execute it
_parse6:
	mov r13, rbx
	jmp _exec

_parse7: ; absolute path
	mov rax, sys_access
	mov rdi, rbx
	mov rsi, X_OK
	syscall

	cmp rax, F_OK
	jl _parse4

	mov r13, r15
	jmp _exec


;input: r12 (return address), r15 (buffer)
;output: r8 (length)
_strlen:
	xor r8, r8

_strlen1:
	cmp byte [r8+r15], 0x0
	je _parse1
	cmp byte [r8+r15], 0xa
	je _parse1
	inc r8
	jmp _strlen1

; input: rcx (a), r13 (b)
; output: rbx (string)
; clobbered: r8, r11
_concat:
	mov r8, -0x1
	jmp _jlen1

_jlen1:
	inc r8
	cmp byte [r8+rcx], 0x0
	je _jlen02
	cmp byte [r8+rcx], 0xa
	je _jlen02
	jmp _jlen1

_jlen02:
	dec r8
	mov r11, -0x1

_jlen2:
	inc r8
	inc r11
	cmp byte [r11+r13], 0x0
	je _treg
	cmp byte [r11+r13], 0xa
	je _treg
	jmp _jlen2

_treg:
	cmp r8, 0xff
	jg _boe
	xchg r15, rbx
	mov r8, -0x1
	mov r12, _jrsinc
	jmp _bzero

_jrsinc:
	xchg r15, rbx
	mov r8, -0x1
	mov r11, -0x1

_join1:
	inc r8
	cmp byte [r8+rcx], 0x0
	je _join02
	cmp byte [r8+rcx], 0xa
	je _join02
	mov al, [r8+rcx]
	mov [r8+rbx], al
	jmp _join1

_join02:
	mov byte [r8+rbx], `/`
_join2:
	inc r8
	inc r11
	cmp byte [r11+r13], 0x0
	je _parse5
	cmp byte [r11+r13], `\n`
	je _parse5
	mov al, [r11+r13]
	mov [r8+rbx], al
	jmp _join2

_boe:
	mov rax, sys_write
	mov rdi, 0x1
	mov rsi, boe_str
	mov rdx, boe_str_len
	jmp _quit

; interrupt signal handler
_sigint:
	cmp dword [cpid], 0x0
	jl _sigint_nc

__sigint_c: ; kill the child
	mov rax, sys_kill
	mov rdi, [cpid]
	mov rsi, 0x2
	syscall

_sigint_nc:
	mov r12, _read_loop
	jmp _weol

; input: r12 (return address)
; output: none
; Writes end of line to the terminal
_weol:
	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, eol
	mov rdx, 0x1
	syscall
	jmp r12

_quit:
	mov rax, sys_exit
	xor rdi, rdi
	syscall

;cd [dir (rax)]
;changes to the given directory
_builtin_cd:
	mov rdi,rax
	mov rax, sys_chdir
	syscall
	test rax, rax
	jz _read_loop
	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, no_dir_str
	mov rdx, no_dir_str_len
	syscall
	jmp _read_loop
;usage: exit [status]
;exits with the given status or 0 if one hasn't been provided
_builtin_exit:
	;convert first arg to an int if present
	;exit with that code
	_string_to_int:
		xor rdi, rdi
		;accumulate in rdi since it's also the register used to provide the status
		;to sys_exit
		xor rdx, rdx
		cmp r12, 0
		jz _string_to_int_end
	_string_to_int_loop:
		mov dl, [rax] ; Convert this to a number
		test dl, dl ;Checks for NULL
		jz _string_to_int_end
		sub dl, `0` ;sub because we'll need to do this anyway
		jl _invalid_int
		cmp dl, 9 ;since we've already subtracted we can just compase with 9
		jg _invalid_int
		imul rdi,10
		add rdi, rdx
		inc rax
		jmp _string_to_int_loop
	_string_to_int_end:
 	mov rax, sys_exit
 	syscall
_invalid_int:
	mov rax,sys_write
	mov rdi, fd_stdout
	mov rsi, invalid_int_str
	mov rdx, invalid_int_str_len
	syscall
	jmp _read_loop

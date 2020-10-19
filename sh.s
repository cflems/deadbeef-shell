section .data
	sigs dd 0x2
	cpid dd 0x0
	eol db `\n`
	eol_mask db `\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`,`\n`
	env_str db "/etc/environment", 0x0

  prompt_str db "[0xdeadbeef] "
  prompt_str_len equ $-prompt_str

	not_func_str db "Error: program not found.", `\n`
  not_func_str_len equ $-not_func_str

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

section .bss
	;These must all be divisible by 16!
	input_buffer_size equ 4096
	input_buffer resb input_buffer_size

	path_buffer_size equ 4096
	path_buffer resb path_buffer_size

	concat_buffer_size equ 8192
	concat_buffer resb concat_buffer_size ;Double so the path and input can never overflow concat_buffer when combined

section .text
	global _start

_start:
	; TODO: handle interrupt signal
	_handle_args:
		pop r15 ;argc
		_handle_args_loop:
			pop r9 ;argv[i]
			;Arg value
			dec r15
			jnz _handle_args_loop
		add rsp, 8 ;Remove the 0 between envp and argv
	mov r15, input_buffer ;stdin input
	mov rbx, concat_buffer ;Concatenated directory and command name

  ; input: none
  ; output: r9 (path elements), r10 (length)
  ; clobbered: r8, r12
  ; other: r15 (buffer)
  _parse_path:
	mov r10, `\0\0\0PATH=`
	_parse_path_loop:
		pop r8
		;If we get to the end and find no path exit
		cmp r8, 0
		je _quit
		mov r12, [r8]
		shl r12, 24
		cmp r12, r10
		jne _parse_path_loop
	;The start of the array
	add r8, 5
	mov r10, 1
	push 0
	push r8
	dec r8
	
	_path_split_loop:
		inc r8
		mov al, [r8]
		cmp al, 0
		je _path_split_exit
		
		cmp al, `:`
		jne _path_split_loop
		;Add the path to the stack
		inc r10
		mov byte [r8], 0
		lea rcx, [r8+1]
		push rcx
		jmp _path_split_loop
	_path_split_exit:
		mov r9, rsp
_read_loop:
	mov rax, sys_write
	mov rdi, fd_stdout
	mov rsi, prompt_str
	mov rdx, prompt_str_len
	syscall

	call _bzero

_read_loopr:
	xor rax, rax ;sys_read
	xor rdi, rdi ;stdin
	mov rsi, r15
	mov rdx, input_buffer_size
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

;Writes 0s in buffer r15 until r8 reaches input_buffer_size
;input: r15 (buffer)
;output: none
_bzero:
	xor r8, r8
	_bzero_main:
		movups [r15+r8], xmm0
		add r8, 16
		cmp r8, input_buffer_size
		jl _bzero_main
	ret

;input: r15 (buffer)
;output: r13 (path), r14 (arguments)
;clobbered: r8, rax, rbx, rcx
_parse:
	;syscall 80 is chdir, so do that first, it's easiest
	;It takes a path string.
	;also needs pipes (|, >, <)
	xor r13, r13 ;for _strlen
	push r13 ;push 0
	call _strlen

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
	cmp r8, 1
	jg _parse1r
	mov r13, 1
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
	test r13, r13
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
	;mov r13, r15
	mov rdi, [r9+r8*8]
	push r8
  ; input: rdi (a), r15 (b)
  ; output: rbx (string)
  ; clobbered: r8, r11
  _concat_dir:
  	xor r8,r8 ;new string's length (and for _dirty_strcpy_1, also the
  			;initial string length)
  	;Copies the contents of rdi to rbx in blocks of
  	;16, doesn't bother to clean up stuff past the null
  	;so moves that too, but it doesn't matter, just make
  	;sure the buffer is big enough
  	_dirty_strcpy_1:
  		movDqU xmm2, [rdi+r8]
  		movDqU [rbx+r8],xmm2

  		pcmpistri xmm1, xmm2, 122
  		jz _dirty_strcpy_1_exit

  		PcmpIstrI xmm0, xmm2, 122 ;if there was a null in the
  						;copied string exit loop
  		jz _dirty_strcpy_1_exit
  		add r8,15
  		jmp _dirty_strcpy_1
  	_dirty_strcpy_1_exit:
  	add r8,rcx
  	inc r8
  	mov byte [rbx+r8], '/'
  	inc r8
  	xor r11, r11
  	_dirty_strcpy_2:
  		movdqu xmm2, [r15+r11]
  		movdqu [rbx+r8], xmm2

  		pcmpistri xmm1, xmm2, 122
  		jz _parse5

  		pcmpistri xmm0, xmm2, 122
  		jz _parse5

  		add r8, 15
  		add r11, 15
  		jmp _dirty_strcpy_2

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
	mov rdi, r15
	mov rsi, X_OK
	syscall

	cmp rax, F_OK
	jl _parse4

	mov r13, r15
	jmp _exec


;input: r15 (buffer)
;Clobbered: rsi
;output: r8 (length)
_strlen:
	xor r8, r8
	xchg rsi, rcx ;bacup rcx, let rsi get clobbered
	MovDqU xmm1, [eol_mask]
	_strlen1:
		PcmpIstrI xmm1, [r15+r8], 122
		jz _strlen_end
		PcmpIstrI xmm0, [r15+r8], 122
		jz _strlen_end
		add r8, 15
		jmp _strlen1
	_strlen_end:
	inc rcx
	add r8, rcx
	xchg rsi,rcx
	ret

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
		test r12, r12
		jz _string_to_int_end
	_string_to_int_loop:
		mov dl, [rax] ; Convert this to a number
		test dl, dl ;Checks for NULL
		jz _string_to_int_end
		sub dl, `0` ;sub because we'll need to do this anyway
		jl _invalid_int
		cmp dl, 9 ;since we've already subtracted we can just compase with 9
		jg _invalid_int
		imul rdi, 10
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

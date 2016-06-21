section .data
	sigs: dd 0x2
	cpid: dd 0x0
	eol: db `\n`
	msg: db "Welcome to deadbeef shell", 0x21, `\n`
	prompt: db "[0xdeadbeef]", 0x20
	nfe: db "Error: program not found", 0x2e, `\n`
	env: db "/etc/environment", 0x0
	boem: db "Error: input overflows buffer", 0x2e, `\n`

  ;Syscall constants
  sys_read equ 0x00
  sys_write equ 0x01
  sys_open equ 0x02
  sys_close equ 0x03
  stub_fork equ 0x39
  stub_execve equ 0x3b
  sys_exit equ 0x3c
  sys_wait4 equ 0x3d
  sys_kill equ 0x3e


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
	mov rdi, 0x1
	mov rsi, msg
	mov rdx, 0x1b
	syscall

	jmp _parse_path

_rloop:
	mov rax, sys_write
	mov rdi, 0x1
	mov rsi, prompt
	mov rdx, 0xd
	syscall

	mov r8, -0x1
	mov r12, _rloopr
	jmp _bzero

_rloopr:
	mov rax, sys_read
	mov rdi, 0x0
	mov rsi, r15
	mov rdx, 0xff
	syscall

	; check for _quit
	mov r12, _quit
	cmp byte [r15], 0x0
	je _weol

	; call _parse
	jmp _parse

_exec:
	; fork so we don't hurt ourselves
	mov rax, stub_fork
	syscall
	mov dword [cpid], eax
	cmp dword [cpid], 0x0
	jne _wait4_it

	; now that we know what to execute, do so
	mov rax, stub_execve
	mov rdi, r13
	mov rsi, r14
	mov rdx, 0x0
	syscall

	; and now kill the child process
	jmp _quit

_wait4_it:
	;This function is obsolete, replace with 247 (sys_waitid)
	mov rdi, rax
	mov rax, sys_wait4
	xor rsi, rsi ; null status pointer
	xor rdx, rdx
	xor rcx, rcx ; null rusage pointer
	syscall

	mov dword [cpid], -0x1
	jmp _rloop

; input: none
; output: r9 (path elements), r10 (length)
; clobbered: r8, r12
; other: r15 (buffer)
_parse_path:
	mov rax, sys_open
	mov rdi, env
	mov rsi, 0x0
	syscall
	cmp rax, 0x0
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
	cmp rax, 0x0
	jl _quit
	mov r8, r9
	dec r8

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
	cmp al, 0x0
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
	jmp _rloop

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
_parse: ; needs special commands: cd exit export eval
	;syscall 80 is chdir, so do that first, it's easiest
	;It takes a path string.
	;also needs pipes (|, >, <)
	push 0x0
	xor r13, r13
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
	cmp r8, 0x0
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
	lea rax, [r8+r15+0x1]
	push rax
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
	mov r13, r15
	mov rcx, [r9+r8*8]
	push r8
	jmp _concat

_parse4: ; not found
	mov rax, sys_write
	mov rdi, 0x1
	mov rsi, nfe
	mov rdx, 0x1a
	syscall
	jmp _rloop

; Checks that the program rbx exists before doing anything, this is hacky, slow
; and should therefore be replaced by a version using sys_access with flag X_OK
_parse5:
	pop r8

	mov rax, sys_open
	mov rdi, rbx
	xor rsi, rsi
	xor rdx, rdx
	syscall

  ;Check if it was opened successfully to check if it exists
	cmp rax, 0x0
	jl _parse3

	mov rdi, rax
	mov rax, sys_close
	syscall

; We'll fall through to here if the file is accessible, therefore we should execute it
_parse6:
	mov r13, rbx
	jmp _exec

_parse7: ; absolute path
	mov rax, sys_open
	mov rdi, r15
	xor rsi, rsi
	xor rdx, rdx
	syscall

	cmp rax, 0x0
	jl _parse4

	mov rdi, rax
	mov rax, sys_close
	syscall

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
	mov rsi, boem
	mov rdx, 0x1f
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
	mov r12, _rloop
	jmp _weol

; input: r12 (return address)
; output: none
; Writes end of line to the terminal
_weol:
	mov rax, sys_write
	mov rdi, 0x1
	mov rsi, eol
	mov rdx, 0x1
	syscall
	jmp r12

_quit:
	mov rax, sys_exit
	mov rdi, 0x0
	syscall

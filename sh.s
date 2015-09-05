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

	mov rax, 0x1
	mov rdi, 0x1
	mov rsi, msg
	mov rdx, 0x1b
	syscall

	jmp parse_path

rloop:
	mov rax, 0x1
	mov rdi, 0x1
	mov rsi, prompt
	mov rdx, 0xd
	syscall

	mov r8, -0x1
	mov r12, rloopr
	jmp bzero

rloopr:
	mov rax, 0x0
	mov rdi, 0x0
	mov rsi, r15
	mov rdx, 0xff
	syscall

	; check for quit
	cmp byte [r15], 0x0
	mov r12, quit
	je weol

	; call parse
	jmp parse

exec:
	; fork so we don't hurt ourselves
	mov rax, 0x39
	syscall
	mov dword [cpid], eax
	cmp dword [cpid], 0x0
	jne wait4_it

	; now that we know what to execute, do so
	mov rax, 0x3b
	mov rdi, r13
	mov rsi, r14
	mov rdx, 0x0
	syscall

	; and now kill the child process
	jmp quit

wait4_it:
	mov rdi, rax
	mov rax, 0x3d
	xor rsi, rsi ; null status pointer
	xor rdx, rdx
	xor rcx, rcx ; null rusage pointer
	syscall

	mov dword [cpid], -0x1
	jmp rloop

; input: none
; output: r9 (path elements), r10 (length)
; clobbered: r8, r12
; other: r15 (buffer)
parse_path:
	mov rax, 0x2
	mov rdi, env
	mov rsi, 0x0
	syscall
	cmp rax, 0x0
	jl quit

	mov r8, -0x1
	mov r12, parse_path2
	jmp bzero

parse_path2:
	mov rdi, rax
	mov rax, 0x0
	mov rsi, r9
	mov rdx, 0xff
	syscall
	cmp rax, 0x0
	jl quit
	mov r8, r9
	dec r8

pathfinder:
	inc r8
	xor rax, rax
	mov byte al, [r8]
	cmp al, 0x50
	jne pathfinder
	mov byte al, [r8+1]
	cmp al, 0x41
	jne pathfinder
	mov byte al, [r8+2]
	cmp al, 0x54
	jne pathfinder
	mov byte al, [r8+3]
	cmp al, 0x48
	jne pathfinder
	mov byte al, [r8+4]
	cmp al, 0x3d
	jne pathfinder
	mov byte al, [r8+5]
	cmp al, 0x22
	jne pathfinder
	cmp al, 0x0
	je quit
	add r8, 0x6
	mov r10, 0x1
	push 0x0
	push r8
	dec r8

pathender:
	inc r8
	mov al, [r8]
	cmp al, 0x3a
	je pathender1
	cmp al, 0x22
	jne pathender
	mov byte [r8], 0x0
	mov r9, rsp
	jmp rloop

pathender1:
	inc r10
	mov byte [r8], 0x0
	lea rcx, [r8+0x1]
	push rcx
	jmp pathender

;input: r8 (iterator), r15 (buffer), r12 (return address)
;output: none
bzero:
	inc r8
	mov byte [r8+r15], 0x0
	cmp r8, 0xff
	jle bzero
	jmp r12

;input: r15 (buffer)
;output: r13 (path), r14 (arguments)
;clobbered: r8, rax, rbx, rcx
parse: ; needs special commands: cd exit export echo eval pwd
	;also needs pipes (|, >, <)
	push 0x0
	xor r13, r13
	jmp strlen

; go through and sub/push
parse1:
	cmp byte [r8+r15], 0x20
	je subzp
	cmp byte [r8+r15], 0x0a
	je subz
	cmp byte [r8+r15], 0x2f
	je sabsf

parse1r:
	dec r8
	cmp r8, 0x0
	jl parse2
	jmp parse1

sabsf:
	mov r13, 0x1
	jmp parse1r

subz:
	mov byte [r8+r15], 0x0
	jmp parse1

subzp:
	mov byte [r8+r15], 0x0
	lea rax, [r8+r15+0x1]
	push rax
	jmp parse1

parse2:
	push rbx
	mov r14, rsp
	cmp r13, 0x0
	jg parse7
	mov r8, -0x1

parse3:
	inc r8
	cmp r8, r10
	je parse4
	mov r13, r15
	mov rcx, [r9+r8*8]
	push r8
	jmp concat

parse4: ; not found
	mov rax, 0x1
	mov rdi, 0x1
	mov rsi, nfe
	mov rdx, 0x1a
	syscall
	jmp rloop

parse5: ; test rbx
	pop r8

	mov rax, 0x2
	mov rdi, rbx
	xor rsi, rsi
	xor rdx, rdx
	syscall

	cmp rax, 0x0
	jl parse3
	
	mov rdi, rax
	mov rax, 0x3
	syscall

parse6: ; found it
	mov r13, rbx
	jmp exec

parse7: ; absolute path
	mov rax, 0x2
	mov rdi, r15
	xor rsi, rsi
	xor rdx, rdx
	syscall

	cmp rax, 0x0
	jl parse4

	mov rdi, rax
	mov rax, 0x3
	syscall

	mov r13, r15
	jmp exec
	

;input: r12 (return address), r15 (buffer)
;output: r8 (length)
strlen:
	xor r8, r8

strlen1:
	cmp byte [r8+r15], 0x0
	je parse1
	cmp byte [r8+r15], 0xa
	je parse1
	inc r8
	jmp strlen1

; input: rcx (a), r13 (b)
; output: rbx (string)
; clobbered: r8, r11
concat:
	mov r8, -0x1
	jmp jlen1

jlen1:
	inc r8
	cmp byte [r8+rcx], 0x0
	je jlen02
	cmp byte [r8+rcx], 0xa
	je jlen02
	jmp jlen1

jlen02:
	dec r8
	mov r11, -0x1

jlen2:
	inc r8
	inc r11
	cmp byte [r11+r13], 0x0
	je treg
	cmp byte [r11+r13], 0xa
	je treg
	jmp jlen2

treg:
	cmp r8, 0xff
	jg boe
	xchg r15, rbx
	mov r8, -0x1
	mov r12, rsinc
	jmp bzero

rsinc:
	xchg r15, rbx
	mov r8, -0x1
	mov r11, -0x1

join1:
	inc r8
	cmp byte [r8+rcx], 0x0
	je join02
	cmp byte [r8+rcx], 0xa
	je join02
	mov al, [r8+rcx]
	mov [r8+rbx], al
	jmp join1

join02:
	mov byte [r8+rbx], 0x2f
join2:
	inc r8
	inc r11
	cmp byte [r11+r13], 0x0
	je parse5
	cmp byte [r11+r13], 0xa
	je parse5
	mov al, [r11+r13]
	mov [r8+rbx], al
	jmp join2

boe:
	mov rax, 0x1
	mov rdi, 0x1
	mov rsi, boem
	mov rdx, 0x1f
	jmp quit

; interrupt signal handler
sigint:
	cmp dword [cpid], 0x0
	jl sigint_nc

sigint_c: ; kill the child
	mov rax, 0x3e
	mov rdi, [cpid]
	mov rsi, 0x2
	syscall

sigint_nc:
	mov r12, rloop
	jmp weol

; input: r12 (return address)
; output: none
weol:
	mov rax, 0x1
	mov rdi, 0x1
	mov rsi, eol
	mov rdx, 0x1
	syscall
	jmp r12

quit:
	mov rax, 0x3c
	mov rdi, 0x0
	syscall

section .data
	sigs: dd 0x2
	cpid: dd 0x0
	eol: db 0xa
	msg: db "Welcome to deadbeef shell", 0x21, 0x0a
	prompt: db "[0xdeadbeef]", 0x20
	nfe: db "Error: program not found", 0x2e, 0x0a
	env: db "/etc/environment", 0x0
	boem: db "Error: input overflows buffer", 0x2e, 0x0a

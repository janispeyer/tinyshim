; Make it tiny?
; https://www.muppetlabs.com/~breadbox/software/tiny/teensy.html
SYS_EXIT     equ  1
SYS_WRITE    equ  4
SYS_EXECVE   equ 11
SYS_READLINK equ 85

FD_STDOUT    equ  1

PATH_MAX     equ 4096


section .text
global  _start

_start:
    ; Read absolute path for this executable.
    ; readlink('/proc/self/exe', self_path, self_path_len);
    mov edx, self_path_len ; int bufsiz
    mov ecx, self_path     ; char* buf
    mov ebx, abs_path      ; char* path
    mov eax, SYS_READLINK
    int 0x80

    ; length < 0 => error
    cmp eax, 0
    jl error

    ; length == self_path_len => Path might have been truncated.
    ; If we want to support longer paths, a future workaround might
    ; be to allocate more bytes and try again.
    cmp eax, self_path_len
    je error

    ; Find last '/'.
    ; There has to be at least one '/', because it is an absolute path.
    mov edx, eax
find_slash:
    dec edx
    cmp byte [self_path+edx], '/'
    jne find_slash

    ; len(ld_path) > PATH_MAX => error
    ; ecx = len(ld_path)
    lea ecx, [edx+ld_file_len]
    cmp ecx, PATH_MAX
    jg error

    ; len(exe_path) > PATH_MAX => error
    ; ecx = len(exe_path)
    lea ecx, [eax+dynbin_path_len+1]
    cmp ecx, PATH_MAX
    jg error
    ; Add trailing '\0' to create c-string.
    dec ecx
    mov byte [exe_path+ecx], 0

    ; Create path to our ld (ld_path).
    ; 1. copy dirname(self_path) to ld_path
    mov ecx, edx         ; length
    lea edi, [ld_path]   ; destination address
    lea esi, [self_path] ; source address
    rep movsb
    ; 2. copy ld_file to ld_path
    mov ecx, ld_file_len   ; length
    lea edi, [ld_path+edx] ; destination address
    lea esi, [ld_file] ; source address
    rep movsb

    ; Create path to dynamic executable (exe_path).
    ; 1. copy dirname(self_path) to exe_path
    mov ecx, edx         ; length
    lea edi, [exe_path]  ; destination address
    lea esi, [self_path] ; source address
    rep movsb
    ; 2. copy '/../dynbin' to exe_path
    mov ecx, dynbin_path_len ; length
    lea edi, [exe_path+edx]  ; destination address
    lea esi, [dynbin_path]   ; source address
    rep movsb
    ; 3. copy basename(self_path) to exe_path
    mov ecx, eax
    sub ecx, edx ; length = len(self_path) - len(dirname(self_path))
    lea edi, [exe_path+edx+dynbin_path_len] ; destination address
    lea esi, [self_path+edx]                ; source address
    rep movsb

    mov ecx, [esp]   ; argc
    mov edx, [esp+4] ; &argv[0]

    ; argc + 4 > ld_argv_len => error
    ; We add 3 arguments to argv and need space for the trailing NULL.
    lea eax, [(ecx+4)*4]
    cmp eax, ld_argv_len
    jg error

    ; Construct argv with which we call ld.
    ; ld_argv = [&argv[0], "--library-path", "$ORIGIN/../lib", exe_path, ..argv[1..]]
    mov [ld_argv], edx
    mov dword [ld_argv+1*4], ld_arg_1
    mov dword [ld_argv+2*4], ld_arg_2
    mov dword [ld_argv+3*4], exe_path

    ; Copy argv[1..] into ld_argv[4..].
    dec ecx                ; length = argc-1
    lea edi, [ld_argv+4*4] ; destination address = &ld_argv[4]
    lea esi, [esp+2*4]     ; source address = &argv[1]
    rep movsd ; <-- movs dword!

    ; TODO: Remove test print
    ; write("smallshim works!\n")
    mov edx, len
    mov ecx, msg
    mov ebx, FD_STDOUT
    mov eax, SYS_WRITE
    int 0x80

    mov ecx, [esp] ; argc

    ; execve(ld_path, ld_argv, envp)
    lea edx, [esp + ecx*4 + 2*4] ; char** envp
    mov ecx, ld_argv             ; char** argv
    mov ebx, ld_path             ; char*  filename
    mov eax, SYS_EXECVE
    int 0x80

    ; No exit here, because we call execve.
    ; If execve fails, we fall through to the error label bellow.

error:
    ; write("ldshim failed\n")
    mov edx, error_msg_len
    mov ecx, error_msg
    mov ebx, FD_STDOUT
    mov eax, SYS_WRITE
    int 0x80

    ; exit(1)
    mov bl,1
    xor eax, eax
    inc eax ; <-- mov eax, SYS_EXIT
    int 0x80

;section     .data
; Putting strings in the same section makes the binary smaller.
; https://stackoverflow.com/questions/69862933/decrease-nasm-asembly-executable-size

ld_file      db  '/../lib/ld-linux-x86-64.so.2',0
ld_file_len  equ $ - ld_file

dynbin_path      db  '/../dynbin'
dynbin_path_len  equ $ - dynbin_path

abs_path db '/proc/self/exe',0
ld_arg_1 db '--library-path',0
ld_arg_2 db '$ORIGIN/../lib',0

msg     db  'smallshim works!',0xa
len     equ $ - msg

error_msg      db 'ldshim failed',0xa
error_msg_len  equ $ - error_msg


; Can we define this to not be part of the binary?
; https://www.nasm.us/doc/nasmdoc8.html#section-8.9.2
section .data

self_path      times PATH_MAX db 0
self_path_len  equ $ - self_path

exe_path       times PATH_MAX db 0
exe_path_len   equ $ - exe_path

ld_path        times PATH_MAX db 0
ld_path_len    equ $ - exe_path

section .pointers write pointer

; TODO: maybe we should dynamicylly allocate ld_argv
ld_argv        times 32000 dd 0
ld_argv_len    equ $ - ld_argv

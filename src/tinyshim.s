; Using dark magic to create tiny binary:
; https://www.muppetlabs.com/~breadbox/software/tiny/teensy.html

; ----- v ELF Header v -----
BITS 32
            org 0x08048000

ehdr:                                                 ; Elf32_Ehdr
            db      0x7F, "ELF", 1, 1, 1, 0         ;   e_ident
    times 8 db      0
            dw      2                               ;   e_type
            dw      3                               ;   e_machine
            dd      1                               ;   e_version
            dd      _start                          ;   e_entry
            dd      phdr - $$                       ;   e_phoff
            dd      0                               ;   e_shoff
            dd      0                               ;   e_flags
            dw      ehdrsize                        ;   e_ehsize
            dw      phdrsize                        ;   e_phentsize
            dw      1                               ;   e_phnum
            dw      0                               ;   e_shentsize
            dw      0                               ;   e_shnum
            dw      0                               ;   e_shstrndx

ehdrsize    equ     $ - ehdr

phdr:                                                 ; Elf32_Phdr
            dd      1                               ;   p_type
            dd      0                               ;   p_offset
            dd      $$                              ;   p_vaddr
            dd      $$                              ;   p_paddr
            dd      filesize                        ;   p_filesz
            dd      filesize                        ;   p_memsz
            dd      5                               ;   p_flags
            dd      0x1000                          ;   p_align

phdrsize    equ     $ - phdr
; ----- ^ ELF Header ^ -----


SYS_EXIT     equ  1
SYS_WRITE    equ  4
SYS_EXECVE   equ 11
SYS_READLINK equ 85

FD_STDOUT    equ  1

PATH_MAX     equ 4096


section .text
global  _start

; This program runs `ld` with the added command line parameter `--library-path`.
; Expectations:
; * Target ld executable is located at "<SHIM_PATH>/../lib/ld-linux-x86-64.so.2"
; * Target executable (that should be run by ld) is located at "<SHIM_PATH>/../dynbin/<TARGET_FILE>"
; <SHIM_PATH> is the path to the directory in which this executable (shim executable) is located.
; <TARGET_FILE> is the filename of this executable (and the filename of the target executable).
;
; The expected directory layout is:
; |-- lib
; |    `-- ld-linux-x86-64.so.2
; |-- dynbin
; |    `-- <TARGET_FILE>
; `-- bin
;      `-- <TARGET_FILE>
_start:
    ; Visual explanation how the following code does this.
    ; Stack right now:
    ; +------+------+------+---
    ; | envp | argv | argc |
    ; +------+------+------+---
    ;                      ^ esp
    ;
    ; With some more detail:
    ; +----------+------------+-----+----------+----------+------------+-----+----------+------+---
    ; | &envp[M] | &envp[M-1] | ... | &envp[0] | &argv[N] | &argv[N-1] | ... | &argv[0] | argc |
    ; +----------+------------+-----+----------+----------+------------+-----+----------+------+---
    ;                                                                                          ^ esp
    ;
    ; Stack just before we call `execve(ld_path, ld_argv, envp)`:
    ; +------+------+------+---------+----------+---------+---
    ; | envp | argv | argc | ld_argv | exe_path | ld_path |
    ; +------+------+------+---------+----------+---------+---
    ;                      ^ esp                ^ ebp     ^ ebx
    ;
    ; ld_argv:
    ;     Arguments we pass to ld.
    ;     ld_argv = [&argv[0], "--library-path", "$ORIGIN/../lib", &exe_path, ..argv[1..], NULL]
    ; exe_path:
    ;     Path to target executable.
    ;     We pass a pointer to exe_path to ld (see ld_argv[3]).
    ;     exe_path = "<SHIM_PATH>/../dynbin/<TARGET_FILE>"
    ; ld_path:
    ;     Path to ld.
    ;     ld_path =  "<SHIM_PATH>/../lib/ld-linux-x86-64.so.2"

    ; ecx = argc
    mov ecx, [esp]

    ; ebp = &ld_argv[0]
    mov ebp, esp
    lea eax, [(ecx+4)*4]
    sub ebp, eax

    ; Construct ld_argv with which we will call ld.
    ; ld_argv = [&argv[0], "--library-path", "$ORIGIN/../lib", &exe_path, ..argv[1..], NULL]
    mov eax, [esp+4] ; &argv[0]
    mov dword [ebp + 0*4], eax
    mov dword [ebp + 1*4], ld_arg_1
    mov dword [ebp + 2*4], ld_arg_2
    lea eax, [ebp - (PATH_MAX+dynbin_path_len+1)]
    mov dword [ebp + 3*4], eax ; ld_argv[3] = &exe_path
    mov dword [esp - 1*4], 0   ; ld_argv[ld_argc] = NULL

    ; Copy argv[1..] into ld_argv[4..].
    dec ecx              ; length = argc-1
    lea edi, [ebp + 4*4] ; destination address = &ld_argv[4]
    lea esi, [esp + 2*4] ; source address = &argv[1]
    rep movsd ; <-- movs dword!

    ; ebp = &exe_path
    mov ebp, eax

    ; Read absolute path of this executable.
    ; readlink('/proc/self/exe', &exe_path, PATH_MAX);
    mov edx, PATH_MAX ; int   bufsiz
    mov ecx, ebp      ; char* buf
    mov ebx, abs_path ; char* path
    mov eax, SYS_READLINK
    int 0x80

    ; length < 0 => error
    cmp eax, 0
    jl error

    ; length == PATH_MAX => Path might have been truncated.
    ; If we want to support longer paths, a future workaround might
    ; be to allocate more bytes and try again.
    cmp eax, PATH_MAX
    je error

    ; Find last '/'.
    ; There has to be at least one '/', because it is an absolute path.
    mov edx, eax
find_slash:
    dec edx
    cmp byte [ebp+edx], '/'
    jne find_slash

    ; ebx = &ld_path
    lea ebx, [ebp+eax+dynbin_path_len+1]

    ; Create path to our ld (ld_path).
    ; 1. Copy dirname(self_path) to ld_path.
    mov ecx, edx                         ; length
    lea edi, [ebx] ; destination address
    lea esi, [ebp]                       ; source address
    rep movsb
    ; 2. Copy ld_file to ld_path.
    mov ecx, ld_file_len ; length
    ; destination address (edi) is already at the correct address, after the first copy.
    lea esi, [ld_file]   ; source address
    rep movsb
    ; ld_file contains '\0' in its constant.

    ; Create path to the target executable (exe_path).
    ; We destroy self_path in the process to build exe_path in-place.
    ; 1. Copy basename(self_path) to exe_path.
    std ; set direction flag (copy backwards)
        ; We need to copy backwards, because source and destination might overlap.
    mov ecx, eax
    sub ecx, edx         ; length = len(self_path) - len(dirname(self_path))
    lea edi, [ebx-2]     ; destination address
    lea esi, [ebp+eax-1] ; source address
    rep movsb
    cld ; clear direction flag
    ; 2. Add '\0' at the end of exe_path to create a c-string.
    mov byte [ebx-1], 0
    ; 3. Copy '/../dynbin' to exe_path.
    mov ecx, dynbin_path_len ; length
    lea edi, [ebp+edx]       ; destination address
    lea esi, [dynbin_path]   ; source address
    rep movsb

    ; edi = argc
    mov edi, [esp]

    ; execve(ld_path, ld_argv, envp)
    lea edx, [esp + edi*4 + 2*4]                  ; char** envp
    lea ecx, [ebp + (PATH_MAX+dynbin_path_len+1)] ; char** argv
    ; lea ebx, [ebx]                              ; char*  filename
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

; Putting strings in the same section makes the binary smaller.
; section     .data

ld_file      db  '/../lib/ld-linux-x86-64.so.2',0
ld_file_len  equ $ - ld_file

dynbin_path      db  '/../dynbin'
dynbin_path_len  equ $ - dynbin_path

abs_path db '/proc/self/exe',0
ld_arg_1 db '--library-path',0
ld_arg_2 db '$ORIGIN/../lib',0

error_msg      db 'ldshim failed',0xa
error_msg_len  equ $ - error_msg

filesize      equ     $ - $$

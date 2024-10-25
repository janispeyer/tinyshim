build/smallshim: build/smallshim.o
	ld -s -m elf_i386 build/smallshim.o -o build/smallshim

build/smallshim.o: src/smallshim.s
	mkdir -p build
	nasm -f elf src/smallshim.s -o build/smallshim.o

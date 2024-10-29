all: build/smallshim build/tinyshim

build/smallshim: build/smallshim.o
	ld -s -m elf_i386 build/smallshim.o -o build/smallshim

build/smallshim.o: src/smallshim.s
	mkdir -p build
	nasm -f elf --reproducible src/smallshim.s -o build/smallshim.o

build/tinyshim: src/tinyshim.s
	mkdir -p build
	nasm -f bin --reproducible src/tinyshim.s -o build/tinyshim
	chmod +x build/tinyshim

clean:
	rm -R build

test: all
	cd testzapp && $(MAKE)
	cp build/tinyshim testzapp/build/pack/bin/test
	./testzapp/build/pack/bin/test $(ARGS)

strace: all
	cd testzapp && $(MAKE)
	cp build/tinyshim testzapp/build/pack/bin/test
	strace ./testzapp/build/pack/bin/test $(ARGS)
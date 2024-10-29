LDFLAGS=-Wl,-rpath=XORIGIN/../lib

zapp: src/test.c
	rm -Rf build

	bash -c "mkdir -pv build/pack/{bin,dynbin,lib}"
	cp /lib/x86_64-linux-gnu/libc.so.6 build/pack/lib
# To test if dynamic linking works:
# Try to make the executable think the following library is libc and watch it fail.
# cp /lib64/ld-linux-x86-64.so.2 build/pack/lib/libc.so.6
	cp /lib64/ld-linux-x86-64.so.2 build/pack/lib

	export SOURCE_DATE_EPOCH=1262304000
	gcc $(LDFLAGS) src/test.c -o build/pack/dynbin/test
	sed -i '0,/XORIGIN/{s/XORIGIN/$$ORIGIN/}' build/pack/dynbin/test

#include <stdio.h>

int main(int argc, char** argv) {
	printf("c binary\n");

	for (int i = 0; i < argc; ++i) {
		printf("%d: %s\n", i, argv[i]);
	}

	if (argv[argc] == NULL) {
		printf("good argv\n");
		return 0;
	} else {
		printf("bad argv\n");
		return 1;
	}
}

CC = clang
CFLAGS = -std=c2x -D_GNU_SOURCE -Weverything -Wno-pre-c2x-compat -Wno-declaration-after-statement -Wno-unsafe-buffer-usage
PROGS = due watch

.PHONY: all clean

all: $(PROGS)

due: due.c
	$(CC) $(CFLAGS) -o $@ $^
watch: watch.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm $(PROGS)

CC = clang
CFLAGS = -std=c2x -D_GNU_SOURCE -Weverything -Wno-pre-c2x-compat -Wno-declaration-after-statement -Wno-unsafe-buffer-usage
PROGS = run-at watcher

.PHONY: all clean

all: $(PROGS)

run-at: run-at.c
	$(CC) $(CFLAGS) -o $@ $^
watcher: watcher.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm $(PROGS)

CC = clang
CFLAGS = -std=c2x -D_GNU_SOURCE -Weverything -Wno-pre-c2x-compat -Wno-declaration-after-statement -Wno-unsafe-buffer-usage

.PHONY: all clean

all: watcher

watcher: watcher.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm watcher

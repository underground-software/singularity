CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-c++98-compat -Wno-gnu-designator -Wno-gnu-case-range -Wno-initializer-overrides -Wno-declaration-after-statement -Wno-four-char-constants -Wno-pre-c2x-compat -D_GNU_SOURCE
#CFLAGS += -DDEBUG -Og -g

.PHONY: all clean

all: pop3

pop3: pop3.c
	$(CC) $(CFLAGS) -o $@ $^
clean:
	-rm pop3

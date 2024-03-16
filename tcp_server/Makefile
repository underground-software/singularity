CC = clang
CFLAGS = -std=c2x -Weverything -Wno-declaration-after-statement -Wno-c++98-compat -Wno-padded \
	-Wno-unsafe-buffer-usage -Wno-disabled-macro-expansion -Wno-pre-c2x-compat -D_GNU_SOURCE

ifdef DEBUG
	CFLAGS += -DDEBUG -Og -g
endif

.PHONY: all clean

all: tcp_server

tcp_server: tcp_server.c
	$(CC) $(CFLAGS) -o $@ $^
clean:
	-rm tcp_server

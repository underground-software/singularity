CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-declaration-after-statement -Wno-pre-c2x-compat -D_GNU_SOURCE

ifdef DEBUG
	CFLAGS += -DDEBUG -Og -g
endif

.PHONY: all clean

all: init_journal restrict_access append_journal

init_journal: init_journal.c email.h
	$(CC) $(CFLAGS) -o $@ $<

restrict_access: restrict_access.c
	$(CC) $(CFLAGS) -o $@ $<

append_journal: append_journal.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	-rm init_journal restrict_access append_journal

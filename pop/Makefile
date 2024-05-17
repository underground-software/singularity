CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-c++98-compat -Wno-gnu-designator -Wno-gnu-case-range -Wno-initializer-overrides \
	-Wno-declaration-after-statement -Wno-four-char-constants -Wno-pre-c2x-compat -Wno-disabled-macro-expansion -D_GNU_SOURCE

ifdef DEBUG
	CFLAGS += -DDEBUG -Og -g
endif

.PHONY: all clean

all: pop3 init_journal

pop3: pop3.c types.h
	$(CC) $(CFLAGS) -o $@ $<

init_journal: init_journal.c types.h
	$(CC) $(CFLAGS) -o $@ $<

clean:
	-rm pop3 init_journal

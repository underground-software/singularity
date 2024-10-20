CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-c++98-compat -Wno-gnu-designator -Wno-gnu-case-range -Wno-initializer-overrides \
	-Wno-declaration-after-statement -Wno-four-char-constants -Wno-pre-c2x-compat -Wno-disabled-macro-expansion -Wno-switch -Wno-switch-enum -D_GNU_SOURCE

# Add flags for coverage support
ADDITIONAL_CFLAGS =
ifeq ($(COVERAGE), 1)
	ADDITIONAL_CFLAGS = -fprofile-instr-generate -fcoverage-mapping -mllvm -runtime-counter-relocation
endif

ifdef DEBUG
	CFLAGS += -DDEBUG -Og -g
endif

.PHONY: all clean

all: pop3 pop_wrapper

pop3: pop3.c journal/email.h
	$(CC) $(CFLAGS) $(ADDITIONAL_CFLAGS) -o $@ $<

pop_wrapper: pop_wrapper.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm pop3
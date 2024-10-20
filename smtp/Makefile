CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-c++98-compat -Wno-gnu-designator \
	-Wno-initializer-overrides -Wno-declaration-after-statement -Wno-four-char-constants \
	-Wno-pre-c2x-compat -Wno-disabled-macro-expansion -D_GNU_SOURCE -DHOSTNAME='"$(SRVNAME)"'

# Add flags for coverage support
ADDITIONAL_CFLAGS =
ifeq ($(COVERAGE), 1)
	ADDITIONAL_CFLAGS = -fprofile-instr-generate -fcoverage-mapping -mllvm -runtime-counter-relocation
endif

ifdef DEBUG
	CFLAGS += -DDEBUG -Og -g
endif

.PHONY: all clean
all: smtp smtp_wrapper

smtp: smtp.c
ifndef SRVNAME
	$(error "you must pass SRVNAME=<FQDN>")
endif
	$(CC) $(CFLAGS) $(ADDITIONAL_CFLAGS) -o $@ $^

smtp_wrapper: smtp_wrapper.c
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm smtp


CC = clang
CFLAGS = -std=c2x -Weverything -Wno-unsafe-buffer-usage -Wno-c++98-compat -Wno-gnu-designator \
	-Wno-initializer-overrides -Wno-declaration-after-statement -Wno-four-char-constants \
	-Wno-pre-c2x-compat -Wno-disabled-macro-expansion -D_GNU_SOURCE -DHOSTNAME='"$(SRVNAME)"'
#CFLAGS += -DDEBUG -Og -g
.PHONY: all clean
all: smtp

smtp: smtp.c
ifndef SRVNAME
	$(error "you must pass SRVNAME=<FQDN>")
endif
	$(CC) $(CFLAGS) -o $@ $^

clean:
	-rm smtp



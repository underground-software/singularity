#include <ctype.h>
#include <err.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sendfile.h>
#include <sys/xattr.h>
#include <time.h>
#include <uchar.h>
#include <unistd.h>

#include "types.h"

#define SEND(STR) send(STR "\r\n", sizeof(STR "\r\n") - 1)
static void send(const char *msg, size_t size)
{
	size_t off = 0;
	do
	{
		ssize_t ret = write(STDOUT_FILENO, msg + off, size - off);
		//non recoverable, as the proper way to close an SMTP connection involves sending a
		//final 421 response, but if we failed to write here, we won't be able to do that...
		if(ret <= 0)
			exit(2);
		//safe to cast to size_t because we know that ret > 0
		off += (size_t)ret;
	}
	while(off < size);
}

static uint32_t get_command(void)
{
	uint32_t word = 0;
	size_t i;
	for(i = 0; i < 4; ++i)
	{
		int c = getchar();
		if(c == EOF)
			errx(0, "got eof while reading command");
		word <<= 8;
		switch(c)
		{
		case 'A' ... 'Z':
		case 'a' ... 'z':
			word |= ((unsigned char)c) | 0x20;
			break;
		default:
			warnx("saw character %d during get_command", c);
			[[fallthrough]];
		case ' ':
		case '\r':
		case '\n':
			ungetc(c, stdin);
			word |= ' ';
			break;
		}
	}
	int c = getchar();
	if(c != ' ' && c != '\r' && c != '\n')
		return '    ';
	ungetc(c, stdin);
	return word;
}

//consumes \r or \r\n or \n.
//prints a warning if just \r or just \n is found
//precondition that the next char to read is \r or \n
static void eat_newline(void)
{
	int c = getchar();
	if(c == '\n')
	{
		warnx("unpaired \\n in input");
		return;
	}
	if(c != '\r')
		errx(1, "precondition to eat_newline violated");
	c = getchar();
	if(c != '\n')
	{
		ungetc(c, stdin);
		warnx("unpaired \\r in input");
	}
}

#define LINE_LIMIT 1023
#define STRINGIZE_H(X) #X
#define STRINGIZE(X) STRINGIZE_H(X)

static void eat_rest(void)
{
	if(EOF == scanf("%*[^\r\n]"))
		errx(1, "got eof during eat_rest");
	eat_newline();
}

static size_t read_line_chunk(char buf[static LINE_LIMIT + 1])
{
	size_t size;
	int noc = scanf("%" STRINGIZE(LINE_LIMIT) "[^\r\n]%zn", buf, &size);
	if(noc == EOF)
		errx(1, "got eof during read_line");
	if(noc < 1)
		size = 0;
	if(size < LINE_LIMIT)
		eat_newline();
	return size;
}

static bool read_line(char buf[static LINE_LIMIT + 1], size_t *outsize)
{
	if((*outsize = read_line_chunk(buf)) < LINE_LIMIT)
		return true;
	*outsize = -(size_t)1;
	eat_rest();
	return false;
}

static bool check_credentials(size_t u_size, const char *username, size_t p_size, const char *password)
{
#ifdef CHECK_CREDS
	if(u_size != 4)
		return false;
	if(memcmp(username, "test", 4))
		return false;
	if(p_size != 4)
		return false;
	if(memcmp(password, "asdf", 4))
		return false;
#else
	(void)u_size;
	(void)p_size;
	(void)username;
	(void)password;
#endif
	return true;
}

static struct email *maildrop;
static size_t num_emails;

static void load_emails(int journal_fd)
{
	off_t limit;
	ssize_t ret = fgetxattr(journal_fd, "user.data_end", &limit, sizeof limit);
	if(sizeof limit != ret)
		err(1, "unable to read journal size from journal file");
	if(0 > limit)
		errx(1, "invalid journal size: negative");
	size_t maildrop_size = (size_t)limit;
	if(maildrop_size % sizeof(struct email))
		errx(1, "invalid journal size: not divisible by size of email struct");
	num_emails = maildrop_size / sizeof(struct email);
	//mmap will not accept a size of zero, so we need to check, but if size is zero, the
	//default value of NULL for maildrop is perfectly adequate since no code should access it.
	if(num_emails)
		maildrop = mmap(NULL, maildrop_size, PROT_READ, MAP_PRIVATE, journal_fd, 0);
	if(MAP_FAILED == maildrop)
		err(1, "unable to map journal file");
}

static bool pending_deletes(void)
{
	for(size_t i = 0; i < num_emails; ++i)
		if(!maildrop[i].active)
			return true;
	return false;
}

enum state
{
	START,
	USER,
	LOGIN,
	QUIT,
};

#define REPLY(STR) { SEND(STR); break; }

int main(int argc, char **argv)
{
	char line_buff[LINE_LIMIT + 1];
	size_t line_size = 0;
	char username[LINE_LIMIT + 1];
	size_t username_size = 0;
	int flags = fcntl(STDOUT_FILENO, F_GETFL);
	if(0 > flags)
		err(1, "unable to get flags from stdout");
	flags &= ~O_APPEND;
	if(0 > fcntl(STDOUT_FILENO, F_SETFL, flags))
		err(1, "unable to set flags for stdout");

	if(argc != 3)
		errx(1, "Usage: %s <mail directory> <journal file>", argv[0]);
	int journal_fd = open(argv[2], O_RDONLY);
	if(0 > journal_fd)
		err(1, "Unable to open journal file \"%s\"", argv[1]);
	if(chdir(argv[1]))
		errx(1, "Unable to change directory to mail folder \"%s\"", argv[1]);
	load_emails(journal_fd);
	SEND("+OK POP3 server ready");
	for(enum state state = START; state != QUIT;)
	{
		uint32_t command = get_command();
		switch(command)
		{
		case 'quit':
			eat_rest();
			state = QUIT;
			if(pending_deletes())
				REPLY("-ERR unable to delete some messages")
			else
				REPLY("+OK bye")
		case 'capa':
			eat_rest();
			REPLY("+OK capabilities list follows\r\n"
			"USER\r\n"
			"UIDL\r\n"
			"TOP\r\n"
			"EXPIRE NEVER\r\n"
			"IMPLEMENTATION KDLP\r\n"
			".")
		case 'noop':
			eat_rest();
			REPLY("+OK did nothing")
		case 'user':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != START)
				REPLY("-ERR command out of sequence")
			{
				char *ptr = line_buff;
				while(ptr < line_buff + line_size && isspace(*ptr))
					++ptr;
				if(ptr == line_buff)
					REPLY("-ERR unrecognized command")
				if(ptr == line_buff + line_size)
					REPLY("-ERR parameter required for user command")
				username_size = (size_t)(line_buff + line_size - ptr);
				memcpy(username, ptr, username_size);
			}
			state = USER;
			REPLY("+OK got username")
		case 'pass':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != USER)
				REPLY("-ERR command out of sequence")
			if(line_buff[0] != ' ')
				REPLY("-ERR unrecognized command")
			if(!check_credentials(username_size, username, line_size - 1, line_buff + 1))
				REPLY("-ERR unauthorized")
			state = LOGIN;
			REPLY("+OK got username")
		case 'rset':
			eat_rest();
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			for(size_t i = 0; i < num_emails; ++i)
				maildrop[i].active = true;
			REPLY("+OK reset complete")
		case 'stat':
			eat_rest();
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			size_t active_emails = 0;
			off_t total_size = 0;
			for(size_t i = 0; i < num_emails; ++i)
				if(maildrop[i].active)
				{
					active_emails++;
					total_size += maildrop[i].size;
				}
			{
				char stat_message[64];
				size_t message_len = (size_t)snprintf(stat_message, sizeof stat_message, "+OK %zu %"SCNiMAX"\r\n", active_emails, (intmax_t)total_size);
				if(sizeof stat_message <= message_len)
				{
					warnx("stat buffer was not big enough");
					REPLY("-ERR internal server error")
				}
				send(stat_message, message_len);
			}
			break;
		case 'list':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			if(line_size == 0)
			{
				SEND("+OK maildrop follows");
				for(size_t i = 0; i < num_emails; ++i)
				{
					if(!maildrop[i].active)
						continue;
					char stat_message[64];
					size_t message_len = (size_t)snprintf(stat_message, sizeof stat_message, "%zu %"SCNiMAX"\r\n", i + 1, (intmax_t)maildrop[i].size);
					if(sizeof stat_message <= message_len)
					{
						warnx("stat buffer was not big enough: %d", __LINE__);
						continue;
					}
					send(stat_message, message_len);
				}
				SEND(".");
			}
			else
			{
				char *endptr;
				uintmax_t arg = strtoumax(line_buff, &endptr, 10);
				if(endptr != line_buff + line_size)
					REPLY("-ERR invalid index to stat command")
				if(arg == 0 || arg > (uintmax_t)num_emails)
					REPLY("-ERR index out of bounds for stat command")
				size_t index = (size_t)arg - 1;
				if(!maildrop[index].active)
					REPLY("-ERR Invalid index")
				char stat_message[64];
				size_t message_len = (size_t)snprintf(stat_message, sizeof stat_message, "+OK %zu %"SCNiMAX"\r\n", index + 1, (intmax_t)maildrop[index].size);
				if(sizeof stat_message <= message_len)
				{
					warnx("stat buffer was not big enough: %d", __LINE__);
					REPLY("-ERR internal server error")
				}
				send(stat_message, message_len);
			}
			break;
		case 'uidl':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			if(line_size == 0)
			{
				SEND("+OK ids follow");
				for(size_t i = 0; i < num_emails; ++i)
				{
					if(!maildrop[i].active)
						continue;
					char uidl_message[64];
					size_t message_len = (size_t)snprintf(uidl_message, sizeof uidl_message, "%zu %s\r\n", i + 1, maildrop[i].name);
					if(sizeof uidl_message <= message_len)
					{
						warnx("stat buffer was not big enough: %d", __LINE__);
						continue;
					}
					send(uidl_message, message_len);
				}
				SEND(".");
			}
			else
			{
				char *endptr;
				uintmax_t arg = strtoumax(line_buff, &endptr, 10);
				if(endptr != line_buff + line_size)
					REPLY("-ERR invalid index to uidl command")
				if(arg == 0 || arg > (uintmax_t)num_emails)
					REPLY("-ERR index out of bounds for uidl command")
				size_t index = (size_t)arg - 1;
				if(!maildrop[index].active)
					REPLY("-ERR Invalid index")
				char uidl_message[64];
				size_t message_len = (size_t)snprintf(uidl_message, sizeof uidl_message, "+OK %zu %s\r\n", index + 1, maildrop[index].name);
				if(sizeof uidl_message <= message_len)
				{
					warnx("stat buffer was not big enough: %d", __LINE__);
					REPLY("-ERR internal server error")
				}
				send(uidl_message, message_len);
			}
			break;
		case 'dele':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			if(line_size == 0)
				REPLY("-ERR arg required for dele command")
			{
				char *endptr;
				uintmax_t arg = strtoumax(line_buff, &endptr, 10);
				if(endptr != line_buff + line_size)
					REPLY("-ERR invalid index to dele command")
				if(arg == 0 || arg > (uintmax_t)num_emails)
					REPLY("-ERR index out of bounds for dele command")
				size_t index = (size_t)arg - 1;
				if(!maildrop[index].active)
					REPLY("-ERR Invalid index")
				maildrop[index].active = false;
			}
			REPLY("+OK marked for deletion")
		case 'retr':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			if(line_size == 0)
				REPLY("-ERR arg required for retr command")
			{
				char *endptr;
				uintmax_t arg = strtoumax(line_buff, &endptr, 10);
				if(endptr != line_buff + line_size)
					REPLY("-ERR invalid index to retr command")
				if(arg == 0 || arg > (uintmax_t)num_emails)
					REPLY("-ERR index out of bounds for retr command")
				size_t index = (size_t)arg - 1;
				if(!maildrop[index].active)
					REPLY("-ERR Invalid index")
				int fd = open(maildrop[index].name, O_RDONLY);
				if(0 > fd)
					REPLY("-ERR internal server error")
				SEND("+OK message follows");
				off_t offset = 0;
				do
				{
					ssize_t ret = sendfile(STDOUT_FILENO, fd, &offset, (size_t)(maildrop[index].size - offset));
					if(0 > ret)
						err(1, "unable to sendfile");
				}
				while(offset < maildrop[index].size);
			}
			break;
		case 'top ':
			if(!read_line(line_buff, &line_size))
				REPLY("-ERR Parameters too long")
			if(state != LOGIN)
				REPLY("-ERR unauthenticated")
			if(line_size == 0)
				REPLY("-ERR arg required for dele command")
			{
				char *endptr;
				uintmax_t arg = strtoumax(line_buff, &endptr, 10);
				if(endptr == line_buff || endptr == line_buff + line_size)
					REPLY("-ERR missing args to top command")
				if(endptr[0] != ' ' || endptr[1] != '0' || endptr[2] != '\0') //we only support top <idx> 0 for now
					REPLY("-ERR top arg 2 of nonzero value unsupported")
				if(arg == 0 || arg > (uintmax_t)num_emails)
					REPLY("-ERR index out of bounds for stat command")
				size_t index = (size_t)arg - 1;
				if(!maildrop[index].active)
					REPLY("-ERR Invalid index")
				int fd = open(maildrop[index].name, O_RDONLY);
				if(0 > fd)
					REPLY("-ERR internal server error")
				SEND("+OK message follows");
				off_t offset = 0;
				do
				{
					ssize_t ret = sendfile(STDOUT_FILENO, fd, &offset, (size_t)(maildrop[index].top_limit - offset));
					if(0 > ret)
						err(1, "unable to sendfile");
				}
				while(offset < maildrop[index].top_limit);
			}
			REPLY(".")
		default:
			eat_rest();
			REPLY("-ERR command not recognized")
		}
	}
}

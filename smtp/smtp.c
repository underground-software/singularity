#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <time.h>
#include <uchar.h>
#include <unistd.h>

#ifndef HOSTNAME
#error "you must #define HOSTNAME"
#define HOSTNAME
#endif

#define UPPERCASE_LETTERS(MACRO) \
	MACRO('A') \
	MACRO('B') \
	MACRO('C') \
	MACRO('D') \
	MACRO('E') \
	MACRO('F') \
	MACRO('G') \
	MACRO('H') \
	MACRO('I') \
	MACRO('J') \
	MACRO('K') \
	MACRO('L') \
	MACRO('M') \
	MACRO('N') \
	MACRO('O') \
	MACRO('P') \
	MACRO('Q') \
	MACRO('R') \
	MACRO('S') \
	MACRO('T') \
	MACRO('U') \
	MACRO('V') \
	MACRO('W') \
	MACRO('X') \
	MACRO('Y') \
	MACRO('Z') \

#define LOWERCASE_LETTERS(MACRO) \
	MACRO('a') \
	MACRO('b') \
	MACRO('c') \
	MACRO('d') \
	MACRO('e') \
	MACRO('f') \
	MACRO('g') \
	MACRO('h') \
	MACRO('i') \
	MACRO('j') \
	MACRO('k') \
	MACRO('l') \
	MACRO('m') \
	MACRO('n') \
	MACRO('o') \
	MACRO('p') \
	MACRO('q') \
	MACRO('r') \
	MACRO('s') \
	MACRO('t') \
	MACRO('u') \
	MACRO('v') \
	MACRO('w') \
	MACRO('x') \
	MACRO('y') \
	MACRO('z') \

#define DIGITS(MACRO) \
	MACRO('0') \
	MACRO('1') \
	MACRO('2') \
	MACRO('3') \
	MACRO('4') \
	MACRO('5') \
	MACRO('6') \
	MACRO('7') \
	MACRO('8') \
	MACRO('9') \


#define BASE64_ALPHABET(X) \
	UPPERCASE_LETTERS(X) \
	LOWERCASE_LETTERS(X) \
	DIGITS(X) \
	X('+') \
	X('/') \

#define ALL_SYMBOLS(X) \
	BASE64_ALPHABET(X) \
	X('=') \
	X('<') \
	X('>') \
	X(':') \
	X('.') \
	X('@') \
	X('-') \
	X(' ') \
	X('\r') \
	X('\n') \

#define VERIFY_ENCODING(CHAR) _Static_assert(u8##CHAR == CHAR, "Encoding of " #CHAR " character differs between normal char literal and u8 char literal");

ALL_SYMBOLS(VERIFY_ENCODING)

_Static_assert(__BYTE_ORDER__ == __LITTLE_ENDIAN, "Big endian byte order not supported");


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
		#define CASE(CHAR) case CHAR:
		UPPERCASE_LETTERS(CASE)
		LOWERCASE_LETTERS(CASE)
		#undef CASE
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

[[noreturn]] static void bail(char *log_message)
{
	SEND("421 Closing connection");
	errx(1, "%s", log_message);
}

enum {LUT_COUNTER_BASE = __COUNTER__ + 1};
#define LUT_ENTRY(CHAR) [CHAR] = __COUNTER__ - LUT_COUNTER_BASE,

//ensure the table is big enough to hold all possible values of chart8_t
static const uint8_t b64_lookup[1 << (sizeof(unsigned char) * CHAR_BIT)] =
{
	//ensure that all values not otherwise specified will return -1 from LUT
	[0 ... (sizeof b64_lookup / sizeof b64_lookup[0]) - 1] = (uint8_t)INT8_C(-1),
	['='] = 0,
	BASE64_ALPHABET(LUT_ENTRY)
};
_Static_assert(__COUNTER__ - LUT_COUNTER_BASE == 64, "Base64 alphabet does not contain 64 entries");

static bool base64_decode(size_t size, char *buf, size_t *pout_size)
{
	size_t j = 0, out_size = 0, num_equals = 0;
	bool seen_equals = false;
	bool encountered_error = false;
	uint32_t word = 0;
	for(size_t i = 0; i < size; ++i)
	{
		char c = buf[i];
		if(c == '=')
			++num_equals;
		else if(num_equals != 0)
		{
			warnx("saw non padding character after first padding equals in group");
			encountered_error = true;
		}
		uint8_t val = b64_lookup[(unsigned char)c];
		if((uint8_t)INT8_C(-1) == val)
		{
			encountered_error = true;
			warnx("invalid character %d in base64", c);
		}
		word <<= 6;
		word |= val;
		//if this is the last iteration, pretend we saw as many = as we would need to finish a set of four.
		for(;i + 1 == size && j < 3; ++j)
		{
			encountered_error = true;
			warnx("missing padding character in base64");
			word <<= 6;
			++num_equals;
		}
		if(++j == 4)
		{
			buf[out_size++] = (char)((word & 0xFF0000) >> 16);
			buf[out_size++] = (char)((word & 0x00FF00) >> 8);
			buf[out_size++] = (char)((word & 0x0000FF) >> 0);
			switch(num_equals)
			{
			case 4:
			case 3:
				warnx("invalid base64 group with %zu equals", num_equals);
				encountered_error = true;
				--out_size;
				[[fallthrough]];
			case 2:
				--out_size;
				[[fallthrough]];
			case 1:
				--out_size;
				if(seen_equals)
				{
					warnx("base64 contains more than one group with equals padding");
					encountered_error = true;
				}
				seen_equals = true;
				[[fallthrough]];
			case 0:
				break;

			}
			j = 0;
			num_equals = 0;
		}
	}
	*pout_size = out_size;
	return !encountered_error;
}

//precondition if expected data contains letters, they are lowercase
static bool case_insensitive_expect(size_t in_size, const char *in_buff, size_t expected_size, const char *expected_data)
{
	if(in_size != expected_size)
		return false;
	for(size_t i = 0; i < expected_size; ++i)
	{
		char c = in_buff[i];
		if('A' <= c && c <= 'Z')
			c |= 0x20;
		if(c != expected_data[i])
			return false;
	}
	return true;
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

static bool validate_and_case_fold_email_address(size_t size, char *buff)
{
	for(size_t i = 0; i < size; ++i)
	{
		char c = buff[i];
		if('A' <= c && c <= 'Z')
		{
			//case fold to lowercase equivalent
			c |= 0x20;
			buff[i] = c;
			continue;
		}
		if('a' <= c && c <= 'z')
			continue;
		//no email addresses starting with these characters
		if(i > 0 && (('0' <= c && c <= '9') || c == '.' || c == '_' || c == '-'))
			continue;
		return false;
	}
	return true;
}

static size_t unique_string(size_t size, char *buf)
{
	static uint64_t sequence_counter = 0;
	uint64_t sequence_num = sequence_counter++;
	uint64_t timestamp = (uint64_t)time(NULL);
	uint64_t pid = (uint64_t)getpid();
	size_t ret = (size_t)snprintf(buf, size, "%" PRIu64 ".%" PRIu64 ".%" PRIu64,
		pid, timestamp, sequence_num);
	if(ret >= size)
		return -(size_t)1;
	return ret;
}

static char *now(void)
{
	static char date_buf[256];
	time_t timestamp = time(NULL);
	struct tm local_time;
	localtime_r(&timestamp, &local_time);
	if(0 == strftime(date_buf, sizeof date_buf, "%a, %d %b %Y %T %z (%Z)", &local_time))
		errx(1, "date_buf not big enough");
	return date_buf;
}

#define CURR_EMAIL_FD 10
#define CURR_SESSION_FD 11
#define CURR_SESSION_DIR_FD 12

static int base_dir_fd, mail_dir_fd, log_dir_fd;
static char line_buff[LINE_LIMIT + 1];
static size_t line_size;
static char from_address[LINE_LIMIT + 1];
static size_t from_address_size;
static char username[256];
static size_t username_size;
static char message_id[256];
static size_t message_id_size;
static char recipient[256];
static size_t recipient_size;
static struct stat statbuf;
static dev_t base_dev;

static void close_log_session(void)
{
	if(0 > fdatasync(CURR_SESSION_FD))
		warn("Unable to sync session log to disk");
	char filename[256];
	if((-(size_t)1) == unique_string(sizeof filename, filename))
		errx(1, "Unable to generate unique filename");
#ifdef LINKAT_NOT_BROKEN
	if(0 > linkat(CURR_SESSION_FD, "", CURR_SESSION_DIR_FD, filename, AT_EMPTY_PATH))
#else
	if(0 > linkat(AT_FDCWD, "/proc/self/fd/" STRINGIZE(CURR_SESSION_FD), CURR_SESSION_DIR_FD, filename, AT_SYMLINK_FOLLOW))
#endif
		warn("Unable to link existing session into filesystem");
	close(CURR_SESSION_FD);
}

static void open_log_session(void)
{
	if(0 > dup3(log_dir_fd, CURR_SESSION_DIR_FD, O_CLOEXEC))
		warn("Unable to duplicate log_dir_fd into CURR_SESSION_DIR_FD");
	int fd = openat(base_dir_fd, ".", O_TMPFILE | O_RDWR, 0640);
	if(0 > fd)
		warn("Unable allocate descriptor to store log");
	if(CURR_SESSION_FD != fd)
	{
		if(0 > dup3(fd, CURR_SESSION_FD, O_CLOEXEC))
			warn("Unable dup descriptor for log into CURR_SESSION_FD");
		close(fd);
	}
}

enum state
{
	START,
	GREET,
	LOGIN,
	MAIL,
	RCPT,
	QUIT,
};

#define REPLY(STR) { SEND(STR); return; }

static void handle_auth(enum state *state)
{
	bool login = true;
	if(!read_line(line_buff, &line_size))
		REPLY("500 Parameters too long")
	if(*state != GREET)
		REPLY("503 Command out of sequence")
	if(!case_insensitive_expect(line_size, line_buff, 6, " login"))
		login = false;
	if(!login && (line_size < 7 || !case_insensitive_expect(7, line_buff, 7, " plain ")))
		REPLY("504 Command parameter not supported")
	if(login)
	{
		SEND("334 VXNlcm5hbWU6");
		if(!read_line(line_buff, &line_size))
			REPLY("500 Parameters too long")
		if(line_size == 1 && line_buff[0] == '*')
			REPLY("501 Cancelled")
		if(!base64_decode(line_size, line_buff, &username_size))
			REPLY("501 Invalid base64")
		if(username_size > sizeof username)
			REPLY("535 Username too long")
		memcpy(username, line_buff, username_size);
		if(!validate_and_case_fold_email_address(username_size, username))
			REPLY("535 Invalid username")
		SEND("334 UGFzc3dvcmQ6");
		if(!read_line(line_buff, &line_size))
			REPLY("500 Parameters too long")
		if(line_size == 1 && line_buff[0] == '*')
			REPLY("501 Cancelled")
		if(!base64_decode(line_size, line_buff, &line_size))
			REPLY("501 Invalid base64")
	}
	else
	{
		memmove(line_buff, line_buff + 7, line_size - 7);
		line_size -= 7;
		if(!base64_decode(line_size, line_buff, &line_size))
			REPLY("501 Invalid base64")
		if(line_size == 0 || line_buff[0] != '\0')
			REPLY("535 Authentication credentials invalid")
		char *user_start = line_buff + 1;
		char *user_end = memchr(user_start, '\0', line_size - 1);
		if(user_end == NULL)
			REPLY("535 Authentication credentials invalid")
		username_size = (size_t)(user_end - user_start);
		memcpy(username, user_start, username_size);
		if(!validate_and_case_fold_email_address(username_size, username))
			REPLY("535 Invalid username")
		char *pass_start = user_end + 1;
		char *pass_end = line_buff + line_size;
		line_size = (size_t)(pass_end - pass_start);
		memmove(line_buff, pass_start, line_size);
	}
	if(!check_credentials(username_size, username, line_size, line_buff))
		REPLY("535 Authentication credentials invalid")
	*state = LOGIN;
	dprintf(CURR_SESSION_FD, "%ld %.*s\n", time(NULL), (int)username_size, username);
	REPLY("235 Authentication successful")
}

static void handle_mail(enum state *state)
{
	if(!read_line(line_buff, &line_size))
		REPLY("500 Parameters too long")
	switch(*state)
	{
	case LOGIN:
		from_address_size = (size_t)snprintf(from_address, sizeof from_address,
			" from:<%.*s@" HOSTNAME ">", (int)username_size, username);
		//this should be impossible
		if(from_address_size >= sizeof from_address)
			bail("not enough space for from address");
		if(!case_insensitive_expect(line_size, line_buff, from_address_size, from_address))
			REPLY("550 Not authorized to send mail as that user")
		{
			int fd = openat(base_dir_fd, ".", O_TMPFILE | O_RDWR, 0640);
			if(0 > fd)
				REPLY("451 Unable allocate descriptor to store message")
			//if the fd number we got happens to already be CURR_EMAIL_FD, we don't need to do anything
			if(fd != CURR_EMAIL_FD)
			{
				int ret = dup3(fd, CURR_EMAIL_FD, O_CLOEXEC);
				close(fd);
				if(0 > ret)
					REPLY("451 Unable allocate descriptor to store message")
			}
		}
		message_id_size = unique_string(sizeof message_id, message_id);
		message_id[message_id_size] = '\0';
		dprintf(CURR_EMAIL_FD,
			"Received: by " HOSTNAME " ; %s\r\n"
			"Message-ID: <%.*s@" HOSTNAME ">\r\nFrom: <%.*s@" HOSTNAME ">\r\n",
			now(), (int)message_id_size, message_id, (int)username_size, username);
		*state = MAIL;
		REPLY("250 OK")
	case GREET:
		REPLY("530 Authentication required")
	case START:
	case MAIL:
	case RCPT:
	case QUIT:
		REPLY("503 Command out of sequence")
	}
}

static void handle_rcpt(enum state *state)
{
	if(!read_line(line_buff, &line_size))
		REPLY("500 Parameters too long")
	switch(*state)
	{
	case MAIL:
	case RCPT:
		if(line_size < 5 || !case_insensitive_expect(5, line_buff, 5, " to:<"))
			REPLY("553 Invalid mailbox")
		{
			#define SIZE_LEFT(PTR) (line_size - (size_t)(PTR - line_buff))
			char *user_start = line_buff + 5;
			char *user_end = memchr(user_start, '@', SIZE_LEFT(user_start));
			if(!user_end)
				REPLY("501 Invalid argument")
		#define X(s) (sizeof(s) - 1), s
			if(!case_insensitive_expect(SIZE_LEFT(user_end), user_end,
				X("@" HOSTNAME ">")))
				REPLY("550 Only local users allowed")
		#undef X
			if((size_t)(user_end - user_start) >= sizeof recipient)
				REPLY("550 Username too long")
			recipient_size = (size_t)(user_end - user_start);
			#undef SIZE_LEFT
			memcpy(recipient, user_start, recipient_size);
		}
		recipient[recipient_size] = '\0';
		if(!validate_and_case_fold_email_address(recipient_size, recipient))
			REPLY("550 Invalid username")
		if(*state < RCPT) //first recipient (only ever one iteration)
		{
			dprintf(CURR_EMAIL_FD, "To: <%.*s@" HOSTNAME ">\r\n", (int)recipient_size, recipient);
			*state = RCPT;
			int assignment_log_fd = openat(base_dir_fd, recipient,
				O_CLOEXEC | O_DIRECTORY | O_PATH);
			if(0 > assignment_log_fd)
				REPLY("250 OK")
			if(0 > fstat(assignment_log_fd, &statbuf))
				warn("Unable to stat assignment_log_fd");
			if(base_dev != statbuf.st_dev)
				warnx("Logs directory should be stored on the same physical device as the base dir");
			if(0 > dup3(assignment_log_fd, CURR_SESSION_DIR_FD, O_CLOEXEC))
				warn("Unable to dup assignment_log_fd into CURR_SESSION_DIR_FD");
			if(0 > fchown(CURR_EMAIL_FD, statbuf.st_uid, statbuf.st_gid))
				warn("Unable to chown email to assignment group");
			REPLY("250 OK")
		}
		dprintf(CURR_EMAIL_FD, " , <%.*s@" HOSTNAME ">\r\n", (int)recipient_size, recipient);
		REPLY("250 OK")
	case START:
	case GREET:
	case LOGIN:
	case QUIT:
		REPLY("503 Command out of sequence")
	}
}

static void handle_data(enum state *state)
{
	if(!read_line(line_buff, &line_size))
		REPLY("500 Parameters too long")
	if(*state != RCPT)
		REPLY("503 Command out of sequence")
	if(line_size != 0)
		REPLY("503 Syntax error")
	off_t curr_size = lseek(CURR_EMAIL_FD, 0, SEEK_CUR);
	if(0 > curr_size)
	{
		warn("unable to get position in email fd");
		REPLY("451 Error in processing")
	}
	SEND("354 Start input");
	enum data_state
	{
		HEADERS,
		BODY,
		FINISHED,
	};
	enum error
	{
		NONE,
		NOT_ENOUGH_SPACE,
		USER_SYNTAX_ISSUE,
		INTERNAL_SERVER_ERROR,
	};
	bool first_line = true;
	enum error error = NONE;
	#define ERROR_NES(...) { warnx(__VA_ARGS__); error = NOT_ENOUGH_SPACE; last_state = dstate = BODY; break; }
	#define ERROR_USI(...) { warnx(__VA_ARGS__); error = USER_SYNTAX_ISSUE; last_state = dstate = BODY; break; }
	#define ERROR_ISE(...) { warnx(__VA_ARGS__); error = INTERNAL_SERVER_ERROR; last_state = dstate = BODY; break; }
	#define CHECK_WRITE_FAIL(VARNAME) { if(0 > VARNAME) ERROR_NES("not enough space %d", __LINE__) else curr_size += (off_t)VARNAME; }
	for(enum data_state dstate = HEADERS, last_state = HEADERS; dstate != FINISHED;)
	{
		if(dstate == BODY && last_state == HEADERS)
			if(0 > fsetxattr(CURR_EMAIL_FD, "user.top_limit", &curr_size, sizeof curr_size, 0))
				ERROR_ISE("unable to set xattr on message")
		last_state = dstate;
		line_size = read_line_chunk(line_buff);
		switch(dstate)
		{
		case HEADERS:
			if(line_size == 0) //blank line -> end of headers
			{
				dstate = BODY;
			}
			else if(line_buff[0] == '.')
			{
				if(line_size == 1)
				{
					warnx("end of message before end of headers blank line");
					error = USER_SYNTAX_ISSUE;
					dstate = FINISHED;
					continue;
				}
				else if(line_buff[1] != '.')
					ERROR_USI("missing second dot for dot stuffing")
			}

			else if(line_buff[0] == ' ') //starts with space -> line folding continuation
			{
				if(first_line)
					ERROR_USI("first header line has a line folding space")
			}
			else //something else -> start of a header
			{
				char *colon = memchr(line_buff, ':', line_size);
				if(NULL == colon)
					ERROR_USI("header without a colon")
				#define MATCHES_HDR(STR) (line_size >= ((sizeof (STR))-1) && \
					case_insensitive_expect((sizeof (STR) -1), line_buff, \
					(sizeof(STR) - 1), STR)) ||
				if(MATCHES_HDR("message-id:") MATCHES_HDR("from:") MATCHES_HDR("to:") 0) //we provide these headers
				{
					int bytes = dprintf(CURR_EMAIL_FD, "X-KDLP-Orig-"); //change the name of the reserved header by prefixing it with X-KDLP-Orig-
					CHECK_WRITE_FAIL(bytes)
				}
				#undef MATCHES_HDR
				for(size_t i = 0; line_buff + i != colon; ++i)
					if(line_buff[i] < 33 || 126 < line_buff[i])
						ERROR_USI("invalid character %d in header name", line_buff[i])
				if(error != NONE) //break in ERROR macro will only break out of loop
					break;
			}
			first_line = false;
			{
				int bytes = dprintf(CURR_EMAIL_FD, "%.*s\r\n", (int)line_size, line_buff);
				CHECK_WRITE_FAIL(bytes)
			}
			break;
		case BODY:
			if(line_buff[0] == '.')
			{
				if(line_size == 1) //end of message
					dstate = FINISHED;
				else if(line_buff[1] != '.')
					ERROR_USI("missing second dot for dot stuffing")
			}
			if(error != NONE)
				break;
			{
				int bytes = dprintf(CURR_EMAIL_FD, "%.*s\r\n", (int)line_size, line_buff);
				if(0 > bytes)
					ERROR_NES("not enough space %d", __LINE__)
			}
			while(line_size == LINE_LIMIT)
			{
				line_size = read_line_chunk(line_buff);
				int bytes = dprintf(CURR_EMAIL_FD, "%.*s\r\n", (int)line_size, line_buff);
				if(0 > bytes)
					ERROR_NES("not enough space %d", __LINE__)
			}
			break;
		case FINISHED:
			__builtin_unreachable();
		}
	}
	#undef ERROR_NES
	#undef ERROR_USI
	#undef ERROR_ISE
	#undef CHECK_WRITE_FAIL
	*state = LOGIN;
	switch(error)
	{
	case NONE:
		break;
	case NOT_ENOUGH_SPACE:
		REPLY("452 Not enough space")
	case USER_SYNTAX_ISSUE:
		REPLY("554 Syntax error in message contents")
	case INTERNAL_SERVER_ERROR:
		REPLY("451 Local error in processing")
	}
	if(0 > fdatasync(CURR_EMAIL_FD))
	{
		warn("Unable to sync email file to disk");
		REPLY("451 Error storing message")
	}
#ifdef LINKAT_NOT_BROKEN
	if(0 > linkat(CURR_EMAIL_FD, "", mail_dir_fd, message_id, AT_EMPTY_PATH))
#else
	if(0 > linkat(AT_FDCWD, "/proc/self/fd/" STRINGIZE(CURR_EMAIL_FD), mail_dir_fd, message_id, AT_SYMLINK_FOLLOW))
#endif
	{
		warn("Unable to link existing session into filesystem");
		REPLY("451 Error storing message")
	}
	close(CURR_EMAIL_FD);
	dprintf(CURR_SESSION_FD, "%s\n", message_id);
	REPLY("250 OK")
}

#undef REPLY
#define REPLY(STR) { SEND(STR); break; }

int main(int argc, char **argv)
{
	if(0 <= fcntl(CURR_EMAIL_FD, F_GETFD) || errno != EBADF)
		errx(1, "File descriptor needed for current email (number " STRINGIZE(CURR_EMAIL_FD) ") is already in use");
	if(0 <= fcntl(CURR_SESSION_FD, F_GETFD) || errno != EBADF)
		errx(1, "File descriptor needed for current session log (number " STRINGIZE(CURR_SESSION_FD) ") is already in use");
	if(0 <= fcntl(CURR_SESSION_DIR_FD, F_GETFD) || errno != EBADF)
		errx(1, "File descriptor needed for session output directory (number " STRINGIZE(CURR_SESSION_DIR_FD) ") is already in use");
	if(argc != 2)
		errx(1, "Usage: %s <output directory>", argv[0]);
	base_dir_fd = openat(AT_FDCWD, argv[1], O_CLOEXEC | O_DIRECTORY | O_PATH);
	if(0 > base_dir_fd)
		err(1, "Unable to open output directory %s", argv[1]);
	if(0 > fstat(base_dir_fd, &statbuf))
		err(1, "Unable to stat base_dir_fd");
	base_dev = statbuf.st_dev;
	mail_dir_fd = openat(base_dir_fd, "mail", O_CLOEXEC | O_DIRECTORY | O_PATH);
	if(0 > mail_dir_fd)
		err(1, "Unable to open mail directory");
	if(0 > fstat(mail_dir_fd, &statbuf))
		err(1, "Unable to stat mail_dir_fd");
	if(base_dev != statbuf.st_dev)
		errx(1, "Mail directory should be stored on the same physical device as the base dir");
	log_dir_fd = openat(base_dir_fd, "logs", O_CLOEXEC | O_DIRECTORY | O_PATH);
	if(0 > log_dir_fd)
		err(1, "Unable to open logs directory");
	if(0 > fstat(log_dir_fd, &statbuf))
		err(1, "Unable to stat log_dir_fd");
	if(base_dev != statbuf.st_dev)
		errx(1, "Logs directory should be stored on the same physical device as the base dir");

	SEND("220 SMTP server ready");
	for(enum state state = START; state != QUIT;)
	{
		uint32_t command = get_command();
		switch(command)
		{
		case 'noop':
			eat_rest();
			REPLY("250 OK")
		case 'quit':
			eat_rest();
			if(state >= LOGIN)
				close_log_session();
			state = QUIT;
			REPLY("221 Goodbye")
		case 'helo':
			bail("got helo greeting");
		case 'ehlo':
			eat_rest();
			if(state >= LOGIN)
				close_log_session();
			open_log_session();
			state = GREET;
			REPLY("250-KDLP hello\r\n250 AUTH LOGIN PLAIN")
		case 'rset':
			eat_rest();
			if(state >= LOGIN)
				close_log_session();
			open_log_session();
			state = GREET;
			REPLY("250 OK")
		case 'auth':
			handle_auth(&state);
			break;
		case 'mail':
			handle_mail(&state);
			break;
		case 'rcpt':
			handle_rcpt(&state);
			break;
		case 'data':
			handle_data(&state);
			break;
		case 'help':
		case 'vrfy':
		case 'expn':
		case 'send':
		case 'soml':
		case 'saml':
		case 'turn':
			eat_rest();
			REPLY("502 Not implemented")
		default:
			eat_rest();
			REPLY("500 Unrecognized command")
		}
	}
	return 0;
}

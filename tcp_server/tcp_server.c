#include <arpa/inet.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef DEFAULT_PORT
#define DEFAULT_PORT 1337
#endif

#define STR_H(X) #X
#define STR(X) STR_H(X)

static int get_handler_fd(const char *handler_path, bool interpreted)
{
	int flags = O_PATH;
	if(!interpreted)
		flags |= O_CLOEXEC;
	int handler = open(handler_path, flags);
	if(0 > handler)
		err(1, "invalid handler program \"%s\"", handler_path);
	return handler;
}

static void verify_non_setuid(int handler_fd)
{
	struct stat stat;
	if(0 > fstat(handler_fd, &stat))
		err(1, "unable to stat handler program");
	if(stat.st_mode & (S_ISUID | S_ISGID))
		errx(1, "it is forbidden to combine chroot with a setuid/setgid handler program");
}

static int setup_socket(bool loopback, const char *port_str, const char *bind_addr_str)
{
	struct sockaddr_in bind_addr =
	{
		.sin_family = AF_INET,
		.sin_port = htons(DEFAULT_PORT),
		.sin_addr = { .s_addr = htonl(loopback ? INADDR_LOOPBACK : INADDR_ANY), },
	};
	if(NULL != port_str)
	{
		char *endptr;
		errno = 0;
		long port = strtol(port_str, &endptr, 0);
		if(endptr == port_str || *endptr != '\0')
		{
			errno = EINVAL;
			err(1, "invalid port \"%s\"", port_str);
		}
		if(port < 0 || port > UINT16_MAX)
		{
			errno = ERANGE;
			err(1, "invalid port \"%s\"", port_str);
		}
		bind_addr.sin_port = htons((uint16_t)port);
	}
	if(NULL != bind_addr_str)
	{
		if(!inet_aton(bind_addr_str, &bind_addr.sin_addr))
			errx(1, "invalid bind address \"%s\"", bind_addr_str);
	}
	int socket_fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, IPPROTO_TCP);
	if(0 > socket_fd)
		err(1, "unable to open socket");
#ifdef DEBUG
	static const int one = 1;
	if(0 > setsockopt(socket_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one))
		err(1, "unable to set re-use flag on socket");
#endif
	if(0 > bind(socket_fd, (const struct sockaddr *)&bind_addr, sizeof bind_addr))
		err(1, "unable to bind to address");
	if(0 > listen(socket_fd, 32))
		err(1, "unable to listen for connections");
	return socket_fd;
}

static void setup_signal_handler(void)
{
	struct sigaction child_act;
	if(0 > sigaction(SIGCHLD, NULL, &child_act))
		err(1, "failed to get default signal action for SIGCHLD (this is a bug)");
	child_act.sa_flags |= SA_NOCLDWAIT; //avoid needing to reap children processes
	if(0 > sigaction(SIGCHLD, &child_act, NULL))
		err(1, "failed to set signal action for SIGCHLD (this is a bug)");
}

static void setup_chroot(const char *chroot_path)
{
	if(0 > chroot(chroot_path))
		err(1, "unable to chroot into chroot directory \"%s\"", chroot_path);
	if(0 > chdir("/"))
		err(1, "unable to chdir into new root \"%s\" after chroot", chroot_path);
}

static void accept_connection(int socket_fd, int handler_fd, char **handler_argv)
{
	int client_socket_fd = accept4(socket_fd, NULL, NULL, SOCK_CLOEXEC);
	if(0 > client_socket_fd)
		err(1, "client accept failed");
	switch(fork())
	{
	case -1:
		err(1, "failed to create child for request");
	case 0:
		dup2(client_socket_fd, STDIN_FILENO);
		dup2(client_socket_fd, STDOUT_FILENO);
		fexecve(handler_fd, handler_argv, environ);
		err(1, "failed to execute handler for request");
	default:
		close(client_socket_fd);
	}
}

[[gnu::format(printf, 2, 3)]] [[noreturn]]
static void usage(const char *prog_name, const char *error_message, ...)
{
	fprintf(stderr,
		"Usage: %s [flags or options ...] handler [args ...]\n"
		"Flags:\n"
		"\t-h: display this message and exit\n"
		"\t-l: select loopback interface (127.0.0.1) as bind address (incompatible with -b)\n"
		"\t-i: specify that handler is an interpreted script that needs to have access to itself to run\n"
		"Options:\n"
		"\t-c directory: chroot into directory `directory` after setting up handler but before accepting any connections\n"
		"\t-p port: listen on port `port` instead of default " STR(DEFAULT_PORT) "\n"
		"\t-b address: bind to address `address` instead of default 0.0.0.0 (incompatible with -l)\n"
		"Arguments:\n"
		"\thandler: this program will be executed for each incoming connection with its stdin and stdout attached to the socket\n"
		"\targs: any subsequent arguments will be provided as argv for handler when it is invoked\n"
		"\t\t- Note: if you wish to provide arguments you must include a value for argv[0] as well (usually the name of the program)\n",
		prog_name);

	if(!error_message)
		exit(0);

	fputs("Error: ", stderr);
	va_list args;
	va_start(args, error_message);
	vfprintf(stderr, error_message, args);
	va_end(args);
	fputc('\n', stderr);
	exit(1);
}

struct options
{
	bool interpreted, loopback;
	char *chroot_dir, *port, *bind_addr;
	char *handler_path, **handler_argv;
};

static struct options parse_arguments(int argc, char **argv)
{
	bool interpreted = false;
	bool loopback = false;
	char *chroot_dir = NULL;
	char *port = NULL;
	char *bind_addr = NULL;
	for(;;)
	{
		//the `+` character at the beginning means that processing stops at the first non-option
		//element (i.e. one that does not start with a dash) which should be the handler program
		//this ensures that the order of further options are passed on unmodified to the handler
		switch(getopt(argc, argv, "+:hilc:p:b:"))
		{
		case 'h':
			usage(argv[0], NULL);
		case 'i':
			if(interpreted)
				usage(argv[0], "the -i option can only be specified once");
			interpreted = true;
			continue;
		case 'l':
			if(bind_addr)
				usage(argv[0], "the -l option is incompatible with -b");
			if(loopback)
				usage(argv[0], "the -l option can only be specified once");
			loopback = true;
			continue;
		case 'c':
			if(chroot_dir)
				usage(argv[0], "the -c option can only be specified once");
			chroot_dir = optarg;
			continue;
		case 'p':
			if(port)
				usage(argv[0], "the -p option can only be specified once");
			port = optarg;
			continue;
		case 'b':
			if(loopback)
				usage(argv[0], "the -b option is incompatible with -l");
			if(bind_addr)
				usage(argv[0], "the -b option can only be specified once");
			bind_addr = optarg;
			continue;
		case ':':
			usage(argv[0], "the -%c option requires an argument", optopt);
		case '?':
			usage(argv[0], "the option -%c is not recognized", optopt);
		case -1:
			break;
		}
		break;
	}
	if(NULL == argv[optind])
		usage(argv[0], "no handler program was specified");
	return (struct options)
	{
		.interpreted = interpreted,
		.loopback = loopback,
		.chroot_dir = chroot_dir,
		.port = port,
		.bind_addr = bind_addr,
		.handler_path = argv[optind],
		.handler_argv = &argv[optind + 1],
	};
}

int main(int argc, char **argv)
{
	struct options options = parse_arguments(argc, argv);

	int handler_fd = get_handler_fd(options.handler_path, options.interpreted);

	if(NULL != options.chroot_dir)
	{
		verify_non_setuid(handler_fd);
		setup_chroot(options.chroot_dir);
	}

	setup_signal_handler();

	int socket_fd = setup_socket(options.loopback, options.port, options.bind_addr);

	for(;;)
		accept_connection(socket_fd, handler_fd, options.handler_argv);
}

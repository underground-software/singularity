#include <err.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/inotify.h>
#include <sys/wait.h>
#include <unistd.h>

static int inotifyfd;

static struct inotify_event *get_event(void)
{
	static char read_buff[1024 * 10], *next = NULL, *end = NULL;
	if (next >= end) {
		ssize_t ret = read(inotifyfd, read_buff, sizeof read_buff);
		if (ret < 0)
			return NULL;
		end = read_buff + ret;
		next = read_buff;
	}
	struct inotify_event *evt = (void *)next;
	next += sizeof(*evt) + evt->len;
	return evt;
}

static void setup_signal_handler(void)
{
	struct sigaction child_act;
	if(0 > sigaction(SIGCHLD, NULL, &child_act))
		err(1, "failed to get default signal action for SIGCHLD (this is a bug)");
	child_act.sa_flags |= SA_NOCLDWAIT; //avoid needing to reap children processes
	if(0 > sigaction(SIGCHLD, &child_act, NULL))
		err(1, "failed to set signal action for SIGCHLD (this is a bug)");
	// we need to explicitly handle sigterm because when running as PID 1 inside
	// a container all signals without handlers (except SIG{KILL,STP}) are ignored
	if(SIG_ERR == signal(SIGTERM, _Exit))
		err(1, "failed to set handler for SIGTERM (this is a bug)");
}


int main(int argc, char **argv)
{
	setup_signal_handler();

	if (0 > (inotifyfd = inotify_init1(IN_CLOEXEC)))
		err(1, "inotify_init1");

	if (argc != 3)
		errx(1, "Usage: %s directory script", argv[0]);
	char *dir = argv[1], *exe = argv[2];

	int watch_desc = inotify_add_watch(inotifyfd, dir, IN_MASK_CREATE | IN_ONLYDIR | IN_CREATE);
	if (0 > watch_desc)
		err(1, "failed to create watch for directory: '%s'", dir);

	for (;;) {
		struct inotify_event *event = get_event();
		if (!event)
			err(1, "get event");

		switch (fork()) {
		case -1:
			err(1, "fork failed");
		case 0:
			execl(exe, exe, dir, event->name, (char *)NULL);
			err(1, "failed to exec \"%s\"", exe);
		default:
			break;
		}
	}
}

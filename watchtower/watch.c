#include <err.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
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

int main(int argc, char **argv)
{
	if (0 > (inotifyfd = inotify_init1(IN_CLOEXEC)))
		err(1, "inotify_init1");

	if (argc != 3)
		errx(1, "Usage: %s directory script", argv[0]);
	char *dir = argv[1], *exe = argv[2];

	int watch_desc = inotify_add_watch(inotifyfd, dir, IN_MASK_CREATE | IN_ONLYDIR | IN_CREATE);
	if (0 > watch_desc)
		err(1, "failed to create watch for directory: '%s'", dir);

	//avoid needing to reap children
	signal(SIGCHLD, SIG_IGN);
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
		}
	}
}

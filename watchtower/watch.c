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

/*
 * argv must contain pairs of paths to directories and paths to executables delimited by spaces
 */

int main (int, char **argv)
{
	if (0 > (inotifyfd = inotify_init1(IN_CLOEXEC)))
		err(1, "inotify_init1");

	// skip the program name
	++argv;

	int last_watch_desc = -1;
	// for each pair of (watched directory, executable path) in argv
	for (char *dir, *exe; (dir = argv[0]) && (exe = argv[1]); argv += 2) {
		int watch_desc = inotify_add_watch(inotifyfd, dir, IN_MASK_CREATE | IN_ONLYDIR | IN_CREATE);
		if(0 > watch_desc)
			err(1, "failed to create watch for directory: '%s'", dir);
		if(-1 != last_watch_desc && watch_desc != last_watch_desc + 1)
			errx(1, "watch descriptors from the kernel were not sequential. (BUG!!!)");
		last_watch_desc = watch_desc;
	}
	if(last_watch_desc == -1)
		errx(1, "no directories provided");


	for (;;) {
		struct inotify_event *event = get_event();
		if (!event)
			err(1, "get event");

		//argv has been incremented to point to the end of the array instead of the beginning
		char **argv_pair = &argv[2 * (event->wd - last_watch_desc)];

		char *dir = argv_pair[-2];
		char *exe = argv_pair[-1];

		pid_t pid = fork();
		if (0 > pid)
			err(1, "fork failed");
		if (!pid && 0 > execl(exe, exe, dir, event->name, (char *)NULL))
			err(1, "failed to exec '%s'", exe);
		int childret;
		if (waitpid(pid, &childret, 0) == -1)
			err(1, "waitpid failed");
		if (!WIFEXITED(childret) || WEXITSTATUS(childret))
			warnx("child (%s) exited abnormally with status=%d", exe, childret);
	}
}

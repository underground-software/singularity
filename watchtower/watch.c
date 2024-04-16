#include <limits.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/inotify.h>
#include <err.h>
#include <unistd.h>
#include <stdio.h>

/*
 * argv must contain pairs of paths to directories and paths to executables delimited by spaces
 */

int main (int, char **argv)
{
	int inotifyfd;
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

	FILE * inotify_file = fdopen(inotifyfd, "r");


	for (;;) {
		uint8_t _Alignas(struct inotify_event) event_buf[sizeof(struct inotify_event) + NAME_MAX + 1];
		struct inotify_event *event = (struct inotify_event *)event_buf;

		// read one inotify event header
		if (1 != fread(event, sizeof *event, 1, inotify_file))
			err(1, "fread");

		// read the path corresponding to this event
		if (event->len != fread(event->name, sizeof(char), (size_t)event->len, inotify_file))
			err(1, "fread");

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

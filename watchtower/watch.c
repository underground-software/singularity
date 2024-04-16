
#include <limits.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/timerfd.h>
#include <time.h>
#include <err.h>
#include <unistd.h>
#include <errno.h>
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

	// for each pair of (watched directory, executable path) in argv
	for (char *dir, *exe, **argv_iter = argv; (dir = argv_iter[0]) && (exe = argv_iter[1]); argv_iter += 2) {
		argv_iter[0] = (intptr_t)inotify_add_watch(inotifyfd, dir, IN_CREATED);
	}

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

		for (char *dir, *exe, **argv_iter = argv; (dir = argv_iter[0]) && (exe = argv_iter[1]); argv_iter += 2) {
			// run the program as a child process and wait for it to finish
			pid_t pid = fork();
			if (0 > pid)
				err(1, "fork failed");
			if (!pid && 0 > execl(exe, exe, (char *)NULL))
				err(1, "failed to exec '%s'", exe);
			int childret;
			if (waitpid(pid, &childret, 0) == -1)
				err(1, "waitpid failed");
			if (!WIFEXITED(childret) || WEXITSTATUS(childret))
				warnx("child (%s) exited abnormally with status=%d", exe, childret);
		}
	}
	return 0;
}

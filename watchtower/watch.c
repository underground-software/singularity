
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

int main (int argc, char **argv)
{
	int inotifyfd;
	if (0 > (inotifyfd = inotify_init1(IN_CLOEXEC)))
		err(1, "inotify_init1");

	FILE * inotify_file = fdopen(inotifyfd, "r");

	// skip the program name
	++argv;

	// for each pair of (watched directory, executable path) in argv
	for (char *dir, *exe, **argv_iter = argv; (dir = argv_iter[0]) && (exe = argv_iter[1]); argv_iter += 2) {
		argv_iter[0] = (intptr_t)inotify_add_watch(inotifyfd, dir, IN_CREATED);
	}

	for (;;) {
		struct inotify_event ev;
		if (1 != fread(&ev, sizeof ev, 1, inotify_file))
			err(1, "fread");

		char buf[256];

		if (ev.len > sizeof buf)
			err(1, "directory name too long");

		fread(buf, sizeof (char), ev.len, inotify_file);


		for (char *dir, *exe, **argv_iter = argv; (dir = argv_iter[0]) && (exe = argv_iter[1]); argv_iter += 2) {
			//
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

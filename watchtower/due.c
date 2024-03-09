#include <signal.h>
#include <sys/signalfd.h>
#include <limits.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <time.h>
#include <err.h>
#include <unistd.h>
#include <errno.h>

void handle_sigalrm(int signal_index) {
	signal(SIGALRM, handle_sigalrm);
}

/*
 * argv must contain pairs of timestamps and paths to executables delimited by spaces
 * the timesamps must be monotonically increasing
 */
int main (int argc, char **argv)
{
	/* // Avoid needing to reap children processes */
	/* struct sigaction child_act; */
	/* if(0 > sigaction(SIGCHLD, NULL, &child_act)) */
	/* 	err(1, "failed to get default signal action for SIGCHLD (this is a bug)"); */
	/* child_act.sa_flags |= SA_NOCLDWAIT; */
	/* if(0 > sigaction(SIGCHLD, &child_act, NULL)) */
	/* 	err(1, "failed to set signal action for SIGCHLD (this is a bug)"); */
	signal(SIGALRM, handle_sigalrm);
	sigset_t mask;
	if (sigfillset(&mask))
		err(1, "sigfillset");
	int sigfd = signalfd(-1, &mask, SFD_CLOEXEC);

	for (char * next; next = *++argv;) {
		char * endptr;
		intmax_t timestamp = strtoimax(next, &endptr, 10);
		if (endptr == next || *endptr != '\0')
			errx(1, "failed to parse argv entry \"%s\"", next);
		// get executable path
		next = *++argv;
		for (;;) {
			intmax_t now = (intmax_t)time(NULL);
			// once the due date is in the past, exec
			if (timestamp < now) {
				pid_t pid;
				int childret;
				switch((pid = fork())) {
				case -1:
					err(1, "fork failed");
				case 0:
					execl(next, next, (char *)NULL);
				default:
					if (waitpid(pid, &childret, 0) == -1)
						err(1, "waitpid failed");
					if (!WIFEXITED(childret) || WEXITSTATUS(childret))
						warnx("child (%s) exited abnormally with status=%d", next, childret);
				}
			}
			if (timestamp - now > UINT_MAX)
				errx(1, "due date more than 2**32 seconds in the future");
			// now safe to downcast intmax_t difference to unsigned
			unsigned timetowait = (unsigned)(timestamp - now);
			if (alarm(timetowait))
				errx(1, "bug! pending alarm detected (how?)");

			struct signalfd_siginfo info;
			if (read(sigfd, &info, sizeof info) != sizeof info)
				err(1, "failed to read signal info");
			if (info.ssi_signo != SIGALRM)
				errx(1, "caught unexepcted signal %d", info.ssi_signo);
		}
	}

	return 0;
}

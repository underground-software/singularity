#include <signal.h>
#include <limits.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <sys/timerfd.h>
#include <time.h>
#include <err.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

/* void handle_sigalrm(int signal_index) { */
/* 	signal(SIGALRM, handle_sigalrm); */
/* } */

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
	//signal(SIGALRM, handle_sigalrm);
	/* sigset_t mask; */
	/* int sigfd; */
	/* if (sigemptyset(&mask) == -1) */
	/* 	err(1, "sigemptyset"); */
	/* if (sigaddset(&mask, SIGALRM) == -1) */
	/* 	err(1, "sigaddset"); */
	/* if (sigprocmask(SIG_BLOCK, &mask, NULL) == -1) */
	/* 	err(1, "sigprocmask"); */

       	/* if ((sigfd = signalfd(-1, &mask, SFD_CLOEXEC)) == -1) */
		/* err(1, "signalfd"); */

	int timerfd;
	if (0 > (timerfd = timerfd_create(CLOCK_REALTIME, TFD_CLOEXEC)))
		err(1, "timerfd_create");

	for (char * next; next = *++argv;) {
		char * endptr;
		intmax_t parsed_timestamp = strtoimax(next, &endptr, 10);
		if (endptr == next || *endptr != '\0' || parsed_timestamp != (intmax_t)(time_t)parsed_timestamp)
			errx(1, "failed to parse argv entry \"%s\"", next);
		time_t timestamp = (time_t)parsed_timestamp;
		// get executable path
		next = *++argv;
		for (;;) {
			time_t now = time(NULL);
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
					goto next_entry;
				}
			}

			if (0 > timerfd_settime(timerfd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
					&(struct itimerspec){.it_value.tv_sec = (time_t)timestamp }, NULL))
				err(1, "timerfd_settime");

			read(timerfd, &(uint64_t){}, sizeof (uint64_t));
		}
next_entry:
	}

	return 0;
}

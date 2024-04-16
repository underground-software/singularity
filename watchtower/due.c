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

/*
 * argv must contain pairs of timestamps and paths to executables delimited by spaces
 * the timesamps must be monotonically increasing
 */

int main (int argc, char **argv)
{
	int timerfd;
	if (0 > (timerfd = timerfd_create(CLOCK_REALTIME, TFD_CLOEXEC)))
		err(1, "timerfd_create");

	// skip the program name
	++argv;

	// for each pair of (expiry time, executable path) in argv
	for (char *timestr, *exe; (timestr = argv[0]) && (exe = argv[1]); argv += 2) {

		// parse and validate the timestamp
		char * endptr;
		intmax_t parsed_timestamp = strtoimax(timestr, &endptr, 10);

		// if the downcasted value of parsed_timestamp differs from the original, we lost information in
		// the cast and the value is too big for a time_t
		if (endptr == timestr || *endptr != '\0' || parsed_timestamp != (intmax_t)(time_t)parsed_timestamp)
			errx(1, "failed to parse argv entry \"%s\"", timestr);
		time_t timestamp = (time_t)parsed_timestamp;

		// block until the time in the past
		for (time_t now = time(NULL); now < timestamp; now = time(NULL)) {
			if (0 > timerfd_settime(timerfd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
					&(struct itimerspec){.it_value.tv_sec = (time_t)timestamp }, NULL))
				err(1, "timerfd_settime");

			// block until timer expires or clock jumps weirdly
			read(timerfd, &(uint64_t){}, sizeof (uint64_t));
		}

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

	return 0;
}

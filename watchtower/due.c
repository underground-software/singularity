#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int timerfd;
	if (0 > (timerfd = timerfd_create(CLOCK_REALTIME, TFD_CLOEXEC)))
		err(1, "timerfd_create");

	if (argc != 3)
		errx(1, "Usage: %s timestamp script", argv[0]);
	char *timestr = argv[1], *exe = argv[2], *endptr;

	// parse and validate the timestamp
	errno = 0;
	intmax_t parsed_timestamp = strtoimax(timestr, &endptr, 10);
	if (endptr == timestr || *endptr != '\0')
		errx(1, "failed to parse timestamp \"%s\"", timestr);

	// how to properly check for a range error with a strtoXXX function
	if ((parsed_timestamp == INTMAX_MAX || parsed_timestamp == INTMAX_MIN) && errno == ERANGE)
		errx(1, "provided value \"%s\" is outside the valid range for time_t", timestr);

	time_t timestamp = (time_t)parsed_timestamp;
	// if the downcasted value of timestamp differs from parsed_timestamp when cast back
	// to an intmax_t we lost information in the cast and the value is too big for a time_t
	if (parsed_timestamp != timestamp)
		errx(1, "provided value \"%s\" is outside the valid range for time_t", timestr);

	// block until the time in the past
	while (time(NULL) < timestamp) {
		if (0 > timerfd_settime(timerfd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
				&(struct itimerspec){.it_value.tv_sec = timestamp }, NULL))
			err(1, "timerfd_settime");

		// block until timer expires or clock jumps weirdly
		read(timerfd, &(uint64_t){}, sizeof (uint64_t));
	}

	// exec the program
	execl(exe, exe, (char *)NULL);
	err(1, "failed to exec '%s'", exe);
}

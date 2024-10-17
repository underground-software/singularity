#include <err.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/xattr.h>
#include <unistd.h>

#define END_MARKER_XATTR "user.data_end"

int main(int argc, char **argv)
{
	if(2 != argc)
		errx(1, "Usage: %s <journal file>", argv[0]);
	char *journalfile = argv[1];
	int journal = openat(AT_FDCWD, journalfile, O_RDWR);
	if(0 > journal)
		err(1, "Unable to open journal file %s", journalfile);
	if(flock(journal, LOCK_EX))
		err(1, "Unable to get exlusive lock on journal file");
	int pipes[2];
	if(pipe2(pipes, 0))
		err(1, "Unable to make pipes");
	off_t end;
	if(sizeof end != fgetxattr(journal, END_MARKER_XATTR, &end, sizeof end))
		err(1, "journal file is missing end marker");
	if(end < 0)
		errx(1, "journal end marker is negative");
	int pipe_cap = fcntl(pipes[0], F_GETPIPE_SZ);
	if(0 > pipe_cap)
		err(1, "unable to determine pipe capacity");
	for(;;)
	{
		ssize_t r_ret = splice(STDIN_FILENO, NULL, pipes[1], NULL, (size_t)pipe_cap, 0);
		if(0 > r_ret)
			err(1, "failed to splice data from stdin to pipe");
		if(0 == r_ret)
			break;
		size_t bytes_read_remaining = (size_t)r_ret;
		do
		{
			ssize_t w_ret = splice(pipes[0], NULL, journal, &end, bytes_read_remaining, 0);
			if(0 >= w_ret)
				err(1, "failed to splice data from pipe to journal");
			bytes_read_remaining -= (size_t)w_ret;
		}
		while(bytes_read_remaining > 0);
	}
	if(fdatasync(journal))
		err(1, "failed to sync new data to journal");
	if(fsetxattr(journal, END_MARKER_XATTR, &end, sizeof end, XATTR_REPLACE))
		err(1, "failed to update end marker to reflect new data");
	if(fdatasync(journal))
		err(1, "failed to sync new data to journal");
	if(close(journal))
		err(1, "close returned unexpected error");
	return 0;
}

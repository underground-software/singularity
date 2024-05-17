#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/xattr.h>

static char attr_buf[4096];

int main(int argc, char **argv)
{
	if(argc < 4 || argv[2][0]!='-' || (argv[2][1]!='a' && argv[2][1]!='d') || argv[2][2] != '\0')
		errx(1, "Usage: %s [journal file] [-a|-d] username(s)...", argv[0]);
	int journalfd = open(argv[1], O_RDWR);
	if(0 > journalfd)
		err(1, "Unable to open journal file \"%s\"", argv[1]);
	off_t limit;
	if(sizeof limit != fgetxattr(journalfd, "user.data_end", &limit, sizeof limit))
		err(1, "Unable to read end of data marker from journal file");
	bool denying = argv[2][1]=='d';
	for(char **username = &argv[3]; *username; ++username)
	{
		if(sizeof attr_buf <= (size_t)snprintf(attr_buf, sizeof attr_buf, "user.%s_limit", *username))
			errx(1, "Username \"%s\" is too long", *username);
		int ret;
		if(denying)
			ret = fsetxattr(journalfd, attr_buf, &limit, sizeof limit, 0);
		else
			ret = fremovexattr(journalfd, attr_buf);
		if(0 > ret)
			err(1, "Unable to modify attribute \"%s\"", attr_buf);
	}
	return 0;
}

#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/xattr.h>

static char attr_buf[4096];

int main(int argc, char **argv)
{
	char action;
	if(argc < 4 || argv[2][0]!='-' || !(action = argv[2][1]) || argv[2][2] != '\0')
usage:
		errx(1, "Usage: %s [journal file] [-a|-d|-u] username(s)...", argv[0]);
	int journalfd = open(argv[1], O_RDWR);
	if(0 > journalfd)
		err(1, "Unable to open journal file \"%s\"", argv[1]);
	off_t limit;
	if(sizeof limit != fgetxattr(journalfd, "user.data_end", &limit, sizeof limit))
		err(1, "Unable to read end of data marker from journal file");
	for(char **username = &argv[3]; *username; ++username)
	{
		if(sizeof attr_buf <= (size_t)snprintf(attr_buf, sizeof attr_buf, "user.%s_limit", *username))
			errx(1, "Username \"%s\" is too long", *username);
		int ret;
		switch(action)
		{
		case 'u':
			ret = fsetxattr(journalfd, attr_buf, &limit, sizeof limit, 0);
			break;
		case 'd':
			ret = fsetxattr(journalfd, attr_buf, &limit, sizeof limit, XATTR_CREATE);
			break;
		case 'a':
			ret = fremovexattr(journalfd, attr_buf);
			break;
		default:
			goto usage;
		}
		if(0 > ret)
			err(1, "Unable to modify attribute \"%s\"", attr_buf);
	}
	return 0;
}

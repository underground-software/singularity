#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

#include "types.h"

//despite being in linux since 3.15 (2014) and glibc since 2.28 (2018) musl still
//does not have support for the renameat2 system call (though at time of writing,
//it is hopefully coming soon https://www.openwall.com/lists/musl/2024/05/07/7)
#ifndef RENAME_EXCHANGE
#include <sys/syscall.h>
#define RENAME_EXCHANGE  (1 << 1)
static int renameat2(int oldfd, const char *old, int newfd, const char *new, unsigned flags)
{
	return (int)syscall(SYS_renameat2, oldfd, old, newfd, new, flags);
}
#endif

static void write_with_retry(int fd, void *data, size_t size)
{
	char *data_p = data;
	size_t off = 0;
	do
	{
		ssize_t ret = write(fd, data_p + off, size - off);
		if(ret < 0)
			err(1, "unable to write data");
		off += (size_t)ret;
	}
	while(off < size);
}

static void load_emails(int journal_fd, char *path)
{
	int mail_dir = openat(AT_FDCWD, path, O_RDONLY | O_DIRECTORY);
	if(0 > mail_dir)
		err(1, "unable to open mail directory \"%s\"", path);
	DIR *dir = fdopendir(mail_dir);
	if(!dir)
		err(1, "Unable to open directory stream");
	errno = 0;
	for(struct dirent *ptr = readdir(dir); NULL != ptr; errno = 0, ptr = readdir(dir))
	{
		int fd = openat(mail_dir, ptr->d_name, O_RDONLY | O_NOFOLLOW);
		if(0 > fd)
			err(1, "unable to open file \"%s\"", ptr->d_name);
		struct stat statbuf;
		if(0 > fstat(fd, &statbuf))
			err(1, "unable to stat file \"%s\"", ptr->d_name);
		//skip non regular files (e.g. symlinks, directories)
		if(!S_ISREG(statbuf.st_mode))
			continue;
		struct email email =
		{
			.size = statbuf.st_size,
			.active = true,
		};
		if(sizeof email.top_limit != fgetxattr(fd, "user.top_limit", &email.top_limit, sizeof email.top_limit))
			err(1, "unable to read end of headers marker from email \"%s\"", ptr->d_name);
		close(fd);
		size_t size = strlen(ptr->d_name);
		if(size >= sizeof email.name)
			errx(1, "filename of email %s is too long", ptr->d_name);
		memcpy(email.name, ptr->d_name, size + 1);
		write_with_retry(journal_fd, &email, sizeof email);
	}
	if(errno)
		err(1, "Unable to read from directory");
	closedir(dir);
}

static void replicate_xattrs(int targetfd, char *srcpath)
{
	//ought to be big enough for our purposes
	static char buf[16348];
	ssize_t ret = listxattr(srcpath, buf, sizeof buf);
	if(0 > ret)
		err(1, "unable to fetch xattrs from \"%s\"", srcpath);
	char *end = buf + (size_t)ret;
	for(char *ptr = buf; ptr < end; ptr += 1 + strnlen(ptr, (size_t)(end - ptr)))
	{
		if(ptr[0] != 'u' || ptr[1] != 's' || ptr[2] != 'e' || ptr[3] != 'r' || ptr[4] != '.')
			continue;
		if(!strncmp(ptr, "user.data_end", (size_t)(end - ptr)))
			continue;
		off_t limit;
		if(sizeof limit != getxattr(srcpath, ptr, &limit, sizeof limit))
			err(1, "invalid attribute \"%s\"", ptr);
		if(fsetxattr(targetfd, ptr, &limit, sizeof limit, 0))
			err(1, "unable to set attr \"%s\"", ptr);
	}
}


int main(int argc, char **argv)
{
	char *journal_file=NULL, *temp_file, *email_folder=NULL, *new_file;
	switch(argc)
	{
	case 2:
		new_file = argv[1];
		break;
	case 4:
		journal_file = argv[1];
		new_file = temp_file = argv[2];
		email_folder = argv[3];
		break;
	default:
		errx(1, "Usage: %s [journal file] ([temp file name] [folder with emails])", argv[0]);
	}

	int new_fd = openat(AT_FDCWD, new_file, O_CREAT | O_EXCL | O_WRONLY, 0600);
	if(0 > new_fd)
		err(1, "Unable to create file \"%s\"", new_file);
	if(email_folder)
	{
		load_emails(new_fd, email_folder);
		replicate_xattrs(new_fd, journal_file);
	}
	off_t f_pos = lseek(new_fd, 0, SEEK_CUR);
	if(fsetxattr(new_fd, "user.data_end", &f_pos, sizeof f_pos, 0))
		err(1, "unable to write journal file size to journal file");
	if(fdatasync(new_fd))
		err(1, "unable to sync data to disk");
	if(close(new_fd))
		err(1, "error occured while closing journal file");
	if(!email_folder)
		return 0;
	if(renameat2(AT_FDCWD, journal_file, AT_FDCWD, temp_file, RENAME_EXCHANGE))
		err(1, "unable to update replace journal file we new data");
	if(unlink(temp_file))
		err(1, "unable to remove temporary file");
	return 0;
}

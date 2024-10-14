#ifndef JOURNAL_EMAIL_H
#define JOURNAL_EMAIL_H
struct email
{
	off_t size;
	off_t top_limit;
	bool active;
	char name[31];
};
_Static_assert(sizeof(struct email) == 48, "size of struct email should be 48");
#endif//JOURNAL_EMAIL_H

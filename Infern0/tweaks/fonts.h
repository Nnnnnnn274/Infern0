#include <stdio.h>

char fonts[4096];

int readrepos();
int fetchrepo(char repo[]);
int downloadfont(const char *fontname);
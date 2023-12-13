#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <string.h>

int main(int argc, char* argv[])
{
    char dest[PATH_MAX];
    memset(dest,0,sizeof(dest)); // readlink does not null terminate!
    if (readlink("/proc/self/exe", dest, PATH_MAX) == -1) {
        perror("ERROR");
    }
    char scriptPath[PATH_MAX];
    sprintf(scriptPath, "%s.py", dest);
    argv[0] = scriptPath;

    char* newArgv[argc+2];
    newArgv[0] = "python3";
    newArgv[argc+1] = NULL;

    int j = 0;
    for (j = 0; j < argc; j++){
       printf("argv[%d]: %s\n", j, argv[j]);
       newArgv[j+1] = argv[j];
    }

    if ( execvp("python3", newArgv) == -1 ){
        perror("ERROR");
    }
    return 0;
}
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    // Set the environment variable
    int result = setenv("LLVM_PROFILE_FILE", "/coverage/coverage-%p.profraw%c", 1);

    if (result != 0) {
        return 1;
    }

    // Define the program to execute (predefined)
    char *program ="/usr/local/bin/smtp_";

    // Create a new array to hold the arguments for execvp, including the program name
    char** exec_args = (char**) malloc(sizeof(char*) * (unsigned long) (argc + 1));

    // Set the program ßßßname as the first argument
    exec_args[0] = program;

    // Copy the rest of the arguments passed to your program to the new exec_args array
    for (int i = 1; i < argc; i++) {
        exec_args[i] = argv[i];
    }

    // Terminate the array with a NULL pointer (as required by execvp)
    exec_args[argc] = NULL;

    // Execute the program, replacing the current process
    execvp(program, exec_args);

    // If execvp returns, it means it failed
    return 1;
}

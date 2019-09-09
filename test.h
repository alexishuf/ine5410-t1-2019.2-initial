#ifndef INE5410_TEST_H_

#include "simulation.h"
#include <stdio.h>

typedef struct test_s {
    FILE* file;
    int width, height;
    simulation_t sim;
    int pid;
    int shutting_down;
    person_t* persons;
    int persons_cap;
    int persons_size;
    pthread_t inserter;
    int insertion_interval;
    person_t* insertions;
    int insertions_cap;
    int insertions_size;
} test_t;

int  test_setup(test_t* test, int n_threads, const char* path);
void test_run(test_t* test, int cycles);
void test_tear_down(test_t* test);


#endif /*INE5410_TEST_H_*/

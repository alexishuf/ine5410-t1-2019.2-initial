#include "test.h"
#include <time.h>
#include <sys/time.h>
#include <regex.h>
#include <errno.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>

#define STAGE_SIZE       1
#define STAGE_OBSTACLES  2
#define STAGE_PERSONS    3
#define STAGE_INSERTIONS 4

static int test_mk_rx(regex_t* rx, const char* str) {
    int err;
    if ((err = regcomp(rx, str, REG_EXTENDED|REG_NEWLINE))) {
        int size = regerror(err, rx, NULL, 0);
        char* err_buf = malloc(size+1);
        regerror(err, rx, err_buf, size);
        printf("Error compiling regex: %s\n", err_buf);
        free(err_buf);
    }
    return err;
}

int test_parse_int(const char* str, regmatch_t* match) {
    char buf[32];
    int size = match->rm_eo - match->rm_so;
    assert(size < 32);
    memcpy(buf, str+match->rm_so, size);
    buf[size] = 0;
    return strtol(buf, NULL, 10);
}

static person_t* test__emplace_person(person_t** data, int* cap, int* size) {
    if (*size == *cap) {
        // validator-pthreads.c não lida bem com sem_t mudando de endereço
        // destroi as pessoas e as reconstrói na nova localização
        *cap *= 2;
        person_t* ndata = (person_t*) malloc(*cap * sizeof(person_t));
        for (int i = 0; i < *size; ++i) {
            person_t cp = (*data)[i];
            person_destroy(*data+i); //destroi sem_t
            person_init(ndata+i, cp.id); //cria novo sem_t
            ndata[i].current_pos = cp.current_pos;
            ndata[i].goal_pos = cp.goal_pos;
            ndata[i].time = cp.time;
        }
        free(*data);
        *data = ndata;
    }
    person_t* p = *data + *size;
    ++*size;
    return p;
}

static void test__free_persons(person_t* data, int size) {
    for (int i = 0; i < size; ++i)
        person_destroy(data+i);
    free(data);
}


int  test_setup(test_t* t, int n_threads, const char* path) {
    int err = 0;
    t->pid = t->shutting_down = t->width = t->height = 0;
    t->persons =    (person_t*)malloc(sizeof(person_t)*(t->persons_cap = 100));
    t->insertions = (person_t*)malloc(sizeof(person_t)*(t->insertions_cap = 10));
    t->insertions_size = t->persons_size = 0;
    t->insertion_interval = 0;
    
    t->file = fopen(path, "r");
    if (t->file == NULL) {
        int code = errno;
	sprintf("Não consegui abrir o arquivo %s: %s", path, strerror(code));
        return code;
    }

    regex_t rx_hdr_obstacles, rx_hdr_persons, rx_hdr_insertions;
    regex_t rx_size, rx_obstacle, rx_person;
    test_mk_rx(&rx_hdr_obstacles, "obstacles[ \t]*:");
    test_mk_rx(&rx_hdr_persons, "persons[ \t]*:");
    test_mk_rx(&rx_hdr_insertions,
               "insertions[ \t]*:[ \t]*([0-9]+)");
    test_mk_rx(&rx_size, "([0-9]+)[ \t]*x[ \t]*([0-9]+)");
    test_mk_rx(&rx_obstacle,
               "([0-9]+) *, *([0-9]+) *@ *([0-9]+) *x *([0-9]+)");
    test_mk_rx(&rx_person,
               "([0-9]+) *, *([0-9]+) *-> *([0-9]+) *, *([0-9]+)");

    char* buf = NULL;
    size_t n = 0;
    int stage = STAGE_SIZE;
    regmatch_t groups[5]; // max number is 4 groups (rx_person) + whole
    while (getline(&buf, &n, t->file)>=0) {
        if (regexec(&rx_hdr_obstacles, buf, 1, groups, 0) == 0) {
            stage = STAGE_OBSTACLES;
        } else if (regexec(&rx_hdr_persons, buf, 1, groups, 0) == 0) {
            stage = STAGE_PERSONS;
        } else if (regexec(&rx_hdr_insertions, buf, 2, groups, 0) == 0) {
            stage = STAGE_INSERTIONS;
        } else if (stage == STAGE_SIZE) {
            if (regexec(&rx_size, buf, 3, groups, 0) == 0) {
                int w = test_parse_int(buf, groups+1);
                int h = test_parse_int(buf, groups+2);
                simulation_init(&t->sim, n_threads, w, h);
            }
        } else if (stage == STAGE_OBSTACLES) {
            if (regexec(&rx_obstacle, buf, 5, groups, 0) == 0) {
                int x = test_parse_int(buf, groups+1);
                int y = test_parse_int(buf, groups+2);
                int w = test_parse_int(buf, groups+3);
                int h = test_parse_int(buf, groups+4);
                for (pos_t p = {x, y}; p.y < h; ++p.y) {
                    for (p.x = x; p.x < w; ++p.x) 
                        grid_set(&t->sim.grid, p, GRID_OBJ_OBSTACLE);
                }
            }
        } else if (stage == STAGE_PERSONS || stage == STAGE_INSERTIONS) {
            if (regexec(&rx_person, buf, 5, groups, 0) == 0) {
                pos_t p0 = {0, 0}, p1 = {0, 0};
                p0.x = test_parse_int(buf, groups+1);
                p0.y = test_parse_int(buf, groups+2);
                p1.x = test_parse_int(buf, groups+3);
                p1.y = test_parse_int(buf, groups+4);
                person_t* p;
                if (stage == STAGE_PERSONS) {
                    p = test__emplace_person(&t->persons, &t->persons_cap,
                                             &t->persons_size);
                    person_init(p, ++t->pid);
                } else {
                    p = test__emplace_person(&t->insertions, &t->insertions_cap,
                                             &t->insertions_size);
                    person_init(p, -1);
                }
                p->current_pos = p0;
                p->goal_pos    = p1;
                if (stage == STAGE_PERSONS) {
                    if (grid_get(&t->sim.grid, p0, NULL) != GRID_OBJ_EMPTY) {
                        printf("Caso de teste %s insere duas pessoas na "
                               "posição (%d,%d)!\n", path, p0.x, p0.y);
                        err = 2;
                        break;
                    }
                    simulation_plug_unsafe(&t->sim, p);
                }
            }
        }
    }

    regfree(&rx_hdr_obstacles);
    regfree(&rx_hdr_persons);
    regfree(&rx_hdr_insertions);
    regfree(&rx_size);
    regfree(&rx_obstacle);
    regfree(&rx_person);
    free(buf);
    if (err) {
        simulation_destroy(&t->sim);
        test__free_persons(t->persons, t->persons_size);
        test__free_persons(t->insertions, t->insertions_size);
    }
    return err;
}

void* test_inserter(void* arg) {
    test_t* t = (test_t*)arg;
    while (t->shutting_down) {
        int ipid = t->pid;
        for (int i = 0; i < t->insertions_size; ++i) {
            t->insertions[i].id = ++ipid;
            simulation_plug(&t->sim, t->insertions+i);
        }
        if (t->insertion_interval) {
            struct timespec ts = {0, 1000000l*t->insertion_interval};
            nanosleep(&ts, NULL);
        }
        for (int i = 0; i < t->insertions_size; ++i) 
            simulation_unplug(&t->sim, t->insertions+i);
    }
    return NULL;
}

void test_run(test_t* t, int cycles) {
    pos_t* initials = (pos_t*)malloc(t->persons_size*sizeof(pos_t));
    for (int i = 0; i < t->persons_size; ++i)
        initials[i] = t->persons[i].current_pos;

    pthread_create(&t->inserter, NULL, test_inserter, t);
    simulation_start(&t->sim);
    double sum_ms = 0;
    struct timeval start, end;
    gettimeofday(&start, NULL);
    for (int i = 0; i < cycles; ++i) {
        for (int j = 0; j < t->persons_size; ++j)
            person_join(t->persons+j);
        gettimeofday(&end, NULL);

        double s_usec = start.tv_sec*1000.0 + start.tv_usec/1000.0,
               e_usec =   end.tv_sec*1000.0 +   end.tv_usec/1000.0;
        double ms = e_usec - s_usec;
        sum_ms += ms;
        printf("Cycle %d took %.3f ms\n", i, ms);
        fflush(stdout);

        if (i < cycles-1) {
            gettimeofday(&start, NULL);
            //plug them back in their initial positions
            for (int j = 0; j < t->persons_size; ++j) {
                t->persons[j].current_pos = initials[j];
                simulation_plug(&t->sim, t->persons+j);
            }
        }
    }
    printf("Avg. per cycle: %.3f\n", sum_ms/cycles);

    free(initials);
}

void test_tear_down(test_t* t) {
    t->shutting_down = 1;
    pthread_join(t->inserter, NULL);
    simulation_destroy(&t->sim);
    for (int i = 0; i < t->persons_size; ++i)
        person_join(t->persons+i);
    test__free_persons(t->persons, t->persons_size);
    test__free_persons(t->insertions, t->insertions_size);
}

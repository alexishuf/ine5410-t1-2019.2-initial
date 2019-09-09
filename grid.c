#include "grid.h"
#include <string.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <math.h>

/* --- --- --- --- pos_t  --- --- --- --- */

pos_t mk_pos(int x, int y) {
    pos_t p = {x, y};
    return p;
}
double pos_distance(pos_t from, pos_t to) {
    return sqrt(pow((to.x - from.x), 2) + pow(to.y - from.y, 2));
}
pos_t pos_add(pos_t a, pos_t b) {
    pos_t p = {a.x+b.x, a.y+b.y};
    return p;
}
int pos_equals(pos_t a, pos_t b) {
    return a.x == b.x && a.y == b.y;
}


/* --- --- --- --- grid_t  --- --- --- --- */

void grid_init(grid_t* grid, int width, int height) {
    grid->data = calloc(width*height, sizeof(person_t*));
    grid->width = width;
    grid->height = height;
}

void grid_destroy(grid_t* grid) {
    free(grid->data);
}

int grid_isvalid(grid_t* grid, pos_t pos) {
    int ok = pos.x >= 0 && pos.y >= 0;
    if (ok && grid)
        ok = pos.x < grid->width && pos.y < grid->height;
    return ok;
}

int grid_get(grid_t* grid, pos_t pos, person_t** out_person) {
    assert(grid_isvalid(grid, pos));
    ptrdiff_t* ptr = (ptrdiff_t*)grid->data + (pos.y * grid->width + pos.x);
    ptrdiff_t type = *ptr;
    if (type < GRID_OBJ__MIN || type > GRID_OBJ__MAX) {
        type = GRID_OBJ_PERSON;
        if (out_person)
            *out_person = *(person_t**)ptr;
    }
    return type;
}

int grid_set(grid_t* grid, pos_t pos, int type) {
    assert(grid_isvalid(grid, pos));
    assert(type != GRID_OBJ_PERSON);
    ptrdiff_t* ptr = (ptrdiff_t*)grid->data + (pos.y * grid->width + pos.x);
    ptrdiff_t old = *ptr;
    *ptr = type;
    return old < GRID_OBJ__MIN || old > GRID_OBJ__MAX ? GRID_OBJ_PERSON : old;
}

int grid_set_person(grid_t* grid, pos_t pos, person_t* person) {
    assert(grid_isvalid(grid, pos));
    int old = grid_get(grid, pos, NULL);
    person_t** ptr = (person_t**)grid->data + (pos.y * grid->width + pos.x);
    *ptr = person;
    person->current_pos = pos;
    return old;
}

//                                 x   y    x   y    x   y
pos_t grid_neighbor_offsets[] = {{-1, -1}, {0, -1}, {1, -1},
                                 {-1,  0}, /*___*/  {1,  0},
                                 {-1,  1}, {0,  1}, {1,  1}};

// Causa um erro se o tamanho de grid_neighbor_offsets for alterado
int static_assert__grid_neighbor_offsets
    [sizeof(grid_neighbor_offsets)/sizeof(pos_t) == GRID_NEIGHBOR_COUNT ? 1 : -1];


/* --- --- --- person --- --- --- */

void person_init(person_t* person, int id) {
    memset(person, 0, sizeof(person_t));
    person->current_pos = mk_pos(-1, -1);
    person->goal_pos = mk_pos(-1, -1);
    person->id = id;
    person->last_move = person->time = 0;
}

void person_destroy(person_t* person) {
}


void person_join(person_t* person) {
    printf("[ERRO] person_join() não implementado !!!\n");
    abort();
}

pos_t person_next_pos(person_t* p, grid_t* g) {
    if (!grid_isvalid(g, p->current_pos) || !grid_isvalid(g, p->goal_pos)
        || pos_equals(p->goal_pos, p->current_pos)) {
        return p->current_pos; // no movement
    }
    
    /*******************************************************************
     * CUIDADO: INE5410 é sobre CONCORRÊNCIA E PARALELISMO.            *
     *                                                                 *
     * O algoritmo abaixo, se usado como path planning, é ingênuo e    *
     * não funciona no caso geral. Estou usando o algoritmo mais fácil *
     * de entender (que por coincidência é um dos piores em termos de  *
     * funcionalidade). No mundo real, deveria ser usado A*            *
     *******************************************************************/

    float best_dist = INFINITY;
    pos_t best_cand = p->current_pos;
    for (int i = 0; i < GRID_NEIGHBOR_COUNT; ++i) {
	pos_t cand = pos_add(p->current_pos, grid_neighbor_offsets[i]);
        if (!grid_isvalid(g, cand))
            continue;
	if (grid_get(g, cand, NULL) != GRID_OBJ_EMPTY)
	    continue;
	float dist = pos_distance(cand, p->goal_pos);
	if (dist < best_dist) {
	    best_dist = dist;
	    best_cand = cand;
	}
    }

    return best_cand;
}


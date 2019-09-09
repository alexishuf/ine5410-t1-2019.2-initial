#include "simulation.h"
#include <stdlib.h>
#include <assert.h>
#include <stdio.h>


void simulation_init(simulation_t* sim, int n_threads, int width, int height) {
    grid_init(&sim->grid, width, height);
    sim->time = 0;
    // ...
}

void simulation_destroy(simulation_t* simulation) {
    // ...
    grid_destroy(&simulation->grid);
    // ...
}

int simulation_plug_unsafe(simulation_t* sim, person_t* person) {
    // ...
}

int simulation_plug(simulation_t* simulation, person_t* person) {
    // ...
}

void simulation_unplug(simulation_t* simulation, person_t* person) {
    // ...
}

void simulation_start(simulation_t* simulation) {
    // ...
}

void simulation_pause(simulation_t* simulation) {
    // ...
}

void simulation_continue(simulation_t* simulation) {
    // ...
}


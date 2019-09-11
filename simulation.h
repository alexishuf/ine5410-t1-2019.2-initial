#ifndef INE5410_SIMULATION_H_
#define INE5410_SIMULATION_H_

#include "grid.h"
#include "queue.h"

typedef struct simulation_s {
    grid_t grid;
    size_t time;
    // Você provavelmente quer adicionar coisas aqui
} simulation_t;

/**
 * Inicializa um simulation com largura width e altura height cuja simulação
 * usará n_threads.
 */
void simulation_init(simulation_t* simulation, int n_threads, int width, int height);

/**
 * Libera quaisquer recursos alocados no simulation_init()
 *
 * Caso a simulação esteja em execução, essa função deve terminar todas as
 * threads realizando a execução antes de efetivamente destruir o simulation.
 */
void simulation_destroy(simulation_t* simulation);

/**
 * Insere uma pessoa no simulation. A pessoa será inserida na passagem de um
 * turno para outro, de modo a não causar inconsistências na simulação. 
 *
 * Caso a posição já esteja ocupada, retorna com valor 0. Se person->current_pos
 * estiver vazio, retorna com valor 1.
 *
 * Precondições:
 * - *person permanecerá válido até o unplug via simulation_unploug(simulation,
 *    person) ou até a liberação do simulation, com simulation_destroy(simulation)
 *   [UNDEFINED BEHAVIOR se violada]
 */
int simulation_plug_unsafe(simulation_t* simulation, person_t* person);

/**
 * Versão de simulation_plug_unsafe que pode ser chamada com a simulação em
 * andamento.
 *
 * A pessoa será inserida de modo a não causar inconsistências na simulação. 
 * Isso implica que essa função bloqueará até que a inserção seja segura
 */
int simulation_plug(simulation_t* simulation, person_t* person);

/**
 * Remove uma pessoa específica da simulação.
 */
void simulation_unplug(simulation_t* simulation, person_t* person);

/**
 * Inicia a execução do simulation. Essa função não bloqueia: ela retorna
 * imediatamente e a execução prossegue em background.
 */
void simulation_start(simulation_t* simulation);

#endif /*INE5410_SIMULATION_H_*/

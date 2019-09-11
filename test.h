#ifndef INE5410_TEST_H_

#include "simulation.h"
#include <stdio.h>

typedef struct test_s {
    /**
     * Arquivo descrevendo o cenário de teste.
     */
    FILE* file;
    simulation_t sim;
    /**
     * Contador usado para atribuir id's aos person_t's inseridos no
     * simulation_t.
     */
    int pid;
    
    /**
     * Sinaliza que o teste deve terminar (usado para sinaliza o fim
     * para a thread inserter).
     */
    int shutting_down;

    /**
     * Arrays de pessoas a serem simulation_plug()adas antes do início
     * da simulação.
     */
    person_t* persons;
    int persons_cap;  ///< capacidade de persons
    int persons_size; ///< número de person_t's atualmente em persons
    
    /**
     * Thread que repetidamente chama simulation_plug()/simulation_unplug().
     * Essas chamadas são concorrentes à execução da simulação
     */
    pthread_t inserter;

    /**
     * Quantos milisegundos uma pessoa no bloco insertions fica inserida 
     */
    int insertion_interval;

    /**
     * Lista de pessoas a serem simulation_plug()adas e
     * simulation_unplug()adas em cada loop da thread inserter.
     */
    person_t* insertions;
    int insertions_cap;  ///< capacidade de insertions
    int insertions_size; ///<  número de person_t's atualmente em insertions
} test_t;

/**
 * Configura um cenário de teste, inicializando todos os atributos do test_t*
 * fornecido. path é o caminho do arquivo .test e n_threads é repassado a 
 * simulation_init().
 * 
 * Caso ocorra um erro, essa função destruirá tudo que foi inicializado, de modo
 * que test_tear_down() não é necessário em caso de falha.
 */
int  test_setup(test_t* test, int n_threads, const char* path);

/**
 * Chama simulation_start(), executa cycles ciclos de
 * simulation_plug()/simulation_unplug() com test->persons. Essa
 * função só termina um ciclo quando todos os person_t em
 * test->persons retornaram dos person_join().
 */
void test_run(test_t* test, int cycles);

/**
 * Destroi a simulação e libera os recursos no test_t.
 */
void test_tear_down(test_t* test);


#endif /*INE5410_TEST_H_*/

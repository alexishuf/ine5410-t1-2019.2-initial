#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "test.h"

int main(int argc, char** argv) {
    int cycles = 1;
    if (argc < 3) {
        printf("Uso: %s n_threads test [cycles]\n"
               "\n"
               "Onde: \n"
               "    n_threads é o número de threads a serem usadas na simulação\n"
               "    test      é o caminho de um arquivo de testes, como \n"
               "              tests/forever_alone.\n"
               "    cycles    é o número de vezes que cada person_t é re-plugado\n"
               "              após chegar no seu objetivo. O padrão é %d",
               argv[0], cycles);
        return 1;
    }
    int n_threads = atoi(argv[1]);
    if (argc >= 4) 
        cycles = atoi(argv[3]);
    
    test_t test;
    int err = 0;
    if ((err = test_setup(&test, n_threads, argv[2])))
        return err;
    test_run(&test, cycles);
    test_tear_down(&test);
    
    return err;
}

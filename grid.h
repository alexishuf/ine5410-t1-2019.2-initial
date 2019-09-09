#ifndef INE5410_GRID_H_

#include <stddef.h>
#include <semaphore.h>

/* --- --- --- --- forward declarations --- --- --- --- */

struct person_s;
struct grid_s;
typedef struct person_s person_t;
typedef struct grid_s grid_t;

/* --- --- --- --- pos_t  --- --- --- --- */

typedef struct pos_s {
    //  y
    //  ^
    //  |  *  pos_t p = {2, 1}; 
    //  +-------> x    
    int x, y;
} pos_t;

/**
 * Cria um pos_t com o x e y fornecidos.
 */
pos_t mk_pos(int x, int y);

/**
 * Retorna a distancia euclidiana (comprimento da reta ligando as posições)
 * Não considera a existência de obstáculos
 */
double pos_distance(pos_t from, pos_t to);

/**
 * Adiciona dois pos_t. Retorna mk_pos(a.x+b.x, a.y+b.y)
 */
pos_t pos_add(pos_t a, pos_t b);

/**
 * Retorna 1 se a == b ou retorna zero em caso contrário.
 */
int pos_equals(pos_t a, pos_t b);


/* --- --- --- --- grid_t  --- --- --- --- */

typedef struct grid_s {
    void* data;
    int width, height;
} grid_t;

/**
 * Inicializa um grid com largura width e altura height.

 * Posições com x ou y negativos, assim como posições com x > width ou y >
 * height são consideradas inválidas.
 */
void grid_init(grid_t* grid, int width, int height);

/**
 * Libera quaisquer recursos alocados por grid_init(grid)
 */
void grid_destroy(grid_t* grid);

/**
 * Retorna 1 se pos é inválida considerando o grid fornecido.
 *
 * Uma posição é inválida se qualquer uma dessas  condições for verdadeira:
 *
 * - pos.x < 0
 * - pos.y < 0
 * - pos.x >= grid->width
 * - pos.y >= grid->height
 *
 * Se grid == NULL, as útilmas duas condições de validade não são
 * avaliadas (considera-se um grid infinito).
 */
int grid_isvalid(grid_t* grid, pos_t pos);

#define GRID_OBJ_EMPTY     0 ///< célula vazia
#define GRID_OBJ_PERSON    1 ///< há um person_t* na célula
#define GRID_OBJ_OBSTACLE  2 ///< há um obstáculo na célula
#define GRID_OBJ_INVALID  -1 ///< posição está fora dos limites do grid

#define GRID_OBJ__MIN -1
#define GRID_OBJ__MAX  3

/**
 * Obtem o objeto na posição indicada do grid. Se o objeto é um person_t*,
 * coloca o ponteiro em *out_person. Para os demais casos, out_person NÃO 
 * é alterado. O retorno da função é um valor GRID_OBJ_* e indica o que há 
 * na posição.
 *
 * Precondições:
 * - grid != NULL                        [SIGSEGV se violada]
 * - pos está dentro dos limites do grid [retorna GRID_OBJ_INVALID se violada]
 *
 * Efeitos (se as precondições forem satisfeitas):
 * - *out_person != NULL, se grid_person != NULL e o retorno for GRID_OBJ_PERSON
 * - *out_person inalterado se retorno != GRID_OBJ_PERSON
 * 
 * Exemplo para obter a pessao na célula (2, 1):
 *
 *     person_t* p = &smith;
 *     grid_set(mk_pos(2, 1), &neo);
 *     if (grid_get(mk_pos(2, 1), &p) == GRID_OBJ_PERSON) {
 *         //p == &neo
 *     } else  {
 *         //p == &smith (permanece inalterado -- não há pessoa)
 *     }
 */
int grid_get(grid_t* grid, pos_t pos, person_t** out_person);

/**
 * Define o conteúdo da célula indicada pela posição fornecida. Retorna o tipo
 * de objeto que até então estava na célula.
 *
 * Precondições:
 * - grid != NULL             [SIGSEGV se violada]
 * - type != GRID_OBJ_PERSON  [abort() se violada]
 * - type != GRID_OBJ_INVALID [abort() se violada]
 * - grid_isvalid(pos)        [retorna GRID_OBJ_INVALID se violada]
 *
 * Efeito (se precondições forem respeitadas):
 * - grid_get(pos, &person_ptr) == type
 */
int grid_set(grid_t* grid, pos_t pos, int type);

/**
 * Define que a pessoa fornecida está na célula identificada pela posição. Retorna o tipo
 * de objeto que até então estava na célula ou GRID_OBJ_INVALID se a posição
 * está fora dos limites do grid.
 *
 * Precondições:
 * - grid != NULL [SIGSEGV se violada]
 * - person != NULL [abort() se violada]
 * - pos é válida [retorna GRID_OBJ_INVALIDse violada]
 *
 * Efeito (se pré-condições forem respeitadas):
 * - grid_get(pos, &person_ptr) == GRID_OBJ_PERSON && person_ptr == person
 */
int grid_set_person(grid_t* grid, pos_t pos, person_t* person);

/**
 * Lista de 8 offsets que permitem computar os 8 vizinhos de um
 * ponto. Veja um exemplo de uso em person_next_pos(), definida no
 * grid.c
 */
#define GRID_NEIGHBOR_COUNT 8
extern pos_t grid_neighbor_offsets[GRID_NEIGHBOR_COUNT];

/* --- --- --- --- person_t  --- --- --- --- */

typedef struct person_s {
    int    id;
    pos_t  current_pos;
    pos_t  goal_pos;
    size_t time, last_move;
    // Talvez falte algo aqui...
} person_t;

/**
 * Inicializa o person_t apontado por person
 */
void person_init(person_t* person, int id);
/**
 * Destrói quaisquer recursos que person_init(person) tenha alocado
 */
void person_destroy(person_t* person);

/**
 * Bloqueia até que essa pessoa chegue na sua posição objetivo
 */
void person_join(person_t* person);

/**
 * Calcula a próxima posição da pessoa para que ela atinja seu objetivo dentro
 * do grid fornecido.
 */
pos_t person_next_pos(person_t* person, grid_t* grid);


#endif /*INE5410_GRID_H_*/


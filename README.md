# Normalizador Estadístico Vectorizado (x86-64 NASM + C)

Implementación y evaluación cuantitativa de rendimiento entre una solución escalar (SSE) y una vectorial (AVX2 de 256 bits) para cálculo de descriptores estadísticos y normalización $z$-score.

> **Documentación Completa:** El informe técnico formal, análisis microarquitectónico, benchmarks y diagramas se encuentran en [`Informe_Arquitectura_de_Computadores_1.pdf`](Informe_Arquitectura_de_Computadores_1.pdf) y [`PDF de Diagramas.pdf`](PDF%20de%20Diagramas.pdf).

---

## 1. Compilación

### Automática (Makefile)
```bash
make clean
make
```

### Manual desde consola (Paso a paso)
```bash
mkdir -p obj bin data

# Compilar capa C (driver)
gcc -std=gnu11 -Wall -Wextra -O2 -g -Iinclude -c src/driver.c -o obj/driver.o

# Compilar y enlazar versión Escalar
nasm -f elf64 -g -F dwarf asm/scalar/stats_scalar.asm -o obj/stats_scalar.o
gcc -std=gnu11 -O2 -g -o bin/norm_scalar obj/driver.o obj/stats_scalar.o -lm

# Compilar y enlazar versión Vectorial (AVX2)
nasm -f elf64 -g -F dwarf asm/vector/stats_vector.asm -o obj/stats_vector.o
gcc -std=gnu11 -O2 -g -o bin/norm_vector obj/driver.o obj/stats_vector.o -lm
```

---

## 2. Ejecución y Pruebas con Python

### Suite completa de pruebas (Verificación automática de casos borde)
```bash
python3 tools/run_all_tests.py
```

### Flujo manual con scripts de apoyo
```bash
# 1. Generar datos de prueba (N=1000, modo aleatorio)
python3 tools/gen_input.py 1000 data/input.dat random

# 2. Ejecutar kernels (ej: 10 repeticiones)
./bin/norm_scalar data/input.dat data/out_scalar.dat 10
./bin/norm_vector data/input.dat data/out_vector.dat 10

# 3. Validar correctud contra referencia matemática en Python
python3 tools/verify_reference.py data/input.dat data/out_vector.dat.stats.txt 1e-4

# 4. (Opcional) Ejecutar batería de benchmarks y gráficos de speedup
python3 tools/run_benchmarks.py
```

---

## 3. Depuración e Inspección con GDB

### Ejecución automatizada (auditoría de registros YMM y memoria)
```bash
gdb -q -x tools/gdb_session.gdb
```

### Ejecución interactiva en consola
```bash
gdb ./bin/norm_vector
(gdb) break normalize_array
(gdb) run data/test_16.dat data/out_vec_16.dat 1
(gdb) print $ymm0.v8_float
(gdb) stepi
(gdb) x/8fw out
(gdb) continue
(gdb) quit
```

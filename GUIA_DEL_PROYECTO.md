# 📖 GUÍA COMPLETA DEL PROYECTO: NORMALIZADOR ESTADÍSTICO VECTORIZADO
> **Explicación desde cero para entender qué hace cada archivo, cómo se conectan entre sí y por qué existen.**

---

## 🌟 1. La Gran Idea del Proyecto (Explicación sin tecnicismos)

Imagina que trabajas en una fábrica con sensores de temperatura o en un hospital analizando pulsos cardíacos. Tienes una lista gigante de **millones de números**. Con esos números necesitas hacer dos cosas:

1. **Sacar estadísticas básicas:**
   - La **suma** de todos los números.
   - El **promedio (media $\mu$):** cuál es el valor típico.
   - El número **mínimo** y el **máximo**.
   - La **varianza ($\sigma^2$) y desviación estándar ($\sigma$):** qué tan dispersos o locos están los datos respecto al promedio.

2. **Normalizar los datos (Calcular el *Z-score*):**
   - Transformar cada número para que la nueva lista tenga un promedio de $0$. Esto sirve para comparar señales o mediciones en una misma escala justa. La fórmula matemática es:
     $$\text{Nuevo Número} = \frac{\text{Número Original} - \text{Promedio}}{\text{Desviación Estándar}}$$

### ¿Por qué hay dos formas de resolverlo (Escalar vs. Vectorial)?

El procesador de tu computadora puede trabajar de dos maneras:
- **Modo Escalar (Cajero tradicional):** Atiende los datos **uno por uno**. Toma el dato 1, lo suma, luego el dato 2, luego el dato 3...
- **Modo Vectorial / SIMD (Cajero con escáner múltiple):** Gracias a una tecnología llamada **AVX2**, el procesador tiene "brazos anchos" que pueden agarrar y calcular **8 números al mismo tiempo** en un solo latido del reloj de la computadora.

**El objetivo central del proyecto:** Construir ambas soluciones desde cero, medir cuántas veces más rápido es procesar de 8 en 8 frente a 1 en 1 (*Speedup*), y verificar que las matemáticas den exactamente el mismo resultado.

---

## 🗺️ 2. Mapa de Conexión entre Archivos

Así viajan los datos a través del proyecto:

```
[1. tools/gen_input.py] ──(Crea datos aleatorios)──> [data/input.dat]
                                                             │
                                                             ▼
                                                    [src/driver.c] (El Director de Orquesta)
                                                             │
                    ┌────────────────────────────────────────┴────────────────────────────────────────┐
                    ▼                                                                                 ▼
      [asm/scalar/stats_scalar.asm]                                                     [asm/vector/stats_vector.asm]
       (Cálculo 1 a 1: Modo Escalar)                                                     (Cálculo de 8 en 8: Modo AVX2)
                    │                                                                                 │
                    ▼                                                                                 ▼
        [data/output_scalar.dat]                                                          [data/output_vector.dat]
        [data/output_scalar.dat.stats.txt]                                                [data/output_vector.dat.stats.txt]
                    │                                                                                 │
                    └────────────────────────────────────────┬────────────────────────────────────────┘
                                                             ▼
                                                [tools/verify_reference.py]
                                              (El Juez: Comprueba que no haya errores)
```

---

## 📁 3. Ficha Detallada de Cada Archivo

A continuación se detalla cada componente del proyecto respondiendo a:
- ¿Qué es?
- ¿Para qué sirve?
- Lenguaje
- ¿Con qué se conecta?
- ¿Cómo funciona por dentro?
- ¿Qué genera y cómo lo genera?

---

### 1. `Makefile` (El Automatizador de Construcción)
- **¿Qué es?** Es el recetario de cocina del proyecto. Le dice a la computadora cómo transformar todos los textos de código en programas ejecutables.
- **¿Para qué sirve?** Para que no tengas que escribir comandos largos y difíciles en la consola cada vez que cambias una línea de código. Solo escribes `make` y él hace todo.
- **Lenguaje:** Sintaxis de GNU Make / Bash.
- **¿Con qué se conecta?**
  - Con el compilador **GCC** (para compilar C).
  - Con el ensamblador **NASM** (para compilar los archivos `.asm`).
  - Con `src/driver.c`, `asm/scalar/stats_scalar.asm`, y `asm/vector/stats_vector.asm`.
- **¿Cómo funciona por dentro?**
  1. Revisa qué archivos cambiaron recientemente.
  2. Llama a `nasm` para convertir `stats_scalar.asm` en `obj/stats_scalar.o`.
  3. Llama a `nasm` para convertir `stats_vector.asm` en `obj/stats_vector.o`.
  4. Llama a `gcc` para compilar `src/driver.c` en `obj/driver.o`.
  5. Une (*linkea*) el driver con el código escalar y crea el ejecutable `bin/norm_scalar`.
  6. Une el driver con el código vectorial y crea el ejecutable `bin/norm_vector`.
- **¿Qué genera y cómo?** Genera la carpeta `bin/` con dos programas listos para hacer doble clic o ejecutar por terminal: `norm_scalar` y `norm_vector`.

---

### 2. `include/stats.h` (El Contrato o Puente de Comunicación)
- **¿Qué es?** Es un archivo de cabecera (*header*). Funciona como un contrato legal entre el lenguaje C y el lenguaje Ensamblador.
- **¿Para qué sirve?** El programa en C necesita llamar a funciones que están escritas en ensamblador (`sum_array`, `compute_stats`, `normalize_array`). `stats.h` le avisa a C: *"Oye C, estas 3 funciones existen, reciben estos datos y devuelven estos resultados"*.
- **Lenguaje:** C (Header C99/GNU11).
- **¿Con qué se conecta?**
  - Con `src/driver.c` (C lo incluye al inicio).
  - Con los dos archivos de ensamblador (`stats_scalar.asm` y `stats_vector.asm`), los cuales deben respetar obligatoriamente las firmas aquí descritas.
- **¿Cómo funciona por dentro?**
  Declara formalmente 3 funciones:
  1. `float sum_array(const float *arr, int n);`
  2. `void compute_stats(const float *arr, int n, float *mean, float *var, float *min, float *max);`
  3. `void normalize_array(const float *in, float *out, int n, float mean, float stddev);`
- **¿Qué genera y cómo?** No genera archivos físicos por sí mismo; proporciona las reglas de tipos para que el compilador sepa conectar C con Ensamblador sin confusiones de memoria.

---

### 3. `src/driver.c` (El Director de Orquesta)
- **¿Qué es?** Es el programa principal (*main*). Se encarga de toda la logística: abrir archivos, pedir memoria a la computadora, medir el tiempo con cronómetro de alta precisión y guardar los resultados.
- **¿Para qué sirve?** En el procesador es muy tedioso abrir archivos o imprimir en pantalla usando ensamblador puro. Por eso, C se encarga de la "oficina y administración", mientras que el ensamblador se encarga de la "fuerza bruta de cálculo".
- **Lenguaje:** C (C11).
- **¿Con qué se conecta?**
  - Lee los archivos generados por `tools/gen_input.py` (ej. `input.dat`).
  - Llama a las funciones de `stats_scalar.asm` o `stats_vector.asm`.
  - Genera los archivos de salida `output.dat` y `output.dat.stats.txt`.
- **¿Cómo funciona por dentro paso a paso?**
  1. **Lectura:** Abre `input.dat`, lee el número $N$ y luego lee los $N$ números flotantes.
  2. **Memoria Especial (`aligned_alloc`):** Pide memoria RAM alineada a múltiplos exactos de 32 bytes (requisito obligatorio para que las instrucciones rápidas AVX2 no exploten con un error de segmentación).
  3. **Cronómetro doble:**
     - Activa un cronómetro de milisegundos con `clock_gettime`.
     - Activa un contador de ciclos internos de reloj del CPU con `__rdtsc`.
  4. **Ejecución repetida:** Corre los cálculos varias veces (por ejemplo 30 veces) para sacar un promedio de tiempo real sin fluctuaciones.
  5. **Muestra y guarda:** Imprime en pantalla las estadísticas y crea el archivo binario normalizado.
- **¿Qué genera y cómo?**
  - Muestra una tabla en pantalla con $N$, suma, media, varianza, desviación estándar, mínimo, máximo, tiempo en milisegundos y ciclos de CPU.
  - Genera `output.dat` (archivo binario con los datos normalizados).
  - Genera `output.dat.stats.txt` (resumen en texto plano para que sea fácil de leer por otros programas).

---

### 4. `asm/scalar/stats_scalar.asm` (El Obrero Tradicional - Escalar)
- **¿Qué es?** Es el código que realiza las operaciones matemáticas usando el método tradicional de un solo número a la vez.
- **¿Para qué sirve?** Sirve como la versión de control y referencia para demostrar cuánto tarda una computadora cuando calcula elemento por elemento.
- **Lenguaje:** Ensamblador x86-64 (Sintaxis NASM) usando instrucciones SSE escalares.
- **¿Con qué se conecta?** Es llamado directamente desde `driver.c` cuando ejecutamos `bin/norm_scalar`.
- **¿Cómo funciona por dentro?**
  - `sum_array`: Usa `movss` para cargar 1 número en el registro `XMM1` y `addss` para sumarlo a un acumulador `XMM0`. Repite esto $N$ veces.
  - `compute_stats`:
    1. Recorre la lista de inicio a fin para calcular la suma total, y con `minss`/`maxss` va recordando el número más pequeño y más grande visto hasta el momento.
    2. Divide la suma entre $N$ usando `divss` para obtener el promedio ($\mu$).
    3. Hace un segundo recorrido calculando $(x_i - \mu)^2$ con `subss` y `mulss` y los acumula para obtener la varianza ($\sigma^2$).
  - `normalize_array`: Para cada dato hace $(x_i - \mu) \times \frac{1}{\sigma}$ y lo escribe en la memoria de salida. Si $\sigma = 0$ (todos los números eran iguales), copia los números tal cual para evitar dividir entre cero.
- **¿Qué genera y cómo?** Escribe los resultados numéricos directamente en los registros del procesador (`XMM0`) y en las direcciones de memoria RAM que le indicó `driver.c`.

---

### 5. `asm/vector/stats_vector.asm` (El Obrero de Alto Rendimiento - AVX2)
- **¿Qué es?** Es el núcleo de máxima velocidad del proyecto. Utiliza extensiones **AVX2**, operando sobre registros ultra anchos de 256 bits llamados `YMM`.
- **¿Para qué sirve?** Para acelerar el cálculo al máximo, procesando 8 números de 32 bits en una sola instrucción de procesador.
- **Lenguaje:** Ensamblador x86-64 con tecnología SIMD AVX2.
- **¿Con qué se conecta?** Es llamado por `driver.c` cuando ejecutamos `bin/norm_vector`.
- **¿Cómo funciona por dentro?**
  1. **Procesamiento de 8 en 8:** En lugar de avanzar de 1 en 1, avanza de 8 en 8 floats (saltos de 32 bytes en memoria). Usa `vmovaps` para cargar 8 números de un solo golpe a `YMM1` y `vaddps` para sumarlos en paralelo.
  2. **Reducción Horizontal:** Al final del bucle, tiene 8 sumas parciales acumuladas en un solo registro ancho. Mediante instrucciones como `vextractf128`, `vaddps` y `vhaddps`, "pliega" los 8 carriles hasta combinarlos en un único número final.
  3. **Manejo del Remanente (*Tail loop*):** Si la cantidad de datos no es múltiplo de 8 (por ejemplo, si hay 15 datos: entran 8 en el primer bloque y sobran 7), los 7 sobrantes son procesados uno a uno en un bucle de cierre para no dejar nada por fuera ni leer memoria prohibida.
  4. **Limpieza (`vzeroupper`):** Antes de terminar, apaga los registros anchos para que la computadora no sufra lentitud al volver al código en C.
- **¿Qué genera y cómo?** Escribe en memoria los mismos resultados matemáticos que la versión escalar, pero gastando hasta **5 a 7 veces menos tiempo de procesador**.

---

### 6. `tools/gen_input.py` (El Generador de Datos de Prueba)
- **¿Qué es?** Un script de Python que crea archivos binarios de prueba con números aleatorios o patrones especiales.
- **¿Para qué sirve?** El programa necesita datos para procesar. Este script fabrica archivos pequeños (para buscar errores) y archivos gigantescos de hasta 50 millones de números (para medir velocidad en la memoria caché).
- **Lenguaje:** Python 3 (con aceleración automática por NumPy si está instalado).
- **¿Con qué se conecta?** Produce los archivos `.dat` que luego lee `driver.c`.
- **¿Cómo funciona por dentro?**
  - Genera números según el modo elegido:
    * `random`: números aleatorios entre -100 y 100.
    * `constant`: llena todo con el número `5.0` (caso crítico donde la varianza es 0).
    * `edge`: mezcla números gigantes ($10^6$), números diminutos ($0.0001$) y negativos.
  - Guarda los datos en formato **binario little-endian**:
    * Primeros 4 bytes: un número entero que indica cuántos elementos hay ($N$).
    * Siguientes $N \times 4$ bytes: la secuencia continua de floats.
- **¿Qué genera y cómo?** Archivos `.dat` en la carpeta `data/`. Por ejemplo:
  - `input.dat` (1,000 datos).
  - `input_large_1m.dat` (1 millón de datos, ~3.8 MB).
  - `input_large_50m.dat` (50 millones de datos, ~190 MB).

---

### 7. `tools/verify_reference.py` (El Auditor / Juez de Correctud)
- **¿Qué es?** Es un script auditor en Python que calcula la "verdad matemática absoluta" y la compara contra los resultados que arrojó nuestro código en C y Ensamblador.
- **¿Para qué sirve?** Para tener la certeza científica de que el programa no inventó números, no hubo errores de redondeo excesivos y no se corrompió la memoria.
- **Lenguaje:** Python 3.
- **¿Con qué se conecta?**
  - Lee el archivo original de entrada (`input.dat`).
  - Lee el resumen generado por el driver (`output.dat.stats.txt`).
  - Lee el archivo binario resultante (`output.dat`).
- **¿Cómo funciona por dentro?**
  1. Lee los números de entrada y calcula con Python la suma, media, varianza, desviación, mínimo y máximo.
  2. Lee los resultados que imprimió nuestro programa en C/Ensamblador.
  3. Calcula el **error relativo** de cada estadística:
     $$\text{Error} = \frac{|\text{Valor Obtenido} - \text{Valor Real}|}{|\text{Valor Real}|}$$
  4. Comprueba que el error sea menor a la tolerancia permitida ($1 \times 10^{-4}$).
  5. Comprueba los datos normalizados número por número.
- **¿Qué genera y cómo?** Muestra una tabla comparativa en la consola indicando `OK` en color verde o `FALLA` en rojo para cada métrica, culminando en un veredicto general: `PASA` o `FALLA`.

---

### 8. `README.md` (El Manual de Referencia de la Cátedra)
- **¿Qué es?** El documento base entregado por los profesores con las especificaciones del laboratorio.
- **¿Para qué sirve?** Define los requerimientos del sistema operativo, comandos sugeridos y las pautas para la entrega.
- **Lenguaje:** Markdown (Texto plano estructurado).

---

## ⚙️ 4. El Ciclo Completo de Uso (Paso a Paso)

Si quisieras explicarle a alguien cómo se usa todo el proyecto de principio a fin, son solo 4 órdenes:

### Paso 1: Fabricar los datos
```bash
python3 tools/gen_input.py --all data
```
*(Crea desde casos vacíos $N=0$ hasta pruebas gigantes de $50$ millones de números).*

### Paso 2: Compilar el proyecto
```bash
make
```
*(El `Makefile` orquesta a GCC y NASM para construir los ejecutables).*

### Paso 3: Ejecutar ambas versiones
```bash
# Versión lenta (Escalar):
./bin/norm_scalar data/input.dat data/output_scalar.dat 30

# Versión rápida (Vectorial AVX2):
./bin/norm_vector data/input.dat data/output_vector.dat 30
```
*(El número 30 indica que repetirá la prueba 30 veces para calcular promedios fiables).*

### Paso 4: Auditar que todo esté perfecto
```bash
python3 tools/verify_reference.py data/input.dat data/output_vector.dat.stats.txt
```
*(El script juez certifica que los resultados coincidan al 100% con la verdad matemática).*

---

## 💡 5. Diccionario Rápido de Conceptos Clave

- **Float de 32 bits (Precisión Simple):** Es la forma estándar en que la computadora guarda números con decimales usando exactamente 4 bytes de memoria.
- **Little-Endian:** La forma en que procesadores Intel y AMD ordenan los bytes en la memoria (el byte menos significativo va primero).
- **SIMD (Single Instruction, Multiple Data):** Filosofía donde una sola orden del procesador opera sobre muchos datos a la vez.
- **AVX2:** La tecnología de Intel/AMD que permite hacer operaciones SIMD sobre 256 bits (8 floats a la vez).
- **Alineación a 32 bytes:** Colocar los datos en direcciones de memoria que sean múltiplos de 32 (0, 32, 64, 96...). Si no se hace, la instrucción rápida `vmovaps` falla inmediatamente.
- **Speedup:** Cuántas veces es más rápida una versión que otra. Si la versión escalar tarda $7\text{ ms}$ y la vectorial tarda $1\text{ ms}$, el Speedup es de $7\times$.

# Especificación Técnica y Arquitectura del Normalizador Estadístico Vectorizado

Documento técnico que detalla la fundamentación matemática, el diseño arquitectónico a nivel de hardware/software, el mapeo de registros del procesador y el comportamiento de los componentes del sistema.

## 1. Fundamentación Teórica y Formulación Matemática

El sistema procesa arreglos continuos de datos en punto flotante de precisión simple (estándar IEEE 754, 32 bits por elemento), representados como un vector $\mathbf{X} = \{x_0, x_1, \dots, x_{N-1}\} \in \mathbb{R}^N$. El procesamiento comprende dos etapas: reducción estadística y transformación afín de normalización (*z-score*).

### 1.1 Reducción Estadística Descriptiva

1. **Suma Total ($S$):**
   $$S = \sum_{i=0}^{N-1} x_i$$

2. **Media Aritmética ($\mu$):**
   $$\mu = \frac{S}{N} = \frac{1}{N} \sum_{i=0}^{N-1} x_i$$

3. **Valores Extremos:**
   $$x_{\min} = \min_{0 \le i < N} (x_i), \quad x_{\max} = \max_{0 \le i < N} (x_i)$$

4. **Varianza Poblacional ($\sigma^2$):**
   $$\sigma^2 = \frac{1}{N} \sum_{i=0}^{N-1} (x_i - \mu)^2$$

5. **Desviación Estándar Poblacional ($\sigma$):**
   $$\sigma = \sqrt{\sigma^2}$$

### 1.2 Normalización de Señal (*Z-score*)

Cada elemento $x_i$ es transformado a una escala estándar adimensional centrada en cero con dispersión unitaria:
$$y_i = \frac{x_i - \mu}{\sigma} = (x_i - \mu) \times \frac{1}{\sigma}$$

Condición de frontera singular: Si la señal es homogénea ($x_i = C \ \forall \ i$), se tiene $\sigma^2 = 0 \implies \sigma = 0$. Para evitar la indeterminación por división entre cero o la emisión de valores no numéricos (`NaN`), el sistema aplica:
$$y_i = x_i \quad \text{si} \quad \sigma < 1 \times 10^{-12}$$

## 2. Paradigmas de Ejecución: SISD vs. SIMD

El proyecto compara cuantitativamente dos estrategias de cómputo en el microprocesador x86-64:

### 2.1 Modelo Escalar (SISD - Single Instruction, Single Data)
* Opera sobre registros escalares SSE de 128 bits utilizando únicamente su carril inferior de 32 bits (`XMM0`-`XMM15`).
* Procesa un único elemento por instrucción (`movss`, `addss`, `subss`, `mulss`, `divss`, `minss`, `maxss`).
* Complejidad de instrucciones dependiente linealmente de la cardinalidad de la entrada: $\mathcal{O}(N)$ ciclos de despacho.

### 2.2 Modelo Vectorial (SIMD - Single Instruction, Multiple Data)
* Opera sobre extensiones vectoriales AVX2 con registros anchos de 256 bits (`YMM0`-`YMM15`).
* Procesa simultáneamente paquetes de 8 números float32 por ciclo de instrucción (`vmovaps`, `vaddps`, `vsubps`, `vmulps`, `vminps`, `vmaxps`).
* Reduce la cantidad de iteraciones en el bucle principal en un factor de 8 ($\lfloor N / 8 \rfloor$ iteraciones).
* Requiere dos mecanismos adicionales obligatorios:
  * **Reducción Horizontal:** Fusión intra-registro de los 8 carriles paralelos hacia un único escalar mediante extracción de mitades (`vextractf128`), sumas vectoriales y permutaciones de carril (`vhaddps`, `vshufps`).
  * **Manejo del Remanente (*Tail Loop*):** Procesamiento de los $N \pmod 8$ elementos residuales mediante un bucle de cierre escalar para evitar accesos fuera de los límites de memoria asignada.

## 3. Arquitectura de Software y Flujo de Interconexión

El sistema se basa en una arquitectura modular desacoplada:

```
[ tools/gen_input.py ] ──────────> Genera archivo binario <input.dat>
                                              │
                                              ▼
                                     [ src/driver.c ]
                    (Gestor de E/S, alineación 32B, cronometría de hardware)
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    ▼                                                   ▼
      [ asm/scalar/stats_scalar.asm ]                     [ asm/vector/stats_vector.asm ]
          (Kernel Escalar SISD)                               (Kernel Vectorial AVX2)
                    │                                                   │
                    ▼                                                   ▼
       <output_scalar.dat> (.stats.txt)                    <output_vector.dat> (.stats.txt)
                    │                                                   │
                    └─────────────────────────┬─────────────────────────┘
                                              ▼
                                [ tools/verify_reference.py ]
                              (Auditor numérico de tolerancia)
```

## 4. Descripción Técnica Detallada de Módulos

### 4.1 `Makefile`
* **Definición:** Script de construcción determinista para entornos GNU Make.
* **Función:** Compila el driver en C mediante `gcc` y los núcleos en ensamblador mediante `nasm`, generando los binarios `bin/norm_scalar` y `bin/norm_vector`.
* **Banderas de compilación:**
  * C: `-std=gnu11 -Wall -Wextra -O2 -g -Iinclude`.
  * NASM: `-f elf64 -g -F dwarf` (generación de símbolos de depuración DWARF para GDB).
  * Enlazador: `-lm` (enlace con la biblioteca matemática estándar).

### 4.2 `include/stats.h`
* **Definición:** Archivo de cabecera que estipula la interfaz binaria de funciones entre C y Ensamblador.
* **Función:** Define el contrato formal de los kernels bajo la convención System V AMD64 ABI:

| Función | Argumentos de Entrada | Retorno / Salidas en Memoria |
| :--- | :--- | :--- |
| `sum_array` | `rdi`: `const float *arr`, `esi`: `int n` | `xmm0`: Suma acumulada $S$ |
| `compute_stats` | `rdi`: `arr`, `esi`: `n`, `rdx`: `mean*`, `rcx`: `var*`, `r8`: `min*`, `r9`: `max*` | `[rdx]`: $\mu$, `[rcx]`: $\sigma^2$, `[r8]`: $x_{\min}$, `[r9]`: $x_{\max}$ |
| `normalize_array` | `rdi`: `in*`, `rsi`: `out*`, `edx`: `n`, `xmm0`: $\mu$, `xmm1`: $\sigma$ | Arreglo `out` escrito en memoria |

### 4.3 `src/driver.c`
* **Definición:** Punto de entrada del programa ejecutable implementado en C11.
* **Funciones asignadas:**
  1. Lectura del archivo binario de entrada (`read_input`).
  2. Reserva de memoria dinámica alineada a límites de 32 bytes (`aligned_alloc(32, bytes_redondeados)`) para habilitar transferencias alineadas `vmovaps`.
  3. Medición precisa del tiempo de pared mediante llamadas directas a `clock_gettime(CLOCK_MONOTONIC)` circundando únicamente los llamados a los kernels.
  4. Contabilización de ciclos de CPU mediante el registro de reloj de hardware `__rdtsc()` con serialización de pipeline mediante `_mm_lfence()`.
  5. Ejecución iterativa para cómputo de media y desviación estándar de tiempos ($\text{avg\_ms} \pm \text{std\_ms}$).
  6. Volcado del arreglo normalizado resultante a archivo binario de salida y serialización de parámetros métricos a `<salida>.stats.txt`.

### 4.4 `asm/scalar/stats_scalar.asm`
* **Definición:** Implementación en ensamblador x86-64 puro de los kernels bajo modelo escalar.
* **Detalle algorítmico:**
  * `sum_array`: Inicializa `xmm0` en $0.0$; itera de uno en uno acumulando con `addss`.
  * `compute_stats`: Preserva los registros no volátiles `rbx`, `rbp`, `r12`-`r15`. Ejecuta la primera pasada determinando suma total y actualizando extremos con `minss` y `maxss`. Calcula $\mu = S / n$ (`divss`). En la segunda pasada acumula $(x_i - \mu)^2$ mediante `subss`, `mulss` y `addss`, computando finalmente $\sigma^2 = \text{acumulador} / n$.
  * `normalize_array`: Precalcula el factor inverso de escala $\frac{1}{\sigma}$ con `divss`. Transforma cada celda mediante `mulss` para minimizar la latencia frente a divisiones repetitivas. Si $\sigma < 1 \times 10^{-12}$, transfiere los elementos de entrada a la salida de forma directa.

### 4.5 `asm/vector/stats_vector.asm`
* **Definición:** Implementación en ensamblador x86-64 utilizando el repertorio de instrucciones AVX2.
* **Detalle algorítmico:**
  * `sum_array`: Limpia el acumulador vectorial `ymm0` mediante `vxorps`. Procesa bloques contiguos de 8 floats alineados (`vmovaps`), acumulando con `vaddps`. Extrae los 128 bits superiores con `vextractf128`, combina mediante `vaddps` y realiza reducción intra-registro mediante pares sucesivos de `vhaddps`. Los elementos residuales se computan escalarmente en el bucle *tail*. Finaliza con `vzeroupper` para evitar penalizaciones de transición de estado.
  * `compute_stats`: En la primera pasada replica $x_0$ mediante `vbroadcastss` en `ymm4` (mínimo) y `ymm5` (máximo). Procesa de 8 en 8 floats ejecutando `vaddps`, `vminps` y `vmaxps` en paralelo. Ejecuta reducciones horizontales diferenciadas para suma (`vhaddps`) y extremos (`vminps`/`vmaxps` con permutaciones de canal `vshufps`). En la segunda pasada replica la media calculada $\mu$ sobre los 8 carriles con `vbroadcastss ymm7, xmm0` y calcula en paralelo 8 residuos cuadráticos simultáneos (`vsubps` y `vmulps`).
  * `normalize_array`: Efectúa broadcast de $\mu$ (`ymm7`) y del factor $\frac{1}{\sigma}$ (`ymm8`). Aplica sustracción y escalamiento empaquetado (`vsubps`, `vmulps`) con transferencias alineadas de lectura y escritura (`vmovaps`).
* **Mapeo de Registros en Kernel Vectorial:**

| Etapa | Registro | Contenido / Función Técnica |
| :--- | :--- | :--- |
| Pasada 1 | `ymm0` | 8 acumuladores paralelos de suma total |
| Pasada 1 | `ymm4` | 8 acumuladores de mínimos parciales |
| Pasada 1 | `ymm5` | 8 acumuladores de máximos parciales |
| Pasada 2 | `ymm7` | Réplica escalar de la media: $[\mu, \mu, \mu, \mu, \mu, \mu, \mu, \mu]$ |
| Pasada 2 | `ymm3` | 8 acumuladores paralelos de diferencias cuadráticas |
| Pasada 2 | `ymm6` | Buffer temporal de diferencias $(x_i - \mu)$ y cuadrados $(x_i - \mu)^2$ |
| Normalización | `ymm8` | Réplica del factor inverso: $[\frac{1}{\sigma}, \frac{1}{\sigma}, \dots, \frac{1}{\sigma}]$ |

### 4.6 `tools/gen_input.py`
* **Definición:** Script de soporte para sintetizar archivos binarios de entrada conforme a la especificación de diseño.
* **Formato binario estructurado (Little-Endian):**
  * Bytes $[0, 3]$: Entero con signo de 32 bits (`int32_t`) correspondiente a la longitud $N$.
  * Bytes $[4, 4 + 4N - 1]$: Secuencia contigua de $N$ flotantes IEEE 754 de 32 bits (`float32`).
* **Modos de generación:**
  * `random`: Distribución uniforme continua en el intervalo $[-100.0, 100.0]$.
  * `constant`: Matriz homogénea con valor fijado en $5.0$ ($\sigma^2 = 0$, prueba de singularidad).
  * `edge`: Secuencia de alternancia con valores numéricos críticos ($\pm 1 \times 10^6, 0.0, \pm 1 \times 10^{-4}, \pm 1.0$).

### 4.7 `tools/verify_reference.py`
* **Definición:** Validador formal de exactitud computacional.
* **Procedimiento:** Carga el archivo binario original, calcula las referencias estadísticas empleando aritmética de 64 bits (`float64`) en Python, lee los resultados reportados en `<output>.stats.txt` y calcula el error relativo de cada campo:
  $$\text{Error Relativo} = \frac{|\text{Valor}_{\text{obtenido}} - \text{Valor}_{\text{referencia}}|}{\max(|\text{Valor}_{\text{referencia}}|, 1 \times 10^{-12})}$$
  Adicionalmente, valida la concordancia celda por celda del archivo binario de salida normalizado. Emite código de salida $0$ (`PASA`) si todos los parámetros cumplen $\text{Error Relativo} \le 1 \times 10^{-4}$, o código $1$ (`FALLA`) en caso contrario.

## 5. Métrica de Desempeño: Factor de Aceleración (*Speedup*)

La eficiencia relativa del cómputo vectorizado se cuantifica mediante la relación de tiempo de ejecución del kernel:

$$\text{Speedup} = \frac{T_{\text{escalar}}}{T_{\text{vectorial}}}$$

Comportamiento esperado según la jerarquía de memoria y dimensión de la entrada ($N$):
* **Régimen de sobrecosto ($N < 16$):** $\text{Speedup} \le 1.0\times$ producto de la latencia fija en las reducciones horizontales y transiciones de pipeline frente a un bucle escalar directo.
* **Régimen de cómputo en caché L1/L2 ($10^3 \le N \le 10^5$):** $\text{Speedup} \in [6.5\times, 7.6\times]$, próximo al límite asintótico teórico de AVX2 ($8.0\times$ para datos de 32 bits).
* **Régimen dominado por ancho de banda de memoria DRAM ($N \ge 10^6$):** $\text{Speedup} \in [3.5\times, 5.5\times]$, donde el cuello de botella se traslada de la tasa de ejecución de la ALU vectorial hacia la saturación del bus de memoria principal.

# 8. Conclusiones, limitaciones y trabajo futuro

## 8.1 Conclusiones

1. **Validación empírica del paralelismo SIMD AVX2:**
   - La implementación en ensamblador NASM x86-64 explotando registros `ymm` de 256 bits demostró una aceleración de **hasta $5.80\times$** frente a la versión escalar SISD sobre conjuntos de datos residentes en caché ($N = 10^5$), alcanzando el **$72.5\%$ de la eficiencia teórica máxima** ($8.0\times$).
   - A nivel microarquitectónico, el motor vectorial redujo el volumen total de instrucciones ejecutadas en **$7.19\times$** y la tasa de fallos de caché a solo $8.80\%$, manteniendo una fidelidad numérica absoluta con error residual acotado ($| \text{diff} | < 1.19 \times 10^{-6}$).

2. **Impacto de la jerarquía de memoria y el *Memory Wall*:**
   - Se evidenció cuantitativamente la transición entre dos regímenes operativos:
     - **Régimen *Compute-Bound* ($N \le 10^6$):** Operando dentro de las cachés L1/L2/L3, el datapath vectorial procesa datos a máxima tasa de transferencia, sosteniendo un speedup de entre $4.90\times$ y $5.80\times$.
     - **Régimen *Memory-Bound* ($N = 20 \times 10^6$):** Al desbordar la capacidad de la caché L3 ($\sim 80\text{ MB}$ requeridos frente a los $10\text{ MB}$ de L3 física), la tasa de fallos de caché escaló al **$91.22\%$**. El ancho de banda del bus DRAM saturó la tasa de entrega de operandos, reduciendo el speedup a **$2.44\times$**.

> [CAPTURA: Consola de 'perf stat' contrastando métricas de fallos de caché entre N=10^5 (Compute-Bound, 8.8% miss rate) y N=20M (Memory-Bound, 91.2% miss rate)]

3. **Restricción asintótica por Ley de Amdahl:**
   - En conjuntos de datos reducidos ($N \le 10^3$), la ganancia se ve estrictamente acotada por la fracción secuencial obligatoria ($s$):
     $$S = \frac{1}{s + \frac{1-s}{p}}$$
   - Dicha fracción comprende el prólogo/epílogo del protocolo de llamadas C, el cálculo escalar de raíces cuadradas y divisiones de descriptores (`vsqrtss`, `vdivss`), la reducción horizontal en árbol (`vextractf128`, `vhaddps`) y el procesamiento del remanente (*tail loop*).

4. **Robustez e integridad en bajo nivel:**
   - Se garantizó la estabilidad del sistema mediante el cumplimiento riguroso de la convención de llamadas System V AMD64 ABI (preservación de `rbx`, `r12`–`r15`), el alineamiento estricto a 32 bytes (`aligned_alloc(32, ...)`) para eludir fallos de protección general `#GP(0)` al ejecutar `vmovaps`, y el uso sistemático de `vzeroupper` en cada epílogo para neutralizar penalizaciones por cambio de estado AVX-SSE ($\sim 70$ ciclos).

---

## 8.2 Limitaciones observadas

1. **Cuello de botella en el ancho de banda del canal DRAM:**
   - La capacidad de cómputo pico de las unidades vectoriales AVX2 excede el ancho de banda suministrado por la controladora de memoria principal DDR4/DDR5 en configuraciones monohilo. Al procesar arreglos masivos ($N \ge 20 \times 10^6$), las unidades de cómputo FPU permanecen la mayor parte del tiempo ociosas (*pipeline stalls*) esperando la llegada de líneas de caché de 64 bytes desde la memoria principal.

2. **Restricción a ejecución monohilo (Carencia de paralelismo TLP):**
   - El sistema opera exclusivamente sobre un único hilo de ejecución. A pesar de maximizar el paralelismo de datos (DLP) dentro de un núcleo físico, no explota el paralelismo a nivel de hilos (*Thread-Level Parallelism* - TLP) inherente a microarquitecturas multinúcleo contemporáneas, desaprovechando los núcleos lógicos restantes del procesador.

---

## 8.3 Trabajo futuro

1. **Fusión de instrucciones con FMA3 (`vfmadd231ps`):**
   - En el cálculo de la varianza $\sum (x_i - \mu)^2$, reemplazar la secuencia de resta, multiplicación y suma separadas por la instrucción FMA3:
   ```nasm
   ; Reemplazo en el bucle principal de varianza:
   vsubps      ymm2, ymm0, ymm4         ; ymm2 = x_i - mu
   vfmadd231ps ymm1, ymm2, ymm2         ; ymm1 = ymm1 + (ymm2 * ymm2) en una sola micro-op
   ```
   - **Impacto:** Reduce la presión sobre el decodificador de instrucciones, elimina un ciclo de latencia en la tubería y suprime un paso de redondeo intermedio IEEE 754.

2. **Desenrollado de bucles (*Loop Unrolling* 2x/4x) con múltiples acumuladores:**
   - Intercalar operaciones sobre múltiples registros vectoriales independientes (`ymm0`–`ymm3` para carga y `ymm8`–`ymm11` como acumuladores) para procesar 16 o 32 floats por iteración:
   ```nasm
   ; Desenrollado 2x con acumuladores independientes (ocultamiento de latencia RAW)
   vmovaps     ymm0, [rdi + rax*4]      ; Bloque A (8 floats)
   vmovaps     ymm1, [rdi + rax*4 + 32] ; Bloque B (8 floats)
   vaddps      ymm8, ymm8, ymm0         ; Acumulador A
   vaddps      ymm9, ymm9, ymm1         ; Acumulador B (sin dependencia de ymm8)
   add         rax, 16
   ```
   - **Impacto:** Rompe las cadenas de dependencia de datos (*Read-After-Write*), permitiendo a la lógica *Out-of-Order* de la CPU saturar simultáneamente los puertos de ejecución 0 y 1.

3. **Instrucciones de almacenamiento sin asignación temporal (*Non-Temporal Stores*):**
   - Sustituir `vmovaps` por `vmovntps` en la fase de escritura del arreglo normalizado `out`:
   ```nasm
   vmovntps    [rsi + rax*4], ymm0      ; Escritura directa a DRAM eludiendo caché L3
   ```
   - **Impacto:** Evita contaminar la caché L3 con datos que no serán reutilizados de inmediato y suprime el tráfico del bus asociado al protocolo de lectura previa de línea (*Read-For-Ownership* - RFO), mitigando directamente el impacto del *Memory Wall*.

4. **Paralelismo multinúcleo híbrido (SIMD + OpenMP / Pthreads):**
   - Integrar una partición de dominios a nivel de software donde el arreglo se divide en bloques contiguos alineados a 32 bytes asignados a múltiples hilos de hardware:
   ```c
   #pragma omp parallel for schedule(static)
   for (size_t chunk = 0; chunk < n_threads; ++chunk) {
       // Cada hilo invoca el kernel AVX2 sobre su porción local del vector
   }
   ```
   - **Impacto:** Combina el paralelismo a nivel de datos (DLP, factor $8\times$) con el paralelismo a nivel de hilos (TLP, factor $N_{\text{cores}}\times$), superando las restricciones impuestas por la ejecución monohilo.

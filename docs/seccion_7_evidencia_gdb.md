# 7. Evidencia de la sesión de GDB

## 7.1. Propósito técnico y microarquitectónico (OA5)

Esta sesión de depuración en bajo nivel mediante GNU GDB audita en tiempo de ejecución el cumplimiento de la convención de llamadas System V AMD64 ABI, contrasta microarquitectónicamente el datapath escalar SISD (operación sobre 1 float de 32 bits en el carril inferior de `xmm3`) frente al datapath vectorial SIMD AVX2 (operación paralela sobre 8 floats en `ymm0`), valida la alineación física estricta a 32 bytes en memoria requerida por `vmovaps`, y certifica la convergencia numérica bit a bit entre ambas implementaciones procesando el caso de prueba $N = 16$ (`tc-06_in.dat`).

---

## 7.2. Secuencia de comandos y justificación de breakpoints

### 7.2.1. Kernel Escalar (`bin/norm_scalar`)
* **Paso 1 (Carga y argumentos):** `set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_sc_out.dat 1` — Carga el archivo de entrada con $N = 16$ floats y define 1 iteración para aislar el flujo de control.
* **Breakpoint 1 (`asm/scalar/stats_scalar.asm:167`):** Entrada a `normalize_array` (`test edx, edx`).
  * *Justificación:* Auditar la recepción de punteros de memoria en registros enteros (`rdi = in`, `rsi = out`, `edx = n = 16`) y parámetros escalares de coma flotante en `xmm0` (media $\mu = -5.637640$) y `xmm1` (desviación estándar $\sigma = 48.620003$).
* **Breakpoint 2 (`asm/scalar/stats_scalar.asm:184`):** Dentro del bucle `.norm_loop`, inmediatamente tras `divss xmm3, xmm1`.
  * *Justificación:* Verificar el procesamiento escalar estricto: un único float activo en `xmm3.v4_float[0]`, mientras el registro índice `eax` avanza de 1 en 1 ($\Delta \text{offset} = 4\text{ bytes}$).
* **Paso de salida:** Comandos `delete 2` (evita detenerse en las 16 repeticiones del bucle) y `finish` (ejecuta hasta retornar al marco llamador en `src/driver.c:140`).
* **Inspección de memoria:** Comandos `print (void*)out` y `x/8fw out` para examinar el volcado secuencial del búfer normalizado.

### 7.2.2. Kernel Vectorial (`bin/norm_vector`)
* **Paso 1 (Carga y argumentos):** `set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_vc_out.dat 1` — Mismo vector de entrada de $N = 16$ floats para contraste directo.
* **Breakpoint 1 (`asm/vector/stats_vector.asm:248`):** Entrada a `normalize_array` (`test edx, edx`).
  * *Justificación:* Verificar parámetros recibidos antes de la replicación (*broadcast*) de $\mu$ y $\sigma$ a los 8 carriles mediante `vbroadcastss ymm4, xmm0` y `vbroadcastss ymm5, xmm1`.
* **Breakpoint 2 (`asm/vector/stats_vector.asm:271`):** Dentro de `.norm_vec_loop`, tras la instrucción `vdivps ymm0, ymm0, ymm5`.
  * *Justificación:* Capturar el registro `ymm0` conteniendo simultáneamente los 8 floats calculados en una sola instrucción SIMD, con avance de 8 en 8 elementos ($\Delta \text{offset} = 32\text{ bytes}$ vía `add eax, 8`).
* **Paso de salida:** Comandos `delete 2` (omite la segunda iteración) y `finish` (retorna a `src/driver.c:140`).
* **Validación de alineación física a 32 bytes e inspección:** Comando `print ((unsigned long)out) % 32` (comprueba módulo 0 para evitar fallos de protección general `#GP(0)` en `vmovaps`) y volcado `x/8fw out`.

---

## 7.3. Transcripciones de depuración (Listado `lst:gdb`)

### 7.3.1. Sesión GDB en Kernel Escalar (`bin/norm_scalar`)

> [CAPTURA ESCALAR: GDB inspeccionando registro xmm3 tras divss con 1 solo float activo en carril 0, eax=0 e inspección x/8fw out tras finish]

```gdb
(gdb) file bin/norm_scalar
Reading symbols from bin/norm_scalar...
(gdb) set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_sc_out.dat 1
(gdb) break asm/scalar/stats_scalar.asm:167
Breakpoint 1 at 0x17c0: file asm/scalar/stats_scalar.asm, line 167.
(gdb) break asm/scalar/stats_scalar.asm:184
Breakpoint 2 at 0x17df: file asm/scalar/stats_scalar.asm, line 184.
(gdb) run
Breakpoint 1, normalize_array () at asm/scalar/stats_scalar.asm:167
167	    test    edx, edx
(gdb) print $xmm0.v4_float
$1 = {-5.63764048, 0, 0, 0}
(gdb) print $xmm1.v4_float
$2 = {48.6200027, 0, 0, 0}
(gdb) continue
Breakpoint 2, normalize_array () at asm/scalar/stats_scalar.asm:184
184	    movss   [rsi + rax*4], xmm3    ; out[i] = xmm3
(gdb) print $xmm3.v4_float
$3 = {0.899751365, 0, 0, 0}
(gdb) print $eax
$4 = 0
(gdb) delete 2
(gdb) finish
Run till exit from #0  normalize_array () at asm/scalar/stats_scalar.asm:184
main (argc=4, argv=0x7fffffffe348) at src/driver.c:140
140	        clock_gettime(CLOCK_MONOTONIC, &t1);
(gdb) print (void*)out
$5 = (void *) 0x555555559520
(gdb) x/8fw out
0x555555559520:	0.899751365	1.82348073	-0.0602805801	-0.851318777
0x555555559530:	-1.11406946	-1.66397166	0.220615491	0.60411936
```

### 7.3.2. Sesión GDB en Kernel Vectorial (`bin/norm_vector`)

> [CAPTURA VECTORIAL: GDB inspeccionando registro ymm0 con 8 floats tras vdivps, verificación de alineación ((unsigned long)out) % 32 == 0 y volcado x/8fw out]

```gdb
(gdb) file bin/norm_vector
Reading symbols from bin/norm_vector...
(gdb) set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_vc_out.dat 1
(gdb) break asm/vector/stats_vector.asm:248
Breakpoint 1 at 0x1b07: file asm/vector/stats_vector.asm, line 248.
(gdb) break asm/vector/stats_vector.asm:271
Breakpoint 2 at 0x1b4b: file asm/vector/stats_vector.asm, line 271.
(gdb) run
Breakpoint 1, normalize_array () at asm/vector/stats_vector.asm:248
248	    test    edx, edx
(gdb) print $ymm0.v8_float
$1 = {-5.63764048, 0, 0, 0, 0, 0, 0, 0}
(gdb) print $ymm1.v8_float
$2 = {48.6200027, 0, 0, 0, 0, 0, 0, 0}
(gdb) continue
Breakpoint 2, normalize_array () at asm/vector/stats_vector.asm:271
271	    vmovaps [rsi + rax*4], ymm0    ; guarda 8 floats alineados
(gdb) print $ymm0.v8_float
$3 = {0.899751365, 1.82348073, -0.0602805801, -0.851318777, -1.11406946, -1.66397166, 0.220615491, 0.60411936}
(gdb) print $eax
$4 = 0
(gdb) delete 2
(gdb) finish
Run till exit from #0  normalize_array () at asm/vector/stats_vector.asm:271
main (argc=4, argv=0x7fffffffe348) at src/driver.c:140
140	        clock_gettime(CLOCK_MONOTONIC, &t1);
(gdb) print (void*)out
$5 = (void *) 0x555555559520
(gdb) print ((unsigned long)out) % 32
$6 = 0
(gdb) x/8fw out
0x555555559520:	0.899751365	1.82348073	-0.0602805801	-0.851318777
0x555555559530:	-1.11406946	-1.66397166	0.220615491	0.60411936
```

---

## 7.4. Tabla comparativa de hallazgos en bajo nivel

| Dimensión Técnica | Kernel Escalar (`bin/norm_scalar`) | Kernel Vectorial (`bin/norm_vector`) | Implicación Microarquitectónica |
| :--- | :--- | :--- | :--- |
| **Paradigma ISA** | SISD (SSE escalar) | SIMD (AVX2 empaquetado) | Paralelismo de datos a nivel de instrucción ($8\times$). |
| **Registro de datos** | `xmm3` (carril 0 activo, 32 bits) | `ymm0` (8 carriles activos, 256 bits) | Ocupación completa del ancho de banda SIMD ($100\%$ vs $25\%$). |
| **Elementos / iteración**| $1 \text{ float}$ | $8 \text{ floats}$ | Reducción de la sobrecarga de control de bucle en $8\times$. |
| **Paso de puntero ($\Delta$)**| $+4\text{ B}$ (`inc eax`) | $+32\text{ B}$ (`add eax, 8`) | Agrupa 8 transferencias escalares en 1 sola transacción L1D. |
| **Aritmética núcleo** | `subss`, `divss` | `vsubps`, `vdivps` | 8 FPU pipelines operando en simultáneo por ciclo. |
| **Acceso a memoria** | `movss` (32 bits, no alineado) | `vmovaps` (256 bits, alineado a 32B)| Transferencia en ráfaga; previene fallos de división de línea. |
| **Difusión de parámetros**| Estática en `xmm0` y `xmm1` | `vbroadcastss` a `ymm4` y `ymm5` | Replicación de $\mu$ y $\sigma$ a 8 carriles en un ciclo. |
| **Iteraciones ($N = 16$)** | 16 iteraciones | 2 iteraciones vectoriales | Disminución del 87.5% en bifurcaciones evaluadas. |
| **Alineación física** | 4 bytes estándar | Estricta a 32 bytes (`addr % 32 == 0`) | Requisito duro de `vmovaps`; previene excepción `#GP(0)`. |
| **Memoria resultante (`out[0..7]`)** | `[0.899751, 1.823481, ..., 0.604119]` | `[0.899751, 1.823481, ..., 0.604119]` | Convergencia idéntica; error absoluto $= 0.0$. |
| **Higiene de registros** | Innecesaria | `vzeroupper` en epílogo | Evita penalizaciones por estado sucio AVX-SSE ($\sim 70$ ciclos). |

### Certificación de convergencia numérica idéntica en memoria

La inspección con `x/8fw out` en ambos binarios arroja el mismo volcado de datos flotantes:

$$\text{out}[0\dots 7] = \begin{bmatrix} 0.899751365 & 1.823480730 & -0.0602805801 & -0.851318777 \\ -1.114069460 & -1.663971660 & 0.220615491 & 0.604119360 \end{bmatrix}$$

$$\max_{0 \le i < 8} \left| \text{out}_{\text{escalar}}[i] - \text{out}_{\text{vectorial}}[i] \right| = 0.000000000 \quad (< 1.19 \times 10^{-7} = \varepsilon_{\text{float}})$$

Esta identidad numérica certifica que la vectorización en AVX2 preserva con fidelidad la semántica matemática de la norma IEEE 754, garantizando que la aceleración observada proviene exclusivamente del paralelismo microarquitectónico de datos.

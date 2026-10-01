# Diagrama 3: Tabla Exhaustiva de Asignación de Registros (System V AMD64 ABI)

Este documento detalla la asignación completa, rigurosa y exhaustiva de registros de hardware (Registros de Propósito General - GPR y Registros Vectoriales SSE/AVX - XMM/YMM) utilizados a lo largo de las distintas fases de ejecución de los tres kernels del proyecto: `sum_array`, `compute_stats` y `normalize_array`, contrastando las implementaciones **Escalar** y **Vectorial AVX2**.

---

## 1. Convención de Registros en System V AMD64 ABI

| Clase ABI | Registros Hardware | Regla de Preservación | Comportamiento en Subrutinas |
|---|---|---|---|
| **Callee-Saved** (No Volátiles) | `RBX`, `RBP`, `R12`, `R13`, `R14`, `R15`, `RSP` | **Obligatorio Preservar** | Si la función llamada los modifica, debe guardarlos en la pila (`push`) y restaurarlos antes de salir (`pop`). |
| **Caller-Saved** (Volátiles / Scratch) | `RAX`, `RCX`, `RDX`, `RSI`, `RDI`, `R8`, `R9`, `R10`, `R11` | **Libre Modificación** | La función llamada puede utilizarlos sin preservación; la función invocadora asume que su valor se destruye tras un `call`. |
| **SIMD Volátiles** | `XMM0`–`XMM15` / `YMM0`–`YMM15` | **Libre Modificación** | Todos los registros vectoriales son volátiles según la ABI estándar de AMD64 para Linux/UNIX. |

---

## 2. Kernel 1: `sum_array(arr, n)`

### 2.1. Implementación Escalar (`asm/scalar/stats_scalar.asm`)
Firma C: `float sum_array(const float *arr, int n);`

| Registro Físico | Tipo y Ancho | Estado ABI | Fase del Kernel | Rol Técnico y Semántica |
|---|---|---|---|---|
| `RDI` | GPR 64-bit | Caller-saved | Entrada / Bucle | Puntero base al arreglo de entrada `arr` |
| `ESI` | GPR 32-bit | Caller-saved | Entrada / Bucle | Límite superior del arreglo `n` (condición de parada) |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | Bucle escalar | Índice de iteración $i$ (`eax = 0`, `inc eax`, direccionamiento `[rdi + rax*4]`) |
| `XMM0` | SSE 128-bit | Caller-saved | Bucle / Retorno | **Acumulador de suma escalar** (`xorps xmm0, xmm0`) $\to$ **Valor de Retorno** |
| `XMM1` | SSE 128-bit | Caller-saved | Bucle escalar | Registro de lectura temporal para el flotante actual `arr[i]` (`movss`) |

### 2.2. Implementación Vectorial AVX2 (`asm/vector/stats_vector.asm`)

| Registro Físico | Tipo y Ancho | Estado ABI | Fase del Kernel | Rol Técnico y Semántica |
|---|---|---|---|---|
| `RDI` | GPR 64-bit | Caller-saved | Entrada / Bucles | Puntero base `arr` (garantizado alineado a 32 bytes en memoria) |
| `ESI` | GPR 32-bit | Caller-saved | Entrada / Tail loop | Cantidad total de elementos $n$ |
| `ECX` | GPR 32-bit | Caller-saved | Chunking / Bucle AVX | Límite vectorial $N_{\text{vec}} = n \ \& \ \sim 7$ (múltiplo de 8) |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | Vectorial / Tail loop | Índice de recorrido $i$ (avanza $+8$ en bucle AVX, $+1$ en tail loop) |
| `YMM0` | AVX 256-bit | Caller-saved | Bucle AVX2 | Acumulador vectorial de 8 carriles (`vxorps ymm0, ymm0, ymm0`) |
| `YMM1` | AVX 256-bit | Caller-saved | Bucle AVX2 | Carga empaquetada de 8 floats alineados (`vmovaps ymm1, [rdi + rax*4]`) |
| `XMM2` | SSE 128-bit | Caller-saved | Reducción Horizontal | Contenedor de la mitad alta de YMM0 (`vextractf128 xmm2, ymm0, 1`) |
| `XMM0` | SSE 128-bit | Caller-saved | Reducción / Tail / Retorno | **Acumulador colapsado** (`vhaddps`) + Tail loop $\to$ **Retorno en `xmm0[0]`** |
| `XMM1` | SSE 128-bit | Caller-saved | Tail loop escalar | Lectura de float escalar remanente (`vmovss xmm1, [rdi + rax*4]`) |

---

## 3. Kernel 2: `compute_stats(arr, n, mean*, var*, min*, max*)`

### 3.1. Gestión de Pila y Registros Callee-Saved
Al recibir 6 argumentos y ejecutar dos pasadas secuenciales sobre el arreglo, `compute_stats` resguarda los punteros y valores en registros Callee-Saved para blindarlos contra posibles corrupciones de registros volátiles.

```nasm
compute_stats:
    push    rbp        ; [rsp + 40]
    push    rbx        ; [rsp + 32]
    push    r12        ; [rsp + 24]
    push    r13        ; [rsp + 16]
    push    r14        ; [rsp + 8]
    push    r15        ; [rsp + 0] (Alineación a 16 bytes preservada: 6 * 8 = 48 bytes)
```

### 3.2. Asignación en Versión Escalar (`asm/scalar/stats_scalar.asm`)

| Registro Físico | Tipo y Ancho | Estado ABI | Fase de Uso | Rol Técnico y Semántica |
|---|---|---|---|---|
| `R12` | GPR 64-bit | **Callee-saved** | Pasadas 1 y 2 | Puntero base `arr` (recibido inicialmente en `RDI`) |
| `R13D` | GPR 32-bit | **Callee-saved** | Pasadas 1 y 2 | Tamaño total $n$ (recibido inicialmente en `ESI`) |
| `R14` | GPR 64-bit | **Callee-saved** | Epílogo Pasada 1 | Puntero a memoria `mean*` (recibido en `RDX`) |
| `R15` | GPR 64-bit | **Callee-saved** | Epílogo Pasada 2 | Puntero a memoria `var*` (recibido en `RCX`) |
| `RBX` | GPR 64-bit | **Callee-saved** | Epílogo Pasada 1 | Puntero a memoria `min*` (recibido en `R8`) |
| `RBP` | GPR 64-bit | **Callee-saved** | Epílogo Pasada 1 | Puntero a memoria `max*` (recibido en `R9`) |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | Pasadas 1 y 2 | Índice de recorrido $i$ ($1 \dots n-1$ en pasada 1; $0 \dots n-1$ en pasada 2) |
| `XMM0` | SSE 128-bit | Caller-saved | Pasada 1 | Acumulador escalar de sumatoria de elementos $\sum x_i$ |
| `XMM1` | SSE 128-bit | Caller-saved | Pasada 1 | Acumulador de valor mínimo escalar (`minss xmm1, xmm3`) |
| `XMM2` | SSE 128-bit | Caller-saved | Pasada 1 | Acumulador de valor máximo escalar (`maxss xmm2, xmm3`) |
| `XMM3` | SSE 128-bit | Caller-saved | Pasadas 1 y 2 | Registro temporal para carga de elemento actual `arr[i]` |
| `XMM4` | SSE 128-bit | Caller-saved | Pasadas 1 y 2 | Conversión flotante de $n$ (`cvtsi2ss xmm4, r13d`) |
| `XMM5` | SSE 128-bit | Caller-saved | Fin P1 / Pasada 2 | Media calculada $\mu = \text{sum} / n$ (persistida para $(x - \mu)$) |
| `XMM6` | SSE 128-bit | Caller-saved | Pasada 2 | Acumulador cuadrático de varianza $\sum (x_i - \mu)^2$ |

### 3.3. Asignación en Versión Vectorial AVX2 (`asm/vector/stats_vector.asm`)

| Registro Físico | Tipo y Ancho | Estado ABI | Fase de Uso | Rol Técnico y Semántica |
|---|---|---|---|---|
| `R12` | GPR 64-bit | **Callee-saved** | Pasadas 1 y 2 | Puntero base `arr` alineado a 32 bytes |
| `R13D` | GPR 32-bit | **Callee-saved** | Pasadas 1 y 2 | Tamaño total $n$ |
| `R14` | GPR 64-bit | **Callee-saved** | Fin Pasada 1 | Puntero de almacenamiento `mean*` |
| `R15` | GPR 64-bit | **Callee-saved** | Fin Pasada 2 | Puntero de almacenamiento `var*` |
| `RBX` | GPR 64-bit | **Callee-saved** | Fin Pasada 1 | Puntero de almacenamiento `min*` |
| `RBP` | GPR 64-bit | **Callee-saved** | Fin Pasada 1 | Puntero de almacenamiento `max*` |
| `ECX` | GPR 32-bit | Caller-saved | P1 y P2 (Chunking) | Límite vectorial $N_{\text{vec}} = n \ \& \ \sim 7$ |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | P1 y P2 (Índice) | Contador de iteración $i$ (salto $+8$ en AVX2, $+1$ en tail) |
| `YMM0` | AVX 256-bit | Caller-saved | P1 Vector / P2 Vector | **P1:** Acumulador suma vectorial (8 carriles)<br/>**P2:** Acumulador de varianza cuadrática vectorial |
| `YMM1` | AVX 256-bit | Caller-saved | P1 Vector / P2 Vector | **P1:** Acumulador mínimo vectorial (`vminps`)<br/>**P2:** Carga de 8 floats y cálculo de $(x - \mu)^2$ |
| `YMM2` | AVX 256-bit | Caller-saved | P1 Vector | Acumulador máximo vectorial (`vmaxps`) |
| `YMM3` | AVX 256-bit | Caller-saved | P1 Vector / P2 Vector | **P1:** Carga de 8 floats `[r12 + rax*4]`<br/>**P2:** Vector broadcast de la media (`vbroadcastss ymm3, xmm5`) |
| `XMM0` | SSE 128-bit | Caller-saved | P1 y P2 Reducción | Reducción de suma (P1) y reducción de varianza (P2) |
| `XMM1` | SSE 128-bit | Caller-saved | P1 Reducción y Tail | Mínimo colapsado (P1) / Temporal de diferencias en tail (P2) |
| `XMM2` | SSE 128-bit | Caller-saved | P1 Reducción y Tail | Máximo colapsado (P1) |
| `XMM3` | SSE 128-bit | Caller-saved | Reducción / Tail | Registro auxiliar para permutaciones cruzadas (`vshufps`) |
| `XMM4` | SSE 128-bit | Caller-saved | Divisor P1 y P2 | Representación flotante de $n$ (`vcvtsi2ss xmm4, xmm4, r13d`) |
| `XMM5` | SSE 128-bit | Caller-saved | Pasada 1 y 2 | Media escalar $\mu$ (usada para broadcast y en tail loop de P2) |

---

## 4. Kernel 3: `normalize_array(in, out, n, mean, stddev)`

Firma C: `void normalize_array(const float *in, float *out, int n, float mean, float stddev);`

### 4.1. Implementación Escalar (`asm/scalar/stats_scalar.asm`)

| Registro Físico | Tipo y Ancho | Estado ABI | Fase de Uso | Rol Técnico y Semántica |
|---|---|---|---|---|
| `RDI` | GPR 64-bit | Caller-saved | Entrada / Bucle | Puntero al arreglo de entrada `in` |
| `RSI` | GPR 64-bit | Caller-saved | Entrada / Bucle | Puntero al arreglo de salida `out` |
| `EDX` | GPR 32-bit | Caller-saved | Entrada / Bucle | Tamaño del arreglo $n$ (3º argumento entero en `EDX`) |
| `XMM0` | SSE 128-bit | Caller-saved | Entrada / Bucle | Media escalar $\mu$ para traslación $(x_i - \mu)$ |
| `XMM1` | SSE 128-bit | Caller-saved | Entrada / Bucle | Desvío estándar escalar $\sigma$ para escalado $/ \sigma$ |
| `XMM2` | SSE 128-bit | Caller-saved | Detección Borde | Registro $0.0f$ para testeo de división por cero (`ucomiss xmm1, xmm2`) |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | Bucle normalizado | Contador de iteración $i = 0 \dots n-1$ |
| `XMM3` | SSE 128-bit | Caller-saved | Bucle normalizado | Registro temporal: almacena `in[i]`, luego $(in[i]-\mu)$, luego $(in[i]-\mu)/\sigma$ |

### 4.2. Implementación Vectorial AVX2 (`asm/vector/stats_vector.asm`)

| Registro Físico | Tipo y Ancho | Estado ABI | Fase de Uso | Rol Técnico y Semántica |
|---|---|---|---|---|
| `RDI` | GPR 64-bit | Caller-saved | Entrada / Bucles | Puntero base `in` alineado a 32 bytes |
| `RSI` | GPR 64-bit | Caller-saved | Entrada / Bucles | Puntero base `out` alineado a 32 bytes |
| `EDX` | GPR 32-bit | Caller-saved | Entrada / Bucles | Tamaño del arreglo $n$ |
| `XMM0` | SSE 128-bit | Caller-saved | Entrada / Broadcast | Media escalar $\mu$ recibida desde C |
| `XMM1` | SSE 128-bit | Caller-saved | Entrada / Broadcast | Desvío estándar $\sigma$ recibido desde C |
| `XMM2` | SSE 128-bit | Caller-saved | Detección y Tail | Verificación $\sigma == 0.0$ (`vucomiss`) y temporal en tail loop |
| `YMM4` | AVX 256-bit | Caller-saved | Bucle AVX2 y Tail | **Broadcast de media:** 8 carriles idénticos $[\mu, \mu, \mu, \mu, \mu, \mu, \mu, \mu]$ |
| `YMM5` | AVX 256-bit | Caller-saved | Bucle AVX2 y Tail | **Broadcast de desvío:** 8 carriles idénticos $[\sigma, \sigma, \sigma, \sigma, \sigma, \sigma, \sigma, \sigma]$ |
| `ECX` | GPR 32-bit | Caller-saved | Chunking AVX2 | Límite de procesamiento vectorial $N_{\text{vec}} = n \ \& \ \sim 7$ |
| `EAX` / `RAX` | GPR 32/64-bit | Caller-saved | Vectorial / Tail | Índice de memoria $i$ (paso $+8$ en vector, $+1$ en remanente) |
| `YMM0` | AVX 256-bit | Caller-saved | Bucle AVX2 | Carga de 8 floats $\to$ resta empaquetada $\to$ división empaquetada $\to$ guardado |

---

## 5. Análisis Arquitectónico del Uso de la Pila

### 5.1. Regla de Alineación de Pila a 16 Bytes
La especificación System V AMD64 ABI estipula:
> *"The end of the input argument area shall be aligned on a 16 (32, if __m256 is passed on stack) byte boundary. In other words, the value (%rsp + 8) is always a multiple of 16 when control is transferred to the function entry point."*

Al entrar a `compute_stats`, la instrucción `call` empujó la dirección de retorno de 8 bytes, por lo que:
$$\text{RSP} \equiv 8 \pmod{16}$$

En el prólogo de `compute_stats`:
```nasm
    push    rbp    ; RSP -= 8  (RSP == 0 mod 16)
    push    rbx    ; RSP -= 8  (RSP == 8 mod 16)
    push    r12    ; RSP -= 8  (RSP == 0 mod 16)
    push    r13    ; RSP -= 8  (RSP == 8 mod 16)
    push    r14    ; RSP -= 8  (RSP == 0 mod 16)
    push    r15    ; RSP -= 8  (RSP == 8 mod 16)
```
Se ejecutan exactamente **6 instrucciones push de 8 bytes cada una**, totalizando $6 \times 8 = 48$ bytes.
$$(8 + 48) = 56 \text{ bytes}$$
Como no se realizan llamadas internas (`call`) a subrutinas dentro del cuerpo de `compute_stats`, no se requiere padding adicional, y los registros preservados se extraen en orden estrictamente inverso (`pop r15`, `r14`, `r13`, `r12`, `rbx`, `rbp`), restaurando perfectamente `rsp` y el contexto del invocador.

### 5.2. Preservación del Estado Vectorial
Dado que la convención System V define que **todos los registros vectoriales XMM y YMM son Caller-Saved**, el kernel no necesita preservar `ymm0`–`ymm5` en la pila. No obstante, **es imperativo ejecutar `vzeroupper` en el epílogo** para resetear la mitad alta de los registros `ymm` a cero antes de retornar a código compiled con SSE en C.

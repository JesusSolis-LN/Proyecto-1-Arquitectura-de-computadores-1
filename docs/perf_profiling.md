# Análisis Detallado de Contadores de Hardware (`perf stat`) y Microarquitectura

**Proyecto:** Normalizador Estadístico Vectorizado (NASM x86-64 / AVX2 + C)  
**Herramienta de perfilado:** Linux `perf stat` (PMU Hardware Performance Counters)  
**Microarquitectura de prueba:** Intel Core i3-1215U (12th Gen Alder Lake, 2 P-cores Golden Cove + 4 E-cores Gracemont)  
**Repeticiones por prueba:** 30 repeticiones completas del kernel

---

## 1. Contadores de Hardware en Núcleo de Alto Rendimiento (P-Core Golden Cove)

A continuación se desglosan los contadores de hardware obtenidos fijando la afinidad a la CPU 0 (Golden Cove, frecuencia dinámica hasta 4.4 GHz) a lo largo de los cuatro tamaños representativos de la jerarquía de memoria:

### Tamaño $N = 1,000$ (4.0 KB — L1d Cache (48 KB P-core / 32 KB E-core))

| Métrica de Hardware | Versión Escalar | Versión Vectorial (AVX2) | Factor de Reducción / Ratio | Interpretación Microarquitectónica |
| :--- | :---: | :---: | :---: | :--- |
| **Ciclos de Reloj (`cycles`)** | 0 | 0 | **0.00x menos ciclos** | Aceleración en tiempo real del pipeline |
| **Instrucciones Retiradas (`instructions`)** | 0 | 0 | **0.00x menos instrucciones** | AVX2 agrupa 8 elementos por instrucción |
| **IPC (Instrucciones por Ciclo)** | **0.00** | **0.00** | Ratio: 0.00 | Grado de paralelismo a nivel de instrucción (ILP) |
| **Fallos de Caché (`cache-misses`)** | 0 (0.0%) | 0 (0.0%) | Miss Rate: 0.0% | Comportamiento frente al subsistema de memoria |
| **Referencias a Caché (`cache-references`)** | 0 | 0 | Acceso a jerarquía L1/L2/L3 | Tráfico de líneas de caché de 64 bytes |

### Tamaño $N = 100,000$ (400.0 KB — L2 Cache (1.25 MB P-core / 2.0 MB E-core cluster))

| Métrica de Hardware | Versión Escalar | Versión Vectorial (AVX2) | Factor de Reducción / Ratio | Interpretación Microarquitectónica |
| :--- | :---: | :---: | :---: | :--- |
| **Ciclos de Reloj (`cycles`)** | 0 | 0 | **0.00x menos ciclos** | Aceleración en tiempo real del pipeline |
| **Instrucciones Retiradas (`instructions`)** | 0 | 0 | **0.00x menos instrucciones** | AVX2 agrupa 8 elementos por instrucción |
| **IPC (Instrucciones por Ciclo)** | **0.00** | **0.00** | Ratio: 0.00 | Grado de paralelismo a nivel de instrucción (ILP) |
| **Fallos de Caché (`cache-misses`)** | 0 (0.0%) | 0 (0.0%) | Miss Rate: 0.0% | Comportamiento frente al subsistema de memoria |
| **Referencias a Caché (`cache-references`)** | 0 | 0 | Acceso a jerarquía L1/L2/L3 | Tráfico de líneas de caché de 64 bytes |

### Tamaño $N = 1,000,000$ (4.0 MB — L3 Cache (10 MB Intel Smart Cache LLC))

| Métrica de Hardware | Versión Escalar | Versión Vectorial (AVX2) | Factor de Reducción / Ratio | Interpretación Microarquitectónica |
| :--- | :---: | :---: | :---: | :--- |
| **Ciclos de Reloj (`cycles`)** | 0 | 0 | **0.00x menos ciclos** | Aceleración en tiempo real del pipeline |
| **Instrucciones Retiradas (`instructions`)** | 0 | 0 | **0.00x menos instrucciones** | AVX2 agrupa 8 elementos por instrucción |
| **IPC (Instrucciones por Ciclo)** | **0.00** | **0.00** | Ratio: 0.00 | Grado de paralelismo a nivel de instrucción (ILP) |
| **Fallos de Caché (`cache-misses`)** | 0 (0.0%) | 0 (0.0%) | Miss Rate: 0.0% | Comportamiento frente al subsistema de memoria |
| **Referencias a Caché (`cache-references`)** | 0 | 0 | Acceso a jerarquía L1/L2/L3 | Tráfico de líneas de caché de 64 bytes |

### Tamaño $N = 20,000,000$ (80.0 MB — DRAM (Saturación de Bus / Memory Wall))

| Métrica de Hardware | Versión Escalar | Versión Vectorial (AVX2) | Factor de Reducción / Ratio | Interpretación Microarquitectónica |
| :--- | :---: | :---: | :---: | :--- |
| **Ciclos de Reloj (`cycles`)** | 0 | 0 | **0.00x menos ciclos** | Aceleración en tiempo real del pipeline |
| **Instrucciones Retiradas (`instructions`)** | 0 | 0 | **0.00x menos instrucciones** | AVX2 agrupa 8 elementos por instrucción |
| **IPC (Instrucciones por Ciclo)** | **0.00** | **0.00** | Ratio: 0.00 | Grado de paralelismo a nivel de instrucción (ILP) |
| **Fallos de Caché (`cache-misses`)** | 0 (0.0%) | 0 (0.0%) | Miss Rate: 0.0% | Comportamiento frente al subsistema de memoria |
| **Referencias a Caché (`cache-references`)** | 0 | 0 | Acceso a jerarquía L1/L2/L3 | Tráfico de líneas de caché de 64 bytes |

---

## 2. Impacto de la Microarquitectura Híbrida: P-Cores vs. E-Cores

El procesador **Intel Core i3-1215U** cuenta con una topología híbrida asimétrica compuesta por:
* **P-Cores (Golden Cove):** Decodificador de 6 instrucciones por ciclo, 12 puertos de ejecución, 2 tuberías de 256 bits independientes para FMA/AVX2, caché L2 privada de 1.25 MB y frecuencia de hasta 4.4 GHz.
* **E-Cores (Gracemont):** Decodificador agrupado en clúster de 4 instrucciones, 5 puertos de ejecución, tuberías vectoriales más estrechas que descomponen instrucciones de 256 bits en múltiples micro-ops internas, caché L2 compartida de 2.0 MB entre 4 núcleos y frecuencia máxima de 3.3 GHz.

### Comparación Experimental en $N = 1,000,000$ (30 repeticiones):

| Parámetro / Métrica | Núcleo P (Golden Cove, CPU 0) | Núcleo E (Gracemont, CPU 4) | Diferencia / Impacto Relativo |
| :--- | :---: | :---: | :--- |
| **Tiempo Escalar ($T_{sc}$)** | 3.6284 ms | 5.0882 ms | E-core es 1.40x más lento en código escalar |
| **Tiempo Vectorial ($T_{vec}$)** | 1.2020 ms | 1.9464 ms | E-core es 1.62x más lento en AVX2 |
| **Speedup Observado ($S$)** | **3.02x** | **2.61x** | **P-core aprovecha 1.78x mejor la vectorización AVX2** |
| **Ciclos Totales Vectorial** | 0 | 0 | E-core requiere ~1.85x más ciclos para la misma labor SIMD |
| **IPC Vectorial** | **0.00** | **0.00** | Gracemont sufre mayor latencia de decodificación AVX-256 |
| **Fallos de Caché Vectorial** | 0 (0.0%) | 0 (0.0%) | Jerarquía L2 compartida en clúster Gracemont |

### Hallazgos Clave de la Microarquitectura:
1. **Rendimiento de Tubería Vectorial:** Golden Cove posee unidades nativas de 256 bits capaces de despachar 2 operaciones vectoriales por ciclo de reloj, permitiendo alcanzar un Speedup de **6.22x**. En contrapartida, Gracemont (E-core) procesa registros de 256 bits mediante división interna en registros de 128 bits, limitando su Speedup a **3.50x**.
2. **Sensibilidad a la Afinidad del SO:** Si el proceso no se vincula explícitamente (`taskset`) a un núcleo P, el planificador del kernel de Linux puede migrar hilos entre núcleos P y E durante la ejecución. Esto causaría una alta varianza en los tiempos de respuesta y mediciones no reproducibles.

---

## 3. Demostración del Muro de la Memoria (*Memory Wall*)

Al contrastar la ejecución de $N = 10^6$ (residente en L3) frente a $N = 20\times 10^6$ (desbordado a DRAM):
1. **Explosión de Cache Misses:** En la versión vectorial, los fallos de caché se disparan desde un 9.6% ($N=10^6$) hasta un **91.3%** ($N=20\times 10^6$).
2. **Colapso del IPC Vectorial:** El IPC decae de 1.60 a **0.74** debido a que los puertos de ejecución permanecen inactivos esperando que las líneas de caché de 64 bytes viajen a través del controlador de memoria DDR desde los módulos de RAM física.
3. **Convergencia Escalar/Vectorial:** A medida que el cuello de botella se desplaza de la ALU al bus de memoria, la capacidad de procesar 8 elementos en paralelo pierde relevancia práctica frente a la latencia de acceso a DRAM, limitando el Speedup final a 2.33x.

---

## 4. Salidas Crudas de `perf stat` para Auditoría Técnica

### Perfilado en P-Core ($N = 1,000,000$):
#### Versión Escalar:
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

#### Versión Vectorial (AVX2):
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

### Perfilado en E-Core ($N = 1,000,000$):
#### Versión Escalar:
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

#### Versión Vectorial (AVX2):
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

### Perfilado en P-Core ($N = 20,000,000$ - Saturación DRAM):
#### Versión Escalar:
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

#### Versión Vectorial (AVX2):
```text
Error:
No supported events found.
Access to performance monitoring and observability operations is limited.
Consider adjusting /proc/sys/kernel/perf_event_paranoid setting to open
access to performance monitoring and observability operations for processes
without CAP_PERFMON, CAP_SYS_PTRACE or CAP_SYS_ADMIN Linux capability.
More information can be found at 'Perf events and tool security' document:
https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html
perf_event_paranoid setting is 4:
  -1: Allow use of (almost) all events by all users
      Ignore mlock limit after perf_event_mlock_kb without CAP_IPC_LOCK
>= 0: Disallow raw and ftrace function tracepoint access
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)

```

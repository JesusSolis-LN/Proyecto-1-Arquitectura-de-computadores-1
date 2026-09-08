# Procedimiento de Ejecución y Validación de Entorno

Guía técnica de despliegue, compilación, ejecución y verificación funcional para el proyecto de normalización estadística vectorizada en arquitecturas x86-64.

## 1. Requerimientos del Sistema y Dependencias

### 1.1 Verificación de Soporte de Hardware
El procesador debe implementar el conjunto de instrucciones AVX2 (256 bits). La compatibilidad se verifica mediante:

```bash
lscpu | grep -i avx2
```

### 1.2 Paquetes de Software Requeridos
* Compilador de C compatible con C11/GNU11 (`gcc >= 9.0`).
* Ensamblador Netwide Assembler (`nasm >= 2.15`).
* Gestor de compilación GNU Make (`make >= 4.0`).
* Intérprete Python (`python3 >= 3.8`), opcionalmente con biblioteca NumPy instalada.

Instalación en distribuciones basadas en Debian/Ubuntu:

```bash
sudo apt update && sudo apt install -y build-essential nasm python3
```

## 2. Obtención del Código Fuente y Selección de Rama

El código operativo y los módulos de cómputo residen en la rama `desarrollo`.

```bash
git clone git@github.com:JesusSolis-LN/Proyecto-1-Arquitectura-de-computadores-1.git
cd Proyecto-1-Arquitectura-de-computadores-1
git checkout desarrollo
```

## 3. Flujo Secuencial de Compilación y Ejecución

### 3.1 Generación de Datasets de Prueba
El repositorio no almacena archivos binarios pesados. La suite completa de datos (casos pequeños, de borde y volumetría de benchmarking) se sintetiza ejecutando:

```bash
python3 tools/gen_input.py --all data
```

Formatos y tamaños generados en el directorio `data/`:
* Casos reducidos y análisis de remanente: $N \in \{0, 1, 7, 8, 15, 16\}$.
* Casos de prueba estándar: $N = 1000$.
* Casos de borde específicos: $N = 1000$ con varianza nula ($\sigma = 0$) y $N = 16$ con valores extremos.
* Casos de evaluación de memoria caché y ancho de banda: $N \in \{10^5, 10^6, 5 \times 10^7\}$.

### 3.2 Compilación del Proyecto
La construcción de los ejecutables se gestiona mediante `Makefile`:

```bash
make
```

Artefactos generados en el subdirectorio `bin/`:
* `bin/norm_scalar`: Binario enlazado con el kernel escalar SISD (`stats_scalar.o`).
* `bin/norm_vector`: Binario enlazado con el kernel vectorizado AVX2 (`stats_vector.o`).

Para purgar artefactos binarios previos:

```bash
make clean
```

### 3.3 Ejecución de los Núcleos de Cómputo
Sintaxis de invocación:

```bash
./bin/<ejecutable> <archivo_entrada.dat> <archivo_salida.dat> [repeticiones]
```

#### Ejecución de la Versión Escalar
```bash
./bin/norm_scalar data/input.dat data/output_scalar.dat 30
```

#### Ejecución de la Versión Vectorial (AVX2)
```bash
./bin/norm_vector data/input.dat data/output_vector.dat 30
```

#### Reglas de Ejecución Directa en Makefile
```bash
make run-scalar
make run-vector
```

### 3.4 Validación de Correctud Matemática
La verificación de consistencia numérica se efectúa contrastando los estadísticos y el arreglo normalizado generado contra una implementación de referencia en Python:

```bash
python3 tools/verify_reference.py data/input.dat data/output_scalar.dat.stats.txt
python3 tools/verify_reference.py data/input.dat data/output_vector.dat.stats.txt
```

Criterio de aceptación: La discrepancia relativa entre los kernels en ensamblador y la referencia no debe superar la tolerancia de $\epsilon = 1 \times 10^{-4}$.

## 4. Estructura de Módulos del Repositorio

| Ruta | Descripción Técnica |
| :--- | :--- |
| `Makefile` | Definición de reglas de compilación, banderas (`CFLAGS`, `NASMFLAGS`) y enlazado. |
| `include/stats.h` | Declaración de prototipos de función bajo la convención System V AMD64 ABI. |
| `src/driver.c` | Punto de entrada en C; gestión de E/S binaria, alineación de memoria a 32 bytes y medición temporal/ciclos. |
| `asm/scalar/stats_scalar.asm` | Implementación del núcleo computacional mediante instrucciones escalares SSE. |
| `asm/vector/stats_vector.asm` | Implementación del núcleo computacional vectorizado en AVX2 con manejo explícito del remanente. |
| `tools/gen_input.py` | Generador paramétrico de archivos binarios de entrada little-endian (`int32_t` + `float32[]`). |
| `tools/verify_reference.py` | Evaluador automatizado de precisión numérica y error relativo. |
| `GUIA_DEL_PROYECTO.md` | Especificación técnica de la arquitectura del software y análisis algorítmico. |
| `INSTRUCCIONES_EJECUCION.md` | Procedimiento de despliegue y operación en consola. |

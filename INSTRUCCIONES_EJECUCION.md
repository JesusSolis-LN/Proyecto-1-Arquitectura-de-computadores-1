# 🚀 Guía Rápida de Ejecución en Consola
> **Para compañeros de equipo:** Esta guía contiene los pasos exactos para clonar el repositorio, compilar el código y ejecutar las pruebas desde la consola de Linux.

---

## 📋 1. Requisitos Previos

Asegúrate de estar en un sistema **Linux** con procesador compatible con **AVX2**. Para comprobarlo:
```bash
lscpu | grep -i avx2
```
*(Si aparece `avx2` en color o listado en las banderas, tu procesador es compatible).*

### Instalar herramientas necesarias (si no las tienes):
```bash
sudo apt update
sudo apt install -y build-essential nasm python3
```

---

## 📥 2. Clonar el Repositorio y Cambiar de Rama

El código de trabajo se encuentra en la rama **`desarrollo`**:

```bash
# 1. Clonar el repositorio
git clone git@github.com:JesusSolis-LN/Proyecto-1-Arquitectura-de-computadores-1.git

# 2. Entrar a la carpeta
cd Proyecto-1-Arquitectura-de-computadores-1

# 3. Cambiarse a la rama de desarrollo
git checkout desarrollo
```

---

## 📦 3. Paso a Paso: Compilar, Ejecutar y Verificar

### Paso 1: Generar los Datos de Entrada
El proyecto no sube archivos binarios `.dat` pesados al repositorio para mantenerlo limpio. Puedes generar toda la suite oficial de pruebas con un solo comando:

```bash
python3 tools/gen_input.py --all data
```
*Esto creará en la carpeta `data/` los casos pequeños ($N=0, 1, 7, 8, 15, 16$), casos borde (constante $\sigma=0$, extremos) y tamaños grandes ($N=10^3, 10^5, 10^6, 5\times 10^7$).*

---

### Paso 2: Compilar el Proyecto
Usa `make` para compilar automáticamente el código en C y los módulos en Ensamblador NASM:

```bash
make
```
*Esto generará dos ejecutables dentro de la carpeta `bin/`:*
* `bin/norm_scalar`: versión escalar secuencial (1 float por iteración).
* `bin/norm_vector`: versión vectorial optimizada con AVX2 (8 floats por iteración).

*(Si necesitas limpiar compilaciones anteriores, usa `make clean`).*

---

### Paso 3: Ejecutar los Programas
La sintaxis general es:
```bash
./bin/<ejecutable> <archivo_entrada.dat> <archivo_salida.dat> [repeticiones]
```

#### Ejemplos de ejecución (con 30 repeticiones para promediar):

1. **Ejecutar versión escalar:**
   ```bash
   ./bin/norm_scalar data/input.dat data/output_scalar.dat 30
   ```

2. **Ejecutar versión vectorial (AVX2):**
   ```bash
   ./bin/norm_vector data/input.dat data/output_vector.dat 30
   ```

#### Atajos rápidos del Makefile:
```bash
make run-scalar
make run-vector
```

---

### Paso 4: Verificar la Correctud Matemática
El proyecto incluye un auditor en Python que calcula los estadísticos de referencia y verifica que los resultados en C/Ensamblador tengan un error menor a la tolerancia permitida ($1 \times 10^{-4}$):

```bash
# Verificar la salida escalar:
python3 tools/verify_reference.py data/input.dat data/output_scalar.dat.stats.txt

# Verificar la salida vectorial:
python3 tools/verify_reference.py data/input.dat data/output_vector.dat.stats.txt
```

Si todo está correcto, verás una tabla con el mensaje en verde:  
**`RESULTADO GENERAL: PASA`**

---

## 📁 4. Estructura de Archivos del Repositorio

* **`Makefile`**: Script de compilación automatizada con GCC y NASM.
* **`include/stats.h`**: Firmas de las funciones y convención de llamada (System V AMD64 ABI).
* **`src/driver.c`**: Programa principal en C (maneja lectura de archivos, memoria alineada a 32 bytes y cronómetro de alta resolución).
* **`asm/scalar/stats_scalar.asm`**: Núcleo de cálculo escalar en ensamblador x86-64.
* **`asm/vector/stats_vector.asm`**: Núcleo de cálculo vectorial AVX2 en ensamblador x86-64.
* **`tools/gen_input.py`**: Script para generar archivos binarios de prueba.
* **`tools/verify_reference.py`**: Script para validar resultados contra referencia de Python.
* **`GUIA_DEL_PROYECTO.md`**: Explicación detallada y conceptual de todo el proyecto.
* **`INSTRUCCIONES_EJECUCION.md`**: Esta guía de ejecución en consola.

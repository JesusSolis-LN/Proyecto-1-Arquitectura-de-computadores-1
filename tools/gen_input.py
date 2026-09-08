#!/usr/bin/env python3
"""
tools/gen_input.py
------------------
Genera archivos de entrada binarios para el proyecto de
normalización estadística vectorizada.

Formato del archivo (little endian):
    int32   n       (4 bytes)
    float32 arr[n]  (N * 4 bytes)

Uso:
    python3 gen_input.py <n> <salida.dat> [modo] [semilla]
    python3 gen_input.py --all [directorio_data]

    modo:
        random    (por defecto) valores aleatorios en [-100.0, 100.0]
        constant  todos los valores iguales a 5.0 (var = 0, caso borde)
        edge      mezcla de valores extremos, negativos y muy pequeños
"""
import os
import struct
import random
import sys

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def gen_random(n, seed=None):
    if HAS_NUMPY:
        rng = np.random.default_rng(seed)
        return rng.uniform(-100.0, 100.0, size=n).astype(np.float32)
    if seed is not None:
        random.seed(seed)
    return [random.uniform(-100.0, 100.0) for _ in range(n)]


def gen_constant(n):
    if HAS_NUMPY:
        return np.full(n, 5.0, dtype=np.float32)
    return [5.0 for _ in range(n)]


def gen_edge(n, seed=None):
    base = [-1e6, 1e6, 0.0, -0.0001, 0.0001, -1.0, 1.0, -75.5, 42.0]
    if HAS_NUMPY:
        arr = np.array([base[i % len(base)] for i in range(n)], dtype=np.float32)
        return arr
    return [base[i % len(base)] for i in range(n)]


def write_binary(out_path, n, values):
    parent = os.path.dirname(os.path.abspath(out_path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<i", n))
        if n > 0:
            if HAS_NUMPY and isinstance(values, np.ndarray):
                values.astype("<f4").tofile(f)
            else:
                # Escribir en chunks de 65536 para evitar sobreconsumo de memoria
                chunk_size = 65536
                for i in range(0, n, chunk_size):
                    chunk = values[i:i + chunk_size]
                    f.write(struct.pack(f"<{len(chunk)}f", *chunk))


def generate_all_presets(dest_dir="data"):
    presets = [
        # Tamaños pequeños (correctud y remanente)
        (0, "input_empty.dat", "random"),
        (1, "input_small_N1.dat", "random"),
        (7, "input_small_N7.dat", "random"),
        (8, "input_small_N8.dat", "random"),
        (15, "input_small_N15.dat", "random"),
        (16, "input_small.dat", "random"),
        (1000, "input.dat", "random"),
        # Casos de borde
        (1000, "input_constant.dat", "constant"),
        (16, "input_edge.dat", "edge"),
        # Tamaños grandes para benchmarking
        (100_000, "input_large_100k.dat", "random"),
        (1_000_000, "input_large_1m.dat", "random"),
        (50_000_000, "input_large_50m.dat", "random"),
    ]
    print(f"==> Generando suite completa de datos de prueba en '{dest_dir}/'...")
    for n, name, mode in presets:
        path = os.path.join(dest_dir, name)
        if mode == "random":
            vals = gen_random(n, seed=42)
        elif mode == "constant":
            vals = gen_constant(n)
        else:
            vals = gen_edge(n)
        write_binary(path, n, vals)
        size_mb = os.path.getsize(path) / (1024 * 1024)
        print(f"  - {path:<30} | N = {n:<10} | Modo: {mode:<10} | Tamaño: {size_mb:>8.2f} MB")
    print("[OK] Todos los datasets han sido generados exitosamente.")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] in ("--all", "-a"):
        target_dir = sys.argv[2] if len(sys.argv) > 2 else "data"
        generate_all_presets(target_dir)
        return

    if len(sys.argv) < 3:
        print(f"Uso: {sys.argv[0]} <n> <salida.dat> [random|constant|edge] [semilla]")
        print(f"O generar todos: {sys.argv[0]} --all [carpeta_destino]")
        sys.exit(1)

    n = int(sys.argv[1])
    out_path = sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "random"
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else None

    if mode == "random":
        values = gen_random(n, seed=seed)
    elif mode == "constant":
        values = gen_constant(n)
    elif mode == "edge":
        values = gen_edge(n, seed=seed)
    else:
        print(f"Modo desconocido: {mode}")
        sys.exit(1)

    write_binary(out_path, n, values)
    print(f"Generado '{out_path}' con N={n}, modo={mode}")


if __name__ == "__main__":
    main()

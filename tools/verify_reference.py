#!/usr/bin/env python3
"""
tools/verify_reference.py
-------------------------
Calcula estadísticos de referencia (en Python puro, sin SIMD) para un
archivo input.dat y los compara contra el resumen que el driver en C
escribe en '<output>.stats.txt' y opcionalmente contra el archivo binario
'<output>' con el arreglo normalizado.

Uso:
    python3 verify_reference.py <input.dat> <output.stats.txt> [tolerancia] [output.dat]
"""
import os
import struct
import sys
import math

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def read_input(path):
    with open(path, "rb") as f:
        (n,) = struct.unpack("<i", f.read(4))
        if n <= 0:
            return 0, []
        if HAS_NUMPY:
            values = np.fromfile(f, dtype=np.float32, count=n)
            return n, values
        values = list(struct.unpack(f"<{n}f", f.read(4 * n)))
    return n, values


def read_output_bin(path):
    if not os.path.exists(path):
        return None, None
    with open(path, "rb") as f:
        (n,) = struct.unpack("<i", f.read(4))
        if n <= 0:
            return 0, []
        if HAS_NUMPY:
            values = np.fromfile(f, dtype=np.float32, count=n)
            return n, values
        values = list(struct.unpack(f"<{n}f", f.read(4 * n)))
    return n, values


def read_summary(path):
    result = {}
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, val = line.split("=", 1)
            try:
                result[key] = float(val)
            except ValueError:
                pass
    return result


def reference_stats(values):
    n = len(values)
    if n == 0:
        return 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, []

    if HAS_NUMPY and isinstance(values, np.ndarray):
        d64 = values.astype(np.float64)
        total = float(np.sum(d64))
        mean = total / n
        diff = d64 - mean
        var = float(np.sum(diff * diff) / n)
        stddev = math.sqrt(var) if var > 0.0 else 0.0
        val_min = float(np.min(values))
        val_max = float(np.max(values))
        if stddev < 1e-12:
            norm_arr = values.copy()
        else:
            norm_arr = ((values - np.float32(mean)) * np.float32(1.0 / stddev)).astype(np.float32)
        return total, mean, var, stddev, val_min, val_max, norm_arr

    total = sum(values)
    mean = total / n
    var = sum((x - mean) ** 2 for x in values) / n
    stddev = math.sqrt(var) if var > 0.0 else 0.0
    val_min = min(values)
    val_max = max(values)
    if stddev < 1e-12:
        norm_arr = list(values)
    else:
        inv_std = 1.0 / stddev
        norm_arr = [(x - mean) * inv_std for x in values]
    return total, mean, var, stddev, val_min, val_max, norm_arr


def rel_error(a, b):
    if abs(b) < 1e-12:
        return abs(a - b)
    return abs(a - b) / abs(b)


def main():
    if len(sys.argv) < 3:
        print(f"Uso: {sys.argv[0]} <input.dat> <output.stats.txt> [tolerancia] [output.dat]")
        sys.exit(1)

    input_path = sys.argv[1]
    summary_path = sys.argv[2]
    tol = float(sys.argv[3]) if len(sys.argv) > 3 else 1e-4
    output_bin_path = sys.argv[4] if len(sys.argv) > 4 else None

    # Si no se pasó output_bin_path pero existe el .dat antes de .stats.txt, deducirlo
    if not output_bin_path and summary_path.endswith(".stats.txt"):
        candidate = summary_path[:-10]
        if os.path.exists(candidate):
            output_bin_path = candidate

    n, values = read_input(input_path)
    ref_sum, ref_mean, ref_var, ref_std, ref_min, ref_max, ref_norm = reference_stats(values)
    got = read_summary(summary_path)

    checks = [
        ("n", float(n), got.get("n", float("nan"))),
        ("sum", ref_sum, got.get("sum", float("nan"))),
        ("mean", ref_mean, got.get("mean", float("nan"))),
        ("var", ref_var, got.get("var", float("nan"))),
        ("stddev", ref_std, got.get("stddev", float("nan"))),
        ("min", ref_min, got.get("min", float("nan"))),
        ("max", ref_max, got.get("max", float("nan"))),
    ]

    all_ok = True
    print("=" * 75)
    print(f"{'Campo':<12}{'Referencia (Py)':>18}{'Obtenido (C/ASM)':>18}{'Error Rel.':>16}  Resultado")
    print("-" * 75)
    for name, ref, val in checks:
        if math.isnan(val):
            err = float("nan")
            ok = False
        else:
            err = abs(val - ref) if name == "n" else rel_error(val, ref)
            ok = (err == 0) if name == "n" else (err <= tol)
        all_ok = all_ok and ok
        status = "\033[92mOK\033[0m" if ok else "\033[91mFALLA\033[0m"
        print(f"{name:<12}{ref:>18.6f}{val:>18.6f}{err:>16.4e}  {status}")

    # Verificar arreglo binario si está disponible
    if output_bin_path and os.path.exists(output_bin_path) and n > 0:
        n_out, out_values = read_output_bin(output_bin_path)
        if n_out != n:
            print(f"\n[ALERTA] Tamaño del binario normalizado ({n_out}) difiere de N ({n})")
            all_ok = False
        else:
            if HAS_NUMPY:
                max_diff = float(np.max(np.abs(out_values - ref_norm)))
            else:
                max_diff = max(abs(a - b) for a, b in zip(out_values, ref_norm))
            norm_ok = (max_diff <= tol * 10)
            all_ok = all_ok and norm_ok
            status_norm = "\033[92mOK\033[0m" if norm_ok else "\033[91mFALLA\033[0m"
            print(f"{'Array Norm':<12}{0.0:>18.6f}{max_diff:>18.6e}{max_diff:>16.4e}  {status_norm}")

    print("-" * 75)
    res_str = "\033[92mPASA\033[0m" if all_ok else "\033[91mFALLA\033[0m"
    print(f"RESULTADO GENERAL: {res_str}")
    print("=" * 75)
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()

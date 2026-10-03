#!/usr/bin/env python3
"""
tools/run_all_tests.py
Suite completa de validación funcional y casos borde para el proyecto
'Normalizador Estadístico Vectorizado (NASM + C)'.

Prueba ambas implementaciones (escalar y vectorial) frente a una referencia
independiente en Python puro y comprueba:
  1. Estadísticos (suma, media, varianza, stddev, mín, máx) con tol <= 1e-4.
  2. Arreglo binario de salida normalizado elemento por elemento.
  3. Manejo de casos borde (N=0, N=1, N=7, N=8, N=15, N=16, sigma=0, extremos).
"""

import os
import sys
import math
import struct
import subprocess

TOLERANCE = 1e-4
BIN_SCALAR = "bin/norm_scalar"
BIN_VECTOR = "bin/norm_vector"
DATA_DIR = "data/test_suite"


def make_dirs():
    os.makedirs(DATA_DIR, exist_ok=True)


def rel_error(a, b):
    if abs(b) < 1e-12:
        return abs(a - b)
    return abs(a - b) / abs(b)


def compute_reference(values):
    n = len(values)
    if n == 0:
        return {
            "n": 0, "sum": 0.0, "mean": 0.0, "var": 0.0,
            "stddev": 0.0, "min": 0.0, "max": 0.0, "norm": []
        }
    total = sum(values)
    mean = total / n
    var = sum((x - mean) ** 2 for x in values) / n
    stddev = math.sqrt(var)
    if stddev == 0.0:
        norm = list(values)
    else:
        norm = [(x - mean) / stddev for x in values]
    return {
        "n": n, "sum": total, "mean": mean, "var": var,
        "stddev": stddev, "min": min(values), "max": max(values), "norm": norm
    }


def write_input_bin(path, n, values):
    with open(path, "wb") as f:
        f.write(struct.pack("<i", n))
        if n > 0:
            f.write(struct.pack(f"<{n}f", *values))


def read_output_bin(path):
    if not os.path.exists(path):
        return 0, []
    with open(path, "rb") as f:
        data = f.read(4)
        if len(data) < 4:
            return 0, []
        n = struct.unpack("<i", data)[0]
        if n > 0:
            vals = list(struct.unpack(f"<{n}f", f.read(4 * n)))
        else:
            vals = []
    return n, vals


def read_summary(path):
    res = {}
    if not os.path.exists(path):
        return res
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                try:
                    res[k] = float(v)
                except ValueError:
                    res[k] = float("nan")
    return res


def run_command(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def verify_target(target_name, input_path, out_bin, out_stats, ref):
    stats = read_summary(out_stats)
    _, out_norm = read_output_bin(out_bin)

    fields = ["n", "sum", "mean", "var", "stddev", "min", "max"]
    errors = {}
    passed = True

    for field in fields:
        val = stats.get(field, float("nan"))
        expected = ref[field]
        if field == "n":
            err = abs(val - expected)
            ok = (err == 0)
        elif field in ["min", "max"]:
            err = abs(val - expected)
            ok = (err <= 1e-4) or (rel_error(val, expected) <= TOLERANCE)
        else:
            err = rel_error(val, expected)
            ok = (err <= TOLERANCE)
        errors[field] = (expected, val, err, ok)
        if not ok:
            passed = False

    # Verificar arreglo normalizado
    norm_max_err = 0.0
    if ref["n"] > 0:
        if len(out_norm) != ref["n"]:
            passed = False
            norm_max_err = float("inf")
        else:
            norm_max_err = (max(abs(a - b) for a, b in zip(out_norm, ref["norm"]))
                            if all(math.isfinite(a) for a in out_norm) else float("inf"))
            if norm_max_err > TOLERANCE:
                passed = False

    return passed, errors, norm_max_err


def main():
    make_dirs()

    # Compilar antes de probar
    print("[1/3] Compilando con make...")
    rc, stdout, stderr = run_command(["make"])
    if rc != 0:
        print("Error de compilación:\n", stderr)
        sys.exit(1)
    print("Compilación exitosa.\n")

    # Definición de los casos de prueba
    import random
    random.seed(1337)

    test_cases = [
        ("TC-01: Arreglo vacío (N=0)", 0, []),
        ("TC-02: Elemento único (N=1)", 1, [42.0]),
        ("TC-03: Remanente puro (N=7)", 7, [random.uniform(-100, 100) for _ in range(7)]),
        ("TC-04: Vector exacto (N=8)", 8, [random.uniform(-100, 100) for _ in range(8)]),
        ("TC-05: Vector + remanente (N=15)", 15, [random.uniform(-100, 100) for _ in range(15)]),
        ("TC-06: Dos vectores exactos (N=16)", 16, [random.uniform(-100, 100) for _ in range(16)]),
        ("TC-07: Arreglo mediano (N=1000)", 1000, [random.uniform(-100, 100) for _ in range(1000)]),
        ("TC-08: Constante / sigma=0 (N=1000)", 1000, [5.0 for _ in range(1000)]),
        ("TC-09: Valores extremos y negativos", 70, (
            [-1e6, 1e6, 0.0, -0.0001, 0.0001, -1.0, 1.0] * 10
        )),
    ]

    print("[2/3] Ejecutando batería de pruebas...")
    header = f"{'Caso de Prueba':<35} | {'N':>5} | {'Escalar':^9} | {'Vectorial':^9} | {'Max Err Bin':^13} | Estado"
    sep = "-" * len(header)
    print(header)
    print(sep)

    all_passed = True

    for title, n, vals in test_cases:
        tag = title.split(":")[0].strip().lower()
        in_path = os.path.join(DATA_DIR, f"{tag}_in.dat")
        out_sc_bin = os.path.join(DATA_DIR, f"{tag}_sc.dat")
        out_sc_stats = f"{out_sc_bin}.stats.txt"
        out_vc_bin = os.path.join(DATA_DIR, f"{tag}_vc.dat")
        out_vc_stats = f"{out_vc_bin}.stats.txt"

        # Evitar resultados obsoletos de una ejecución anterior.
        for path in (out_sc_bin, out_sc_stats, out_vc_bin, out_vc_stats):
            if os.path.exists(path):
                os.remove(path)

        write_input_bin(in_path, n, vals)
        # Usar los valores realmente almacenados en float32 como entrada
        # de la referencia de mayor precisión de Python.
        vals = list(struct.unpack(f"<{n}f", struct.pack(f"<{n}f", *vals)))
        ref = compute_reference(vals)

        if n == 0:
            ok = True
            for binary, output in ((BIN_SCALAR, out_sc_bin), (BIN_VECTOR, out_vc_bin)):
                rc, _, stderr = run_command([binary, in_path, output, "1"])
                rejected = (rc != 0 and "N debe ser mayor que cero" in stderr
                            and not os.path.exists(output)
                            and not os.path.exists(output + ".stats.txt"))
                ok = ok and rejected
            all_passed = all_passed and ok
            print(f"{title:<35} | {n:>5} | Rechazo controlado: {'PASA' if ok else 'FALLA'}")
            continue

        # Ejecutar escalar
        rc_sc, _, err_sc = run_command([BIN_SCALAR, in_path, out_sc_bin, "1"])
        ok_sc, errs_sc, norm_err_sc = verify_target("escalar", in_path, out_sc_bin, out_sc_stats, ref)

        # Ejecutar vectorial
        rc_vc, _, err_vc = run_command([BIN_VECTOR, in_path, out_vc_bin, "1"])
        ok_vc, errs_vc, norm_err_vc = verify_target("vectorial", in_path, out_vc_bin, out_vc_stats, ref)

        # Comparar salida escalar vs vectorial directamente
        _, sc_norm = read_output_bin(out_sc_bin)
        _, vc_norm = read_output_bin(out_vc_bin)
        sc_vs_vc_err = 0.0
        if n > 0 and len(sc_norm) == len(vc_norm) == n:
            sc_vs_vc_err = max(abs(a - b) for a, b in zip(sc_norm, vc_norm))

        passed = ok_sc and ok_vc and (rc_sc == 0) and (rc_vc == 0) and (sc_vs_vc_err <= TOLERANCE)
        if not passed:
            all_passed = False

        status_str = "✓ PASA" if passed else "✗ FALLA"
        sc_str = "OK" if ok_sc else "FAIL"
        vc_str = "OK" if ok_vc else "FAIL"
        max_err_str = f"{sc_vs_vc_err:.2e}" if n > 0 else "0.00"

        print(f"{title:<35} | {n:>5} | {sc_str:^9} | {vc_str:^9} | {max_err_str:^13} | {status_str}")

    print(sep)
    print()
    if all_passed:
        print("[3/3] RESULTADO FINAL: TODOS LOS CASOS EJECUTADOS PASARON (no garantiza otros tamaños)")
        sys.exit(0)
    else:
        print("[3/3] RESULTADO FINAL: AL MENOS UNA PRUEBA FALLÓ")
        sys.exit(1)


if __name__ == "__main__":
    main()

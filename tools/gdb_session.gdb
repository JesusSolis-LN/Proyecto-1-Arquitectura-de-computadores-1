# Requiere make y python3 tools/run_all_tests.py previamente.
# Caso de 16 elementos. Mantener datos y transcripción junto al informe.
set pagination off
set print pretty on
set debuginfod enabled off
set logging file gdb_evidencia.txt
set logging overwrite on
set logging enabled on
file bin/norm_vector
set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_gdb_out.dat 1

# Detener antes de cmp, jge, vmovaps y vaddps del primer bloque.
tbreak *'sum_array.sum_vec_loop'
run
x/4i $pc
stepi 4
echo \n--- YMM0 inmediatamente después de vaddps: primer bloque ---\n
print $ymm0.v8_float
x/8fw $rdi

# Guardar el puntero al entrar; no depender de variables C optimizadas.
tbreak normalize_array
continue
set $salida = $rsi
set $cantidad = $edx
echo \n--- Cantidad y alineación de salida ---\n
print $cantidad
print ((unsigned long)$salida) % 32
finish
echo \n--- Los 16 valores después de normalize_array ---\n
x/16fw $salida
continue
set logging enabled off
quit

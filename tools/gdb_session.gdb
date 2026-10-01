# Script GDB no interactivo para inspección de bajo nivel
# Caso N = 16: inspecciona registros YMM y memoria física
set pagination off
set print pretty on
set debuginfod enabled off

file bin/norm_vector
set args data/test_suite/tc-06_in.dat data/test_suite/tc-06_gdb_out.dat 1

# 1. Breakpoint al entrar a normalize_array
break normalize_array
run

echo \n--- [GDB EVIDENCIA 1] Estado de registros YMM al ingresar a normalize_array ---\n
print $ymm0.v8_float
print $ymm1.v8_float
info register ymm0

# 2. Avanzar dentro del bucle vectorial: carga y resta de la media (14 instrucciones)
stepi 14
echo \n--- [GDB EVIDENCIA 2] Registro YMM0 tras carga y resta de la media (in[0..7] - mean) ---\n
print $ymm0.v8_float
info register ymm0

# 2.1 Avanzar 1 instrucción adicional (división por desviación estándar)
stepi 1
echo \n--- [GDB EVIDENCIA 2.1] Registro YMM0 tras division vectorial por stddev ((in - mean) / stddev) ---\n
print $ymm0.v8_float
info register ymm0

# 3. Continuar hasta finalizar normalize_array
finish

echo \n--- [GDB EVIDENCIA 3] Arreglo normalizado en memoria (&out[0..7]) y comprobacion de alineacion ---\n
print (void*)out
print ((unsigned long)out) % 32
x/8fw out

continue
quit

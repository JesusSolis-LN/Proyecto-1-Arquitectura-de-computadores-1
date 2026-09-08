# Script de automatización de sesión GDB para caso N=16
# Requerimiento: Sección 2.4.a del pliego de especificaciones

set pagination off
set confirm off

break dbg_vec_sum_loop
break dbg_vec_norm_loop

run data/input_small.dat data/output_debug.dat 1

echo \n[REGISTRO YMM0 - Iteracion 1 (indices 0 a 7)]:\n
print $ymm0.v8_float

continue

echo \n[REGISTRO YMM0 - Iteracion 2 (indices 8 a 15)]:\n
print $ymm0.v8_float

continue

echo \n[REGISTRO YMM0 TRAS NORMALIZACION (indices 0 a 7)]:\n
print $ymm0.v8_float

echo \n[MEMORIA out[0..7] TRAS PRIMERA ESCRITURA VECTORIAL]:\n
x/8fw $rsi

continue

echo \n[MEMORIA out[0..15] COMPLETA TRAS SEGUNDA ESCRITURA VECTORIAL]:\n
x/16fw $rsi

continue
quit

; =============================================================
; stats_scalar.asm
; Version ESCALAR (referencia) de los kernels de computo.
;
; Convencion de llamada: System V AMD64 ABI
;   enteros/punteros: rdi, rsi, rdx, rcx, r8, r9
;   flotantes:        xmm0, xmm1, xmm2, ...
;   retorno float:    xmm0
;   callee-saved:     rbx, rbp, r12-r15 (si los usa, debe preservarlos)
; =============================================================

    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;   rdi = arr, esi = n
;   retorna la suma en xmm0
;
; IMPLEMENTADA COMO EJEMPLO: estudien este patron (recorrido,
; acumulador, condicion de salida) antes de escribir compute_stats
; y normalize_array.
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax           ; eax = i = 0
    xorps   xmm0, xmm0         ; xmm0 = acumulador = 0.0

.sum_loop:
    cmp     eax, esi
    jge     .sum_done
    movss   xmm1, [rdi + rax*4]
    addss   xmm0, xmm1
    inc     eax
    jmp     .sum_loop

.sum_done:
    ret

; ---------------------------------------------------------------
; void compute_stats(const float *arr, int n,
;                     float *mean, float *var, float *min, float *max)
;   rdi = arr, esi = n, rdx = mean*, rcx = var*, r8 = min*, r9 = max*
;
;   var = varianza POBLACIONAL = sum((x - mean)^2) / n
;   Caso borde: si n == 0, escriba 0.0 en mean/var/min/max.
;
; TODO (estudiante):
;   1) Calcular mean = suma(arr) / n. Puede reutilizar sum_array con
;      'call sum_array', pero recuerde que eso destruye los
;      registros caller-saved (rax, rcx, rdx, rsi, rdi, r8-r11):
;      guarde arr/n/mean*/var*/min*/max* en registros callee-saved
;      (rbx, r12-r15) ANTES de llamar.
;   2) Recorrer el arreglo una segunda vez para acumular
;      sum((x - mean)^2) y obtener var = esa suma / n.
;   3) Recorrer el arreglo (puede combinarlo con el paso 1) llevando
;      min y max con comiss + saltos condicionales (ja/jb, etc.)
;      o con las instrucciones minss/maxss.
;   4) Guardar los resultados en las direcciones recibidas por
;      puntero: [rdx]=mean, [rcx]=var, [r8]=min, [r9]=max.
;   5) No olvide restaurar los registros callee-saved en el epilogo.
; ---------------------------------------------------------------
compute_stats:
    ; Prólogo: Preservar registros callee-saved según System V AMD64 ABI
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Verificar caso borde: n <= 0
    test    esi, esi
    jle     .stats_zero

    ; Asignar argumentos a registros seguros
    mov     r12, rdi           ; r12  = arr (puntero base)
    mov     r13d, esi          ; r13d = n
    mov     r14, rdx           ; r14  = mean*
    mov     r15, rcx           ; r15  = var*
    mov     rbx, r8            ; rbx  = min*
    mov     rbp, r9            ; rbp  = max*

    ; -----------------------------------------------------------
    ; PASADA 1: Suma, Mínimo y Máximo en un único recorrido
    ; -----------------------------------------------------------
    ; Inicializar sum, min y max con el primer elemento arr[0]
    movss   xmm0, [r12]        ; xmm0 = acumulador de suma
    movaps  xmm1, xmm0         ; xmm1 = min
    movaps  xmm2, xmm0         ; xmm2 = max
    mov     eax, 1             ; eax = i = 1

.pass1_loop:
    cmp     eax, r13d
    jge     .pass1_done
    movss   xmm3, [r12 + rax*4]; xmm3 = arr[i]
    addss   xmm0, xmm3         ; suma += arr[i]
    minss   xmm1, xmm3         ; min = min(min, arr[i])
    maxss   xmm2, xmm3         ; max = max(max, arr[i])
    inc     eax
    jmp     .pass1_loop

.pass1_done:
    ; Calcular mean = sum / n
    cvtsi2ss xmm4, r13d        ; xmm4 = (float)n
    movaps  xmm5, xmm0         ; xmm5 = sum
    divss   xmm5, xmm4         ; xmm5 = mean = sum / n

    ; Guardar min, max y mean en sus respectivas direcciones
    movss   [rbx], xmm1        ; *min  = min
    movss   [rbp], xmm2        ; *max  = max
    movss   [r14], xmm5        ; *mean = mean

    ; -----------------------------------------------------------
    ; PASADA 2: Varianza poblacional: sum((x - mean)^2) / n
    ; -----------------------------------------------------------
    xor     eax, eax           ; eax = i = 0
    xorps   xmm6, xmm6         ; xmm6 = acumulador de diferencias al cuadrado = 0.0

.pass2_loop:
    cmp     eax, r13d
    jge     .pass2_done
    movss   xmm3, [r12 + rax*4]; xmm3 = arr[i]
    subss   xmm3, xmm5         ; xmm3 = arr[i] - mean
    mulss   xmm3, xmm3         ; xmm3 = (arr[i] - mean)^2
    addss   xmm6, xmm3         ; xmm6 += (arr[i] - mean)^2
    inc     eax
    jmp     .pass2_loop

.pass2_done:
    ; Calcular var = suma_cuadrados / n
    divss   xmm6, xmm4         ; xmm6 = var = suma_cuadrados / (float)n
    movss   [r15], xmm6        ; *var  = var
    jmp     .stats_epilogue

.stats_zero:
    ; Caso borde n <= 0: escribir 0.0 en todos los punteros
    xorps   xmm0, xmm0
    movss   [rdx], xmm0        ; *mean = 0.0
    movss   [rcx], xmm0        ; *var  = 0.0
    movss   [r8],  xmm0        ; *min  = 0.0
    movss   [r9],  xmm0        ; *max  = 0.0

.stats_epilogue:
    ; Epílogo: Restaurar registros callee-saved en orden inverso
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
;
;   out[i] = (in[i] - mean) / stddev
;   Caso borde: si stddev == 0.0, copie in[i] en out[i] tal cual
;   (evite division por cero).
; ---------------------------------------------------------------
normalize_array:
    ; Si n <= 0, no hay elementos que procesar
    test    edx, edx
    jle     .norm_done

    ; Verificar si stddev == 0.0 (evitar división por cero)
    xorps   xmm2, xmm2         ; xmm2 = 0.0
    ucomiss xmm1, xmm2         ; comparar stddev con 0.0
    je      .copy_loop         ; si stddev == 0.0, copiar directamente

    ; Bucle principal de normalización: out[i] = (in[i] - mean) / stddev
    xor     eax, eax           ; i = 0

.norm_loop:
    cmp     eax, edx
    jge     .norm_done
    movss   xmm3, [rdi + rax*4]; xmm3 = in[i]
    subss   xmm3, xmm0         ; xmm3 = in[i] - mean
    divss   xmm3, xmm1         ; xmm3 = (in[i] - mean) / stddev
    movss   [rsi + rax*4], xmm3; out[i] = xmm3
    inc     eax
    jmp     .norm_loop

.copy_loop:
    ; Caso borde stddev == 0.0: copiar in[i] a out[i] sin modificar
    xor     eax, eax           ; i = 0

.copy_inner:
    cmp     eax, edx
    jge     .norm_done
    movss   xmm3, [rdi + rax*4]; xmm3 = in[i]
    movss   [rsi + rax*4], xmm3; out[i] = in[i]
    inc     eax
    jmp     .copy_inner

.norm_done:
    ret

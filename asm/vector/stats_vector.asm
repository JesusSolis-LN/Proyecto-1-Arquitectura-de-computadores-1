; =============================================================
; stats_vector.asm
; Version VECTORIZADA (AVX2, 8 floats por iteracion) de los
; kernels de computo. Misma ABI que la version escalar.
;
; Antes de compilar/ejecutar en su maquina, confirme soporte AVX2:
;   lscpu | grep avx2
;   cat /proc/cpuinfo | grep avx2
; =============================================================

    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;   rdi = arr, esi = n -> retorna la suma en xmm0
;
; IMPLEMENTADA COMO EJEMPLO. Fijense especialmente en:
;   (1) como se calcula cuantos elementos entran en bucles de 8
;       ("and ecx, ~7" redondea n hacia abajo al multiplo de 8),
;   (2) la REDUCCION HORIZONTAL para pasar de 8 sumas parciales
;       (un YMM) a un unico escalar,
;   (3) el BUCLE ESCALAR DE CIERRE para el remanente (n % 8 != 0).
; Reutilicen este mismo patron en compute_stats y normalize_array.
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax               ; eax = i = 0
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = acumulador vectorial (8 carriles) = 0

    mov     ecx, esi
    and     ecx, ~7                ; ecx = n redondeado hacia abajo, multiplo de 8
    test    ecx, ecx
    jle     .sum_reduce

.sum_vec_loop:
    cmp     eax, ecx
    jge     .sum_reduce
    vmovaps ymm1, [rdi + rax*4]    ; carga 8 floats alineados a 32 bytes
    vaddps  ymm0, ymm0, ymm1       ; acumula por carril
    add     eax, 8
    jmp     .sum_vec_loop

.sum_reduce:
    ; --- reduccion horizontal: 8 carriles de ymm0 -> un escalar ---
    vextractf128 xmm2, ymm0, 1     ; xmm2 = mitad alta (carriles 4-7)
    vaddps  xmm0, xmm0, xmm2       ; xmm0 = 4 sumas parciales (carriles 0-3 + 4-7)
    vhaddps xmm0, xmm0, xmm0       ; suma horizontal dentro de 128 bits
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = suma total de los 8 carriles originales

.sum_scalar_tail:
    ; --- elementos sobrantes (n % 8), uno a la vez ---
    cmp     eax, esi
    jge     .sum_done
    vmovss  xmm1, [rdi + rax*4]
    vaddss  xmm0, xmm0, xmm1
    inc     eax
    jmp     .sum_scalar_tail

.sum_done:
    vzeroupper                     ; evita penalizacion de transicion AVX/SSE
    ret

; ---------------------------------------------------------------
; void compute_stats(const float *arr, int n,
;                     float *mean, float *var, float *min, float *max)
;   rdi = arr, esi = n, rdx = mean*, rcx = var*, r8 = min*, r9 = max*
;
;   var = varianza POBLACIONAL = sum((x - mean)^2) / n
;   Caso borde: si n <= 0, escriba 0.0 en mean/var/min/max.
; ---------------------------------------------------------------
compute_stats:
    ; Prólogo: Preservar registros callee-saved
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Caso borde: n <= 0
    test    esi, esi
    jle     .stats_vec_zero

    ; Asignar argumentos a registros callee-saved seguros
    mov     r12, rdi               ; r12  = arr (puntero base alineado a 32 bytes)
    mov     r13d, esi              ; r13d = n
    mov     r14, rdx               ; r14  = mean*
    mov     r15, rcx               ; r15  = var*
    mov     rbx, r8                ; rbx  = min*
    mov     rbp, r9                ; rbp  = max*

    ; -----------------------------------------------------------
    ; PASADA 1: Suma, Mínimo y Máximo vectorizados (AVX2)
    ; -----------------------------------------------------------
    mov     ecx, r13d
    and     ecx, ~7                ; ecx = n redondeado a múltiplo de 8
    cmp     ecx, 8
    jl      .pass1_init_scalar     ; si n < 8, procesar todo en bucle escalar

    ; Caso n >= 8: inicializar acumuladores vectoriales con el primer bloque de 8 floats
    vmovaps ymm0, [r12]            ; ymm0 = acumulador de suma (8 carriles)
    vmovaps ymm1, ymm0             ; ymm1 = acumulador de mínimo (8 carriles)
    vmovaps ymm2, ymm0             ; ymm2 = acumulador de máximo (8 carriles)
    mov     eax, 8                 ; eax = i = 8

.pass1_vec_loop:
    cmp     eax, ecx
    jge     .pass1_vec_reduce
    vmovaps ymm3, [r12 + rax*4]    ; carga 8 floats alineados
    vaddps  ymm0, ymm0, ymm3       ; suma por carril
    vminps  ymm1, ymm1, ymm3       ; mínimo por carril
    vmaxps  ymm2, ymm2, ymm3       ; máximo por carril
    add     eax, 8
    jmp     .pass1_vec_loop

.pass1_vec_reduce:
    ; --- Reducción horizontal de suma (ymm0 -> xmm0) ---
    vextractf128 xmm3, ymm0, 1
    vaddps  xmm0, xmm0, xmm3
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0

    ; --- Reducción horizontal de mínimo (ymm1 -> xmm1) ---
    ; Nota: AVX2 no tiene vhminps; se reduce mediante shuffles
    vextractf128 xmm3, ymm1, 1
    vminps  xmm1, xmm1, xmm3
    vshufps xmm3, xmm1, xmm1, 0x4E ; intercambia mitades de 64 bits (carriles [2,3,0,1])
    vminps  xmm1, xmm1, xmm3
    vshufps xmm3, xmm1, xmm1, 0xB1 ; intercambia carriles adyacentes de 32 bits ([1,0,3,2])
    vminps  xmm1, xmm1, xmm3       ; xmm1[0] = mínimo de los 8 carriles

    ; --- Reducción horizontal de máximo (ymm2 -> xmm2) ---
    vextractf128 xmm3, ymm2, 1
    vmaxps  xmm2, xmm2, xmm3
    vshufps xmm3, xmm2, xmm2, 0x4E
    vmaxps  xmm2, xmm2, xmm3
    vshufps xmm3, xmm2, xmm2, 0xB1
    vmaxps  xmm2, xmm2, xmm3       ; xmm2[0] = máximo de los 8 carriles
    jmp     .pass1_tail_loop

.pass1_init_scalar:
    ; Inicialización para n < 8: cargar primer escalar arr[0]
    vmovss  xmm0, [r12]            ; xmm0 = sum
    vmovaps xmm1, xmm0             ; xmm1 = min
    vmovaps xmm2, xmm0             ; xmm2 = max
    mov     eax, 1                 ; eax = i = 1

.pass1_tail_loop:
    ; Bucle de remanente escalar (tail loop)
    cmp     eax, r13d
    jge     .pass1_done
    vmovss  xmm3, [r12 + rax*4]
    vaddss  xmm0, xmm0, xmm3
    vminss  xmm1, xmm1, xmm3
    vmaxss  xmm2, xmm2, xmm3
    inc     eax
    jmp     .pass1_tail_loop

.pass1_done:
    ; Calcular mean = sum / n
    vcvtsi2ss xmm4, xmm4, r13d     ; xmm4 = (float)n
    vdivss  xmm5, xmm0, xmm4       ; xmm5 = mean = sum / n

    ; Guardar min, max y mean en memoria
    vmovss  [rbx], xmm1            ; *min  = min
    vmovss  [rbp], xmm2            ; *max  = max
    vmovss  [r14], xmm5            ; *mean = mean

    ; -----------------------------------------------------------
    ; PASADA 2: Varianza vectorizada: sum((x - mean)^2) / n
    ; -----------------------------------------------------------
    ; Expandir mean a todos los 8 carriles de ymm3 con vbroadcastss
    vbroadcastss ymm3, xmm5        ; ymm3 = [mean, mean, ..., mean]
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = acumulador vectorial de varianza = 0.0
    xor     eax, eax               ; eax = i = 0

    mov     ecx, r13d
    and     ecx, ~7                ; ecx = n & ~7
    test    ecx, ecx
    jle     .pass2_reduce

    vxorps  ymm6, ymm6, ymm6       ; compensacion Kahan por carril

.pass2_vec_loop:
    cmp     eax, ecx
    jge     .pass2_reduce
    vmovaps ymm1, [r12 + rax*4]    ; carga 8 floats
    vsubps  ymm1, ymm1, ymm3       ; ymm1 = arr[i..i+7] - mean
    vmulps  ymm1, ymm1, ymm1       ; ymm1 = (arr[i..i+7] - mean)^2
    ; Kahan: ocho acumulaciones independientes en float32
    vsubps  ymm1, ymm1, ymm6       ; y = cuadrado - compensacion
    vaddps  ymm7, ymm0, ymm1       ; t = suma + y
    vsubps  ymm6, ymm7, ymm0
    vsubps  ymm6, ymm6, ymm1       ; compensacion = (t - suma) - y
    vmovaps ymm0, ymm7            ; suma = t
    add     eax, 8
    jmp     .pass2_vec_loop

.pass2_reduce:
    ; Reducción horizontal del acumulador cuadrático (ymm0 -> xmm0)
    vextractf128 xmm1, ymm0, 1
    vaddps  xmm0, xmm0, xmm1
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = suma cuadrática parcial

    vxorps  xmm6, xmm6, xmm6       ; compensacion del remanente

.pass2_tail_loop:
    ; Bucle de remanente escalar para la varianza
    cmp     eax, r13d
    jge     .pass2_done
    vmovss  xmm1, [r12 + rax*4]
    vsubss  xmm1, xmm1, xmm5       ; xmm1 = arr[i] - mean
    vmulss  xmm1, xmm1, xmm1       ; xmm1 = (arr[i] - mean)^2
    vsubss  xmm1, xmm1, xmm6
    vaddss  xmm7, xmm0, xmm1
    vsubss  xmm6, xmm7, xmm0
    vsubss  xmm6, xmm6, xmm1
    vmovaps xmm0, xmm7
    inc     eax
    jmp     .pass2_tail_loop

.pass2_done:
    ; Calcular var = suma_cuadratica / n
    vcvtsi2ss xmm4, xmm4, r13d     ; xmm4 = (float)n
    vdivss  xmm0, xmm0, xmm4       ; xmm0 = var = suma_cuadrática / (float)n
    vmovss  [r15], xmm0            ; *var  = var
    jmp     .stats_vec_epilogue

.stats_vec_zero:
    ; Caso borde n <= 0: escribir 0.0 en los 4 punteros
    vxorps  xmm0, xmm0, xmm0
    vmovss  [rdx], xmm0            ; *mean = 0.0
    vmovss  [rcx], xmm0            ; *var  = 0.0
    vmovss  [r8],  xmm0            ; *min  = 0.0
    vmovss  [r9],  xmm0            ; *max  = 0.0

.stats_vec_epilogue:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    vzeroupper
    ret

; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
;
;   out[i] = (in[i] - mean) / stddev
;   Caso borde: si stddev == 0.0, copie in[i] en out[i] tal cual.
; ---------------------------------------------------------------
normalize_array:
    ; Si n <= 0, retornar inmediatamente
    test    edx, edx
    jle     .norm_vec_ret

    ; Verificar si stddev == 0.0 (evitar división por cero)
    vxorps  xmm2, xmm2, xmm2
    vucomiss xmm1, xmm2
    je      .norm_copy_loop

    ; Caso general: stddev > 0.0
    ; Replicar mean y stddev en todos los 8 carriles YMM
    vbroadcastss ymm4, xmm0        ; ymm4 = [mean, mean, ..., mean]
    vbroadcastss ymm5, xmm1        ; ymm5 = [stddev, stddev, ..., stddev]

    mov     ecx, edx
    and     ecx, ~7                ; ecx = n redondeado a múltiplo de 8
    xor     eax, eax               ; eax = i = 0

.norm_vec_loop:
    cmp     eax, ecx
    jge     .norm_scalar_tail
    vmovaps ymm0, [rdi + rax*4]    ; carga 8 floats alineados
    vsubps  ymm0, ymm0, ymm4       ; ymm0 = in[i..i+7] - mean
    vdivps  ymm0, ymm0, ymm5       ; ymm0 = (in[i..i+7] - mean) / stddev
    vmovaps [rsi + rax*4], ymm0    ; guarda 8 floats alineados
    add     eax, 8
    jmp     .norm_vec_loop

.norm_scalar_tail:
    ; Bucle escalar de cierre para los elementos remanentes (n % 8)
    cmp     eax, edx
    jge     .norm_vec_done
    vmovss  xmm2, [rdi + rax*4]
    vsubss  xmm2, xmm2, xmm4       ; xmm4 conserva el mean escalar en carril 0
    vdivss  xmm2, xmm2, xmm5       ; xmm5 conserva el stddev escalar en carril 0
    vmovss  [rsi + rax*4], xmm2
    inc     eax
    jmp     .norm_scalar_tail

.norm_copy_loop:
    ; Caso borde stddev == 0.0: copiar in[i] en out[i] directamente
    mov     ecx, edx
    and     ecx, ~7
    xor     eax, eax

.norm_copy_vec:
    cmp     eax, ecx
    jge     .norm_copy_tail
    vmovaps ymm0, [rdi + rax*4]    ; carga 8 floats
    vmovaps [rsi + rax*4], ymm0    ; almacena 8 floats
    add     eax, 8
    jmp     .norm_copy_vec

.norm_copy_tail:
    cmp     eax, edx
    jge     .norm_vec_done
    vmovss  xmm0, [rdi + rax*4]
    vmovss  [rsi + rax*4], xmm0
    inc     eax
    jmp     .norm_copy_tail

.norm_vec_done:
    vzeroupper

.norm_vec_ret:
    ret

; ==============================================================================
; ARCHIVO: stats_vector.asm (Ubicación: asm/vector/stats_vector.asm)
; PROYECTO: Normalizador estadístico vectorizado (Esqueleto de Cátedra)
; DESCRIPCIÓN: Versión VECTORIZADA (SIMD AVX2, 8 floats por iteración) de los
;              kernels de cómputo.
;              Cumple con la Sección 2.3: utiliza instrucciones alineadas a 32
;              bytes (vmovaps) en el camino principal y bucle escalar para el
;              remanente (tail loop).
;
; CONVENCIÓN DE LLAMADA: System V AMD64 ABI (Linux 64 bits)
;   - Argumentos enteros/punteros: RDI, RSI, RDX, RCX, R8, R9
;   - Argumentos flotantes:        XMM0, XMM1, XMM2, ...
;   - Retorno flotante:            XMM0
;   - Registros callee-saved:      RBX, RBP, R12, R13, R14, R15, RSP
;   - Registros caller-saved:      RAX, RCX, RDX, RSI, RDI, R8-R11, YMM0-YMM15
; ==============================================================================

    global sum_array
    global compute_stats
    global normalize_array

    ; Símbolos de depuración exportados para inspección en GDB
    global dbg_vec_sum_init
    global dbg_vec_sum_loop
    global dbg_vec_sum_reduce
    global dbg_vec_sum_tail
    global dbg_vec_sum_done

    global dbg_vec_stats_init
    global dbg_vec_stats_p1_loop
    global dbg_vec_stats_p1_reduce
    global dbg_vec_stats_mean_done
    global dbg_vec_stats_p2_loop
    global dbg_vec_stats_p2_reduce
    global dbg_vec_stats_done

    global dbg_vec_norm_init
    global dbg_vec_norm_loop
    global dbg_vec_norm_tail
    global dbg_vec_norm_done

section .rodata
    align 32
    const_one:     dd 1.0           ; 1.0f (32 bits IEEE 754)
    epsilon:       dd 1.0e-12       ; Tolerancia para detección de stddev == 0.0

section .text

; ==============================================================================
; FUNCIÓN 1: sum_array
; FIRMA EN C: float sum_array(const float *arr, int n);
;
; ECUACIÓN MATEMÁTICA:
;   S = \sum_{i=0}^{n-1} arr[i]
;
; VECTORIZACIÓN AVX2:
;   - 8 floats procesados por instrucción con vmovaps y vaddps (256 bits alineados).
;   - Reducción horizontal de 8 carriles -> 1 escalar mediante vextractf128 + vaddps + vhaddps.
;   - Bucle escalar de cierre para el remanente (n % 8) con vmovss / vaddss.
; ==============================================================================
sum_array:
    xor     eax, eax                ; eax = i = 0
    vxorps  ymm0, ymm0, ymm0        ; ymm0 = acumulador vectorial (8 carriles) = 0.0f

    mov     ecx, esi
    and     ecx, ~7                 ; ecx = n redondeado hacia abajo al múltiplo de 8
    test    ecx, ecx
    jle     vec_sum_reduce

dbg_vec_sum_init:
    nop

vec_sum_loop:
    cmp     eax, ecx
    jge     vec_sum_reduce

    ; Cargar 8 floats alineados a 32 bytes y sumar en paralelo a los 8 acumuladores
    vmovaps ymm1, [rdi + rax*4]     ; ymm1 = arr[i .. i+7] (alineado a 32 bytes)
    vaddps  ymm0, ymm0, ymm1        ; ymm0[0..7] += ymm1[0..7]

dbg_vec_sum_loop:
    add     eax, 8                  ; Avanzar 8 floats (offset de 32 bytes)
    jmp     vec_sum_loop

vec_sum_reduce:
dbg_vec_sum_reduce:
    ; --- Reducción horizontal: 8 carriles de ymm0 -> 1 escalar en xmm0[0] ---
    vextractf128 xmm2, ymm0, 1      ; xmm2 = carriles altos [4..7] de ymm0
    vaddps  xmm0, xmm0, xmm2        ; xmm0 = [0+4, 1+5, 2+6, 3+7] (4 sumas parciales)
    vhaddps xmm0, xmm0, xmm0        ; xmm0 = [(0+4)+(1+5), (2+6)+(3+7), ...]
    vhaddps xmm0, xmm0, xmm0        ; xmm0[0] = suma total de los 8 carriles originales

vec_sum_tail:
dbg_vec_sum_tail:
    ; --- Bucle escalar de cierre para el remanente (n % 8) ---
    cmp     eax, esi
    jge     vec_sum_done
    vmovss  xmm1, [rdi + rax*4]     ; Cargar float escalar sobrante
    vaddss  xmm0, xmm0, xmm1        ; Suma escalar al acumulador
    inc     eax                     ; Avanzar 1 float
    jmp     vec_sum_tail

dbg_vec_sum_done:
vec_sum_done:
    vzeroupper                      ; Evita penalización de transición AVX/SSE
    ret


; ==============================================================================
; FUNCIÓN 2: compute_stats
; FIRMA EN C:
;   void compute_stats(const float *arr, int n,
;                      float *mean, float *var, float *min, float *max);
;
; ECUACIONES MATEMÁTICAS:
;   1. Suma:     S = \sum arr[i]
;   2. Media:    \mu = S / n
;   3. Mín/Máx:  min = \min(arr[i]), \quad max = \max(arr[i])
;   4. Varianza: \sigma^2 = \frac{1}{n} \sum (arr[i] - \mu)^2
;
; OPTIMIZACIÓN VECTORIAL AVX2:
;   - Pasada 1: Carga 8 floats alineados (vmovaps) por iteración y calcula:
;               * Suma vectorial (vaddps ymm0)
;               * Mínimo vectorial (vminps ymm4)
;               * Máximo vectorial (vmaxps ymm5)
;   - Reducción horizontal de Suma, Mínimo y Máximo.
;   - Remanente escalar para Pasada 1 (vaddss, vminss, vmaxss).
;   - Pasada 2: Broadcast de \mu a los 8 carriles (vbroadcastss ymm7) y cálculo
;               vectorizado de diferencias al cuadrado (vsubps + vmulps) con vmovaps.
;   - Reducción horizontal de suma de cuadrados y división final por n.
; ==============================================================================
compute_stats:
    ; --------------------------------------------------------------------------
    ; 1. Prólogo: Preservar registros callee-saved (System V ABI)
    ; --------------------------------------------------------------------------
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; --------------------------------------------------------------------------
    ; 2. Validación de caso borde: n == 0
    ; --------------------------------------------------------------------------
    test    esi, esi                ; ¿n <= 0?
    jle     vec_stats_zero_n

    ; Preservar punteros y argumentos
    mov     r12, rdi                ; r12 = arr
    mov     r13d, esi               ; r13d = n
    mov     r14, rdx                ; r14 = mean*
    mov     r15, rcx                ; r15 = var*
    mov     rbx, r8                 ; rbx = min*
    mov     rbp, r9                 ; rbp = max*

    ; --------------------------------------------------------------------------
    ; 3. PASADA 1 (VECTORIAL): Suma, Mínimo y Máximo
    ; --------------------------------------------------------------------------
    vxorps  ymm0, ymm0, ymm0        ; ymm0 (suma) = [0.0 ... 0.0]
    vbroadcastss ymm4, [r12]        ; ymm4 (min) = [arr[0] ... arr[0]]
    vbroadcastss ymm5, [r12]        ; ymm5 (max) = [arr[0] ... arr[0]]

    mov     ecx, r13d
    and     ecx, ~7                 ; ecx = n redondeado al múltiplo de 8
    xor     eax, eax                ; eax (i) = 0

dbg_vec_stats_init:
    nop

vec_stats_p1_vec_loop:
    cmp     eax, ecx
    jge     vec_stats_p1_reduce

    vmovaps ymm1, [r12 + rax*4]     ; Cargar 8 floats alineados (32 bytes)
    vaddps  ymm0, ymm0, ymm1        ; ymm0 += ymm1 (Suma)
    vminps  ymm4, ymm4, ymm1        ; ymm4 = min(ymm4, ymm1)
    vmaxps  ymm5, ymm5, ymm1        ; ymm5 = max(ymm5, ymm1)

dbg_vec_stats_p1_loop:
    add     eax, 8
    jmp     vec_stats_p1_vec_loop

vec_stats_p1_reduce:
dbg_vec_stats_p1_reduce:
    ; --- Reducción horizontal de la Suma (ymm0) ---
    vextractf128 xmm2, ymm0, 1
    vaddps  xmm0, xmm0, xmm2
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0        ; xmm0[0] = suma del bucle vectorial

    ; --- Reducción horizontal del Mínimo (ymm4) ---
    vextractf128 xmm2, ymm4, 1
    vminps  xmm4, xmm4, xmm2        ; 4 floats
    vshufps xmm2, xmm4, xmm4, 0x4E  ; swap carriles 64-bit
    vminps  xmm4, xmm4, xmm2        ; 2 floats
    vshufps xmm2, xmm4, xmm4, 0xB1  ; swap carriles 32-bit
    vminps  xmm4, xmm4, xmm2        ; xmm4[0] = mínimo vectorial

    ; --- Reducción horizontal del Máximo (ymm5) ---
    vextractf128 xmm2, ymm5, 1
    vmaxps  xmm5, xmm5, xmm2        ; 4 floats
    vshufps xmm2, xmm5, xmm5, 0x4E  ; swap carriles 64-bit
    vmaxps  xmm5, xmm5, xmm2        ; 2 floats
    vshufps xmm2, xmm5, xmm5, 0xB1  ; swap carriles 32-bit
    vmaxps  xmm5, xmm5, xmm2        ; xmm5[0] = máximo vectorial

vec_stats_p1_tail:
    ; --- Bucle escalar de cierre para Pasada 1 ---
    cmp     eax, r13d
    jge     vec_stats_p1_done
    vmovss  xmm1, [r12 + rax*4]
    vaddss  xmm0, xmm0, xmm1        ; Suma escalar remanente
    vminss  xmm4, xmm4, xmm1        ; Mínimo escalar remanente
    vmaxss  xmm5, xmm5, xmm1        ; Máximo escalar remanente
    inc     eax
    jmp     vec_stats_p1_tail

vec_stats_p1_done:
    ; --------------------------------------------------------------------------
    ; 4. Calcular Media: \mu = S / n
    ; --------------------------------------------------------------------------
    vcvtsi2ss xmm1, xmm1, r13d      ; xmm1 = (float)n
    vdivss  xmm0, xmm0, xmm1        ; xmm0 = \mu = suma / n

    ; Almacenar Media, Mínimo y Máximo en memoria
    vmovss  [r14], xmm0             ; *mean = \mu
    vmovss  [rbx], xmm4             ; *min = min
    vmovss  [rbp], xmm5             ; *max = max

dbg_vec_stats_mean_done:
    nop

    ; --------------------------------------------------------------------------
    ; 5. PASADA 2 (VECTORIAL): Varianza Poblacional \sigma^2 = \frac{1}{n}\sum(x_i - \mu)^2
    ; --------------------------------------------------------------------------
    vbroadcastss ymm7, xmm0         ; ymm7 = [\mu, \mu, \mu, \mu, \mu, \mu, \mu, \mu] (Broadcast de media)
    vxorps  ymm3, ymm3, ymm3        ; ymm3 = acumulador de sumas cuadráticas = 0.0f
    mov     ecx, r13d
    and     ecx, ~7                 ; ecx = n redondeado al múltiplo de 8
    xor     eax, eax                ; eax (i) = 0

vec_stats_p2_vec_loop:
    cmp     eax, ecx
    jge     vec_stats_p2_reduce

    vmovaps ymm1, [r12 + rax*4]     ; Cargar 8 floats alineados (32 bytes)
    vsubps  ymm6, ymm1, ymm7        ; ymm6 = x_i - \mu (8 diferencias simultáneas)
    vmulps  ymm6, ymm6, ymm6        ; ymm6 = (x_i - \mu)^2 (8 cuadrados)
    vaddps  ymm3, ymm3, ymm6        ; ymm3 += (x_i - \mu)^2

dbg_vec_stats_p2_loop:
    add     eax, 8
    jmp     vec_stats_p2_vec_loop

vec_stats_p2_reduce:
dbg_vec_stats_p2_reduce:
    ; --- Reducción horizontal de la suma de cuadrados (ymm3) ---
    vextractf128 xmm2, ymm3, 1
    vaddps  xmm3, xmm3, xmm2
    vhaddps xmm3, xmm3, xmm3
    vhaddps xmm3, xmm3, xmm3        ; xmm3[0] = suma de cuadrados vectorial

vec_stats_p2_tail:
    ; --- Bucle escalar de cierre para Pasada 2 ---
    cmp     eax, r13d
    jge     vec_stats_p2_done
    vmovss  xmm1, [r12 + rax*4]
    vsubss  xmm6, xmm1, xmm7        ; diff = x_i - \mu (xmm7 es el broadcast de \mu)
    vmulss  xmm6, xmm6, xmm6        ; sq_diff = diff^2
    vaddss  xmm3, xmm3, xmm6        ; Acumular al escalar
    inc     eax
    jmp     vec_stats_p2_tail

vec_stats_p2_done:
    ; Calcular varianza: \sigma^2 = sum_sq / n
    vcvtsi2ss xmm1, xmm1, r13d      ; xmm1 = (float)n
    vdivss  xmm3, xmm3, xmm1        ; xmm3 = sum_sq / (float)n
    vmovss  [r15], xmm3             ; *var = \sigma^2

dbg_vec_stats_done:
    jmp     vec_stats_epilogue

vec_stats_zero_n:
    ; Caso borde n == 0: escribir 0.0f en los 4 punteros
    vxorps  xmm0, xmm0, xmm0
    test    rdx, rdx
    jz      vec_stats_epilogue
    vmovss  [rdx], xmm0             ; *mean = 0.0f
    vmovss  [rcx], xmm0             ; *var  = 0.0f
    vmovss  [r8],  xmm0             ; *min  = 0.0f
    vmovss  [r9],  xmm0             ; *max  = 0.0f

vec_stats_epilogue:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    vzeroupper
    ret


; ==============================================================================
; FUNCIÓN 3: normalize_array
; FIRMA EN C:
;   void normalize_array(const float *in, float *out, int n,
;                        float mean, float stddev);
;
; ECUACIÓN MATEMÁTICA:
;   out[i] = \frac{in[i] - \mu}{\sigma} = (in[i] - \mu) \times \frac{1}{\sigma}
;
; CASO BORDE (stats.h):
;   Si stddev == 0.0 (o < epsilon), copie in[i] en out[i] tal cual.
;
; VECTORIZACIÓN AVX2:
;   - vbroadcastss para replicar \mu y (1/\sigma) en todos los 8 carriles.
;   - Bucle vectorial de 8 en 8 con vsubps y vmulps usando vmovaps (alineado).
;   - Bucle escalar de cierre para el remanente (n % 8).
; ==============================================================================
normalize_array:
    ; --------------------------------------------------------------------------
    ; 1. Validación de caso borde: n <= 0
    ; --------------------------------------------------------------------------
    test    edx, edx                ; ¿n <= 0?
    jle     vec_norm_done

    ; --------------------------------------------------------------------------
    ; 2. Comprobar caso borde: stddev == 0.0
    ; --------------------------------------------------------------------------
    vucomiss xmm1, [rel epsilon]
    jb      vec_norm_copy_avx       ; Si stddev < epsilon, copiar in[i] -> out[i] tal cual

    ; --------------------------------------------------------------------------
    ; 3. Precalcular factor de escala inverso y Broadcast vectorial
    ; --------------------------------------------------------------------------
    vbroadcastss ymm7, xmm0         ; ymm7 = [\mu, \mu, \mu, \mu, \mu, \mu, \mu, \mu]
    vmovss  xmm2, [rel const_one]   ; xmm2 = 1.0f
    vdivss  xmm2, xmm2, xmm1        ; xmm2 = 1.0f / \sigma (inv_stddev)
    vbroadcastss ymm8, xmm2         ; ymm8 = [1/\sigma, 1/\sigma, ..., 1/\sigma]

    mov     ecx, edx
    and     ecx, ~7                 ; ecx = n redondeado al múltiplo de 8
    xor     eax, eax                ; eax (i) = 0

dbg_vec_norm_init:
    nop

vec_norm_loop:
    cmp     eax, ecx
    jge     vec_norm_tail

    ; Cargar 8 floats alineados a 32 bytes
    vmovaps ymm0, [rdi + rax*4]     ; ymm0 = in[i .. i+7] (alineado a 32 bytes)
    vsubps  ymm0, ymm0, ymm7        ; ymm0 = in[i] - \mu
    vmulps  ymm0, ymm0, ymm8        ; ymm0 = (in[i] - \mu) * (1 / \sigma)
    vmovaps [rsi + rax*4], ymm0     ; out[i .. i+7] = ymm0 (alineado a 32 bytes)

dbg_vec_norm_loop:
    add     eax, 8
    jmp     vec_norm_loop

vec_norm_tail:
dbg_vec_norm_tail:
    ; --- Bucle escalar de cierre para remanente (n % 8) ---
    cmp     eax, edx
    jge     vec_norm_done
    vmovss  xmm0, [rdi + rax*4]
    vsubss  xmm0, xmm0, xmm7
    vmulss  xmm0, xmm0, xmm8
    vmovss  [rsi + rax*4], xmm0
    inc     eax
    jmp     vec_norm_tail

vec_norm_copy_avx:
    ; Caso borde stddev == 0.0: copiar in[i] en out[i] de 8 en 8 alineado
    mov     ecx, edx
    and     ecx, ~7
    xor     eax, eax

vec_norm_copy_vec_loop:
    cmp     eax, ecx
    jge     vec_norm_copy_tail
    vmovaps ymm0, [rdi + rax*4]
    vmovaps [rsi + rax*4], ymm0
    add     eax, 8
    jmp     vec_norm_copy_vec_loop

vec_norm_copy_tail:
    cmp     eax, edx
    jge     vec_norm_done
    vmovss  xmm0, [rdi + rax*4]
    vmovss  [rsi + rax*4], xmm0
    inc     eax
    jmp     vec_norm_copy_tail

dbg_vec_norm_done:
vec_norm_done:
    vzeroupper
    ret

; ==============================================================================
; ARCHIVO: stats_scalar.asm (Ubicación: asm/scalar/stats_scalar.asm)
; PROYECTO: Normalizador estadístico vectorizado (Esqueleto de Cátedra)
; DESCRIPCIÓN: Versión ESCALAR pura (SISD / SSE escalar) de los kernels de cómputo.
;              Procesa 1 elemento (float de 32 bits) por iteración.
;
; CONVENCIÓN DE LLAMADA: System V AMD64 ABI (Linux 64 bits)
;   - Argumentos enteros/punteros: RDI, RSI, RDX, RCX, R8, R9
;   - Argumentos flotantes:        XMM0, XMM1, XMM2, ...
;   - Retorno flotante:            XMM0
;   - Registros callee-saved:      RBX, RBP, R12, R13, R14, R15, RSP
;   - Registros caller-saved:      RAX, RCX, RDX, RSI, RDI, R8-R11, XMM0-XMM15
; ==============================================================================

    global sum_array
    global compute_stats
    global normalize_array

    ; Símbolos de depuración exportados para inspección paso a paso en GDB
    global dbg_sc_sum_init
    global dbg_sc_sum_loop
    global dbg_sc_sum_done
    global dbg_sc_stats_init
    global dbg_sc_stats_p1_loop
    global dbg_sc_stats_mean_done
    global dbg_sc_stats_p2_loop
    global dbg_sc_stats_done
    global dbg_sc_norm_init
    global dbg_sc_norm_loop
    global dbg_sc_norm_done

section .rodata
    align 16
    const_zero:    dd 0.0           ; 0.0f (32 bits IEEE 754)
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
; MAPEO DE REGISTROS (System V ABI):
;   - Entrada:
;       RDI  : const float *arr (Puntero al arreglo)
;       ESI  : int n            (Cantidad de elementos)
;   - Salida:
;       XMM0 : float            (Suma acumulada total)
;   - Registros de trabajo:
;       EAX  : int i            (Índice de iteración: 0, 1, ..., n-1)
;       XMM1 : float            (Elemento actual arr[i])
; ==============================================================================
sum_array:
    ; --------------------------------------------------------------------------
    ; 1. Validación de caso borde: n <= 0
    ; --------------------------------------------------------------------------
    xorps   xmm0, xmm0              ; xmm0 = 0.0f (Inicializar acumulador)
    test    esi, esi                ; ¿n <= 0?
    jle     sc_sum_done             ; Si n <= 0, retornar 0.0f de forma controlada

    ; --------------------------------------------------------------------------
    ; 2. Inicialización del bucle escalar
    ; --------------------------------------------------------------------------
    xor     eax, eax                ; eax = i = 0

dbg_sc_sum_init:
    ; ==========================================================================
    ; BREAKPOINT GDB: dbg_sc_sum_init
    ; ESTADO ESPERADO:
    ;   - RDI  : Dirección base de arr
    ;   - ESI  : n
    ;   - EAX  : 0 (i = 0)
    ;   - XMM0 : 0.0f
    ; ==========================================================================
    nop

sc_sum_loop:
    cmp     eax, esi                ; ¿i >= n?
    jge     sc_sum_done

    ; Ecuación: xmm0 = xmm0 + arr[i]
    movss   xmm1, [rdi + rax*4]     ; Cargar float32: xmm1 = arr[i]
    addss   xmm0, xmm1              ; xmm0 = xmm0 + arr[i]

dbg_sc_sum_loop:
    inc     eax                     ; i = i + 1
    jmp     sc_sum_loop

dbg_sc_sum_done:
sc_sum_done:
    ret


; ==============================================================================
; FUNCIÓN 2: compute_stats
; FIRMA EN C:
;   void compute_stats(const float *arr, int n,
;                      float *mean, float *var, float *min, float *max);
;
; ECUACIONES MATEMÁTICAS:
;   1. Suma:       S = \sum_{i=0}^{n-1} arr[i]
;   2. Media:      \mu = \frac{S}{n}
;   3. Mín/Máx:    min = \min_{i}(arr[i]), \quad max = \max_{i}(arr[i])
;   4. Varianza:   \sigma^2 = \frac{1}{n} \sum_{i=0}^{n-1} (arr[i] - \mu)^2
;
; MAPEO DE REGISTROS (System V ABI):
;   - Entrada:
;       RDI  : const float *arr (Puntero a datos)
;       ESI  : int n            (Cantidad de elementos)
;       RDX  : float *mean      (Puntero donde guardar \mu)
;       RCX  : float *var       (Puntero donde guardar \sigma^2)
;       R8   : float *min       (Puntero donde guardar mínimo)
;       R9   : float *max       (Puntero donde guardar máximo)
;   - Registros callee-saved preservados:
;       R12  : arr
;       R13D : n
;       R14  : mean*
;       R15  : var*
;       RBX  : min*
;       RBP  : max*
; ==============================================================================
compute_stats:
    ; --------------------------------------------------------------------------
    ; 1. Prólogo: Preservar registros callee-saved según ABI System V AMD64
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
    jle     sc_stats_zero_n

    ; Guardar argumentos en registros callee-saved
    mov     r12, rdi                ; r12 = arr
    mov     r13d, esi               ; r13d = n
    mov     r14, rdx                ; r14 = mean*
    mov     r15, rcx                ; r15 = var*
    mov     rbx, r8                 ; rbx = min*
    mov     rbp, r9                 ; rbp = max*

    ; --------------------------------------------------------------------------
    ; 3. PASO 1: Calcular Suma S, Mínimo y Máximo en un solo recorrido
    ; --------------------------------------------------------------------------
    movss   xmm4, [r12]             ; xmm4 (min) = arr[0]
    movss   xmm5, [r12]             ; xmm5 (max) = arr[0]
    xorps   xmm0, xmm0              ; xmm0 (suma) = 0.0f
    xor     eax, eax                ; eax (i) = 0

dbg_sc_stats_init:
    nop

sc_stats_p1_loop:
    cmp     eax, r13d
    jge     sc_stats_p1_done

    movss   xmm2, [r12 + rax*4]     ; Cargar float32: xmm2 = arr[i]

    ; Ecuación: suma = suma + arr[i]
    addss   xmm0, xmm2              ; xmm0 += arr[i]

    ; Ecuaciones: min = min(min, arr[i]), max = max(max, arr[i])
    minss   xmm4, xmm2              ; xmm4 = min(xmm4, arr[i])
    maxss   xmm5, xmm2              ; xmm5 = max(xmm5, arr[i])

dbg_sc_stats_p1_loop:
    inc     eax                     ; i = i + 1
    jmp     sc_stats_p1_loop

sc_stats_p1_done:
    ; --------------------------------------------------------------------------
    ; 4. Calcular la Media: \mu = S / n
    ; --------------------------------------------------------------------------
    cvtsi2ss xmm1, r13d             ; xmm1 = (float)n
    divss   xmm0, xmm1              ; xmm0 = xmm0 / xmm1 (\mu = suma / n)

    ; Guardar Media, Mínimo y Máximo en las direcciones recibidas por puntero
    movss   [r14], xmm0             ; *mean = \mu (en [R14])
    movss   [rbx], xmm4             ; *min  = min (en [RBX])
    movss   [rbp], xmm5             ; *max  = max (en [RBP])

dbg_sc_stats_mean_done:
    nop

    ; --------------------------------------------------------------------------
    ; 5. PASO 2: Calcular Varianza Poblacional: \sigma^2 = \frac{1}{n} \sum (arr[i] - \mu)^2
    ; --------------------------------------------------------------------------
    xorps   xmm3, xmm3              ; xmm3 = 0.0f (Acumulador de suma cuadrática)
    xor     eax, eax                ; eax (i) = 0

sc_stats_p2_loop:
    cmp     eax, r13d
    jge     sc_stats_p2_done

    movss   xmm2, [r12 + rax*4]     ; xmm2 = arr[i]
    movaps  xmm6, xmm2              ; xmm6 = arr[i]

    ; Ecuación: diff = arr[i] - \mu
    subss   xmm6, xmm0              ; xmm6 = arr[i] - \mu

    ; Ecuación: sq_diff = diff * diff = (arr[i] - \mu)^2
    mulss   xmm6, xmm6              ; xmm6 = (arr[i] - \mu)^2

    ; Ecuación: sum_sq = sum_sq + sq_diff
    addss   xmm3, xmm6              ; xmm3 += (arr[i] - \mu)^2

dbg_sc_stats_p2_loop:
    inc     eax                     ; i = i + 1
    jmp     sc_stats_p2_loop

sc_stats_p2_done:
    ; Ecuación: \sigma^2 = sum_sq / n
    divss   xmm3, xmm1              ; xmm3 = sum_sq / (float)n
    movss   [r15], xmm3             ; *var = \sigma^2 (en [R15])

dbg_sc_stats_done:
    jmp     sc_stats_epilogue

sc_stats_zero_n:
    ; Caso borde n == 0: escribir 0.0f en los 4 punteros de salida
    xorps   xmm0, xmm0
    test    rdx, rdx
    jz      sc_stats_epilogue
    movss   [rdx], xmm0             ; *mean = 0.0f
    movss   [rcx], xmm0             ; *var  = 0.0f
    movss   [r8],  xmm0             ; *min  = 0.0f
    movss   [r9],  xmm0             ; *max  = 0.0f

sc_stats_epilogue:
    ; --------------------------------------------------------------------------
    ; 6. Epílogo: Restaurar registros callee-saved
    ; --------------------------------------------------------------------------
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
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
; MAPEO DE REGISTROS (System V ABI):
;   - Entrada:
;       RDI  : const float *in   (Puntero al arreglo de entrada)
;       RSI  : float *out        (Puntero al arreglo de salida)
;       EDX  : int n             (Cantidad de elementos)
;       XMM0 : float mean        (Media \mu)
;       XMM1 : float stddev      (Desviación estándar \sigma)
;   - Registros de trabajo:
;       EAX  : int i             (Índice de iteración)
;       XMM8 : float mean_copy   (Copia segura de \mu)
;       XMM9 : float inv_stddev  (Factor inverso 1.0f / \sigma)
;       XMM2 : float in[i]
; ==============================================================================
normalize_array:
    ; --------------------------------------------------------------------------
    ; 1. Validación de caso borde: n <= 0
    ; --------------------------------------------------------------------------
    test    edx, edx                ; ¿n <= 0?
    jle     sc_norm_done            ; Si n <= 0, salir inmediatamente

    ; --------------------------------------------------------------------------
    ; 2. Comprobar caso borde: stddev == 0.0
    ; --------------------------------------------------------------------------
    ucomiss xmm1, [rel epsilon]     ; Comparar stddev con epsilon
    jb      sc_norm_copy_loop       ; Si stddev < epsilon, copiar in[i] -> out[i] tal cual

    ; --------------------------------------------------------------------------
    ; 3. Precalcular factor de escala inverso: inv_stddev = 1.0f / stddev
    ; --------------------------------------------------------------------------
    movaps  xmm8, xmm0              ; xmm8 = mean (Guardar copia de mean)
    movss   xmm9, [rel const_one]   ; xmm9 = 1.0f
    divss   xmm9, xmm1              ; xmm9 = 1.0f / stddev (inv_stddev)
    xor     eax, eax                ; eax = i = 0

dbg_sc_norm_init:
    nop

sc_norm_loop:
    cmp     eax, edx
    jge     sc_norm_done

    ; Ecuación: diff = in[i] - \mu
    movss   xmm2, [rdi + rax*4]     ; xmm2 = in[i]
    subss   xmm2, xmm8              ; xmm2 = in[i] - \mu

    ; Ecuación: out[i] = diff * inv_stddev
    mulss   xmm2, xmm9              ; xmm2 = (in[i] - \mu) * (1 / \sigma)

    ; Guardar en out[i]
    movss   [rsi + rax*4], xmm2     ; out[i] = xmm2

dbg_sc_norm_loop:
    inc     eax                     ; i = i + 1
    jmp     sc_norm_loop

sc_norm_copy_loop:
    ; Caso borde stddev == 0.0: copiar in[i] en out[i] tal cual
    xor     eax, eax
sc_norm_copy_step:
    cmp     eax, edx
    jge     sc_norm_done
    movss   xmm2, [rdi + rax*4]     ; xmm2 = in[i]
    movss   [rsi + rax*4], xmm2     ; out[i] = in[i]
    inc     eax
    jmp     sc_norm_copy_step

dbg_sc_norm_done:
sc_norm_done:
    ret

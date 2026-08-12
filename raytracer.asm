section .text
    global render_frame
    global render_frame_part

; void render_frame(uint32_t* pixels, int width, int height, const SceneData* scene)
render_frame:
    push rbp
    mov rbp, rsp
    mov r9, rcx
    xor rcx, rcx ; y_start = 0
    mov r8, rdx  ; y_end = height
    call render_frame_part
    pop rbp
    ret

; void render_frame_part(uint32_t* pixels, int width, int height, int y_start, int y_end, const SceneData* scene)
render_frame_part:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 312 ; 16-byte aligned stack frame

    ; Save arguments
    mov r12, rdi ; pixels
    mov r13, rsi ; width
    mov r14, rdx ; height
    mov [rsp + 24], r8 ; y_end (64-bit)
    mov r15, r9  ; scene

    ; Pre-calculate float constants
    cvtsi2ss xmm14, r13 ; width_f
    cvtsi2ss xmm15, r14 ; height_f
    
    ; aspect_ratio = width / height
    movups xmm12, xmm14
    divss xmm12, xmm15 ; xmm12 = aspect_ratio

    ; inv_width (xmm14) and inv_height (xmm15)
    movss xmm0, [rel one]
    divss xmm0, xmm14
    movups xmm14, xmm0 ; 1.0 / width_f

    movss xmm0, [rel one]
    divss xmm0, xmm15
    movups xmm15, xmm0 ; 1.0 / height_f

    ; dx = 2.0 * inv_width * aspect_ratio * fov_scale
    movss xmm0, xmm14
    mulss xmm0, [rel two]
    mulss xmm0, xmm12
    mulss xmm0, [rel fov_scale]
    movss [rsp + 8], xmm0

    ; start_x = -1.0 * aspect_ratio * fov_scale
    movss xmm1, [rel minus_one]
    mulss xmm1, xmm12
    mulss xmm1, [rel fov_scale]
    movss [rsp + 12], xmm1

    ; inv_height_scale = 2.0 * inv_height * fov_scale
    movss xmm0, xmm15
    mulss xmm0, [rel two]
    mulss xmm0, [rel fov_scale]
    movss [rsp + 16], xmm0

    ; Precalculate sphere data for fast primary ray tracing
    mov edx, [r15 + 504] ; num_spheres
    mov [rsp + 72], rcx  ; save y_start
    xor rcx, rcx
    mov rsi, r15
    movups xmm1, [r15 + 528] ; camera_pos

.precalc_spheres:
    cmp rcx, rdx
    jge .precalc_done

    ; r2 = radius * radius
    movss xmm0, [rsi + 16]
    mulss xmm0, xmm0
    movss [rsp + 32 + rcx*4], xmm0

    ; oc_primary = camera_pos - center
    movups xmm2, xmm1
    movups xmm0, [rsi + 0]
    subps xmm2, xmm0
    mov r11, rcx
    shl r11, 4
    movups [rsp + 128 + r11], xmm2

    ; c_primary = dot(oc_primary, oc_primary) - r2
    movups xmm3, xmm2
    dpps xmm3, xmm2, 0x71
    subss xmm3, [rsp + 32 + rcx*4]
    movss [rsp + 80 + rcx*4], xmm3

    add rsi, 48
    inc rcx
    jmp .precalc_spheres

.precalc_done:
    mov r8, [rsp + 72] ; y = y_start
.loop_y:
    cmp r8, [rsp + 24]
    jge .done

    ; Calculate row pointer rdi = pixels + (y * width) * 4
    mov rdi, r8
    imul rdi, r13
    shl rdi, 2
    add rdi, r12

    ; Pre-calculate screen_y for row: fov_scale - y * inv_height_scale
    cvtsi2ss xmm11, r8
    mulss xmm11, [rsp + 16]
    movss xmm0, [rel fov_scale]
    subss xmm0, xmm11

    ; Pre-calculate base_dir = screen_y * Up + Forward using SIMD in xmm12
    shufps xmm0, xmm0, 0
    movups xmm12, [r15 + 576] ; Up (Vector3)
    mulps xmm12, xmm0
    movups xmm0, [r15 + 544]  ; Forward (Vector3)
    addps xmm12, xmm0         ; + Forward

    ; Cache constant vectors for row loop
    movups xmm14, [r15 + 560] ; Right (Vector3)
    movups xmm15, [r15 + 480] ; plane_normal (Vector3)

    ; Initialize screen_x accumulator in xmm13 = start_x
    movss xmm13, [rsp + 12]

    xor r9, r9 ; x = 0
.loop_x:
    cmp r9, r13
    jge .next_y

    ; Ray direction unnormalized: D_unnorm = screen_x * Right + base_dir
    movups xmm0, xmm13
    shufps xmm0, xmm0, 0
    movups xmm3, xmm14       ; Right (cached in xmm14)
    mulps xmm3, xmm0
    addps xmm3, xmm12        ; + base_dir

    ; Normalize D_unnorm using SIMD dot product and rsqrtps with Newton-Raphson refinement
    movups xmm0, xmm3
    dpps xmm3, xmm3, 0x7F   ; len_sq broadcast to all components
    rsqrtps xmm1, xmm3       ; initial approx 1/sqrt(len_sq)
    movups xmm2, xmm1
    mulps xmm2, xmm2         ; r^2
    mulps xmm2, xmm3         ; r^2 * len_sq
    movups xmm3, [rel three]
    subps xmm3, xmm2         ; 3 - r^2 * len_sq
    mulps xmm1, [rel half_vec]
    mulps xmm1, xmm3         ; refined inv_len
    mulps xmm0, xmm1         ; xmm0 = normalized D

    ; Ray Origin O in xmm1
    movups xmm1, [r15 + 528] ; camera_pos (Vector3)
    
    mov r10d, 1 ; allow 1 bounce

.cast_ray:
    movss xmm7, [rel infinity]
    mov rax, -1 ; hit_type (-1: none, 0: sphere, 1: plane)
    mov rbx, -1 ; hit_sphere_index

    ; 1. Plane Check
    cmp dword [r15 + 500], 0
    je .check_spheres

    ; denom = dot(D, plane_normal)
    movups xmm2, xmm0
    dpps xmm2, xmm15, 0x71   ; plane_normal cached in xmm15

    movups xmm3, xmm2
    andps xmm3, [rel abs_mask]
    comiss xmm3, [rel eps]
    jb .check_spheres

    ; t_plane = -(dot(O, plane_normal) + plane_distance) / denom
    movups xmm3, xmm1
    dpps xmm3, xmm15, 0x71
    addss xmm3, [r15 + 496]
    xorps xmm3, [rel sign_bit]
    divss xmm3, xmm2

    comiss xmm3, [rel eps]
    jbe .check_spheres
    comiss xmm3, xmm7
    jae .check_spheres

    movups xmm7, xmm3
    mov rax, 1

.check_spheres:
    xor rcx, rcx
    mov edx, [r15 + 504]
    mov rsi, r15

.sphere_loop:
    cmp rcx, rdx
    jge .after_spheres

    cmp r10d, 1
    jne .sphere_secondary

    ; --- Primary Ray Sphere Check ---
    mov r11, rcx
    shl r11, 4
    movups xmm2, [rsp + 128 + r11] ; oc_primary

    ; h = dot(D, oc_primary)
    movups xmm3, xmm0
    dpps xmm3, xmm2, 0x71

    ; disc = h^2 - c_primary
    movups xmm5, xmm3
    mulss xmm5, xmm5
    subss xmm5, [rsp + 80 + rcx*4]
    jmp .check_disc

.sphere_secondary:
    ; --- Secondary Ray Sphere Check ---
    movups xmm2, xmm1
    movups xmm4, [rsi + 0]
    subps xmm2, xmm4

    ; h = dot(D, oc)
    movups xmm3, xmm0
    dpps xmm3, xmm2, 0x71

    ; c = dot(oc, oc) - radius^2
    movups xmm4, xmm2
    dpps xmm4, xmm2, 0x71
    subss xmm4, [rsp + 32 + rcx*4]

    ; disc = h^2 - c
    movups xmm5, xmm3
    mulss xmm5, xmm5
    subss xmm5, xmm4

.check_disc:
    comiss xmm5, [rel zero]
    jb .next_sphere

    sqrtss xmm5, xmm5 ; sqrt_d

    ; t1 = -h - sqrt_d
    movups xmm6, xmm3
    addss xmm6, xmm5
    xorps xmm6, [rel sign_bit]

    comiss xmm6, [rel eps]
    ja .check_t_dist

    ; t2 = sqrt_d - h
    movups xmm6, xmm5
    subss xmm6, xmm3

    comiss xmm6, [rel eps]
    jbe .next_sphere

.check_t_dist:
    comiss xmm6, xmm7
    jae .next_sphere

    movups xmm7, xmm6
    mov rax, 0
    mov rbx, rcx

.next_sphere:
    add rsi, 48
    inc rcx
    jmp .sphere_loop

.after_spheres:
    cmp rax, -1
    je .no_hit
    cmp rax, 1
    je .plane_hit

    ; Sphere Hit
    cmp r10d, 0
    je .sphere_dark

    dec r10d
    
    imul rsi, rbx, 48
    add rsi, r15

    ; Hit Point P = O + t_min * D
    movups xmm8, xmm0
    shufps xmm7, xmm7, 0
    mulps xmm8, xmm7
    addps xmm8, xmm1

    ; Normal N = (P - center) / radius
    movups xmm9, xmm8
    movups xmm4, [rsi + 0]
    subps xmm9, xmm4
    movss xmm5, [rel one]
    divss xmm5, [rsi + 16]
    shufps xmm5, xmm5, 0
    mulps xmm9, xmm5

    ; Reflection vector R = D - 2 * dot(N, D) * N
    movups xmm10, xmm9
    dpps xmm10, xmm0, 0x7F
    addps xmm10, xmm10
    mulps xmm10, xmm9
    subps xmm0, xmm10 ; update D to R

    ; New Ray Origin O = P + N * eps_bounce
    movups xmm1, xmm9
    mulps xmm1, [rel eps_bounce_vec]
    addps xmm1, xmm8 ; update O to new origin

    jmp .cast_ray

.sphere_dark:
    movss xmm8, [rel zero]
    movss xmm10, [rel zero]
    movss xmm11, [rel zero]
    jmp .write_color

.plane_hit:
    ; Hit point P = O + t_min * D
    movaps xmm8, xmm0
    shufps xmm7, xmm7, 0
    mulps xmm8, xmm7
    addps xmm8, xmm1

    movss xmm5, xmm8 ; P.x
    movhlps xmm6, xmm8 ; P.z
    addss xmm5, [rel big_constant]
    addss xmm6, [rel big_constant]
    cvttss2si rcx, xmm5
    cvttss2si rdx, xmm6
    add rcx, rdx
    and rcx, 1
    jz .white_sq
    movss xmm8, [rel check_gray]
    movss xmm10, [rel check_gray]
    movss xmm11, [rel check_gray]
    jmp .shade_plane
.white_sq:
    movss xmm8, [rel one]
    movss xmm10, [rel one]
    movss xmm11, [rel one]

.shade_plane:
    movaps xmm5, [rel light_dir_vec]
    dpps xmm5, xmm15, 0x71    ; plane_normal cached in xmm15
    maxss xmm5, [rel zero]
    addss xmm5, [rel ambient]
    minss xmm5, [rel one]

    mulss xmm8, xmm5
    mulss xmm10, xmm5
    mulss xmm11, xmm5
    
    cmp r10d, 0
    jne .write_color
    mulss xmm8, [rel tint_r]
    mulss xmm10, [rel tint_g]
    mulss xmm11, [rel tint_b]
    jmp .write_color

.no_hit:
    movss xmm8, [rel sky_r]
    movss xmm10, [rel sky_g]
    movss xmm11, [rel sky_b]
    cmp r10d, 0
    jne .write_color
    mulss xmm8, [rel tint_r]
    mulss xmm10, [rel tint_g]
    mulss xmm11, [rel tint_b]

.write_color:
    mulss xmm8, [rel c255]
    mulss xmm10, [rel c255]
    mulss xmm11, [rel c255]
    cvtss2si eax, xmm8
    shl eax, 16
    cvtss2si edx, xmm10
    shl edx, 8
    or eax, edx
    cvtss2si edx, xmm11
    or eax, edx
    or eax, 0xFF000000

    mov [rdi], eax
    add rdi, 4

    ; Advance screen_x by dx
    addss xmm13, [rsp + 8]
    inc r9
    jmp .loop_x

.next_y:
    inc r8
    jmp .loop_y

.done:
    add rsp, 312
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .rodata
    one dd 1.0
    two dd 2.0
    half dd 0.5
    minus_one dd -1.0
    zero dd 0.0
    infinity dd 1e30
    c255 dd 255.0
    ambient dd 0.2
    fov_scale dd 0.5
    check_gray dd 0.7
    eps dd 1e-4
    eps_bounce dd 1e-2
    big_constant dd 1000.0
    sky_r dd 0.53
    sky_g dd 0.81
    sky_b dd 0.92
    tint_r dd 1.0
    tint_g dd 0.4
    tint_b dd 0.4
    align 16
    sign_bit dd 0x80000000, 0x0, 0x0, 0x0
    abs_mask dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
    eps_bounce_vec dd 1e-2, 1e-2, 1e-2, 0.0
    three dd 3.0, 3.0, 3.0, 3.0
    half_vec dd 0.5, 0.5, 0.5, 0.5
    light_dir_vec dd 0.577, 0.577, 0.577, 0.0

section .note.GNU-stack noalloc noexec nowrite progbits

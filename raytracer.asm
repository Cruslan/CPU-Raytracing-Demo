section .text
    global render_frame

; void render_frame(uint32_t* pixels, int width, int height, const SceneData* scene)
render_frame:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32 ; Local vars: [rsp+0..11] origin, [rsp+12..23] dir, [rsp+24] bounce

    ; Save arguments
    mov r12, rdi ; pixels
    mov r13, rsi ; width
    mov r14, rdx ; height
    mov r15, rcx ; scene

    ; Pre-calculate float constants
    cvtsi2ss xmm14, r13 ; width_f
    cvtsi2ss xmm15, r14 ; height_f
    
    ; aspect_ratio = width / height
    movaps xmm12, xmm14
    divss xmm12, xmm15

    xor r8, r8 ; y = 0
.loop_y:
    cmp r8, r14
    jge .done

    xor r9, r9 ; x = 0
.loop_x:
    cmp r9, r13
    jge .next_y

    ; screen_y
    cvtsi2ss xmm11, r8
    divss xmm11, xmm15
    mulss xmm11, [rel two]
    subss xmm11, [rel one]
    mulss xmm11, [rel minus_one]
    mulss xmm11, [rel fov_scale]

    ; screen_x
    cvtsi2ss xmm0, r9
    divss xmm0, xmm14
    mulss xmm0, [rel two]
    subss xmm0, [rel one]
    mulss xmm0, xmm12 ; apply aspect ratio
    mulss xmm0, [rel fov_scale] ; apply FOV

    ; Ray direction: D = normalize(screen_x*Right + screen_y*Up + Forward)
    movss xmm3, xmm0
    mulss xmm3, [r15 + 560] ; x * Right.x
    movss xmm4, xmm11
    mulss xmm4, [r15 + 576] ; y * Up.x
    addss xmm3, xmm4
    addss xmm3, [r15 + 544] ; Dir.x

    movss xmm4, xmm0
    mulss xmm4, [r15 + 564] ; x * Right.y
    movss xmm5, xmm11
    mulss xmm5, [r15 + 580] ; y * Up.y
    addss xmm4, xmm5
    addss xmm4, [r15 + 548] ; Dir.y

    movss xmm5, xmm0
    mulss xmm5, [r15 + 568] ; x * Right.z
    movss xmm6, xmm11
    mulss xmm6, [r15 + 584] ; y * Up.z
    addss xmm5, xmm6
    addss xmm5, [r15 + 552] ; Dir.z

    ; Normalize Dir
    movaps xmm0, xmm3
    mulss xmm0, xmm0
    movaps xmm1, xmm4
    mulss xmm1, xmm1
    addss xmm0, xmm1
    movaps xmm1, xmm5
    mulss xmm1, xmm1
    addss xmm0, xmm1
    sqrtss xmm0, xmm0
    
    divss xmm3, xmm0
    divss xmm4, xmm0
    divss xmm5, xmm0

    ; Setup Primary Ray
    movss xmm0, [r15 + 528]
    movss [rsp + 0], xmm0
    movss xmm0, [r15 + 532]
    movss [rsp + 4], xmm0
    movss xmm0, [r15 + 536]
    movss [rsp + 8], xmm0
    
    movss [rsp + 12], xmm3
    movss [rsp + 16], xmm4
    movss [rsp + 20], xmm5
    
    mov dword [rsp + 24], 1 ; allow 1 bounce

.cast_ray:
    movss xmm3, [rsp + 12]
    movss xmm4, [rsp + 16]
    movss xmm5, [rsp + 20]

    movss xmm7, [rel infinity]
    mov r10, -1 ; -1: none, 0: sphere, 1: plane
    mov r11, -1 ; hit_index

    ; 1. Plane Check
    cmp dword [r15 + 500], 0
    je .check_spheres

    ; denom = dir . normal
    movss xmm0, xmm3
    mulss xmm0, [r15 + 480]
    movss xmm1, xmm4
    mulss xmm1, [r15 + 484]
    addss xmm0, xmm1
    movss xmm1, xmm5
    mulss xmm1, [r15 + 488]
    addss xmm0, xmm1

    movaps xmm1, xmm0
    andps xmm1, [rel abs_mask]
    comiss xmm1, [rel eps]
    jb .check_spheres

    ; t = -(origin . normal + dist) / denom
    movss xmm1, [rsp + 0]
    mulss xmm1, [r15 + 480]
    movss xmm2, [rsp + 4]
    mulss xmm2, [r15 + 484]
    addss xmm1, xmm2
    movss xmm2, [rsp + 8]
    mulss xmm2, [r15 + 488]
    addss xmm1, xmm2
    addss xmm1, [r15 + 496]
    mulss xmm1, [rel minus_one]
    divss xmm1, xmm0

    comiss xmm1, [rel eps]
    jbe .check_spheres
    comiss xmm1, xmm7
    jae .check_spheres

    movaps xmm7, xmm1
    mov r10, 1

.check_spheres:
    xor rcx, rcx
    mov eax, [r15 + 504]
.sphere_loop:
    cmp rcx, rax
    jge .after_spheres

    imul rbx, rcx, 48
    lea rbx, [r15 + rbx]

    ; oc = origin - center
    movss xmm0, [rsp + 0]
    subss xmm0, [rbx + 0]
    movss xmm1, [rsp + 4]
    subss xmm1, [rbx + 4]
    movss xmm2, [rsp + 8]
    subss xmm2, [rbx + 8]

    ; b = 2 * (dir . oc)
    movaps xmm6, xmm3
    mulss xmm6, xmm0
    movaps xmm13, xmm4
    mulss xmm13, xmm1
    addss xmm6, xmm13
    movaps xmm13, xmm5
    mulss xmm13, xmm2
    addss xmm6, xmm13
    mulss xmm6, [rel two]

    ; c = (oc . oc) - r^2
    mulss xmm0, xmm0
    mulss xmm1, xmm1
    addss xmm0, xmm1
    mulss xmm2, xmm2
    addss xmm0, xmm2
    movss xmm1, [rbx + 16]
    mulss xmm1, xmm1
    subss xmm0, xmm1

    ; disc = b^2 - 4c
    movaps xmm1, xmm6
    mulss xmm1, xmm1
    movaps xmm2, xmm0
    mulss xmm2, [rel four]
    subss xmm1, xmm2

    comiss xmm1, [rel zero]
    jb .next_sphere

    sqrtss xmm1, xmm1
    movaps xmm2, xmm6
    mulss xmm2, [rel minus_one]
    subss xmm2, xmm1
    divss xmm2, [rel two] ; t1

    comiss xmm2, [rel eps]
    ja .check_t_dist

    ; Try t2 if t1 is behind (for refraction/inside out)
    movaps xmm2, xmm6
    mulss xmm2, [rel minus_one]
    addss xmm2, xmm1
    divss xmm2, [rel two] ; t2

    comiss xmm2, [rel eps]
    jbe .next_sphere

.check_t_dist:
    comiss xmm2, xmm7
    jae .next_sphere

    movaps xmm7, xmm2
    mov r10, 0
    mov r11, rcx

.next_sphere:
    inc rcx
    jmp .sphere_loop

.after_spheres:
    cmp r10, -1
    je .no_hit
    cmp r10, 1
    je .plane_hit

    ; Sphere Hit
    cmp dword [rsp + 24], 0
    je .sphere_dark

    dec dword [rsp + 24]
    
    imul rbx, r11, 48
    lea rbx, [r15 + rbx]

    ; Hit Point P
    movss xmm0, [rsp + 12]
    mulss xmm0, xmm7
    addss xmm0, [rsp + 0] ; P.x
    movss xmm1, [rsp + 16]
    mulss xmm1, xmm7
    addss xmm1, [rsp + 4] ; P.y
    movss xmm2, [rsp + 20]
    mulss xmm2, xmm7
    addss xmm2, [rsp + 8] ; P.z

    ; Normal N in xmm8, xmm9, xmm10
    movaps xmm8, xmm0
    subss xmm8, [rbx + 0]
    divss xmm8, [rbx + 16] ; N.x
    movaps xmm9, xmm1
    subss xmm9, [rbx + 4]
    divss xmm9, [rbx + 16] ; N.y
    movaps xmm10, xmm2
    subss xmm10, [rbx + 8]
    divss xmm10, [rbx + 16] ; N.z

    ; dot(N, I) -> xmm11
    movaps xmm11, xmm8
    mulss xmm11, [rsp + 12]
    movaps xmm13, xmm9
    mulss xmm13, [rsp + 16]
    addss xmm11, xmm13
    movaps xmm13, xmm10
    mulss xmm13, [rsp + 20]
    addss xmm11, xmm13
    
    mulss xmm11, [rel two]

    ; R = I - 2*dot(N,I)*N
    movaps xmm13, xmm8
    mulss xmm13, xmm11
    movss xmm3, [rsp + 12]
    subss xmm3, xmm13 ; R.x
    movss [rsp + 12], xmm3

    movaps xmm13, xmm9
    mulss xmm13, xmm11
    movss xmm4, [rsp + 16]
    subss xmm4, xmm13 ; R.y
    movss [rsp + 16], xmm4

    movaps xmm13, xmm10
    mulss xmm13, xmm11
    movss xmm5, [rsp + 20]
    subss xmm5, xmm13 ; R.z
    movss [rsp + 20], xmm5

    ; Origin = P + N*eps
    mulss xmm8, [rel eps_bounce]
    addss xmm0, xmm8
    movss [rsp + 0], xmm0

    mulss xmm9, [rel eps_bounce]
    addss xmm1, xmm9
    movss [rsp + 4], xmm1

    mulss xmm10, [rel eps_bounce]
    addss xmm2, xmm10
    movss [rsp + 8], xmm2

    jmp .cast_ray

.sphere_dark:
    movss xmm8, [rel zero]
    movss xmm10, [rel zero]
    movss xmm11, [rel zero]
    jmp .write_color

.plane_hit:
    movss xmm0, [r15 + 480] ; normal.x
    movss xmm1, [r15 + 484] ; normal.y
    movss xmm2, [r15 + 488] ; normal.z

    movss xmm13, xmm3
    mulss xmm13, xmm7
    addss xmm13, [rsp + 0] ; P.x
    movss xmm9, xmm5
    mulss xmm9, xmm7
    addss xmm9, [rsp + 8] ; P.z

    addss xmm13, [rel big_constant]
    addss xmm9, [rel big_constant]
    cvttss2si rax, xmm13
    cvttss2si rbx, xmm9
    add rax, rbx
    and rax, 1
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
    movss xmm6, [rel light_dir_x]
    mulss xmm6, xmm0
    movss xmm13, [rel light_dir_y]
    mulss xmm13, xmm1
    addss xmm6, xmm13
    movss xmm13, [rel light_dir_z]
    mulss xmm13, xmm2
    addss xmm6, xmm13
    maxss xmm6, [rel zero]
    addss xmm6, [rel ambient]
    minss xmm6, [rel one]

    mulss xmm8, xmm6
    mulss xmm10, xmm6
    mulss xmm11, xmm6
    
    cmp dword [rsp + 24], 0
    jne .write_color
    mulss xmm8, [rel tint_r]
    mulss xmm10, [rel tint_g]
    mulss xmm11, [rel tint_b]
    jmp .write_color

.no_hit:
    movss xmm8, [rel sky_r]
    movss xmm10, [rel sky_g]
    movss xmm11, [rel sky_b]
    cmp dword [rsp + 24], 0
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

    mov r11, r8
    imul r11, r13
    add r11, r9
    mov [r12 + r11 * 4], eax
    inc r9
    jmp .loop_x

.next_y:
    inc r8
    jmp .loop_y

.done:
    add rsp, 32
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
    four dd 4.0
    minus_one dd -1.0
    zero dd 0.0
    infinity dd 1e30
    c255 dd 255.0
    ambient dd 0.2
    fov_scale dd 0.5
    light_dir_x dd 0.577
    light_dir_y dd 0.577
    light_dir_z dd 0.577
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
    abs_mask dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

section .note.GNU-stack noalloc noexec nowrite progbits

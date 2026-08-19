.text
.globl khz_bounds_check
.type khz_bounds_check,@function
khz_bounds_check:
    cmp %rsi, %rdi
    jb .Lreject
    cmp %rdx, %rdi
    jae .Lreject
    xor %eax, %eax
    ret
.Lreject:
    mov $1, %eax
    ret
.size khz_bounds_check, .-khz_bounds_check

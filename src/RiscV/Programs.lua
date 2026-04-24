-- ModuleScript: RiscV/Programs.lua
local Programs = {}

-- ... (keep other programs the same)

Programs.DebugStore = [[
.text
.globl _start
_start:
    # Test 1: Store ASCII '5' directly and print it
    lui t0, 0x10000
    li t1, 53              # ASCII '5' = 53
    sb t1, 20(t0)          # Store '5' at offset 20
    
    # Print it
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 20
    li a2, 1
    ecall
    
    # Test 2: Print space
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 0         # space at offset 0
    li a2, 1
    ecall
    
    # Test 3: Convert number to ASCII and store
    li t2, 3               # number 3
    addi t2, t2, 48        # convert to ASCII: 3 + 48 = 51 ('3')
    sb t2, 21(t0)          # store at offset 21
    
    # Print it
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 21
    li a2, 1
    ecall
    
    # Print newline
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 1         # newline at offset 1
    li a2, 1
    ecall
    
    li a7, 93; li a0, 0; ecall

.data
space: .ascii " "          # offset 0
newline: .ascii "\n"       # offset 1
# storage area at offsets 20+
]]

Programs.SimpleCalculator = [[
.text
.globl _start
_start:
    # Initialize stack pointer
    lui sp, 0x10002
    
    # Print welcome message
    la a0, msg_welcome
    call print_string
    
    # Test Case 1: Add two 4-digit numbers: 1234 + 5678 = 6912
    la a0, msg_test1
    call print_string
    li a0, 1234
    li a1, 5678
    call add_numbers
    mv s0, a0
    call print_number
    call print_newline
    
    # Test Case 2: Subtract: 9876 - 3456 = 6420
    la a0, msg_test2  
    call print_string
    li a0, 9876
    li a1, 3456
    call subtract_numbers
    mv s0, a0
    call print_number
    call print_newline
    
    # Test Case 3: Add 5-digit numbers: 12345 + 67890 = 80235
    la a0, msg_test3
    call print_string
    li a0, 12345
    li a1, 67890
    call add_numbers
    mv s0, a0
    call print_number
    call print_newline
    
    # Test Case 4: Subtract 5-digit: 99999 - 12345 = 87654
    la a0, msg_test4
    call print_string
    li a0, 99999
    li a1, 12345
    call subtract_numbers
    mv s0, a0
    call print_number
    call print_newline
    
    # Test Case 5: Large addition: 45678 + 54321 = 99999
    la a0, msg_test5
    call print_string
    li a0, 45678
    li a1, 54321
    call add_numbers
    mv s0, a0
    call print_number
    call print_newline
    
    # Exit
    li a7, 93
    li a0, 0
    ecall

#=============================================================================
# Function: add_numbers
# Add two numbers and return the result
# Input: a0 = first number, a1 = second number
# Output: a0 = result
#=============================================================================
add_numbers:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw s0, 0(sp)
    
    add s0, a0, a1        # Simple addition
    mv a0, s0             # Return result
    
    lw s0, 0(sp)
    lw ra, 4(sp)
    addi sp, sp, 8
    ret

#=============================================================================
# Function: subtract_numbers  
# Subtract second number from first
# Input: a0 = first number, a1 = second number
# Output: a0 = result (a0 - a1)
#=============================================================================
subtract_numbers:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw s0, 0(sp)
    
    sub s0, a0, a1        # Simple subtraction
    mv a0, s0             # Return result
    
    lw s0, 0(sp)
    lw ra, 4(sp)
    addi sp, sp, 8
    ret

#=============================================================================
# Function: print_number
# Print a number (up to 5 digits) to screen
# Input: s0 = number to print
#=============================================================================
print_number:
    addi sp, sp, -20
    sw ra, 16(sp)
    sw s0, 12(sp)    # original number
    sw s1, 8(sp)     # working number
    sw s2, 4(sp)     # digit count
    sw s3, 0(sp)     # buffer pointer
    
    mv s1, s0         # working copy
    li s2, 0          # digit count
    la s3, number_buffer
    addi s3, s3, 9    # start from end of 10-byte buffer
    
    # Handle zero case
    bnez s1, extract_digits
    li t0, 48         # ASCII '0'
    sb t0, 0(s3)
    li s2, 1
    j print_digits
    
extract_digits:
    beqz s1, reverse_digits
    
    # Extract least significant digit
    li t0, 10
    remu t1, s1, t0   # digit = number % 10
    divu s1, s1, t0   # number = number / 10
    
    # Convert to ASCII and store
    addi t1, t1, 48   # convert to ASCII
    sb t1, 0(s3)      # store digit
    addi s3, s3, -1   # move buffer pointer back
    addi s2, s2, 1    # increment digit count
    j extract_digits
    
reverse_digits:
    addi s3, s3, 1    # point to first digit
    
print_digits:
    # Print the digits
    li a7, 64         # write syscall
    li a0, 1          # stdout
    mv a1, s3         # buffer start
    mv a2, s2         # digit count
    ecall
    
    lw s3, 0(sp)
    lw s2, 4(sp)
    lw s1, 8(sp)
    lw s0, 12(sp)
    lw ra, 16(sp)
    addi sp, sp, 20
    ret

#=============================================================================
# Function: print_string
# Print a null-terminated string
# Input: a0 = string pointer
#=============================================================================
print_string:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s0, 4(sp)      # string pointer
    sw s1, 0(sp)      # length
    
    mv s0, a0
    li s1, 0
    
    # Calculate string length
    mv t0, s0
strlen_loop:
    lb t1, 0(t0)
    beqz t1, do_print
    addi t0, t0, 1
    addi s1, s1, 1
    j strlen_loop
    
do_print:
    li a7, 64         # write syscall
    li a0, 1          # stdout
    mv a1, s0         # string
    mv a2, s1         # length
    ecall
    
    lw s1, 0(sp)
    lw s0, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

#=============================================================================
# Function: print_newline
# Print a newline character
#=============================================================================
print_newline:
    addi sp, sp, -4
    sw ra, 0(sp)
    
    la a0, newline_char
    call print_string
    
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

.data
# Messages
msg_welcome: .asciz "Simple 4-5 Digit Calculator\n\n"
msg_test1: .asciz "Test 1: 1234 + 5678 = "
msg_test2: .asciz "Test 2: 9876 - 3456 = "
msg_test3: .asciz "Test 3: 12345 + 67890 = "
msg_test4: .asciz "Test 4: 99999 - 12345 = "
msg_test5: .asciz "Test 5: 45678 + 54321 = "
newline_char: .asciz "\n"

# Working space
number_buffer: .space 10      # Buffer for number conversion (up to 5 digits + safety)
]]


Programs.BubSort = [[
.text
.globl _start
_start:
    # Manual address calculation instead of 'la'
    lui sp, 0x10001         # Stack at 0x10001000
    
    # Initialize array manually at known offset
    lui t0, 0x10000         # Data base
    
    # Store array at offset 100: [5, 2, 8, 1, 3]
    li t1, 5; sw t1, 100(t0)
    li t1, 2; sw t1, 104(t0)  
    li t1, 8; sw t1, 108(t0)
    li t1, 1; sw t1, 112(t0)
    li t1, 3; sw t1, 116(t0)
    
    # Print "Original: " - manually stored at offset 0
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 0          # "Original: " at offset 0
    li a2, 10
    ecall
    
    # Print array manually
    lw a0, 100(t0)          # Load array[0]
    call print_single_digit
    call print_space
    
    lw a0, 104(t0)          # Load array[1] 
    call print_single_digit
    call print_space
    
    lw a0, 108(t0)          # Load array[2]
    call print_single_digit  
    call print_space
    
    lw a0, 112(t0)          # Load array[3]
    call print_single_digit
    call print_space
    
    lw a0, 116(t0)          # Load array[4]
    call print_single_digit
    call print_newline
    
    # Simple bubble sort - one pass
    lui t0, 0x10000
    lw t1, 100(t0); lw t2, 104(t0); blt t1, t2, skip1; sw t2, 100(t0); sw t1, 104(t0); skip1:
    lw t1, 104(t0); lw t2, 108(t0); blt t1, t2, skip2; sw t2, 104(t0); sw t1, 108(t0); skip2:  
    lw t1, 108(t0); lw t2, 112(t0); blt t1, t2, skip3; sw t2, 108(t0); sw t1, 112(t0); skip3:
    lw t1, 112(t0); lw t2, 116(t0); blt t1, t2, skip4; sw t2, 112(t0); sw t1, 116(t0); skip4:
    
    # Print "Sorted: "
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 10         # "Sorted: " at offset 10
    li a2, 8
    ecall
    
    # Print sorted array
    lui t0, 0x10000
    lw a0, 100(t0)
    call print_single_digit
    call print_space
    
    lw a0, 104(t0)
    call print_single_digit
    call print_space
    
    lw a0, 108(t0)
    call print_single_digit
    call print_space
    
    lw a0, 112(t0)
    call print_single_digit
    call print_space
    
    lw a0, 116(t0)
    call print_single_digit
    call print_newline
    
    # Exit
    li a7, 93
    li a0, 0
    ecall

print_single_digit:
    # Convert single digit (0-9) to ASCII and print
    addi sp, sp, -4
    sw ra, 0(sp)
    
    addi t0, a0, 48         # Convert to ASCII
    lui t1, 0x10000
    sb t0, 200(t1)          # Store at buffer offset 200
    sb zero, 201(t1)        # Null terminate
    
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 200
    li a2, 1
    ecall
    
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

print_space:
    addi sp, sp, -4
    sw ra, 0(sp)
    
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 18         # Space at offset 18
    li a2, 1
    ecall
    
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

print_newline:
    addi sp, sp, -4
    sw ra, 0(sp)
    
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 19         # Newline at offset 19
    li a2, 1
    ecall
    
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

.data
msg_orig: .ascii "Original: "  # offset 0-9
msg_sort: .ascii "Sorted: "    # offset 10-17
space: .ascii " "              # offset 18
newline: .ascii "\n"           # offset 19
# Array at offset 100-119 (5 integers)
# Buffer at offset 200+ for number conversion
]]

Programs.ArrayTest = [[
.text
.globl _start
_start:
    # Test array initialization and loading
    lui t0, 0x10000
    
    # Store array values [5, 2, 8, 1, 3]
    li t1, 5; sw t1, 100(t0)    # Store 5 at offset 100
    li t1, 2; sw t1, 104(t0)    # Store 2 at offset 104  
    li t1, 8; sw t1, 108(t0)    # Store 8 at offset 108
    li t1, 1; sw t1, 112(t0)    # Store 1 at offset 112
    li t1, 3; sw t1, 116(t0)    # Store 3 at offset 116
    
    # Print "Stored: "
    li a7, 64; li a0, 1; lui a1, 0x10000; li a2, 8; ecall
    
    # Now load and print each value immediately
    lw t2, 100(t0)             # Load array[0]
    addi t2, t2, 48; lui t3, 0x10000; sb t2, 200(t3)
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 200; li a2, 1; ecall
    li t2, 32; sb t2, 201(t3); li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 201; li a2, 1; ecall
    
    lw t2, 104(t0)             # Load array[1]
    addi t2, t2, 48; sb t2, 200(t3)
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 200; li a2, 1; ecall
    li t2, 32; sb t2, 201(t3); li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 201; li a2, 1; ecall
    
    lw t2, 108(t0)             # Load array[2]
    addi t2, t2, 48; sb t2, 200(t3)
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 200; li a2, 1; ecall
    li t2, 32; sb t2, 201(t3); li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 201; li a2, 1; ecall
    
    lw t2, 112(t0)             # Load array[3]
    addi t2, t2, 48; sb t2, 200(t3)
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 200; li a2, 1; ecall
    li t2, 32; sb t2, 201(t3); li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 201; li a2, 1; ecall
    
    lw t2, 116(t0)             # Load array[4]
    addi t2, t2, 48; sb t2, 200(t3)
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 200; li a2, 1; ecall
    
    # Print newline
    li t2, 10; sb t2, 201(t3); li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 201; li a2, 1; ecall
    
    # Exit
    li a7, 93; li a0, 0; ecall

.data
.ascii "Stored: "
]]


Programs.MemoryTest = [[
.text
.globl _start
_start:
    # Test store and load word operations
    lui t0, 0x10000
    
    # Store value 7 at offset 100
    li t1, 7
    sw t1, 100(t0)
    
    # Store value 9 at offset 104  
    li t2, 9
    sw t2, 104(t0)
    
    # Load them back immediately
    lw t3, 100(t0)          # Should be 7
    lw t4, 104(t0)          # Should be 9
    
    # Print first value
    addi t3, t3, 48         # Convert to ASCII
    lui t5, 0x10000
    sb t3, 200(t5)          # Store at buffer
    
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 200
    li a2, 1
    ecall
    
    # Print space
    li t6, 32
    sb t6, 201(t5)
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 201
    li a2, 1
    ecall
    
    # Print second value
    addi t4, t4, 48
    sb t4, 202(t5)
    
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 202
    li a2, 1
    ecall
    
    # Print newline
    li t6, 10
    sb t6, 203(t5)
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 203
    li a2, 1
    ecall
    
    # Exit
    li a7, 93
    li a0, 0
    ecall

.data
.ascii "unused"
]]

Programs.ArithTest = [[
.text
.globl _start
_start:
    # Initialize stack pointer
    lui sp, 0x10002
    
    # Print welcome message
    la a0, msg_welcome
    call print_string
    
    # Test Case 1: "3 + 4 * 2" = 11
    la a0, msg_test1
    call print_string
    la a0, expr1
    call evaluate_expression
    mv s0, a0
    call print_result
    
    # Test Case 2: "(5 + 3) * 2" = 16  
    la a0, msg_test2
    call print_string
    la a0, expr2
    call evaluate_expression
    mv s0, a0
    call print_result
    
    # Test Case 3: "15 / 3 + 2 * 4" = 13
    la a0, msg_test3
    call print_string
    la a0, expr3
    call evaluate_expression
    mv s0, a0
    call print_result
    
    # Test Case 4: Recursive Fibonacci
    la a0, msg_test4
    call print_string
    li a0, 8                # Calculate fib(8)
    call fibonacci
    mv s0, a0
    call print_result
    
    # Exit program
    li a7, 93
    li a0, 0
    ecall

#=============================================================================
# Function: evaluate_expression
# Implements a recursive descent parser for arithmetic expressions
# Grammar: E -> T (('+' | '-') T)*
#          T -> F (('*' | '/') F)*  
#          F -> number | '(' E ')'
# Input: a0 = pointer to null-terminated expression string
# Output: a0 = evaluated result
#=============================================================================
evaluate_expression:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)      # expression pointer
    sw s1, 4(sp)      # current position
    sw s2, 0(sp)      # result accumulator
    
    mv s0, a0         # save expression pointer
    li s1, 0          # start at position 0
    
    # Call parse_expression (entry point)
    mv a0, s0
    mv a1, s1
    call parse_expression
    mv s2, a0         # save result
    
    mv a0, s2         # return result
    lw s2, 0(sp)
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#=============================================================================
# Function: parse_expression  
# Parse: E -> T (('+' | '-') T)*
# Input: a0 = expression string, a1 = current position
# Output: a0 = result, a1 = updated position
#=============================================================================
parse_expression:
    addi sp, sp, -20
    sw ra, 16(sp)
    sw s0, 12(sp)     # expression string
    sw s1, 8(sp)      # current position  
    sw s2, 4(sp)      # left operand
    sw s3, 0(sp)      # right operand
    
    mv s0, a0
    mv s1, a1
    
    # Parse first term
    mv a0, s0
    mv a1, s1
    call parse_term
    mv s2, a0         # left result
    mv s1, a1         # updated position
    
expr_loop:
    # Skip whitespace
    mv a0, s0
    mv a1, s1
    call skip_whitespace
    mv s1, a0
    
    # Check for '+' or '-'
    add t0, s0, s1
    lb t1, 0(t0)
    
    li t2, 43         # ASCII '+'
    beq t1, t2, handle_add
    li t2, 45         # ASCII '-'  
    beq t1, t2, handle_sub
    j expr_done       # No more operators
    
handle_add:
    addi s1, s1, 1    # skip '+'
    mv a0, s0
    mv a1, s1
    call parse_term
    mv s3, a0         # right operand
    mv s1, a1         # updated position
    add s2, s2, s3    # left = left + right
    j expr_loop
    
handle_sub:
    addi s1, s1, 1    # skip '-'
    mv a0, s0
    mv a1, s1
    call parse_term  
    mv s3, a0         # right operand
    mv s1, a1         # updated position
    sub s2, s2, s3    # left = left - right
    j expr_loop
    
expr_done:
    mv a0, s2         # return result
    mv a1, s1         # return position
    
    lw s3, 0(sp)
    lw s2, 4(sp)
    lw s1, 8(sp)
    lw s0, 12(sp)
    lw ra, 16(sp)
    addi sp, sp, 20
    ret

#=============================================================================
# Function: parse_term
# Parse: T -> F (('*' | '/') F)*
# Input: a0 = expression string, a1 = current position
# Output: a0 = result, a1 = updated position
#=============================================================================
parse_term:
    addi sp, sp, -20
    sw ra, 16(sp)
    sw s0, 12(sp)     # expression string
    sw s1, 8(sp)      # current position
    sw s2, 4(sp)      # left operand
    sw s3, 0(sp)      # right operand
    
    mv s0, a0
    mv s1, a1
    
    # Parse first factor
    mv a0, s0
    mv a1, s1
    call parse_factor
    mv s2, a0         # left result
    mv s1, a1         # updated position
    
term_loop:
    # Skip whitespace
    mv a0, s0
    mv a1, s1
    call skip_whitespace
    mv s1, a0
    
    # Check for '*' or '/'
    add t0, s0, s1
    lb t1, 0(t0)
    
    li t2, 42         # ASCII '*'
    beq t1, t2, handle_mul
    li t2, 47         # ASCII '/'
    beq t1, t2, handle_div
    j term_done       # No more operators
    
handle_mul:
    addi s1, s1, 1    # skip '*'
    mv a0, s0
    mv a1, s1
    call parse_factor
    mv s3, a0         # right operand
    mv s1, a1         # updated position
    mul s2, s2, s3    # left = left * right
    j term_loop
    
handle_div:
    addi s1, s1, 1    # skip '/'
    mv a0, s0
    mv a1, s1
    call parse_factor
    mv s3, a0         # right operand
    mv s1, a1         # updated position
    # Handle division by zero
    beqz s3, div_error
    div s2, s2, s3    # left = left / right
    j term_loop
    
div_error:
    li s2, -1         # Return error code
    j term_done
    
term_done:
    mv a0, s2         # return result
    mv a1, s1         # return position
    
    lw s3, 0(sp)
    lw s2, 4(sp)
    lw s1, 8(sp)
    lw s0, 12(sp)
    lw ra, 16(sp)
    addi sp, sp, 20
    ret

#=============================================================================
# Function: parse_factor
# Parse: F -> number | '(' E ')'
# Input: a0 = expression string, a1 = current position
# Output: a0 = result, a1 = updated position
#=============================================================================
parse_factor:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)      # expression string
    sw s1, 4(sp)      # current position
    sw s2, 0(sp)      # result
    
    mv s0, a0
    mv s1, a1
    
    # Skip whitespace
    mv a0, s0
    mv a1, s1
    call skip_whitespace
    mv s1, a0
    
    # Check first character
    add t0, s0, s1
    lb t1, 0(t0)
    
    li t2, 40         # ASCII '('
    beq t1, t2, parse_parentheses
    
    # Must be a number
    mv a0, s0
    mv a1, s1
    call parse_number
    mv s2, a0         # result
    mv s1, a1         # updated position
    j factor_done
    
parse_parentheses:
    addi s1, s1, 1    # skip '('
    mv a0, s0
    mv a1, s1
    call parse_expression
    mv s2, a0         # result
    mv s1, a1         # updated position
    
    # Skip whitespace and expect ')'
    mv a0, s0
    mv a1, s1
    call skip_whitespace
    mv s1, a0
    
    add t0, s0, s1
    lb t1, 0(t0)
    li t2, 41         # ASCII ')'
    bne t1, t2, paren_error
    addi s1, s1, 1    # skip ')'
    j factor_done
    
paren_error:
    li s2, -1         # Error code
    
factor_done:
    mv a0, s2         # return result
    mv a1, s1         # return position
    
    lw s2, 0(sp)
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#=============================================================================
# Function: parse_number
# Parse a decimal number from string
# Input: a0 = string, a1 = position
# Output: a0 = number, a1 = updated position
#=============================================================================
parse_number:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)      # string
    sw s1, 4(sp)      # position
    sw s2, 0(sp)      # accumulated result
    
    mv s0, a0
    mv s1, a1
    li s2, 0          # result = 0
    
number_loop:
    add t0, s0, s1
    lb t1, 0(t0)
    
    # Check if digit (0-9)
    li t2, 48         # ASCII '0'
    blt t1, t2, number_done
    li t2, 57         # ASCII '9'
    bgt t1, t2, number_done
    
    # It's a digit: result = result * 10 + (digit - '0')
    li t2, 10
    mul s2, s2, t2
    li t2, 48
    sub t1, t1, t2    # convert ASCII to digit
    add s2, s2, t1
    
    addi s1, s1, 1    # advance position
    j number_loop
    
number_done:
    mv a0, s2         # return number
    mv a1, s1         # return position
    
    lw s2, 0(sp)
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#=============================================================================
# Function: skip_whitespace
# Skip spaces and tabs
# Input: a0 = string, a1 = position  
# Output: a0 = updated position
#=============================================================================
skip_whitespace:
    mv t0, a1
    
skip_loop:
    add t1, a0, t0
    lb t2, 0(t1)
    
    li t3, 32         # ASCII space
    beq t2, t3, skip_char
    li t3, 9          # ASCII tab
    beq t2, t3, skip_char
    j skip_done
    
skip_char:
    addi t0, t0, 1
    j skip_loop
    
skip_done:
    mv a0, t0
    ret

#=============================================================================
# Function: fibonacci (Recursive)
# Calculate nth Fibonacci number
# Input: a0 = n
# Output: a0 = fib(n)
#=============================================================================
fibonacci:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s0, 4(sp)      # n
    sw s1, 0(sp)      # result accumulator
    
    mv s0, a0
    
    # Base cases: fib(0) = 0, fib(1) = 1
    beqz s0, fib_zero
    li t0, 1
    beq s0, t0, fib_one
    
    # Recursive case: fib(n) = fib(n-1) + fib(n-2)
    addi a0, s0, -1   # n-1
    call fibonacci
    mv s1, a0         # save fib(n-1)
    
    addi a0, s0, -2   # n-2
    call fibonacci
    add s1, s1, a0    # fib(n-1) + fib(n-2)
    
    mv a0, s1
    j fib_done
    
fib_zero:
    li a0, 0
    j fib_done
    
fib_one:
    li a0, 1
    
fib_done:
    lw s1, 0(sp)
    lw s0, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

#=============================================================================
# Function: print_result
# Print the result in s0 with proper formatting
# Input: s0 = number to print
#=============================================================================
print_result:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s0, 4(sp)
    sw s1, 0(sp)
    
    # Print "Result: "
    la a0, msg_result
    call print_string
    
    # Convert number to string and print
    mv a0, s0
    call number_to_string
    call print_string
    
    # Print newline
    la a0, msg_newline
    call print_string
    
    lw s1, 0(sp)
    lw s0, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

#=============================================================================
# Function: number_to_string
# Convert a number to decimal string representation
# Input: a0 = number
# Output: a0 = pointer to null-terminated string
#=============================================================================
number_to_string:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)      # number
    sw s1, 4(sp)      # buffer position (from end)
    sw s2, 0(sp)      # digit count
    
    mv s0, a0
    la s1, number_buffer
    addi s1, s1, 15   # start from end of buffer
    li s2, 0          # digit count
    
    # Handle zero case
    bnez s0, convert_loop
    li t0, 48         # ASCII '0'
    sb t0, 0(s1)
    sb zero, 1(s1)    # null terminate
    mv a0, s1
    j num_convert_done
    
convert_loop:
    # Extract least significant digit
    li t0, 10
    remu t1, s0, t0   # digit = n % 10
    divu s0, s0, t0   # n = n / 10
    
    # Convert digit to ASCII and store
    addi t1, t1, 48
    sb t1, 0(s1)
    addi s1, s1, -1   # move buffer pointer back
    addi s2, s2, 1    # increment digit count
    
    bnez s0, convert_loop
    
    # Move to start of number
    addi s1, s1, 1
    
    # Null terminate
    add t0, s1, s2
    sb zero, 0(t0)
    
    mv a0, s1         # return pointer to string
    
num_convert_done:
    lw s2, 0(sp)
    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

#=============================================================================
# Function: print_string
# Print a null-terminated string
# Input: a0 = string pointer
#=============================================================================
print_string:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s0, 4(sp)      # string pointer
    sw s1, 0(sp)      # length
    
    mv s0, a0
    li s1, 0
    
    # Calculate length
    mv t0, s0
strlen_loop:
    lb t1, 0(t0)
    beqz t1, print_syscall
    addi t0, t0, 1
    addi s1, s1, 1
    j strlen_loop
    
print_syscall:
    li a7, 64         # write syscall
    li a0, 1          # stdout
    mv a1, s0         # string
    mv a2, s1         # length
    ecall
    
    lw s1, 0(sp)
    lw s0, 4(sp)
    lw ra, 8(sp)
    addi sp, sp, 12
    ret

.data
# Test expressions
expr1: .asciz "3 + 4 * 2"
expr2: .asciz "(5 + 3) * 2"  
expr3: .asciz "15 / 3 + 2 * 4"

# Messages
msg_welcome: .asciz "Advanced RISC-V Calculator\n"
msg_test1: .asciz "Test 1: 3 + 4 * 2 = "
msg_test2: .asciz "Test 2: (5 + 3) * 2 = "
msg_test3: .asciz "Test 3: 15 / 3 + 2 * 4 = "
msg_test4: .asciz "Test 4: fib(8) = "
msg_result: .asciz "Result: "
msg_newline: .asciz "\n"

# Working space
number_buffer: .space 16      # Buffer for number-to-string conversion
]]



-- FIXED: Counter program with proper spacing
Programs.CounterDisplay = [[
.text
.globl _start
_start:
    li t0, 0          # counter

count_loop:
    # Print counter value as character
    addi t1, t0, 48   # Convert to ASCII ('0' + counter)
    la t2, digit_buffer
    sb t1, 0(t2)      # Store ASCII character
    sb x0, 1(t2)      # Null terminate
    
    # Print the digit
    li a7, 64
    li a0, 1
    mv a1, t2
    li a2, 1
    ecall
    
    # Print space
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 2    # space_char offset
    li a2, 1
    ecall
    
    addi t0, t0, 1    # counter++
    li t3, 10         # count to 9 (0-9)
    blt t0, t3, count_loop
    
    # Print newline
    li a7, 64
    li a0, 1
    lui a1, 0x10000
    addi a1, a1, 3    # newline_char offset
    li a2, 1
    ecall
    
    li a7, 93
    li a0, 0
    ecall

.data
digit_buffer: .space 4        # Buffer for single digit + null
space_char: .ascii " "        # offset 2
newline_char: .ascii "\n"     # offset 3
]]

-- Even simpler test - just print a sequence with manual addresses
Programs.SimpleCounter = [[
.text
.globl _start

_start:
    li a0, 10       # dividend
    li a1, 3        # divisor
    call divide

    # a0 = quotient (3), a1 = remainder (1)

    # Linux write syscall (very simplified demo)
    li a7, 64
    li a0, 1        # stdout
    la a1, msg
    li a2, 20
    ecall

    li a7, 93       # exit
    li a0, 0
    ecall

divide:
    beq a1, x0, div_by_zero
    div a2, a0, a1
    rem a3, a0, a1
    mv  a0, a2
    mv  a1, a3
    ret

div_by_zero:
    li a0, 0
    li a1, 0
    ret

.data
msg: .ascii "Division done\n"
]]

-- Test multiplication table
Programs.MultiplicationDemo = [[
.text
.globl _start  
_start:
    li t0, 2          # base number
    li t1, 1          # multiplier
    
multiply_loop:
    mul t2, t0, t1    # t2 = 2 * t1
    
    # Print result based on value
    li t3, 2
    beq t2, t3, print_2
    li t3, 4
    beq t2, t3, print_4
    li t3, 6
    beq t2, t3, print_6
    li t3, 8
    beq t2, t3, print_8
    li t3, 10
    beq t2, t3, print_10
    
    # Default case
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 10; li a2, 2; ecall  # "X "
    j continue_mult

print_2:
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 0; li a2, 2; ecall   # "2 "
    j continue_mult
print_4:
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 2; li a2, 2; ecall   # "4 "
    j continue_mult
print_6:
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 4; li a2, 2; ecall   # "6 "
    j continue_mult
print_8:
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 6; li a2, 2; ecall   # "8 "
    j continue_mult
print_10:
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 8; li a2, 3; ecall   # "10 "
    j continue_mult

continue_mult:
    addi t1, t1, 1    # multiplier++
    li t3, 6          # multiply up to 5 (2*1, 2*2, 2*3, 2*4, 2*5)
    blt t1, t3, multiply_loop
    
    # Print newline  
    li a7, 64; li a0, 1; lui a1, 0x10000; addi a1, a1, 12; li a2, 1; ecall
    
    li a7, 93; li a0, 0; ecall

.data
msg2:  .ascii "2 "     # offset 0-1
msg4:  .ascii "4 "     # offset 2-3
msg6:  .ascii "6 "     # offset 4-5
msg8:  .ascii "8 "     # offset 6-7
msg10: .ascii "10 "    # offset 8-10
msgX:  .ascii "X "     # offset 11-12 (but we put at 10 above, fix this)
newl:  .ascii "\n"     # offset 12
]]

return Programs
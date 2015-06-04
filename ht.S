/*
 * Hash table implementation in x64 assembly (AT&T flavour)
 *
 * Copyright (c) 2014 Ahmed Samy  <f.fallen45@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#define INITIAL_SPACE		64

/* This needs to be removed  */
#if defined(__linux__) && !defined(__MSYS__) && !defined(__MINGW32__)
#define	FIRST_ARG		%rdi
#define SECND_ARG		%rsi
#define THIRD_ARG		%rdx
#define FORTH_ARG		%rcx

#define DEF_FUN(name)	.type name, @function
#else
#define FIRST_ARG		%rcx
#define SECND_ARG		%rdx
#define THIRD_ARG		%r8
#define FORTH_ARG		%r9

#define DEF_FUN(name)	.type name, @function
#endif

#define HT_PTR(reg)		(reg)
#define __HT_PTR		HT_PTR(FIRST_ARG)

#define HT_COMMON_MASK(reg)	8(reg)
#define __HT_COMMON_MASK	HT_COMMON_MASK(FIRST_ARG)

#define HT_COMMON_BITS(reg)	16(reg)
#define __HT_COMMON_BITS	HT_COMMON_BITS(FIRST_ARG)

#define HT_SIZE(reg)		24(reg)
#define __HT_SIZE		HT_SIZE(FIRST_ARG)

#define HT_CAP(reg)		32(reg)
#define __HT_CAP		HT_CAP(FIRST_ARG)

/**
	void *htable_init() - Allocate and initialize a hash table

	The data structure:
		  (%ptr)	= table
		8 (%ptr)	= common mask
		16(%ptr)	= common bits
		24(%ptr)	= size
		32(%ptr)	= cap

	Example:
		call htable_init
		movq %rax, WHERE
*/
	.text
.globl htable_init
	DEF_FUN(htable_init)
htable_init:
	pushq	%rdi
	pushq	%rsi
	pushq	%rbx

	movl	$40, %edi	/* See structure above.  */
	call	malloc
	testq	%rax, %rax
	je	failure

	movq	$0,		HT_COMMON_MASK(%rax)	/* 8  */
	movq	$0,		HT_COMMON_BITS(%rax)	/* 16  */
	movq	$0,		HT_SIZE(%rax)		/* 24  */
	movq	$INITIAL_SPACE, HT_CAP(%rax)		/* 32 (See call to calloc below.) */

	movq	%rax, %rbx
	movl	$8, %esi				/* sizeof(uintptr_t)  */
	movl	$INITIAL_SPACE, %edi
	call	calloc					/* Allocate data for the ptr that will hold data.  */
	testq	%rax, %rax				/* Memory allocation failure?  */
	je	htable_failure

	movq	%rax, (%rbx)				/* Move it on top of the data structure.  */
	movq	%rbx, %rax				/* Put the data structure on %rax and return  */

	popq	%rbx
	popq	%rsi
	popq	%rdi
	ret

htable_failure:
	movq	%rbx, %rdi
	call	free

failure:
	popq	%rbx
	popq	%rsi
	popq	%rdi
	ret

/**
	void htable_free(void *ht)
*/
.globl htable_free
	DEF_FUN(htable_free)
htable_free:
	movq	%rdi, %rax
	movq	(%rdi), %rdi
	call	free

	movq	%rax, %rdi
	call	free

	xorq	%rax, %rax
	ret

/**
	void htable_expand(void *ht)
*/
	.section	.text.unlikely	/* cold  */
	DEF_FUN(htable_expand)
htable_expand:
	ret

/**
	void update_common(void *ht, const void *ptr)
*/
	.section 	.text.unlikely		/* cold  */
	DEF_FUN(update_common)
update_common:
	/* We're going to do nasty stuff on the pointer  */
	pushq	FIRST_ARG

	cmpq	$0, __HT_SIZE		/* No elements?  */
	je	__figure_commmons	/* Unlikely, let it have the longer jump.  */

	/* mask diff in %rdx */
	andq	__HT_COMMON_MASK, %rdx
	xorq	__HT_COMMON_BITS, %rdx
	notq	%rdx

	/* bits diff in %rbx */
	movq	%rdx, %rbx
	andq	__HT_COMMON_BITS, %rbx

	movq	__HT_SIZE, %rcx
	movq	__HT_PTR, %rdi

loop_table:
	andq	%rdx, (%rdi, %rcx, 8)	/* ht[i] &= ~maskdiff  */
	orq	%rbx, (%rdi, %rcx, 8)	/* ht[i] |= bitsdiff  */

	subq	$1, %rcx
	jne	loop_table

	andq	%rdx, __HT_COMMON_MASK
	andq	%rdx, __HT_COMMON_BITS

	jmp	done

__figure_commmons:
	movl	$63, %ecx
	jmp 	figure_commons

again:
	subl	$1, %ecx
	je	done

figure_commons:
	btq	%rcx, %rdx
	jnc	again

	movq	%rdx, %rdi	/* Save %rdx for bits  */
	/* ~(1 << %cl)  */
	movq	$-2, %rdx
	rolq	%cl, %rdx
	/* Set mask  */
	movq	%rdx, __HT_COMMON_MASK

	/* Set bits  */
	andq	__HT_COMMON_MASK, %rdi
	movq	%rdi, __HT_COMMON_BITS

done:
	popq	%rdi
	popq	%rcx
	popq	%rbx
	popq	%rdx

	ret


/**
	uintptr_t hash_ptr_bits(void *ht, size_t hash)
*/
	DEF_FUN(hash_ptr_bits)
hash_ptr_bits:
	pushq	%r8

	movq	%rcx, %r8
	movq	__HT_SIZE, %rcx
	movq	%rcx, %rax		/* We return a temporary.  */
	shrq	%cl, %rax		/* hash >> size  */
	xorq	%rcx, %rax		/* (hash >> size) ^ hash  */
	andq	__HT_COMMON_MASK, %rax	/* In total: (hash ^ (hash >> size)) & common_mask  */

	popq	%rbx
	ret

	DEF_FUN(expand_table)
expand_table:
	ret

/**
	void htable_add(void *table, const void *ptr, const size_t hash)
*/
.globl htable_add
	DEF_FUN(htable_add)
htable_add:
	pushq	%rcx

	movq	__HT_SIZE, %rcx
	cmpq	%rcx,__HT_CAP
	jne	proceed
	call	expand_table

proceed:
	movq	__HT_COMMON_MASK, %rdi
	movq	%rdx, %rbx
	andq	%rdi, %rbx		/* (ptr & common_mask)  */
	cmpq	__HT_COMMON_BITS, %rbx
	je	proceed_2
	call	update_common
	
proceed_2:
	call 	hash_ptr_bits
	notq	%rdi			/* ~common_mask  */
	andq	%rdi, %rdx		/* ptr & ~common_mask  */
	orq	%rax, %rdx		/* (ptr & ~common_mask) | bits  */

	/* Add it  */
	movq	__HT_PTR, %r9
	movq	%rdx, (%r9, %r8, 8)
	incq	__HT_SIZE

	xorq	%rax, %rax
	popq	%rcx
	ret

/**
	void *htable_get(table, idx) - Get the pointer at @idx
	@table: the table pointer returned by htable_init()

	Example:
		movl	INDEX, %esi
		movq	TABLE, %rdi
		call	htable_get
		movq	%rax, RESULT
*/
.globl htable_get
	DEF_FUN(htable_get)
htable_get:
	pushq	%rdx

	movq	(%rdi), %rdx
	movq	HT_COMMON_MASK(%rdi), %rax
	movslq	%esi, %rsi
	notq	%rax			/* ~mask  */
	andq	(%rdx, %rsi, 8), %rax	/* (table[index] & ~mask)  */
	orq	HT_COMMON_BITS(%rdi), %rax	/* (table[index] & ~mask) | bits  */

	popq	%rdx
	ret

	.section	.text.unlikely					/* cold  */
.globl htable_size
	DEF_FUN(htable_size)
htable_size:
	movq	__HT_SIZE, %rax
	ret

	.section	.text.unlikely					/* cold  */
.globl htable_cap
	DEF_FUN(htable_cap)
htable_cap:
	movq	__HT_CAP, %rax
	ret

/* vim: set ft=gas:  */


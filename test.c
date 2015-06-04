#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

extern void *htable_init(size_t);
extern void htable_free(void *table);
extern void htable_add(void *, const void *, size_t, size_t);
extern void *htable_get(void *, size_t);

extern size_t htable_size(const void *);
extern size_t htable_cap(const void *);

int main()
{
	/* Retarded test case  */
	void *ht = htable_init(32);
	printf("table: %p (%d / %d)\n", ht, htable_size(ht), htable_cap(ht));

	int i;

	uint32_t *ptr[5];
	for (i = 0; i < 5; ++i) {
		ptr[i] = malloc(sizeof(uint32_t));
		*ptr[i] = i;
		printf("htable_add(%p, %d)\n", ptr[i], i);
		htable_add(ht, ptr[i], i, 0xdeadbeef);
	}

	for (i = 0; i < htable_size(ht); ++i) {
		uint32_t *tmp = htable_get(ht, i);

		printf("htable_get(%d): %p => *%d(original: %p same: %s)\n",
			i, tmp, ptr[i], *tmp, ptr[i] == tmp ? "yes" : "nop"
		);
		free(ptr[i]);
	}

	htable_free(ht);
	return 0;
}

// murmurhash3.h

#ifndef MURMURHASH3_H
#define MURMURHASH3_H

#include <cstdint>

void MurmurHash3_x86_32(const void *key, int len, uint32_t seed, void *out);

#endif // MURMURHASH3_H

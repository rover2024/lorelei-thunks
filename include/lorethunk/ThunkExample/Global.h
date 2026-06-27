#ifndef LORE_THUNKEXAMPLE_GLOBAL_H
#define LORE_THUNKEXAMPLE_GLOBAL_H

#ifdef THUNKEXAMPLE_LIBRARY
#  define THUNKEXAMPLE_EXPORT __attribute__((visibility("default")))
#else
#  define THUNKEXAMPLE_EXPORT
#endif

#endif // LORE_THUNKEXAMPLE_GLOBAL_H

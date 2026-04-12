// Headless smoke test for libmywiki_ai. Verifies the cdylib can be dlopened,
// the expected symbols are present, the version probe returns a string, and
// the null-pointer guard returns an error JSON instead of crashing.
//
// Build & run:
//     cc tests/test_ffi.c -o tests/test_ffi
//     ./tests/test_ffi

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef const char *(*version_fn)(void);
typedef char       *(*node_fn)(const char *, const char *);
typedef void        (*free_fn)(char *);

static const char *candidates[] = {
    "./libmywiki_ai.so",
    "./libmywiki_ai.dylib",
    "libmywiki_ai.so",
    "libmywiki_ai.dylib",
    NULL,
};

int main(void) {
    void *h = NULL;
    for (int i = 0; candidates[i]; i++) {
        h = dlopen(candidates[i], RTLD_LAZY);
        if (h) {
            printf("loaded %s\n", candidates[i]);
            break;
        }
    }
    if (!h) {
        fprintf(stderr, "FAIL: dlopen: %s\n", dlerror());
        return 1;
    }

    version_fn version = (version_fn) dlsym(h, "mywiki_ai_version");
    node_fn    node    = (node_fn)    dlsym(h, "mywiki_ai_node");
    free_fn    sfree   = (free_fn)    dlsym(h, "mywiki_ai_string_free");
    if (!version || !node || !sfree) {
        fprintf(stderr, "FAIL: missing symbol\n");
        return 1;
    }

    const char *v = version();
    if (!v || !*v) {
        fprintf(stderr, "FAIL: empty version\n");
        return 1;
    }
    printf("version ok: %s\n", v);

    char *res = node(NULL, NULL);
    if (!res) {
        fprintf(stderr, "FAIL: node returned NULL\n");
        return 1;
    }
    if (!strstr(res, "\"ok\":false") || !strstr(res, "null")) {
        fprintf(stderr, "FAIL: expected null-guard error JSON, got: %s\n", res);
        sfree(res);
        return 1;
    }
    printf("null guard ok: %s\n", res);
    sfree(res);

    dlclose(h);
    printf("PASS\n");
    return 0;
}

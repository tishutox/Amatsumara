/*
 * flutter_llama core (sdd-flutter-llama-agent 1.1): one C ABI over llama.cpp for every platform bridge
 * (Android JNI, iOS / macOS Objective-C++, Windows / Linux FFI). No global state: every loaded model is a handle.
 * Strings are UTF-8. Functions returning int: >= 0 success (often a length / count), < 0 an FL_ERR_* code.
 * Licence: NativeMindNONC (this file); llama.cpp is MIT.
 */
#ifndef FLUTTER_LLAMA_CORE_H
#define FLUTTER_LLAMA_CORE_H

#include <stdint.h>

#ifdef _WIN32
#define FL_API __declspec(dllexport)
#else
#define FL_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define FL_ERR_ARG         -1   /* bad argument */
#define FL_ERR_NOT_LOADED  -2
#define FL_ERR_TOKENIZE    -3
#define FL_ERR_DECODE      -4
#define FL_ERR_GRAMMAR     -5   /* the GBNF did not parse */
#define FL_ERR_CONTEXT     -6   /* the prompt does not fit the context */
#define FL_ERR_TEMPLATE    -7   /* no usable chat template */
#define FL_ERR_BUFFER      -8   /* the output buffer is too small; the return value of a retry tells the size */
#define FL_ERR_CANCELLED   -9
#define FL_ERR_EMBEDDINGS -10   /* the model / context gives no embeddings */

typedef struct fl_model fl_model;

typedef struct fl_load_params {
  int32_t n_ctx;          /* 0 = the model's training context, capped at 8192 */
  int32_t n_batch;        /* 0 = 512 */
  int32_t n_threads;      /* 0 = half the logical cores, at most 8 */
  int32_t n_gpu_layers;   /* -1 = all, 0 = CPU */
  int32_t embeddings;     /* 1 = the context also returns embeddings */
} fl_load_params;

typedef struct fl_sample_params {
  float temperature;      /* <= 0 = greedy */
  float top_p;
  int32_t top_k;
  float repeat_penalty;   /* 1.0 = off (1.1.x passed it but ignored it; honoured since 1.2.0) */
  int32_t repeat_last_n;  /* 0 = 64 */
  int32_t max_tokens;
  uint32_t seed;          /* 0 = random */
  const char* const* stop;  /* stop strings (NULL-terminated array or NULL) */
} fl_sample_params;

typedef struct fl_message { const char* role; const char* content; } fl_message;

typedef struct fl_usage { int32_t prompt_tokens; int32_t completion_tokens; int32_t stop_reason; /* 0 eos, 1 max, 2 stop string, 3 cancelled */ } fl_usage;

/* One generated piece (not NUL-terminated). Return non-zero to cancel. */
typedef int (*fl_token_cb)(void* user, const char* piece, int32_t len);

FL_API void      fl_backend_init(void);
FL_API fl_model* fl_load(const char* path, const fl_load_params* params, char* err, int32_t err_len);
FL_API void      fl_free(fl_model* m);

/* Formats [msgs] with [tmpl] (NULL = the model's own template; a built-in name such as "chatml" / "llama3" / "gemma" /
 * "phi3" / "mistral-v7"; or a template string), appending the assistant prefix when [add_assistant]. Returns the
 * length; FL_ERR_BUFFER with the needed length in *needed when [out] is too small. */
FL_API int32_t fl_apply_chat_template(fl_model* m, const fl_message* msgs, int32_t n, const char* tmpl, int32_t add_assistant,
                                      char* out, int32_t out_len, int32_t* needed);

/* Generates from [prompt] (the context is cleared first). [gbnf] (optional, root rule "root") constrains sampling.
 * Pieces go to [cb]; [usage] gets the counts. Thread-safe per model (one generation at a time). */
FL_API int32_t fl_generate(fl_model* m, const char* prompt, const fl_sample_params* sp, const char* gbnf,
                           fl_token_cb cb, void* user, fl_usage* usage);

/* Sets the cancel flag of the running generation (any thread). */
FL_API void    fl_stop(fl_model* m);

FL_API int32_t fl_tokenize_count(fl_model* m, const char* text, int32_t add_special);

/* GGUF metadata value by key (e.g. "general.name", "general.license", "tokenizer.chat_template"); the length or < 0. */
FL_API int32_t fl_meta(fl_model* m, const char* key, char* out, int32_t out_len);

/* Model facts: n_params, size in bytes, training context, current context, vocab size. */
typedef struct fl_model_facts { uint64_t n_params; uint64_t size_bytes; int32_t n_ctx_train; int32_t n_ctx; int32_t n_vocab; int32_t has_template; } fl_model_facts;
FL_API int32_t fl_facts(fl_model* m, fl_model_facts* out, char* desc, int32_t desc_len);

/* log P(label | prompt) for each label (sum over the label's tokens); [out] gets n floats. */
FL_API int32_t fl_label_logprobs(fl_model* m, const char* prompt, const char* const* labels, int32_t n, float* out);

/* Mean-pooled, L2-normalised embedding of [text] into [out] (dim floats); returns dim or < 0. */
FL_API int32_t fl_embed(fl_model* m, const char* text, float* out, int32_t dim);

#ifdef __cplusplus
}
#endif
#endif

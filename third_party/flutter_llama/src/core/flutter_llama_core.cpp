// flutter_llama core (sdd-flutter-llama-agent 1.1): see flutter_llama_core.h. Extracted from the Android JNI bridge
// (android/src/main/cpp/flutter_llama_bridge.cpp, 1.1.2) with two human-factor fixes: the context memory is cleared
// before every generation (1.1.x kept appending positions, so repeated calls overflowed the context) and
// repeat_penalty is applied (1.1.x accepted it but never used it).
#include "flutter_llama_core.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "llama.h"

struct fl_model {
  llama_model* model = nullptr;
  llama_context* ctx = nullptr;
  const llama_vocab* vocab = nullptr;
  std::mutex mutex;            // one generation / evaluation at a time
  std::atomic<bool> stop{false};
  bool embeddings = false;
};

namespace {

void set_err(char* err, int32_t len, const std::string& msg) {
  if (!err || len <= 0) return;
  std::strncpy(err, msg.c_str(), static_cast<size_t>(len - 1));
  err[len - 1] = '\0';
}

bool tokenize(const llama_vocab* vocab, const std::string& text, bool add_special, std::vector<llama_token>& out) {
  const int n = -llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.size()), nullptr, 0, add_special, true);
  if (n < 0) return false;
  out.resize(static_cast<size_t>(n));
  return llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.size()), out.data(), n, add_special, true) >= 0;
}

std::string piece(const llama_vocab* vocab, llama_token t) {
  char buf[256];
  int n = llama_token_to_piece(vocab, t, buf, sizeof(buf), 0, true);
  if (n < 0) {
    std::string big(static_cast<size_t>(-n), '\0');
    n = llama_token_to_piece(vocab, t, big.data(), -n, 0, true);
    return n > 0 ? big.substr(0, static_cast<size_t>(n)) : std::string();
  }
  return std::string(buf, static_cast<size_t>(n));
}

// Decodes [tokens] starting at [pos0] on sequence [seq] in n_batch chunks; [logits_last] asks for the last logits only,
// [logits_all] for every token.
bool decode(fl_model* m, const std::vector<llama_token>& tokens, int pos0, llama_seq_id seq, bool logits_all) {
  const int n_batch = static_cast<int>(llama_n_batch(m->ctx));
  llama_batch batch = llama_batch_init(n_batch, 0, 1);
  bool ok = true;
  for (size_t start = 0; start < tokens.size() && ok; start += static_cast<size_t>(n_batch)) {
    const size_t end = std::min(tokens.size(), start + static_cast<size_t>(n_batch));
    batch.n_tokens = 0;
    for (size_t i = start; i < end; ++i) {
      const int k = batch.n_tokens++;
      batch.token[k] = tokens[i];
      batch.pos[k] = pos0 + static_cast<int>(i);
      batch.n_seq_id[k] = 1;
      batch.seq_id[k][0] = seq;
      batch.logits[k] = logits_all || i + 1 == tokens.size();
    }
    ok = llama_decode(m->ctx, batch) == 0;
  }
  llama_batch_free(batch);
  return ok;
}

// Length of the longest complete UTF-8 prefix of [s].
size_t utf8_complete(const std::string& s) {
  size_t i = s.size();
  int back = 0;
  while (i > 0 && back < 4) {
    const unsigned char c = static_cast<unsigned char>(s[i - 1]);
    if ((c & 0xC0) != 0x80) {  // a lead byte or ASCII
      const int need = (c & 0x80) == 0 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : (c & 0xF8) == 0xF0 ? 4 : 1;
      return back + 1 >= need ? s.size() : i - 1;
    }
    --i;
    ++back;
  }
  return s.size();
}

}  // namespace

extern "C" {

FL_API void fl_backend_init(void) {
  static std::once_flag once;
  std::call_once(once, [] {
    llama_backend_init();
    ggml_backend_load_all();
  });
}

FL_API fl_model* fl_load(const char* path, const fl_load_params* params, char* err, int32_t err_len) {
  if (!path) {
    set_err(err, err_len, "path is null");
    return nullptr;
  }
  fl_backend_init();
  fl_load_params p = params ? *params : fl_load_params{0, 0, 0, -1, 0};
  llama_model_params mp = llama_model_default_params();
  mp.n_gpu_layers = p.n_gpu_layers < 0 ? 999 : p.n_gpu_layers;
  llama_model* model = llama_model_load_from_file(path, mp);
  if (!model) {
    set_err(err, err_len, std::string("failed to load model: ") + path);
    return nullptr;
  }
  llama_context_params cp = llama_context_default_params();
  const int train = llama_model_n_ctx_train(model);
  cp.n_ctx = static_cast<uint32_t>(p.n_ctx > 0 ? p.n_ctx : std::min(train > 0 ? train : 4096, 8192));
  cp.n_batch = static_cast<uint32_t>(p.n_batch > 0 ? p.n_batch : 512);
  // Default: half the logical cores (≈ the physical ones), at most 8 for generation. All logical cores make ggml's
  // spinning barriers collapse when the machine is busy (and hyper-threads add nothing to token generation).
  const int hw = static_cast<int>(std::max(1u, std::thread::hardware_concurrency()));
  const int threads = p.n_threads > 0 ? p.n_threads : std::clamp(hw / 2, 1, 8);
  cp.n_threads = threads;
  cp.n_threads_batch = p.n_threads > 0 ? p.n_threads : std::max(1, hw / 2);
  cp.n_seq_max = 2;  // label scoring evaluates candidates on a second sequence
  cp.embeddings = p.embeddings != 0;
  llama_context* ctx = llama_init_from_model(model, cp);
  if (!ctx) {
    llama_model_free(model);
    set_err(err, err_len, "failed to create the context");
    return nullptr;
  }
  auto* m = new fl_model();
  m->model = model;
  m->ctx = ctx;
  m->vocab = llama_model_get_vocab(model);
  m->embeddings = cp.embeddings;
  return m;
}

FL_API void fl_free(fl_model* m) {
  if (!m) return;
  {
    std::lock_guard<std::mutex> lock(m->mutex);
    if (m->ctx) llama_free(m->ctx);
    if (m->model) llama_model_free(m->model);
  }
  delete m;
}

FL_API int32_t fl_apply_chat_template(fl_model* m, const fl_message* msgs, int32_t n, const char* tmpl, int32_t add_assistant,
                                      char* out, int32_t out_len, int32_t* needed) {
  if (!m || (!msgs && n > 0)) return FL_ERR_ARG;
  const char* t = tmpl ? tmpl : llama_model_chat_template(m->model, nullptr);
  if (!t) return FL_ERR_TEMPLATE;
  std::vector<llama_chat_message> chat(static_cast<size_t>(n));
  size_t total = 0;
  for (int i = 0; i < n; ++i) {
    chat[static_cast<size_t>(i)] = {msgs[i].role, msgs[i].content ? msgs[i].content : ""};
    total += std::strlen(chat[static_cast<size_t>(i)].content) + 32;
  }
  std::string buf(std::max<size_t>(total * 2, 256), '\0');
  int32_t len = llama_chat_apply_template(t, chat.data(), chat.size(), add_assistant != 0, buf.data(), static_cast<int32_t>(buf.size()));
  if (len < 0) return FL_ERR_TEMPLATE;
  if (static_cast<size_t>(len) > buf.size()) {
    buf.resize(static_cast<size_t>(len));
    len = llama_chat_apply_template(t, chat.data(), chat.size(), add_assistant != 0, buf.data(), len);
    if (len < 0) return FL_ERR_TEMPLATE;
  }
  if (needed) *needed = len + 1;
  if (!out || out_len < len + 1) return FL_ERR_BUFFER;
  std::memcpy(out, buf.data(), static_cast<size_t>(len));
  out[len] = '\0';
  return len;
}

FL_API void fl_stop(fl_model* m) {
  if (m) m->stop = true;
}

FL_API int32_t fl_generate(fl_model* m, const char* prompt, const fl_sample_params* sp, const char* gbnf,
                           fl_token_cb cb, void* user, fl_usage* usage) {
  if (!m || !prompt) return FL_ERR_ARG;
  std::lock_guard<std::mutex> lock(m->mutex);
  m->stop = false;
  const fl_sample_params s = sp ? *sp : fl_sample_params{0.8f, 0.95f, 40, 1.0f, 64, 256, 0, nullptr};

  std::vector<llama_token> tokens;
  if (!tokenize(m->vocab, prompt, true, tokens)) return FL_ERR_TOKENIZE;
  const int n_ctx = static_cast<int>(llama_n_ctx(m->ctx));
  if (static_cast<int>(tokens.size()) + 1 >= n_ctx) return FL_ERR_CONTEXT;
  const int max_tokens = std::min(s.max_tokens > 0 ? s.max_tokens : 256, n_ctx - static_cast<int>(tokens.size()) - 1);

  llama_memory_clear(llama_get_memory(m->ctx), true);  // fix: 1.1.x reused stale positions
  if (!decode(m, tokens, 0, 0, false)) return FL_ERR_DECODE;

  llama_sampler* chain = llama_sampler_chain_init(llama_sampler_chain_default_params());
  if (gbnf && *gbnf) {
    llama_sampler* g = llama_sampler_init_grammar(m->vocab, gbnf, "root");
    if (!g) {
      llama_sampler_free(chain);
      return FL_ERR_GRAMMAR;
    }
    llama_sampler_chain_add(chain, g);
  }
  if (s.repeat_penalty > 0 && s.repeat_penalty != 1.0f) {
    llama_sampler_chain_add(chain, llama_sampler_init_penalties(s.repeat_last_n > 0 ? s.repeat_last_n : 64, s.repeat_penalty, 0.0f, 0.0f));
  }
  if (s.temperature <= 0) {
    llama_sampler_chain_add(chain, llama_sampler_init_greedy());
  } else {
    if (s.top_k > 0) llama_sampler_chain_add(chain, llama_sampler_init_top_k(s.top_k));
    if (s.top_p > 0 && s.top_p < 1) llama_sampler_chain_add(chain, llama_sampler_init_top_p(s.top_p, 1));
    llama_sampler_chain_add(chain, llama_sampler_init_temp(s.temperature));
    llama_sampler_chain_add(chain, llama_sampler_init_dist(s.seed ? s.seed : std::random_device{}()));
  }

  std::vector<std::string> stops;
  for (const char* const* p = s.stop; p && *p; ++p) {
    if (**p) stops.emplace_back(*p);
  }
  std::string pending;  // text not yet emitted (a possible stop prefix or an incomplete UTF-8 sequence)
  int32_t reason = 1;   // max tokens unless something else ends it
  int generated = 0;
  int pos = static_cast<int>(tokens.size());
  int32_t rc = 0;
  auto emit = [&](size_t n) -> bool {
    if (n == 0) return true;
    const bool cancel = cb && cb(user, pending.data(), static_cast<int32_t>(n)) != 0;
    pending.erase(0, n);
    return !cancel;
  };

  for (; generated < max_tokens; ++generated) {
    if (m->stop) {
      reason = 3;
      break;
    }
    const llama_token t = llama_sampler_sample(chain, m->ctx, -1);
    if (llama_vocab_is_eog(m->vocab, t)) {
      reason = 0;
      break;
    }
    pending += piece(m->vocab, t);
    // A stop string ends the reply (it is not emitted).
    size_t hit = std::string::npos;
    for (const auto& st : stops) hit = std::min(hit, pending.find(st));
    if (hit != std::string::npos) {
      emit(hit);
      pending.clear();
      reason = 2;
      ++generated;
      break;
    }
    // Hold back a suffix that may start a stop string, and an incomplete UTF-8 tail.
    size_t keep = 0;
    for (const auto& st : stops) {
      for (size_t k = std::min(st.size() - 1, pending.size()); k > keep; --k) {
        if (pending.compare(pending.size() - k, k, st, 0, k) == 0) {
          keep = k;
          break;
        }
      }
    }
    const size_t safe = std::min(utf8_complete(pending), pending.size() - keep);
    if (!emit(safe)) {
      reason = 3;
      ++generated;
      break;
    }
    llama_token next = t;
    llama_batch b = llama_batch_get_one(&next, 1);
    if (llama_decode(m->ctx, b) != 0) {
      rc = FL_ERR_DECODE;
      ++generated;
      break;
    }
    ++pos;
  }
  if (rc == 0 && reason != 2 && reason != 3) emit(pending.size());
  llama_sampler_free(chain);
  if (usage) *usage = {static_cast<int32_t>(tokens.size()), generated, reason};
  if (rc < 0) return rc;
  return reason == 3 ? FL_ERR_CANCELLED : generated;
}

FL_API int32_t fl_tokenize_count(fl_model* m, const char* text, int32_t add_special) {
  if (!m || !text) return FL_ERR_ARG;
  std::vector<llama_token> tokens;
  if (!tokenize(m->vocab, text, add_special != 0, tokens)) return FL_ERR_TOKENIZE;
  return static_cast<int32_t>(tokens.size());
}

FL_API int32_t fl_meta(fl_model* m, const char* key, char* out, int32_t out_len) {
  if (!m || !key) return FL_ERR_ARG;
  if (std::strcmp(key, "tokenizer.chat_template") == 0) {
    const char* t = llama_model_chat_template(m->model, nullptr);
    if (!t) return FL_ERR_TEMPLATE;
    const int32_t len = static_cast<int32_t>(std::strlen(t));
    if (!out || out_len < len + 1) return FL_ERR_BUFFER;
    std::memcpy(out, t, static_cast<size_t>(len) + 1);
    return len;
  }
  return llama_model_meta_val_str(m->model, key, out, static_cast<size_t>(out_len));
}

FL_API int32_t fl_facts(fl_model* m, fl_model_facts* out, char* desc, int32_t desc_len) {
  if (!m || !out) return FL_ERR_ARG;
  out->n_params = llama_model_n_params(m->model);
  out->size_bytes = llama_model_size(m->model);
  out->n_ctx_train = llama_model_n_ctx_train(m->model);
  out->n_ctx = static_cast<int32_t>(llama_n_ctx(m->ctx));
  out->n_vocab = llama_vocab_n_tokens(m->vocab);
  out->has_template = llama_model_chat_template(m->model, nullptr) != nullptr;
  if (desc && desc_len > 0) llama_model_desc(m->model, desc, static_cast<size_t>(desc_len));
  return 0;
}

FL_API int32_t fl_label_logprobs(fl_model* m, const char* prompt, const char* const* labels, int32_t n, float* out) {
  if (!m || !prompt || !labels || !out || n <= 0) return FL_ERR_ARG;
  std::lock_guard<std::mutex> lock(m->mutex);
  std::vector<llama_token> ptoks;
  if (!tokenize(m->vocab, prompt, true, ptoks)) return FL_ERR_TOKENIZE;
  const int n_vocab = llama_vocab_n_tokens(m->vocab);
  const int n_ctx = static_cast<int>(llama_n_ctx(m->ctx));
  llama_memory_t mem = llama_get_memory(m->ctx);
  llama_memory_clear(mem, true);
  if (static_cast<int>(ptoks.size()) + 1 >= n_ctx) return FL_ERR_CONTEXT;
  if (!decode(m, ptoks, 0, 0, false)) return FL_ERR_DECODE;
  const float* last = llama_get_logits_ith(m->ctx, -1);
  const std::vector<float> prompt_logits(last, last + n_vocab);

  auto log_softmax_at = [n_vocab](const float* logits, llama_token t) {
    float mx = logits[0];
    for (int i = 1; i < n_vocab; ++i) mx = std::max(mx, logits[i]);
    double sum = 0;
    for (int i = 0; i < n_vocab; ++i) sum += std::exp(static_cast<double>(logits[i] - mx));
    return static_cast<float>(logits[t] - mx - std::log(sum));
  };

  const int p0 = static_cast<int>(ptoks.size());
  for (int li = 0; li < n; ++li) {
    // The label as a continuation (with a leading space if the tokenizer splits words that way).
    std::vector<llama_token> ltoks;
    if (!tokenize(m->vocab, std::string(labels[li] ? labels[li] : ""), false, ltoks) || ltoks.empty()) {
      out[li] = -INFINITY;
      continue;
    }
    float lp = log_softmax_at(prompt_logits.data(), ltoks[0]);
    if (ltoks.size() > 1) {
      llama_memory_seq_rm(mem, 1, -1, -1);
      llama_memory_seq_cp(mem, 0, 1, -1, -1);
      std::vector<llama_token> head(ltoks.begin(), ltoks.end() - 1);
      if (static_cast<int>(head.size()) + p0 >= n_ctx || !decode(m, head, p0, 1, true)) return FL_ERR_DECODE;
      for (size_t k = 1; k < ltoks.size(); ++k) {
        lp += log_softmax_at(llama_get_logits_ith(m->ctx, static_cast<int32_t>(k - 1)), ltoks[k]);
      }
      llama_memory_seq_rm(mem, 1, -1, -1);
    }
    out[li] = lp;
  }
  return n;
}

FL_API int32_t fl_embed(fl_model* m, const char* text, float* out, int32_t dim) {
  if (!m || !text || !out) return FL_ERR_ARG;
  if (!m->embeddings) return FL_ERR_EMBEDDINGS;
  std::lock_guard<std::mutex> lock(m->mutex);
  const int n_embd = llama_model_n_embd(m->model);
  if (dim < n_embd) return FL_ERR_BUFFER;
  std::vector<llama_token> toks;
  if (!tokenize(m->vocab, text, true, toks) || toks.empty()) return FL_ERR_TOKENIZE;
  llama_memory_clear(llama_get_memory(m->ctx), true);
  if (!decode(m, toks, 0, 0, true)) return FL_ERR_DECODE;
  std::vector<double> acc(static_cast<size_t>(n_embd), 0.0);
  const float* pooled = llama_pooling_type(m->ctx) == LLAMA_POOLING_TYPE_NONE ? nullptr : llama_get_embeddings_seq(m->ctx, 0);
  if (pooled) {
    for (int i = 0; i < n_embd; ++i) acc[static_cast<size_t>(i)] = pooled[i];
  } else {
    for (size_t t = 0; t < toks.size(); ++t) {
      const float* e = llama_get_embeddings_ith(m->ctx, static_cast<int32_t>(t));
      if (!e) return FL_ERR_EMBEDDINGS;
      for (int i = 0; i < n_embd; ++i) acc[static_cast<size_t>(i)] += e[i];
    }
    for (auto& v : acc) v /= static_cast<double>(toks.size());
  }
  double norm = 0;
  for (double v : acc) norm += v * v;
  norm = std::sqrt(norm) + 1e-12;
  for (int i = 0; i < n_embd; ++i) out[i] = static_cast<float>(acc[static_cast<size_t>(i)] / norm);
  return n_embd;
}

}  // extern "C"

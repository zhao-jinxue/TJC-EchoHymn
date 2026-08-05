#include "hymn_engine_capi.h"
#include "hymn_engine.h"
#include <cstdlib>
#include <cstring>
#include <sstream>

using echohymn::HymnEngine;

// ==================== FFI 辅助 ====================
namespace {

// 分配 C 字符串（调用者用 free 释放）
char* dupCString(const std::string& s) {
    char* buf = static_cast<char*>(std::malloc(s.size() + 1));
    if (!buf) return nullptr;
    std::memcpy(buf, s.c_str(), s.size() + 1);
    return buf;
}

} // namespace

// ==================== 引擎生命周期 ====================
extern "C" HymnEngineHymn* hymn_engine_create(void) {
    return reinterpret_cast<HymnEngineHymn*>(new HymnEngine());
}

extern "C" void hymn_engine_destroy(HymnEngineHymn* engine) {
    delete reinterpret_cast<HymnEngine*>(engine);
}

extern "C" int hymn_engine_load_from_json(HymnEngineHymn* engine, const char* json) {
    if (!engine || !json) return 0;
    return reinterpret_cast<HymnEngine*>(engine)->loadFromJson(json) ? 1 : 0;
}

extern "C" int hymn_engine_load_from_file(HymnEngineHymn* engine, const char* path) {
    if (!engine || !path) return 0;
    return reinterpret_cast<HymnEngine*>(engine)->loadFromFile(path) ? 1 : 0;
}

extern "C" int hymn_engine_count(HymnEngineHymn* engine) {
    if (!engine) return 0;
    return static_cast<int>(reinterpret_cast<HymnEngine*>(engine)->count());
}

// ==================== 搜索 ====================
extern "C" char* hymn_engine_search(HymnEngineHymn* engine, const char* keyword) {
    if (!engine || !keyword) return nullptr;
    auto ids = reinterpret_cast<HymnEngine*>(engine)->search(keyword);
    std::ostringstream ss;
    for (size_t i = 0; i < ids.size(); ++i) {
        if (i > 0) ss << ',';
        ss << ids[i];
    }
    return dupCString(ss.str());
}

// ==================== 字段访问 ====================
extern "C" char* hymn_engine_get_field(HymnEngineHymn* engine, int id, const char* field) {
    if (!engine || !field) return nullptr;
    const auto* hymn = reinterpret_cast<HymnEngine*>(engine)->findById(id);
    if (!hymn) return nullptr;

    std::string value;
    if (std::strcmp(field, "title") == 0) value = hymn->title;
    else if (std::strcmp(field, "author") == 0) value = hymn->author;
    else if (std::strcmp(field, "composer") == 0) value = hymn->composer;
    else if (std::strcmp(field, "category") == 0) value = hymn->category;
    else if (std::strcmp(field, "audio") == 0) value = hymn->audio;
    else if (std::strcmp(field, "number") == 0) value = std::to_string(hymn->number);
    else return nullptr;

    return dupCString(value);
}

// ==================== 歌词访问 ====================
extern "C" int hymn_engine_lyrics_stanza_count(HymnEngineHymn* engine, int id) {
    if (!engine) return -1;
    const auto* hymn = reinterpret_cast<HymnEngine*>(engine)->findById(id);
    if (!hymn) return -1;
    return static_cast<int>(hymn->lyrics.size());
}

extern "C" int hymn_engine_lyrics_line_count(HymnEngineHymn* engine, int id, int stanza) {
    if (!engine || stanza < 0) return -1;
    const auto* hymn = reinterpret_cast<HymnEngine*>(engine)->findById(id);
    if (!hymn || stanza >= static_cast<int>(hymn->lyrics.size())) return -1;
    return static_cast<int>(hymn->lyrics[stanza].size());
}

extern "C" char* hymn_engine_lyrics_line(HymnEngineHymn* engine, int id, int stanza, int line) {
    if (!engine || stanza < 0 || line < 0) return nullptr;
    const auto* hymn = reinterpret_cast<HymnEngine*>(engine)->findById(id);
    if (!hymn || stanza >= static_cast<int>(hymn->lyrics.size())) return nullptr;
    if (line >= static_cast<int>(hymn->lyrics[stanza].size())) return nullptr;
    return dupCString(hymn->lyrics[stanza][line]);
}
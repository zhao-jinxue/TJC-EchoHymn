#ifndef HYMN_ENGINE_CAPI_H
#define HYMN_ENGINE_CAPI_H

// C ABI 桥接层：用于 dart:ffi 直接调用 C++
// 编译时需链接 hymn_engine.cpp

#ifdef __cplusplus
extern "C" {
#endif

// 不透明句柄
typedef struct HymnEngineHymn HymnEngineHymn;

// 引擎操作
HymnEngineHymn* hymn_engine_create(void);
void hymn_engine_destroy(HymnEngineHymn* engine);
int hymn_engine_load_from_json(HymnEngineHymn* engine, const char* json);
int hymn_engine_load_from_file(HymnEngineHymn* engine, const char* path);
int hymn_engine_count(HymnEngineHymn* engine);

// 搜索：返回以逗号分隔的 id 列表；调用者需 free 返回值
char* hymn_engine_search(HymnEngineHymn* engine, const char* keyword);

// 通过 id 获取字段（返回 UTF-8 字符串，需 free；找不到返回 NULL）
// field 可选值：title / author / composer / category / audio / number
char* hymn_engine_get_field(HymnEngineHymn* engine, int id, const char* field);

// 获取歌词段数；找不到返回 -1
int hymn_engine_lyrics_stanza_count(HymnEngineHymn* engine, int id);

// 获取某段歌词的行数；无此行或找不到返回 -1
int hymn_engine_lyrics_line_count(HymnEngineHymn* engine, int id, int stanza);

// 获取某行歌词（UTF-8，需 free；失败返回 NULL）
char* hymn_engine_lyrics_line(HymnEngineHymn* engine, int id, int stanza, int line);

#ifdef __cplusplus
}
#endif

#endif // HYMN_ENGINE_CAPI_H
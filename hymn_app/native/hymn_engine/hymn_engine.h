#ifndef HYMN_ENGINE_H
#define HYMN_ENGINE_H

#include <string>
#include <vector>

namespace echohymn {

// 诗歌条目
struct Hymn {
    int id;
    int number;
    std::string title;
    std::string author;
    std::string composer;
    std::string category;
    std::string audio;
    std::vector<std::vector<std::string>> lyrics; // 每段歌词
};

// 搜索匹配结果
struct SearchResult {
    int id;
    float score; // 相关度评分
};

// 引擎核心类：负责 JSON 解析、搜索、排序等纯 C++ 逻辑
class HymnEngine {
public:
    // 加载 JSON 数据（从文件路径）
    bool loadFromFile(const std::string& path);

    // 加载 JSON 数据（从内存字符串）
    bool loadFromJson(const std::string& json);

    // 获取全部诗歌
    const std::vector<Hymn>& hymns() const { return hymns_; }
    size_t count() const { return hymns_.size(); }

    // 按 id 查找
    const Hymn* findById(int id) const;

    // 搜索：按 编号 / 标题 / 作者 / 分类 关键字匹配
    // 返回按相关度排序的 id 列表
    std::vector<int> search(const std::string& keyword) const;

    // 全部清除
    void clear();

private:
    std::vector<Hymn> hymns_;

    // 解析单首诗歌 JSON
    static bool parseHymn(const std::string& json, Hymn& hymn);
};

} // namespace echohymn

#endif // HYMN_ENGINE_H
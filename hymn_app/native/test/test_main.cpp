// 简单的原生单元测试：验证 HymnEngine 核心逻辑
#include "hymn_engine.h"

#include <cassert>
#include <iostream>

using namespace echohymn;

const char* kSampleJson = R"json([
    {
        "id": 1,
        "number": 1,
        "title": "天父世界真美丽",
        "author": "Maltbie D. Babcock",
        "composer": "Franklin L. Sheppard",
        "category": "赞美",
        "audio": "https://example.com/a1.mp3",
        "lyrics": [
            ["这是天父世界，", "我们侧耳要听。"],
            ["这是天父世界，", "我心满有安宁。"]
        ]
    },
    {
        "id": 2,
        "number": 2,
        "title": "奇异恩典",
        "author": "John Newton",
        "composer": "英文传统曲调",
        "category": "恩典",
        "audio": "https://example.com/a2.mp3",
        "lyrics": [
            ["奇异恩典，何等甘甜，", "我罪已得赦免。"]
        ]
    }
])json";

int main() {
    HymnEngine engine;

    // 1) 加载 JSON
    assert(engine.loadFromJson(kSampleJson) && "load sample json");
    assert(engine.count() == 2 && "count == 2");

    // 2) 查找
    const Hymn* h1 = engine.findById(1);
    assert(h1 != nullptr);
    assert(h1->title == "天父世界真美丽");
    assert(h1->number == 1);
    assert(h1->lyrics.size() == 2);
    assert(h1->lyrics[0].size() == 2);
    assert(h1->lyrics[1][1] == "我心满有安宁。");

    const Hymn* h2 = engine.findById(2);
    assert(h2 != nullptr);
    assert(h2->category == "恩典");
    assert(h2->lyrics.size() == 1);

    // 不存在的 id
    assert(engine.findById(999) == nullptr);

    // 3) 搜索
    auto byTitle = engine.search("奇异");
    assert(byTitle.size() == 1 && byTitle[0] == 2);

    auto byNumber = engine.search("2");
    assert(byNumber.size() == 1 && byNumber[0] == 2);

    auto byAuthor = engine.search("john");
    assert(byAuthor.size() == 1 && byAuthor[0] == 2);

    auto byCategory = engine.search("赞美");
    assert(byCategory.size() == 1 && byCategory[0] == 1);

    // 无匹配
    auto none = engine.search("不存在");
    assert(none.empty());

    // 4) 空关键字返回全部
    auto all = engine.search("");
    assert(all.size() == 2);

    // 5) clear
    engine.clear();
    assert(engine.count() == 0);

    std::cout << "All native tests passed." << std::endl;
    return 0;
}
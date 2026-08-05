#include "hymn_engine.h"
#include <fstream>
#include <sstream>
#include <cctype>
#include <algorithm>
#include <cstring>

namespace echohymn {

// ==================== 轻量 JSON 解析器（UTF-8） ====================
namespace {

class JsonParser {
public:
    explicit JsonParser(const std::string& text) : text_(text) {}

    // 解析至 EOF，返回是否成功
    bool parse() {
        skipWhitespace();
        if (!parseValue(rootValue_)) return false;
        skipWhitespace();
        return pos_ >= text_.size();
    }

    // 简单键值访问工具
    // 根节点为对象，getString(key)、getInt(key)、getArray(key)
    struct JsonValue {
        enum Type { Null, Bool, Number, String, Array, Object } type = Null;
        bool boolValue = false;
        double numberValue = 0;
        std::string stringValue;
        std::vector<JsonValue> arrayValue;
        std::vector<std::pair<std::string, JsonValue>> objectValue;
    };

    const JsonValue& root() const { return rootValue_; }

    static const JsonValue* getField(const JsonValue& obj, const std::string& key) {
        if (obj.type != JsonValue::Object) return nullptr;
        for (const auto& kv : obj.objectValue) {
            if (kv.first == key) return &kv.second;
        }
        return nullptr;
    }

    static std::string asString(const JsonValue* v, const std::string& def = "") {
        if (!v || v->type != JsonValue::String) return def;
        return v->stringValue;
    }

    static int asInt(const JsonValue* v, int def = 0) {
        if (!v || v->type != JsonValue::Number) return def;
        return static_cast<int>(v->numberValue);
    }

private:
    const std::string& text_;
    size_t pos_ = 0;
    JsonValue rootValue_;

    void skipWhitespace() {
        while (pos_ < text_.size() && std::isspace(static_cast<unsigned char>(text_[pos_]))) {
            ++pos_;
        }
    }

    bool parseValue(JsonValue& out) {
        skipWhitespace();
        if (pos_ >= text_.size()) return false;
        char c = text_[pos_];
        if (c == '{') return parseObject(out);
        if (c == '[') return parseArray(out);
        if (c == '"') return parseString(out.stringValue), out.type = JsonValue::String, true;
        if (c == 't' || c == 'f') return parseBool(out);
        if (c == 'n') return parseNull(out);
        if (c == '-' || std::isdigit(static_cast<unsigned char>(c))) return parseNumber(out);
        return false;
    }

    bool parseObject(JsonValue& out) {
        out.type = JsonValue::Object;
        ++pos_; // consume '{'
        skipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == '}') { ++pos_; return true; }
        while (pos_ < text_.size()) {
            skipWhitespace();
            if (pos_ >= text_.size() || text_[pos_] != '"') return false;
            std::string key;
            parseString(key);
            skipWhitespace();
            if (pos_ >= text_.size() || text_[pos_] != ':') return false;
            ++pos_; // consume ':'
            JsonValue val;
            if (!parseValue(val)) return false;
            out.objectValue.emplace_back(std::move(key), std::move(val));
            skipWhitespace();
            if (pos_ >= text_.size()) return false;
            char c = text_[pos_];
            if (c == ',') { ++pos_; continue; }
            if (c == '}') { ++pos_; return true; }
            return false;
        }
        return false;
    }

    bool parseArray(JsonValue& out) {
        out.type = JsonValue::Array;
        ++pos_; // consume '['
        skipWhitespace();
        if (pos_ < text_.size() && text_[pos_] == ']') { ++pos_; return true; }
        while (pos_ < text_.size()) {
            JsonValue val;
            if (!parseValue(val)) return false;
            out.arrayValue.push_back(std::move(val));
            skipWhitespace();
            if (pos_ >= text_.size()) return false;
            char c = text_[pos_];
            if (c == ',') { ++pos_; continue; }
            if (c == ']') { ++pos_; return true; }
            return false;
        }
        return false;
    }

    void parseString(std::string& out) {
        // assumes text_[pos_] == '"'
        ++pos_;
        out.clear();
        while (pos_ < text_.size()) {
            char c = text_[pos_];
            if (c == '"') { ++pos_; return; }
            if (c == '\\') {
                ++pos_;
                if (pos_ >= text_.size()) break;
                char e = text_[pos_];
                switch (e) {
                    case '"': out += '"'; break;
                    case '\\': out += '\\'; break;
                    case '/': out += '/'; break;
                    case 'b': out += '\b'; break;
                    case 'f': out += '\f'; break;
                    case 'n': out += '\n'; break;
                    case 'r': out += '\r'; break;
                    case 't': out += '\t'; break;
                    case 'u': {
                        // 解析 \uXXXX（仅支持 BMP 直接字符；代理对简化为跳过）
                        if (pos_ + 4 >= text_.size()) break;
                        std::string hex = text_.substr(pos_ + 1, 4);
                        unsigned int code = 0;
                        for (char h : hex) {
                            code <<= 4;
                            if (h >= '0' && h <= '9') code |= (h - '0');
                            else if (h >= 'a' && h <= 'f') code |= (h - 'a' + 10);
                            else if (h >= 'A' && h <= 'F') code |= (h - 'A' + 10);
                            else { code = 0; break; }
                        }
                        // UTF-8 编码
                        if (code < 0x80) {
                            out += static_cast<char>(code);
                        } else if (code < 0x800) {
                            out += static_cast<char>(0xC0 | (code >> 6));
                            out += static_cast<char>(0x80 | (code & 0x3F));
                        } else {
                            out += static_cast<char>(0xE0 | (code >> 12));
                            out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
                            out += static_cast<char>(0x80 | (code & 0x3F));
                        }
                        pos_ += 4;
                        break;
                    }
                    default: out += e; break;
                }
                ++pos_;
            } else {
                out += c;
                ++pos_;
            }
        }
    }

    bool parseBool(JsonValue& out) {
        if (text_.compare(pos_, 4, "true") == 0) {
            out.type = JsonValue::Bool;
            out.boolValue = true;
            pos_ += 4;
            return true;
        }
        if (text_.compare(pos_, 5, "false") == 0) {
            out.type = JsonValue::Bool;
            out.boolValue = false;
            pos_ += 5;
            return true;
        }
        return false;
    }

    bool parseNull(JsonValue& out) {
        if (text_.compare(pos_, 4, "null") == 0) {
            out.type = JsonValue::Null;
            pos_ += 4;
            return true;
        }
        return false;
    }

    bool parseNumber(JsonValue& out) {
        size_t start = pos_;
        if (pos_ < text_.size() && text_[pos_] == '-') ++pos_;
        while (pos_ < text_.size() &&
               (std::isdigit(static_cast<unsigned char>(text_[pos_])) || text_[pos_] == '.' ||
                text_[pos_] == 'e' || text_[pos_] == 'E' || text_[pos_] == '+' || text_[pos_] == '-')) {
            ++pos_;
        }
        if (pos_ == start) return false;
        out.type = JsonValue::Number;
        out.numberValue = std::strtod(text_.substr(start, pos_ - start).c_str(), nullptr);
        return true;
    }
};

// 小写化（ASCII；中文不受影响）
std::string toLowerAscii(const std::string& s) {
    std::string r = s;
    for (char& c : r) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + 32);
    }
    return r;
}

} // namespace

// ==================== HymnEngine 实现 ====================

bool HymnEngine::loadFromFile(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    std::ostringstream ss;
    ss << in.rdbuf();
    return loadFromJson(ss.str());
}

bool HymnEngine::loadFromJson(const std::string& json) {
    JsonParser parser(json);
    if (!parser.parse()) return false;

    const JsonParser::JsonValue& root = parser.root();
    if (root.type != JsonParser::JsonValue::Array) return false;

    std::vector<Hymn> hymns;
    for (const auto& item : root.arrayValue) {
        if (item.type != JsonParser::JsonValue::Object) continue;

        Hymn h;
        h.id = JsonParser::asInt(JsonParser::getField(item, "id"));
        h.number = JsonParser::asInt(JsonParser::getField(item, "number"));
        h.title = JsonParser::asString(JsonParser::getField(item, "title"));
        h.author = JsonParser::asString(JsonParser::getField(item, "author"));
        h.composer = JsonParser::asString(JsonParser::getField(item, "composer"));
        h.category = JsonParser::asString(JsonParser::getField(item, "category"));
        h.audio = JsonParser::asString(JsonParser::getField(item, "audio"));

        const JsonParser::JsonValue* lyrics = JsonParser::getField(item, "lyrics");
        if (lyrics && lyrics->type == JsonParser::JsonValue::Array) {
            for (const auto& stanza : lyrics->arrayValue) {
                if (stanza.type != JsonParser::JsonValue::Array) continue;
                std::vector<std::string> lines;
                for (const auto& line : stanza.arrayValue) {
                    lines.push_back(JsonParser::asString(&line));
                }
                h.lyrics.push_back(std::move(lines));
            }
        }

        hymns.push_back(std::move(h));
    }

    hymns_ = std::move(hymns);
    return !hymns_.empty();
}

const Hymn* HymnEngine::findById(int id) const {
    for (const auto& h : hymns_) {
        if (h.id == id) return &h;
    }
    return nullptr;
}

std::vector<int> HymnEngine::search(const std::string& keyword) const {
    std::string kw = toLowerAscii(keyword);
    std::vector<SearchResult> results;

    for (const auto& h : hymns_) {
        float score = 0.0f;
        bool matched = false;

        // 标题匹配（权重最高）
        if (toLowerAscii(h.title).find(kw) != std::string::npos) {
            score += 3.0f;
            matched = true;
        }
        // 作者
        if (toLowerAscii(h.author).find(kw) != std::string::npos) {
            score += 2.0f;
            matched = true;
        }
        // 分类
        if (toLowerAscii(h.category).find(kw) != std::string::npos) {
            score += 2.0f;
            matched = true;
        }
        // 编号（数字串）
        if (kw.find_first_not_of("0123456789") == std::string::npos && !kw.empty()) {
            if (std::to_string(h.number).find(kw) != std::string::npos) {
                score += 1.5f;
                matched = true;
            }
        }

        if (matched) {
            results.push_back({h.id, score});
        }
    }

    // 按相关度降序
    std::sort(results.begin(), results.end(),
              [](const SearchResult& a, const SearchResult& b) {
                  return a.score > b.score;
              });

    std::vector<int> ids;
    ids.reserve(results.size());
    for (const auto& r : results) ids.push_back(r.id);
    return ids;
}

void HymnEngine::clear() {
    hymns_.clear();
}

} // namespace echohymn
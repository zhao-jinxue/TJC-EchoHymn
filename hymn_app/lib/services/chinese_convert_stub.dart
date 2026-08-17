// Web 端：OpenCC FFI 不可用，返回原文
String toSimplifiedImpl(String text) => text;

/// 简体 → 繁体（Web 端不可用，返回原文）
String toTraditionalImpl(String text) => text;

/// 初始化（Web 端无操作）
void initOpenccImpl(String dir) {}

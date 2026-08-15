# -*- coding: utf-8 -*-
"""注入 coroutine 警告抑制宏到 CMakeLists.txt"""
import io

p = r'E:\EchoHymn\hymn_app\windows\CMakeLists.txt'
c = io.open(p, encoding='utf-8').read()
line = '  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")'
add = ('\n'
       '  # just_audio_windows 插件使用已弃用的 <experimental/coroutine>，抑制其静态断言\n'
       '  target_compile_definitions(${TARGET} PRIVATE '
       '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)')
if line in c and '_SILENCE' not in c:
    c = c.replace(line, line + add, 1)
    io.open(p, 'w', encoding='utf-8', newline='').write(c)
    print('[OK] injected coroutine macro')
else:
    print('[SKIP] line not found or already injected')
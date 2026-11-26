import re
import sys

# 顺序很重要：先去字符串（否则 "weixin://..." 里的 // 会被当成注释，把后半行吃掉）
FILES = sys.argv[1:] or ['Tweak.xm', 'WCTGPopupCenter.m', 'WCTGPopupView.m', 'WCTGPConfig.m']


def strip(code: str) -> str:
    code = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', code)
    code = re.sub(r"'[^'\n]'", "''", code)
    code = re.sub(r'//[^\n]*', '', code)
    code = re.sub(r'/\*.*?\*/', '', code, flags=re.S)
    return code


print(f'{"文件":22s} {"{}":>9s} {"()":>9s} {"[]":>9s}  结论')
bad = 0
for p in FILES:
    s = strip(open(p, encoding='utf-8').read())
    b = (s.count('{'), s.count('}'))
    r = (s.count('('), s.count(')'))
    k = (s.count('['), s.count(']'))
    ok = b[0] == b[1] and r[0] == r[1] and k[0] == k[1]
    bad += 0 if ok else 1
    print(f'{p:22s} {b[0]}/{b[1]:<7d} {r[0]}/{r[1]:<7d} {k[0]}/{k[1]:<7d}  {"OK" if ok else "MISMATCH"}')
print('\n结论:', '全部平衡' if bad == 0 else f'{bad} 个文件不平衡')

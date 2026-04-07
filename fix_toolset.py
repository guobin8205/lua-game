import os
import re

def fix_vcproj(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 添加 VS2017/2019/2022 工具集条件
    pattern = r'<PlatformToolset Condition="\'\$\(VisualStudioVersion\)\' == \'14\.0\'">v140</PlatformToolset>'
    replacement = '''<PlatformToolset Condition="'$(VisualStudioVersion)' == '14.0'">v140</PlatformToolset>
    <PlatformToolset Condition="'$(VisualStudioVersion)' == '15.0'">v141</PlatformToolset>
    <PlatformToolset Condition="'$(VisualStudioVersion)' == '16.0'">v142</PlatformToolset>
    <PlatformToolset Condition="'$(VisualStudioVersion)' == '17.0'">v143</PlatformToolset>'''

    new_content = re.sub(pattern, replacement, content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Fixed: {filepath}")

# 查找所有 vcxproj 文件
frameworks_path = r'E:\repos\cocos\LuaGame\frameworks'
for root, dirs, files in os.walk(frameworks_path):
    for file in files:
        if file.endswith('.vcxproj'):
            filepath = os.path.join(root, file)
            fix_vcproj(filepath)

print("Done!")

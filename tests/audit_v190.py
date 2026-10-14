"""Read-only audit of the supplied historical package with real Lua 5.0."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--lua', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
addon = root / 'ADKPV1.90/ADKP'
entries = [s.strip() for s in (addon / 'ADKP.toc').read_text(encoding='utf-8-sig').splitlines()
           if s.strip() and not s.startswith('##')]
assert entries.index('ADKP_BossAutoLog.lua') < entries.index('ADKP.lua') < entries.index('ADKP_Frame.xml')
assert len(entries) == len(set(entries))
for name in entries:
    assert (addon / name).is_file(), name
    if name.endswith('.xml'):
        ET.parse(addon / name)
main = (addon / 'ADKP.lua').read_text(encoding='utf-8')
start = main.index('function ADKP_QuickFloat_UpdateAutoLogRow()')
end = main.index('function ADKP_BossAutoLog_TogglePanel()', start)
row_code = main[start:end]
assert main.splitlines()[7416].strip() == 'local log = ADKP_GetBossAutoAwardRecords()'
with tempfile.TemporaryDirectory(prefix='adkp-v190-audit-') as directory:
    check = Path(directory) / 'syntax.lua'
    check.write_text('assert(string.find(_VERSION,"^Lua 5%.0")); for i=1,table.getn(arg) do local f,e=loadfile(arg[i]); assert(f,e) end; print("Historical package Lua 5.0 syntax PASS")', encoding='utf-8')
    subprocess.run([args.lua, str(check)] + [str(addon / s) for s in entries if s.endswith('.lua')], cwd=root, check=True)
    function_file = Path(directory) / 'row.lua'
    function_file.write_text('\n' * main[:start].count('\n') + row_code, encoding='utf-8')
    script = Path(directory) / 'load.lua'
    # Filenames are supplied via argv; the package is never changed.
    script.write_text(r'''
local function environment(loadModule)
    local e=setmetatable({}, {__index=_G})
    e._G=e; e.WebDKP_Options={}; e.WebDKP_Log={}
    e.ADKP_TruncateUtf8Glyphs=function(s) return s end
    e.ADKP_QuickFloatFrame={logRow={text={
        SetText=function(self,s) e.display=s end,
        SetTextColor=function() end}}}
    if loadModule then
        local f=assert(loadfile(arg[1])); setfenv(f,e); f()
        assert(type(e.ADKP_GetBossAutoAwardRecords)=="function")
        assert(type(e.ADKP_RefreshBossAutoAwardLog)=="function")
        assert(e.ADKP_BOSS_AUTO_LOG_MAX==30)
    end
    local f=assert(loadfile(arg[2])); setfenv(f,e); f()
    return e
end
local loaded=environment(true)
loaded.ADKP_QuickFloat_UpdateAutoLogRow()
assert(loaded.display=="自动加分: 暂无")
loaded.WebDKP_Log.kill={tableid=1, date="2026-10-14 20:00:00", points=2, awarded={Player={class="战士"}},
    bossAutoAward={id="kill:auto",boss="测试Boss",role="raid"}}
loaded.ADKP_QuickFloat_UpdateAutoLogRow()
assert(loaded.display=="测试Boss 主2/替0")
print("Manifest dependency + actual row refresh PASS (empty and real Boss logs)")
local missing=environment(false)
local ok,err=pcall(missing.ADKP_QuickFloat_UpdateAutoLogRow)
assert(not ok and string.find(err,"7417:",1,true) and string.find(err,"ADKP_GetBossAutoAwardRecords",1,true))
print("Missing-module reproduction: "..err)
''', encoding='utf-8')
    subprocess.run([args.lua, str(script), str(addon / 'ADKP_BossAutoLog.lua'), str(function_file)], cwd=root, check=True)
print('Historical TOC paths/order and XML parsing PASS; historical addon files unchanged')

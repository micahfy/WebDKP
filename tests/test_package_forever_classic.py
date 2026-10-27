"""Regression tests for comment stripping and non-destructive release packaging."""
from datetime import datetime, timezone
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from package_forever_classic import package
from strip_addon_comments import lua_comments, strip_lua, strip_toc, strip_xml, xml_ranges


class CommentTests(unittest.TestCase):
    def test_lua_strings_escapes_long_delimiters_and_token_boundaries(self):
        literals = [b'"-- literal"', b"'it\\'s -- literal'", b'"escaped \\\\"',
                    b'[[-- literal\n<!-- literal -->]]', b'[==[x ]=] -- literal]==]']
        source = b'\xef\xbb\xbf' + b'\r\n'.join(b'local s=' + item + b' -- REMOVE' for item in literals)
        source += b'\r\nlocal x=1--[=[REMOVE\r\n]=]..2\r\nreturn x -- REMOVE EOF'
        result = strip_lua(source)
        self.assertTrue(result.startswith(b'\xef\xbb\xbf'))
        self.assertEqual(result.count(b'\r\n'), source.count(b'\r\n'))
        self.assertEqual(len(result), len(source))
        for literal in literals:
            self.assertIn(literal, result)
        self.assertNotIn(b'REMOVE', result)
        self.assertFalse(list(lua_comments(result)))
        self.assertIn(b'1', result)
        self.assertIn(b'..2', result)

    def test_lua_chinese_bytes_are_preserved_outside_comments(self):
        source = 'local name="张三 四" -- 注释\nreturn name'.encode('utf-8')
        result = strip_lua(source)
        self.assertIn('"张三 四"'.encode('utf-8'), result)
        self.assertNotIn('注释'.encode('utf-8'), result)
        self.assertEqual(strip_lua(result), result)

    def test_invalid_lua_fails_instead_of_shipping_truncated_code(self):
        for source in (b'local x="unfinished', b'--[=[unfinished', b'local x=[==[unfinished'):
            with self.assertRaises(ValueError):
                strip_lua(source)

    def test_xml_comments_inline_lua_and_cdata_literals(self):
        source = b'''<?xml version="1.0" encoding="UTF-8"?>
<Ui><!-- REMOVE XML --><Frame text="keep -- label">
<Scripts><OnLoad><![CDATA[
local text="<!-- literal --> -- string"
local long=[=[-- long string]=]
-- REMOVE LUA
local number=1--[[REMOVE BLOCK]]+2
]]></OnLoad><OnShow>local s=&quot;-- literal&quot; -- REMOVE ENTITY&#10;return s</OnShow>
<OnHide>local s="x<!-- REMOVE JOIN -->y"</OnHide><OnEnter/>
</Scripts></Frame><Script>local t=1 -- REMOVE SCRIPT
return t</Script><Script file="keep--file.lua"/></Ui>'''
        result = strip_xml(source)
        self.assertNotIn(b'REMOVE', result)
        self.assertIn(b'<![CDATA[', result)
        self.assertIn(b'"<!-- literal --> -- string"', result)
        self.assertIn(b'&quot;-- literal&quot;', result)
        self.assertIn(b'text="keep -- label"', result)
        self.assertIn(b'file="keep--file.lua"', result)
        original, cleaned = ET.fromstring(source), ET.fromstring(result)
        self.assertEqual(original.find('.//OnHide').text, cleaned.find('.//OnHide').text)
        self.assertFalse(xml_ranges(result)[0])
        self.assertEqual(strip_xml(result), result)

    def test_xml_entity_delimiters_and_split_cdata_comments(self):
        source = b'<Ui><Scripts><OnLoad>local x=1 &#45;&#45; REMOVE&#13;return x</OnLoad><OnShow><![CDATA[-]]><![CDATA[- REMOVE\nreturn 2]]></OnShow></Scripts></Ui>'
        result = strip_xml(source)
        self.assertNotIn(b'REMOVE', result)
        self.assertIn(b'&#13;', result)
        self.assertIn(b'return x', result)
        self.assertIn(b'return 2', result)
        self.assertEqual(result.count(b'<![CDATA['), 2)
        ET.fromstring(result)

    def test_toc_metadata_and_order_are_preserved(self):
        source = b'## Interface: 16001\r\n# REMOVE\r\n## Version: v1.0F\r\n  # REMOVE\r\nA.lua\r\nB.xml\r\n'
        result = strip_toc(source)
        self.assertNotIn(b'REMOVE', result)
        self.assertIn(b'## Interface: 16001', result)
        self.assertIn(b'## Version: v1.0F', result)
        self.assertTrue(result.endswith(b'A.lua\r\nB.xml\r\n'))


class PackageTests(unittest.TestCase):
    def test_zip_has_version_beijing_time_and_clean_code_without_source_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            addon = root / 'source' / 'ADKP'
            addon.mkdir(parents=True)
            (addon / 'ADKP.toc').write_bytes(b'## Version: v1.0F\nA.lua\nUI.xml\n')
            (addon / 'A.lua').write_bytes(b'local s="-- keep" -- REMOVE\nreturn s')
            (addon / 'UI.xml').write_bytes(b'<Ui><!-- REMOVE --><Scripts><OnLoad>local a=1 -- REMOVE\n</OnLoad></Scripts></Ui>')
            (addon / 'texture.blp').write_bytes(bytes(range(256)))
            before = {p.relative_to(addon): p.read_bytes() for p in addon.rglob('*') if p.is_file()}
            # UTC date differs from the Beijing filename date.
            now = datetime(2026, 10, 25, 18, 3, 4, tzinfo=timezone.utc)
            archive, count, changed = package(addon, root / 'out', now)
            self.assertEqual(archive.name, 'ADKP_Forever_Classic-v1.0F-20261026-020304.zip')
            self.assertEqual((count, changed), (4, 2))
            with zipfile.ZipFile(archive) as output:
                self.assertEqual(set(output.namelist()), {'ADKP/' + p.as_posix() for p in before})
                self.assertIn(b'"-- keep"', output.read('ADKP/A.lua'))
                self.assertNotIn(b'REMOVE', output.read('ADKP/A.lua'))
                self.assertNotIn(b'REMOVE', output.read('ADKP/UI.xml'))
                self.assertEqual(output.read('ADKP/texture.blp'), bytes(range(256)))
            self.assertEqual(before, {p: (addon / p).read_bytes() for p in before})
            duplicate, _, _ = package(addon, root / 'out', now)
            self.assertNotEqual(duplicate, archive)
            self.assertTrue(archive.is_file())
            with self.assertRaises(ValueError):
                package(addon, addon / 'out', now)


if __name__ == '__main__':
    unittest.main()

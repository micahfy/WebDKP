"""Remove Lua/XML/TOC comments without rewriting strings or source encodings."""
import re
from xml.parsers import expat

LONG_OPEN = re.compile(rb'\[(=*)\[')


def blank_comment(data):
    """Keep spacing and physical line endings so adjacent Lua tokens stay apart."""
    return re.sub(rb'[^\r\n]', b' ', data)


def long_bracket(data, start):
    match = LONG_OPEN.match(data, start)
    if not match:
        return None
    close = b']' + match[1] + b']'
    end = data.find(close, match.end())
    if end < 0:
        raise ValueError('Unterminated Lua long string/comment')
    return end + len(close)


def lua_comments(data):
    """Yield real comment byte ranges, skipping quoted and long strings."""
    at = 0
    while at < len(data):
        char = data[at:at + 1]
        if char in (b'"', b"'"):
            quote, at = char, at + 1
            while at < len(data) and data[at:at + 1] != quote:
                at += 2 if data[at:at + 1] == b'\\' else 1
            if at >= len(data):
                raise ValueError('Unterminated Lua quoted string')
            at += 1
        elif data.startswith(b'--', at):
            end = long_bracket(data, at + 2)
            if end is None:
                end = at + 2
                while end < len(data) and data[end] not in (10, 13):
                    end += 1
            yield at, end
            at = end
        elif char == b'[' and (end := long_bracket(data, at)) is not None:
            at = end
        else:
            at += 1


def strip_lua(data):
    output = bytearray(data)
    for start, end in lua_comments(data):
        output[start:end] = blank_comment(data[start:end])
    return bytes(output)


def tag_end(data, start):
    quote = None
    for at in range(start, len(data)):
        char = data[at]
        if quote is not None:
            if char == quote:
                quote = None
        elif char in (34, 39):
            quote = char
        elif char == 62:
            return at + 1
    raise ValueError('Unterminated XML tag')


def xml_ranges(data):
    """Expat identifies markup comments and WoW inline Lua script bodies."""
    parser = expat.ParserCreate()
    stack, comments, scripts = [], [], []

    def start(name, attributes):
        name = name.split(':')[-1]
        at = parser.CurrentByteIndex
        end = tag_end(data, at)
        inline = (bool(stack) and stack[-1][0] == 'Scripts') or (name == 'Script' and 'file' not in attributes)
        empty = data[at:end].rstrip().endswith(b'/>')
        stack.append((name, end, inline and not empty))

    def finish(name):
        _, start, inline = stack.pop()
        if inline:
            scripts.append((start, parser.CurrentByteIndex))

    def comment(text):
        start = parser.CurrentByteIndex
        end = data.find(b'-->', start + 4)
        if end < 0:
            raise ValueError('Unterminated XML comment')
        comments.append((start, end + 3))

    parser.StartElementHandler = start
    parser.EndElementHandler = finish
    parser.CommentHandler = comment
    parser.Parse(data, True)
    return comments, scripts


def script_bytes(body):
    """Decode XML text for Lua lexing, mapping each byte to original XML.

    Keep CDATA delimiters and entity spellings intact, including quoted '--'
    strings and comments whose delimiters were written as numeric entities.
    """
    decoded, positions = bytearray(), []
    at, cdata = 0, False
    entities = {b'amp': b'&', b'lt': b'<', b'gt': b'>', b'quot': b'"', b'apos': b"'"}
    while at < len(body):
        if not cdata and body.startswith(b'<![CDATA[', at):
            cdata, at = True, at + 9
            continue
        if cdata and body.startswith(b']]>', at):
            cdata, at = False, at + 3
            continue
        start = at
        if not cdata and body[at:at + 1] == b'&':
            end = body.find(b';', at + 1)
            if end < 0:
                raise ValueError('Unterminated XML entity')
            entity = body[at + 1:end]
            if entity.startswith(b'#x'):
                value = chr(int(entity[2:], 16)).encode('utf-8')
            elif entity.startswith(b'#'):
                value = chr(int(entity[1:])).encode('utf-8')
            elif entity in entities:
                value = entities[entity]
            else:
                raise ValueError('Custom XML entities in Lua scripts are not supported')
            at = end + 1
        elif not cdata and body[at:at + 1] == b'<':
            raise ValueError('Unexpected nested markup in an inline Lua script')
        elif body[at:at + 1] == b'\r':
            at += 2 if body[at:at + 2] == b'\r\n' else 1
            value = b'\n'  # XML normalizes literal CR/CRLF before executing Lua.
        else:
            value, at = body[at:at + 1], at + 1
        decoded.extend(value)
        positions.extend([(start, at)] * len(value))
    if cdata:
        raise ValueError('Unterminated CDATA section')
    return bytes(decoded), positions


def strip_xml(data):
    comments, _ = xml_ranges(data)
    # XML comments contribute no text, even between two halves of a string.
    for start, end in reversed(comments):
        data = data[:start] + data[end:]
    _, scripts = xml_ranges(data)
    output = bytearray(data)
    for start, end in scripts:
        decoded, positions = script_bytes(data[start:end])
        for left, right in lua_comments(decoded):
            for at in range(left, right):
                if decoded[at] in (10, 13):
                    continue
                raw_start, raw_end = positions[at]
                output[start + raw_start:start + raw_end] = b' ' * (raw_end - raw_start)
    result = bytes(output)
    xml_ranges(result)  # Refuse to ship XML that no longer parses.
    return result


def strip_toc(data):
    output = []
    for line in data.splitlines(keepends=True):
        text = line.lstrip(b' \t')
        if text.startswith(b'#') and not text.startswith(b'##'):
            line = blank_comment(line)
        output.append(line)
    return b''.join(output)


def strip_comments(path, data):
    handler = {'.lua': strip_lua, '.xml': strip_xml, '.toc': strip_toc}.get(path.suffix.lower())
    return handler(data) if handler else data

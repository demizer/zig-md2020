const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const ArrayList = std.ArrayList;
const token = @import("token.zig");
const atxRules = @import("token_atx_heading.zig");
const inlineRules = @import("token_inline.zig");

usingnamespace @import("log.zig");

pub const Lexer = struct {
    buffer: []const u8,
    bufIndex: u32,
    rules: ArrayList(token.TokenRule),
    tokens: ArrayList(token.Token),
    tokenIndex: u64,
    lineNumber: u32,

    pub fn init(allocator: *mem.Allocator, buffer: []const u8) !Lexer {
        // Skip the UTF-8 BOM if present
        var t = Lexer{
            .buffer = buffer,
            .bufIndex = 0,
            .rules = ArrayList(token.TokenRule).init(allocator),
            .tokens = ArrayList(token.Token).init(allocator),
            .tokenIndex = 0,
            .lineNumber = 1,
        };
        try t.registerRule(ruleWhitespace);
        try t.registerRule(atxRules.ruleAtxHeader);
        try t.registerRule(inlineRules.ruleInline);
        try t.registerRule(ruleEOF);
        return t;
    }

    pub fn deinit(l: *Lexer) void {
        l.rules.deinit();
        l.tokens.deinit();
    }

    pub fn registerRule(l: *Lexer, rule: token.TokenRule) !void {
        try l.rules.append(rule);
    }

    /// Get the next token from the input.
    pub fn next(l: *Lexer) !?token.Token {
        for (l.rules.items) |rule| {
            if (try rule(l)) |v| {
                return v;
            }
        }
        return null;
    }

    /// Peek at the next token.
    pub fn peekNext(l: *Lexer) !?token.Token {
        var indexBefore = l.bufIndex;
        var tokenIndexBefore = l.tokenIndex;
        var pNext = try l.next();
        l.bufIndex = indexBefore;
        l.tokenIndex = tokenIndexBefore;
        return pNext;
    }

    /// Gets a character at bufIndex from the source buffer. Returns null if bufIndex exceeds the length of the buffer.
    pub fn getChar(l: *Lexer, bufIndex: u32) ?u8 {
        if (bufIndex >= l.buffer.len) {
            return null;
        }
        return l.buffer[bufIndex];
    }

    pub fn emit(l: *Lexer, tok: token.TokenId, startOffset: u32, endOffset: u32) !?token.Token {
        // log.Debugf("start: {} end: {}\n", .{ start, end });
        var str = l.buffer[startOffset..endOffset];
        var nEndOffset: u32 = endOffset - 1;
        if ((endOffset - startOffset) == 1 or nEndOffset < startOffset) {
            nEndOffset = startOffset;
        }
        var column: u32 = l.offsetToColumn(startOffset);
        if (tok == token.TokenId.EOF) {
            column = l.tokens.items[l.tokens.items.len - 1].column;
            l.lineNumber -= 1;
        }
        var newTok = token.Token{
            .ID = tok,
            .startOffset = startOffset,
            .endOffset = nEndOffset,
            .string = str,
            .lineNumber = l.lineNumber,
            .column = column,
        };
        log.Debugf("emit: {}\n", .{newTok});
        try l.tokens.append(newTok);
        l.bufIndex = endOffset;
        l.tokenIndex = l.tokens.items.len - 1;
        if (mem.eql(u8, str, "\n")) {
            l.lineNumber += 1;
        }
        return newTok;
    }

    /// Returns the column number of offset translated from the start of the line
    pub fn offsetToColumn(l: *Lexer, offset: u32) u32 {
        var i: u32 = offset;
        var start: u32 = 1;
        var char: u8 = 0;
        var foundLastNewline: bool = false;
        if (offset > 0) {
            i = offset - 1;
        }
        // Get the last newline starting from offset
        while (char != '\n') : (i -= 1) {
            if (i == 0) {
                break;
            }
            char = l.buffer[i];
            start = i;
        }
        if (char == '\n') {
            foundLastNewline = true;
            start = i + 1;
        }
        char = 0;
        i = offset;
        // Get the next newline starting from offset
        while (char != '\n') : (i += 1) {
            if (i == l.buffer.len) {
                break;
            }
            char = l.buffer[i];
        }
        // only one line of input or on the first line of input
        if (!foundLastNewline) {
            return offset + 1;
        }
        return offset - start;
    }

    /// Checks for a single whitespace character. Returns true if char is a space character.
    pub fn isSpace(l: *Lexer, char: u8) bool {
        if (char == '\u{0020}') {
            return true;
        }
        return false;
    }

    /// Checks for all the whitespace characters. Returns true if the char is a whitespace.
    pub fn isWhitespace(l: *Lexer, char: u8) bool {
        // A whitespace character is a space (U+0020), tab (U+0009), newline (U+000A), line tabulation (U+000B), form feed
        // (U+000C), or carriage return (U+000D).
        return switch (char) {
            '\u{0020}', '\u{0009}', '\u{000A}', '\u{000B}', '\u{000C}', '\u{000D}' => true,
            else => false,
        };
    }

    pub fn isPunctuation(l: *Lexer, char: u8) bool {
        // Check for ASCII punctuation characters...
        //
        // FIXME: Check against the unicode punctuation tables... there isn't a Zig library that does this that I have found.
        //
        // A punctuation character is an ASCII punctuation character or anything in the general Unicode categories Pc, Pd,
        // Pe, Pf, Pi, Po, or Ps.
        return switch (char) {
            '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~' => true,
            else => false,
        };
    }

    pub fn isCharacter(l: *Lexer, char: u8) bool {
        // TODO: make this more robust by using unicode character sets
        if (!l.isPunctuation(char) and !l.isWhitespace(char)) {
            return true;
        }
        return false;
    }

    /// Get the last token emitted, exclude peek tokens
    pub fn lastToken(l: *Lexer) token.Token {
        return l.tokens.items[l.tokenIndex];
    }

    /// Skip the next token
    pub fn skipNext(l: *Lexer) !void {
        _ = try l.next();
    }
};

/// Get all the whitespace characters greedly.
pub fn ruleWhitespace(t: *Lexer) !?token.Token {
    var index: u32 = t.bufIndex;
    while (t.getChar(index)) |val| {
        if (t.isWhitespace(val)) {
            index += 1;
        } else {
            break;
        }
    }
    if (index > t.bufIndex) {
        return t.emit(.Whitespace, t.bufIndex, index);
    }
    // log.Debugf("t.bufIndex: {} index: {}\n", .{ t.bufIndex, index });
    return null;
}

/// Return EOF at the end of the input
pub fn ruleEOF(t: *Lexer) !?token.Token {
    if (t.bufIndex == t.buffer.len) {
        return t.emit(.EOF, t.bufIndex, t.bufIndex);
    }
    return null;
}

test "lexer: peekNext " {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    // TODO: move this somplace else
    use_rfc3339_date_handler();

    const input = "# foo";
    log.Debugf("input:\n{}\n-- END OF TEST --\n", .{input});

    var t = try Lexer.init(allocator, input);

    if (try t.next()) |tok| {
        assert(tok.ID == token.TokenId.AtxHeader);
    }

    // two consecutive peeks should return the same token
    if (try t.peekNext()) |tok| {
        assert(tok.ID == token.TokenId.Whitespace);
    }
    if (try t.peekNext()) |tok| {
        assert(tok.ID == token.TokenId.Whitespace);
    }
    // The last token does not include peek'd tokens
    assert(t.lastToken().ID == token.TokenId.AtxHeader);

    if (try t.next()) |tok| {
        assert(tok.ID == token.TokenId.Whitespace);
    }
}
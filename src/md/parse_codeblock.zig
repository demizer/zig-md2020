const std = @import("std");
const mem = std.mem;
const log = @import("log.zig");
const State = @import("ast.zig").State;
const Parser = @import("parse.zig").Parser;
const Node = @import("parse.zig").Node;
const Lexer = @import("lexer.zig").Lexer;
const TokenId = @import("token.zig").TokenId;

pub fn stateCodeBlock(p: *Parser) !void {
    if (try p.lex.peekNext()) |tok| {
        var openTok = p.lex.lastToken();
        // log.Debugf("parse block code before openTok: '{}' id: {} len: {}, tok: '{}' id: {} len: {}\n", .{
        //     openTok.string, openTok.ID, openTok.string.len,
        //     tok.string,     tok.ID,     tok.string.len,
        // });
        var hazCodeBlockWhitespace: bool = false;
        if (openTok.ID == TokenId.Whitespace and openTok.string.len > 1) {
            // Check the whitespace for tabs
            for (openTok.string) |val| {
                if (val == '\t' or openTok.string.len >= 4) {
                    hazCodeBlockWhitespace = true;
                    break;
                }
            }
        }
        if (hazCodeBlockWhitespace and tok.ID == TokenId.Text) {
            // log.Debugf("parse block code inside openTok: '{}', tok: '{}'\n", .{ openTok.string, tok.string });
            p.state = Parser.State.CodeBlock;
            var newChild = Node{
                .ID = Node.ID.CodeBlock,
                .Value = openTok.string,
                .PositionStart = Node.Position{
                    .Line = openTok.lineNumber,
                    .Column = openTok.column,
                    .Offset = openTok.startOffset,
                },
                .PositionEnd = undefined,
                .Children = std.ArrayList(Node).init(p.allocator),
                .Level = 0,
            };

            var buf = try std.ArrayListSentineled(u8, 0).init(p.allocator, tok.string);
            defer buf.deinit();

            // skip the whitespace after the codeblock opening
            try p.lex.skipNext();
            var startPos = Node.Position{
                .Line = tok.lineNumber,
                .Column = tok.column,
                .Offset = tok.startOffset,
            };

            while (try p.lex.next()) |ntok| {
                if (ntok.ID == TokenId.Whitespace and mem.eql(u8, ntok.string, "\n")) {
                    // FIXME: loop until de-indent
                    log.Debug("Found a newline, exiting state");
                    try buf.appendSlice(ntok.string);
                    try newChild.Children.append(Node{
                        .ID = Node.ID.Text,
                        .Value = buf.toOwnedSlice(),
                        .PositionStart = startPos,
                        .PositionEnd = Node.Position{
                            .Line = ntok.lineNumber,
                            .Column = ntok.column,
                            .Offset = ntok.endOffset,
                        },
                        .Children = std.ArrayList(Node).init(p.allocator),
                        .Level = 0,
                    });
                    break;
                }
                try buf.appendSlice(ntok.string);
            }

            newChild.PositionEnd = newChild.Children.items[newChild.Children.items.len - 1].PositionEnd;
            try p.root.append(newChild);
            p.state = Parser.State.Start;
        }
    }
}
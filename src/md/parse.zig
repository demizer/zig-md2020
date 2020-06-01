const std = @import("std");
const mem = std.mem;
const test_util = @import("test_util.zig");
const Lexer = @import("lexer.zig").Lexer;
const TokenId = @import("token.zig").TokenId;
const json = std.json;

usingnamespace @import("parse_atx_heading.zig");
usingnamespace @import("log.zig");

/// Function prototype for a State Transition in the Parser
pub const StateTransition = fn (lexer: *Lexer) anyerror!?AstNode;

pub const Node = struct {
    ID: ID,
    Value: ?[]const u8,

    PositionStart: Position,
    PositionEnd: Position,

    Children: std.ArrayList(Node),

    Level: u32,

    pub const Position = struct {
        Line: u32,
        Column: u32,
        Offset: u32,
    };

    pub const ID = enum {
        AtxHeading,
        Text,
        pub fn jsonStringify(
            value: ID,
            options: json.StringifyOptions,
            out_stream: var,
        ) !void {
            try json.stringify(@tagName(value), options, out_stream);
        }
    };

    pub fn deinit(self: *Parser) void {
        self.Children.deinit();
    }

    pub fn jsonStringify(
        value: @This(),
        options: json.StringifyOptions,
        out_stream: var,
    ) !void {
        try out_stream.writeByte('{');
        const T = @TypeOf(value);
        const S = @typeInfo(T).Struct;
        comptime var field_output = false;
        var child_options = options;
        if (child_options.whitespace) |*child_whitespace| {
            child_whitespace.indent_level += 1;
        }
        inline for (S.fields) |Field, field_i| {
            if (Field.field_type == void) continue;

            if (!field_output) {
                field_output = true;
            } else {
                try out_stream.writeByte(',');
            }
            if (child_options.whitespace) |child_whitespace| {
                try out_stream.writeByte('\n');
                try child_whitespace.outputIndent(out_stream);
            }
            try json.stringify(Field.name, options, out_stream);
            try out_stream.writeByte(':');
            if (child_options.whitespace) |child_whitespace| {
                if (child_whitespace.separator) {
                    try out_stream.writeByte(' ');
                }
            }
            if (comptime !mem.eql(u8, Field.name, "Children")) {
                try json.stringify(@field(value, Field.name), child_options, out_stream);
            } else {
                var boop = @field(value, Field.name);
                if (boop.items.len == 0) {
                    _ = try out_stream.writeAll("[]");
                } else {
                    _ = try out_stream.write("[");
                    for (boop.items) |item| {
                        try json.stringify(item, child_options, out_stream);
                    }
                    _ = try out_stream.write("]");
                }
            }
        }
        if (field_output) {
            if (options.whitespace) |whitespace| {
                try out_stream.writeByte('\n');
                try whitespace.outputIndent(out_stream);
            }
        }
        try out_stream.writeByte('}');
        return;
    }
};

/// A non-stream Markdown parser which constructs a tree of Nodes
pub const Parser = struct {
    allocator: *mem.Allocator,

    root: std.ArrayList(Node),
    state: State,
    lex: Lexer,

    pub const State = enum {
        Start,
        AtxHeader,
    };

    pub fn init(
        allocator: *mem.Allocator,
    ) Parser {
        return Parser{
            .allocator = allocator,
            .state = .Start,
            .root = std.ArrayList(Node).init(allocator),
            .lex = undefined,
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.root.items) |item| {
            item.Children.deinit();
        }
        self.root.deinit();
        self.lex.deinit();
    }

    pub fn parse(self: *Parser, input: []const u8) !void {
        self.lex = try Lexer.init(self.allocator, input);
        use_rfc3339_date_handler();
        log.Debugf("input:\n{}\n-- END OF TEST --\n", .{input});
        while (true) {
            if (try self.lex.next()) |tok| {
                switch (tok.ID) {
                    .Invalid => {},
                    .Text => {},
                    .Whitespace => {
                        if (mem.eql(u8, tok.string, "\n")) {}
                    },
                    .AtxHeader => {
                        try StateAtxHeader(self);
                    },
                    .EOF => {
                        log.Debug("Found EOF");
                        break;
                    },
                }
            }
        }
    }
};

/// testNode tests parser output against a json test file containing the expected output
/// - expected: The expected json output. Use @embedFile()!
/// - value: The parser root to test.
/// - dumpJson: If true, only the json value of "value" will be dumped to stdout.
fn testNode(expected: []const u8, value: var, dumpJson: bool) !void {
    const ValidationOutStream = struct {
        const Self = @This();
        pub const OutStream = std.io.OutStream(*Self, Error, write);
        pub const Error = error{
            TooMuchData,
            DifferentData,
        };

        expected_remaining: []const u8,
        dump: bool,

        fn init(exp: []const u8, dumpJsonInner: bool) Self {
            return .{ .expected_remaining = exp, .dump = dumpJsonInner };
        }

        pub fn outStream(self: *Self) OutStream {
            return .{ .context = self };
        }

        fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.dump) {
                std.debug.warn("{}", .{bytes});
                return bytes.len;
            }
            if (self.expected_remaining.len < bytes.len) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    self.expected_remaining,
                    bytes,
                });
                return error.TooMuchData;
            }
            if (!mem.eql(u8, self.expected_remaining[0..bytes.len], bytes)) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    self.expected_remaining[0..bytes.len],
                    bytes,
                });
                return error.DifferentData;
            }
            self.expected_remaining = self.expected_remaining[bytes.len..];
            return bytes.len;
        }
    };
    if (dumpJson) {
        log.Debug("dumped_json: ");
    }
    var vos = ValidationOutStream.init(expected, dumpJson);
    try json.stringify(value, json.StringifyOptions{
        .whitespace = .{
            .indent = .{ .Space = 4 },
            .separator = true,
        },
    }, vos.outStream());
    _ = try vos.outStream().write("\n");
    if (vos.expected_remaining.len > 0) return error.NotEnoughData;
}

test "Parser Test 32" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;
    const input = try test_util.getTest(allocator, 32);

    // TODO: move this somplace else
    use_rfc3339_date_handler();

    log.Debugf("test:\n{}\n-- END OF TEST --\n", .{input});

    var p = Parser.init(std.testing.allocator);
    defer p.deinit();

    // Used https://codebeautify.org/xmltojson to convert ast from spec to json
    const expect = @embedFile("../../test/expect/test32.json");

    var out = p.parse(input);

    // FIXME: Would be much easier to debug if we used real json diff...
    //        Run jsondiff in a container: https://github.com/zgrossbart/jdd or... use a zig json diff library.
    try testNode(expect, p.root.items, false);
}
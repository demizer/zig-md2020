const std = @import("std");

usingnamespace @import("log.zig");

const token = @import("token.zig");
const Tokenizer = @import("token.zig").Tokenizer;

pub fn ruleAtxHeader(t: *Tokenizer) !?token.Token {
    var index: u32 = t.index;
    while (t.getChar(index)) |val| {
        if (val == '#') {
            index += 1;
        } else {
            break;
        }
    }
    if (index > t.index) {
        return t.emit(.AtxHeaderOpen, t.index, index);
    }
    return null;
}

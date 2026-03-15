const std = @import("std");
const app = @import("vocab_assistant").app;

pub fn main(init: std.process.Init) !void {
    try app.run(init);
}

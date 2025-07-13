const std = @import("std");
const http = std.http;
const json = std.json;

const openlib = @import("openlib");

const OpenLibraryBook = openlib.OpenLibraryBook;
const GetOpenLibraryBookResponse = openlib.GetOpenLibraryBookResponse;

fn printUsage(stdout: std.io.AnyWriter) !void {
    const message =
    \\ Usage: isbn [isbn]
    ;

    try stdout.print("{s}", .{message});
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) {
        try printUsage(stdout.any());
        return;
    }

    const isbn: []const u8 = args[1];
    var res = try openlib.getOpenLibraryBook(allocator, isbn);

    if (res.status != http.Status.ok) {
        try stderr.print("Error fetching ISBN data: {d} ({s})\n", .{
            @intFromEnum(res.status),
            res.status.phrase() orelse "Unknown status",
        });
        return;
    }

    const book = res.object.?.book;
    const author_name: []const u8 = blk: {
        const author_key = book.authors[0].key;

        if (std.mem.eql(u8, author_key, "N/A")) {
            break :blk "N/A";
        }

        res = try openlib.getOpenLibraryAuthor(allocator, author_key);

        if (res.status != http.Status.ok) {
            try stderr.print("Error fetching author data: {d} ({s})\n", .{
                @intFromEnum(res.status),
                res.status.phrase() orelse "Unknown status",
            });
            break :blk "N/A";
        }

        break :blk res.object.?.author.name;
    };

    try stdout.print("Title: {s}\n",        .{book.title});
    try stdout.print("Author: {s}\n",       .{author_name});
    try stdout.print("ISBN-13: {s}\n",      .{book.isbn_13[0]});
    try stdout.print("Publishers: {s}\n",   .{book.publishers[0]});
    try stdout.print("Publish Date: {s}\n", .{book.publish_date});
}

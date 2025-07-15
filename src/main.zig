const std = @import("std");
const http = std.http;

const openlib = @import("openlib");
const GetOpenLibraryResponse = openlib.GetOpenLibraryResponse;
const OpenLibraryAuthor = openlib.OpenLibraryAuthor;
const OpenLibraryBook = openlib.OpenLibraryBook;
const OpenLibraryWork = openlib.OpenLibraryWork;

fn printUsage(stdout: std.io.AnyWriter) !void {
    const message =
    \\ Usage: isbn [isbn]
    \\
    ;

    try stdout.print("{s}", .{message});
}

fn printBookInfo(
    stdout: std.io.AnyWriter,
    book: OpenLibraryBook,
    authors: std.ArrayList(OpenLibraryAuthor)
) !void {
    try stdout.print("Title: {s}\n", .{book.title});

    try stdout.print("Author(s):\n", .{});
    for (authors.items) |author| {
        try stdout.print("- {s}\n", .{author.name});
    }

    try stdout.print("ISBN-13:\n", .{});
    for (book.isbn_13) |isbn_13| {
        try stdout.print("- {s}\n", .{isbn_13});
    }

    try stdout.print("Publisher(s):\n", .{});
    for (book.publishers) |publisher| {
        try stdout.print("- {s}\n", .{publisher});
    }

    try stdout.print("Publish Date: {s}\n", .{book.publish_date});
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args: [][:0]u8 = try std.process.argsAlloc(allocator);
    if (args.len != 2) {
        try printUsage(stdout.any());
        return;
    }

    const isbn: []const u8 = args[1];
    var res: GetOpenLibraryResponse = try openlib.getOpenLibraryBook(
        allocator, isbn
    );
    if (res.status != http.Status.ok) {
        try stderr.print("Error fetching ISBN data: {d} ({s})\n", .{
            @intFromEnum(res.status),
            res.status.phrase() orelse "Unknown status",
        });
        return;
    }

    var authors = try std.ArrayList(OpenLibraryAuthor).initCapacity(
        allocator, 10
    );

    const book: OpenLibraryBook = res.object.?.book;
    if (std.mem.eql(u8, book.works[0].key, "N/A")) {
        try authors.append(.{ .name = "N/A" });
        try printBookInfo(stdout.any(), book, authors);
        return;
    }

    res = try openlib.getOpenLibraryWork(allocator, book.works[0].key);
    if (res.status != http.Status.ok) {
        try stderr.print("Error fetching work data: {d} ({s})\n", .{
            @intFromEnum(res.status),
            res.status.phrase() orelse "Unknown status",
        });
        return;
    }

    const first_work: OpenLibraryWork = res.object.?.work;
    for (first_work.authors) |author_key| {
        res = try openlib.getOpenLibraryAuthor(
            allocator, author_key.author.key
        );

        if (res.status != http.Status.ok) {
            try stderr.print("Error fetching author data: {d} ({s})\n", .{
                @intFromEnum(res.status),
                res.status.phrase() orelse "Unknown status",
            });
            return;
        }

        try authors.append(res.object.?.author);
    }

    try printBookInfo(stdout.any(), book, authors);
}

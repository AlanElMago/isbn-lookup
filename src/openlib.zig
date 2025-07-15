const std = @import("std");
const http = std.http;
const json = std.json;

pub const OPEN_LIBRARY_URL = "https://openlibrary.org";
pub const SERVER_HEADER_BUFFER_SIZE = 1024;
pub const MAX_APPEND_SIZE = 65536;

const FetchResponse = struct {
    status: http.Status,
    body: *std.ArrayList(u8),
};

pub const OpenLibraryAuthor = struct {
    const Self = @This();

    name: []const u8,

    pub fn initFromJsonParsed(
        allocator: std.mem.Allocator,
        parsed: json.Parsed(json.Value)
    ) !Self {
        const root = parsed.value;
        var author: Self = .{ .name = undefined };

        if (root.object.get("name")) |name| {
            author.name = try json.parseFromValueLeaky(
                []const u8, allocator, name, .{},
            );
        } else {
            author.name = "N/A";
        }

        return author;
    }
};

pub const OpenLibraryBook = struct {
    const Self = @This();
    const WorkKey = struct { key: []const u8 };

    title:        []const u8,
    isbn_13:      []const []const u8,
    publishers:   []const []const u8,
    publish_date: []const u8,
    works:        []const WorkKey,

    pub fn initFromJsonParsed(
        allocator: std.mem.Allocator,
        parsed: json.Parsed(json.Value)
    ) !Self {
        const root = parsed.value;
        var book: Self = .{
            .title = undefined,
            .isbn_13 = undefined,
            .publishers = undefined,
            .publish_date = undefined,
            .works = undefined,
        };

        if (root.object.get("title")) |title| {
            book.title = try json.parseFromValueLeaky(
                []const u8, allocator, title, .{},
            );
        } else {
            book.title = "N/A";
        }

        if (root.object.get("isbn_13")) |isbn_13| {
            book.isbn_13 = try json.parseFromValueLeaky(
                []const []const u8, allocator, isbn_13, .{},
            );
        } else {
            book.isbn_13 = &.{ "N/A" };
        }

        if (root.object.get("publishers")) |publishers| {
            book.publishers = try json.parseFromValueLeaky(
                []const []const u8, allocator, publishers, .{},
            );
        } else {
            book.publishers = &.{ "N/A" };
        }

        if (root.object.get("publish_date")) |publish_date| {
            book.publish_date = try json.parseFromValueLeaky(
                []const u8, allocator, publish_date, .{},
            );
        } else {
            book.publish_date = "N/A";
        }

        if (root.object.get("works")) |works| {
            book.works = try json.parseFromValueLeaky(
                []WorkKey, allocator, works, .{},
            );
        } else {
            book.works = &.{ .{ .key = "N/A" } };
        }

        return book;
    }
};

pub const OpenLibraryWork = struct {
    const Self = @This();
    const AuthorKey = struct {
        author: struct { key: []const u8 },
        type: struct { key: []const u8 },
    };

    authors: []const AuthorKey,

    pub fn initFromJsonParsed(
        allocator: std.mem.Allocator,
        parsed: json.Parsed(json.Value)
    ) !Self {
        const root = parsed.value;
        var work: Self = .{ .authors = undefined };

        if (root.object.get("authors")) |authors| {
            work.authors = try json.parseFromValueLeaky(
                []AuthorKey, allocator, authors, .{},
            );
        } else {
            work.authors = &.{ .{
                .author = .{ .key = "N/A" },
                .type = .{ .key = "N/A" },
            } };
        }

        return work;
    }
};

pub const GetOpenLibraryResponse = struct {
    object: ?union {
        author: OpenLibraryAuthor,
        book: OpenLibraryBook,
        work: OpenLibraryWork
    },
    status: http.Status,
};

fn fetchJson(allocator: std.mem.Allocator, url: []const u8) !FetchResponse {
    const uri = try std.Uri.parse(url);
    var server_header_buffer: [SERVER_HEADER_BUFFER_SIZE]u8 = undefined;
    var res_body = std.ArrayList(u8).init(allocator);
    const extra_headers = [_]http.Header{
        .{ .name = "accept", .value = "application/json" }
    };

    var client: http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const result = try client.fetch(.{
        .server_header_buffer = server_header_buffer[0..],
        .response_storage = .{ .dynamic = &res_body },
        .max_append_size = MAX_APPEND_SIZE,
        .location = .{ .uri = uri },
        .method = http.Method.GET,
        .extra_headers = extra_headers[0..],
    });

    return .{ .status = result.status, .body = &res_body };
}

pub fn getOpenLibraryBook(
    allocator: std.mem.Allocator,
    isbn: []const u8
) !GetOpenLibraryResponse {
    const url: []u8 = try std.mem.concat(
        allocator, u8, &[_][]const u8{ OPEN_LIBRARY_URL, "/isbn/", isbn },
    );

    const res: FetchResponse = try fetchJson(allocator, url);
    if (res.status != http.Status.ok) {
        return .{ .object = null, .status = res.status };
    }

    const parsed: json.Parsed(json.Value) = try json.parseFromSlice(
        json.Value, allocator, res.body.items, .{}
    );
    const book = try OpenLibraryBook.initFromJsonParsed(allocator, parsed);

    return .{ .object = .{ .book = book }, .status = res.status };
}

pub fn getOpenLibraryAuthor(
    allocator: std.mem.Allocator,
    key: []const u8,
) !GetOpenLibraryResponse {
    const url: []u8 = try std.mem.concat(
        allocator, u8, &[_][]const u8{ OPEN_LIBRARY_URL, key }
    );

    const res: FetchResponse = try fetchJson(allocator, url);
    if (res.status != http.Status.ok) {
        return .{ .object = null, .status = res.status };
    }

    const parsed: json.Parsed(json.Value) = try json.parseFromSlice(
        json.Value, allocator, res.body.items, .{}
    );
    const author = try OpenLibraryAuthor.initFromJsonParsed(allocator, parsed);

    return .{ .object = .{ .author = author }, .status = res.status };
}

pub fn getOpenLibraryWork(
    allocator: std.mem.Allocator,
    key: []const u8,
) !GetOpenLibraryResponse {
    const url: []u8 = try std.mem.concat(
        allocator, u8, &[_][]const u8{ OPEN_LIBRARY_URL, key }
    );

    const res: FetchResponse = try fetchJson(allocator, url);
    if (res.status != http.Status.ok) {
        return .{ .object = null, .status = res.status };
    }

    const parsed: json.Parsed(json.Value) = try json.parseFromSlice(
        json.Value, allocator, res.body.items, .{}
    );
    const work = try OpenLibraryWork.initFromJsonParsed(allocator, parsed);

    return .{ .object = .{ .work = work }, .status = res.status };
}

//! OPA time parsing and manipulation builtins.

const std = @import("std");
const epoch = std.time.epoch;
const common = @import("common.zig");
const Args = common.Args;
const BuiltinError = common.BuiltinError;

const ns_per_us = std.time.ns_per_us;
const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;
const ns_per_min = std.time.ns_per_min;
const ns_per_hour = std.time.ns_per_hour;
const ns_per_day = std.time.ns_per_day;
const s_per_day = std.time.s_per_day;

pub fn nowNs(_: std.mem.Allocator, _: Args) BuiltinError!std.json.Value {
    const ns = std.time.nanoTimestamp();
    return .{ .integer = @intCast(ns) };
}

pub fn parseRfc3339Ns(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const str = try args.getString(0);
    const ns = rfc3339ToNs(str) catch return error.InvalidArguments;
    return .{ .integer = ns };
}

pub fn parseNs(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const layout = try args.getString(0);
    const value = try args.getString(1);

    if (std.mem.eql(u8, layout, "2006-01-02T15:04:05Z07:00") or
        std.mem.eql(u8, layout, "2006-01-02T15:04:05Z") or
        std.mem.eql(u8, layout, "RFC3339"))
    {
        const ns = rfc3339ToNs(value) catch return error.InvalidArguments;
        return .{ .integer = ns };
    }

    return error.InvalidArguments;
}

pub fn parseDurationNs(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const str = try args.getString(0);
    const ns = parseDuration(str) catch return error.InvalidArguments;
    return .{ .integer = ns };
}

pub fn date(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const ns = try args.getInt(0);
    const dt = nsToDateTime(ns);

    var arr = std.json.Array.init(allocator);
    arr.append(.{ .integer = dt.year }) catch return error.AllocationFailed;
    arr.append(.{ .integer = dt.month }) catch return error.AllocationFailed;
    arr.append(.{ .integer = dt.day }) catch return error.AllocationFailed;
    return .{ .array = arr };
}

pub fn clock(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const ns = try args.getInt(0);
    const dt = nsToDateTime(ns);

    var arr = std.json.Array.init(allocator);
    arr.append(.{ .integer = dt.hour }) catch return error.AllocationFailed;
    arr.append(.{ .integer = dt.minute }) catch return error.AllocationFailed;
    arr.append(.{ .integer = dt.second }) catch return error.AllocationFailed;
    return .{ .array = arr };
}

pub fn weekday(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const ns = try args.getInt(0);
    const secs: u64 = @intCast(@divFloor(ns, ns_per_s));
    const es = epoch.EpochSeconds{ .secs = secs };
    const epoch_day = es.getEpochDay().day;
    // Jan 1, 1970 was Thursday. (epoch_day + 3) % 7 gives Monday=0
    const day_index: usize = @intCast(@mod(epoch_day + 3, 7));
    const weekdays = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
    return .{ .string = weekdays[day_index] };
}

pub fn addDate(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    _ = allocator;
    const ns = try args.getInt(0);
    const years = try args.getInt(1);
    const months = try args.getInt(2);
    const days = try args.getInt(3);

    var dt = nsToDateTime(ns);
    dt.year += @intCast(years);

    var total_months = dt.month + @as(i32, @intCast(months));
    while (total_months > 12) {
        total_months -= 12;
        dt.year += 1;
    }
    while (total_months < 1) {
        total_months += 12;
        dt.year -= 1;
    }
    dt.month = total_months;

    const max_day = daysInMonth(@intCast(dt.year), @intCast(dt.month));
    if (dt.day > max_day) dt.day = max_day;

    const base_ns = dateTimeToNs(dt);
    const result = base_ns + days * @as(i64, ns_per_day);
    return .{ .integer = result };
}

pub fn diff(allocator: std.mem.Allocator, args: Args) BuiltinError!std.json.Value {
    const ns1 = try args.getInt(0);
    const ns2 = try args.getInt(1);

    const dt1 = nsToDateTime(ns1);
    const dt2 = nsToDateTime(ns2);

    var years = dt1.year - dt2.year;
    var months = dt1.month - dt2.month;
    var days = dt1.day - dt2.day;

    if (days < 0) {
        months -= 1;
        const prev_month: u4 = if (dt1.month == 1) 12 else @intCast(dt1.month - 1);
        const prev_year: u16 = if (dt1.month == 1) @intCast(dt1.year - 1) else @intCast(dt1.year);
        days += daysInMonth(prev_year, prev_month);
    }
    if (months < 0) {
        years -= 1;
        months += 12;
    }

    var arr = std.json.Array.init(allocator);
    arr.append(.{ .integer = years }) catch return error.AllocationFailed;
    arr.append(.{ .integer = months }) catch return error.AllocationFailed;
    arr.append(.{ .integer = days }) catch return error.AllocationFailed;
    return .{ .array = arr };
}

const DateTime = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,
    ns: i32,
};

fn nsToDateTime(ns: i64) DateTime {
    const total_secs = @divFloor(ns, ns_per_s);
    const nano: i32 = @intCast(@mod(ns, ns_per_s));

    if (total_secs >= 0) {
        const es = epoch.EpochSeconds{ .secs = @intCast(total_secs) };
        const epoch_day = es.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = es.getDaySeconds();

        return .{
            .year = @intCast(year_day.year),
            .month = @intFromEnum(month_day.month),
            .day = @as(i32, month_day.day_index) + 1,
            .hour = @intCast(day_secs.getHoursIntoDay()),
            .minute = @intCast(day_secs.getMinutesIntoHour()),
            .second = @intCast(day_secs.getSecondsIntoMinute()),
            .ns = nano,
        };
    }

    // Handle negative timestamps (before 1970)
    var secs = total_secs;
    var days = @divFloor(secs, s_per_day);
    secs = @mod(secs, s_per_day);
    if (secs < 0) {
        secs += s_per_day;
        days -= 1;
    }

    var year: i32 = 1970;
    while (days < 0) {
        year -= 1;
        const year_days: i64 = if (isLeapYear(@intCast(year))) 366 else 365;
        days += year_days;
    }

    var month: u4 = 1;
    while (month <= 12) {
        const mdays = daysInMonth(@intCast(year), month);
        if (days < mdays) break;
        days -= mdays;
        month += 1;
    }

    return .{
        .year = year,
        .month = month,
        .day = @intCast(days + 1),
        .hour = @intCast(@divFloor(secs, 3600)),
        .minute = @intCast(@divFloor(@mod(secs, 3600), 60)),
        .second = @intCast(@mod(secs, 60)),
        .ns = nano,
    };
}

fn dateTimeToNs(dt: DateTime) i64 {
    var days: i64 = 0;
    const epoch_year: i32 = 1970;

    if (dt.year >= epoch_year) {
        var y = epoch_year;
        while (y < dt.year) : (y += 1) {
            days += if (isLeapYear(@intCast(y))) 366 else 365;
        }
    } else {
        var y = epoch_year;
        while (y > dt.year) {
            y -= 1;
            days -= if (isLeapYear(@intCast(y))) 366 else 365;
        }
    }

    var m: u4 = 1;
    while (m < dt.month) : (m += 1) {
        days += daysInMonth(@intCast(dt.year), m);
    }

    days += dt.day - 1;

    const secs = days * s_per_day + dt.hour * 3600 + dt.minute * 60 + dt.second;
    return secs * ns_per_s + dt.ns;
}

fn isLeapYear(year: u16) bool {
    return epoch.isLeapYear(@intCast(year));
}

fn daysInMonth(year: u16, month: u4) i32 {
    const days = epoch.getDaysInMonth(@intCast(year), @enumFromInt(month));
    return @intCast(days);
}

fn rfc3339ToNs(str: []const u8) !i64 {
    if (str.len < 10) return error.InvalidFormat;

    const year = std.fmt.parseInt(i32, str[0..4], 10) catch return error.InvalidFormat;
    if (str[4] != '-') return error.InvalidFormat;
    const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.InvalidFormat;
    if (str[7] != '-') return error.InvalidFormat;
    const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.InvalidFormat;

    var hour: i32 = 0;
    var minute: i32 = 0;
    var second: i32 = 0;
    var nano: i32 = 0;
    var tz_offset_secs: i64 = 0;

    if (str.len > 10 and str[10] == 'T') {
        if (str.len < 19) return error.InvalidFormat;
        hour = std.fmt.parseInt(i32, str[11..13], 10) catch return error.InvalidFormat;
        if (str[13] != ':') return error.InvalidFormat;
        minute = std.fmt.parseInt(i32, str[14..16], 10) catch return error.InvalidFormat;
        if (str[16] != ':') return error.InvalidFormat;
        second = std.fmt.parseInt(i32, str[17..19], 10) catch return error.InvalidFormat;

        var pos: usize = 19;

        if (pos < str.len and str[pos] == '.') {
            pos += 1;
            var frac_end = pos;
            while (frac_end < str.len and str[frac_end] >= '0' and str[frac_end] <= '9') : (frac_end += 1) {}
            const frac_str = str[pos..frac_end];
            if (frac_str.len > 0) {
                var frac = std.fmt.parseInt(i64, frac_str, 10) catch 0;
                var digits = frac_str.len;
                while (digits < 9) : (digits += 1) frac *= 10;
                while (digits > 9) : (digits -= 1) frac = @divFloor(frac, 10);
                nano = @intCast(frac);
            }
            pos = frac_end;
        }

        if (pos < str.len) {
            const tz_char = str[pos];
            if (tz_char == 'Z') {
                tz_offset_secs = 0;
            } else if (tz_char == '+' or tz_char == '-') {
                if (pos + 6 > str.len) return error.InvalidFormat;
                const tz_hour = std.fmt.parseInt(i64, str[pos + 1 .. pos + 3], 10) catch return error.InvalidFormat;
                const tz_min = std.fmt.parseInt(i64, str[pos + 4 .. pos + 6], 10) catch return error.InvalidFormat;
                tz_offset_secs = tz_hour * 3600 + tz_min * 60;
                if (tz_char == '-') tz_offset_secs = -tz_offset_secs;
            }
        }
    }

    const dt = DateTime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .ns = nano,
    };

    return dateTimeToNs(dt) - tz_offset_secs * ns_per_s;
}

fn parseDuration(str: []const u8) !i64 {
    if (str.len == 0) return error.InvalidFormat;

    var total_ns: i64 = 0;
    var i: usize = 0;
    var negative = false;

    if (str[0] == '-') {
        negative = true;
        i = 1;
    }

    while (i < str.len) {
        var num_end = i;
        while (num_end < str.len and ((str[num_end] >= '0' and str[num_end] <= '9') or str[num_end] == '.')) : (num_end += 1) {}

        if (num_end == i) return error.InvalidFormat;

        const num_str = str[i..num_end];
        var unit_end = num_end;
        while (unit_end < str.len and str[unit_end] >= 'a' and str[unit_end] <= 'z') : (unit_end += 1) {}

        const unit = str[num_end..unit_end];
        if (unit.len == 0) return error.InvalidFormat;

        const multiplier: i64 = if (std.mem.eql(u8, unit, "ns"))
            1
        else if (std.mem.eql(u8, unit, "us") or std.mem.eql(u8, unit, "µs"))
            ns_per_us
        else if (std.mem.eql(u8, unit, "ms"))
            ns_per_ms
        else if (std.mem.eql(u8, unit, "s"))
            ns_per_s
        else if (std.mem.eql(u8, unit, "m"))
            ns_per_min
        else if (std.mem.eql(u8, unit, "h"))
            ns_per_hour
        else
            return error.InvalidFormat;

        if (std.mem.indexOf(u8, num_str, ".")) |_| {
            const val = std.fmt.parseFloat(f64, num_str) catch return error.InvalidFormat;
            total_ns += @intFromFloat(val * @as(f64, @floatFromInt(multiplier)));
        } else {
            const val = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidFormat;
            total_ns += val * multiplier;
        }

        i = unit_end;
    }

    return if (negative) -total_ns else total_ns;
}

test "time.now_ns" {
    const result = try nowNs(std.testing.allocator, Args.init(&.{}));
    try std.testing.expect(result.integer > 0);
}

test "time.parse_rfc3339_ns" {
    const allocator = std.testing.allocator;

    var result = try parseRfc3339Ns(allocator, Args.init(&.{.{ .string = "1970-01-01T00:00:00Z" }}));
    try std.testing.expectEqual(@as(i64, 0), result.integer);

    result = try parseRfc3339Ns(allocator, Args.init(&.{.{ .string = "1970-01-01T00:00:01Z" }}));
    try std.testing.expectEqual(@as(i64, 1_000_000_000), result.integer);

    result = try parseRfc3339Ns(allocator, Args.init(&.{.{ .string = "2021-06-15T12:30:45Z" }}));
    try std.testing.expect(result.integer > 0);
}

test "time.parse_duration_ns" {
    const allocator = std.testing.allocator;

    var result = try parseDurationNs(allocator, Args.init(&.{.{ .string = "1h" }}));
    try std.testing.expectEqual(@as(i64, 3600_000_000_000), result.integer);

    result = try parseDurationNs(allocator, Args.init(&.{.{ .string = "1m30s" }}));
    try std.testing.expectEqual(@as(i64, 90_000_000_000), result.integer);

    result = try parseDurationNs(allocator, Args.init(&.{.{ .string = "500ms" }}));
    try std.testing.expectEqual(@as(i64, 500_000_000), result.integer);
}

test "time.date" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try date(arena.allocator(), Args.init(&.{.{ .integer = 0 }}));
    try std.testing.expectEqual(@as(i64, 1970), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[2].integer);
}

test "time.clock" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try clock(arena.allocator(), Args.init(&.{.{ .integer = 3661_000_000_000 }}));
    try std.testing.expectEqual(@as(i64, 1), result.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[1].integer);
    try std.testing.expectEqual(@as(i64, 1), result.array.items[2].integer);
}

test "time.weekday" {
    const allocator = std.testing.allocator;

    const result = try weekday(allocator, Args.init(&.{.{ .integer = 0 }}));
    try std.testing.expectEqualStrings("Thursday", result.string);
}

//! The calculator itself: what each key does and what the display shows.
//!
//! There is no UIKit or Objective-C here, so the logic can be tested on any
//! machine with `zig test src/calc_mechanics.zig`.
//!
//! It works like a basic pocket calculator: operations run in the order they
//! are entered, so `2 + 3 × 4 =` gives 20, not 14.

const std = @import("std");

/// The most digits that can be typed into one number.
const max_digits = 9;

/// Every key on the calculator. The UI stores these as button tags, so the
/// digits come first and `Key.digit_7` has the value 7.
pub const Key = enum(u8) {
    digit_0,
    digit_1,
    digit_2,
    digit_3,
    digit_4,
    digit_5,
    digit_6,
    digit_7,
    digit_8,
    digit_9,
    decimal,
    add,
    subtract,
    multiply,
    divide,
    equals,
    clear,
    negate,
    percent,
    backspace,
};

const Op = enum { add, subtract, multiply, divide };

pub const Calculator = struct {
    /// What the display shows. Kept null-terminated so the UI can hand it
    /// straight to `NSString`.
    text_buf: [40]u8 = [_]u8{'0'} ++ [_]u8{0} ** 39,
    text_len: usize = 1,
    /// The left-hand side of the pending operation.
    accumulator: f64 = 0,
    pending: ?Op = null,
    /// The next digit starts a new number instead of extending the display.
    fresh: bool = true,
    /// The display holds a right-hand operand that has not been used yet.
    operand_ready: bool = false,
    /// The display shows "Error"; the next key starts over.
    failed: bool = false,

    pub fn text(self: *const Calculator) [:0]const u8 {
        return self.text_buf[0..self.text_len :0];
    }

    pub fn press(self: *Calculator, key: Key) void {
        if (self.failed) {
            // After an error only a new number or clear makes sense.
            switch (key) {
                .digit_0, .digit_1, .digit_2, .digit_3, .digit_4, .digit_5, .digit_6, .digit_7, .digit_8, .digit_9, .decimal, .clear => self.* = .{},
                else => return,
            }
        }
        switch (key) {
            .digit_0, .digit_1, .digit_2, .digit_3, .digit_4, .digit_5, .digit_6, .digit_7, .digit_8, .digit_9 => self.typeDigit('0' + @intFromEnum(key)),
            .decimal => self.typeDecimal(),
            .add => self.chooseOp(.add),
            .subtract => self.chooseOp(.subtract),
            .multiply => self.chooseOp(.multiply),
            .divide => self.chooseOp(.divide),
            .equals => self.equals(),
            .clear => self.* = .{},
            .negate => self.negate(),
            .percent => self.percent(),
            .backspace => self.backspace(),
        }
    }

    fn value(self: *const Calculator) f64 {
        return std.fmt.parseFloat(f64, self.text()) catch 0;
    }

    fn startEntry(self: *Calculator) void {
        if (self.fresh) {
            self.setText("0");
            self.fresh = false;
        }
        self.operand_ready = true;
    }

    fn typeDigit(self: *Calculator, digit: u8) void {
        self.startEntry();
        const current = self.text();
        if (std.mem.eql(u8, current, "0")) {
            self.setText(&.{digit});
        } else if (std.mem.eql(u8, current, "-0")) {
            self.setText(&.{ '-', digit });
        } else if (countDigits(current) < max_digits) {
            self.append(digit);
        }
    }

    fn typeDecimal(self: *Calculator) void {
        self.startEntry();
        if (std.mem.indexOfScalar(u8, self.text(), '.') == null) self.append('.');
    }

    fn backspace(self: *Calculator) void {
        if (self.fresh) return;
        self.text_len -= 1;
        self.text_buf[self.text_len] = 0;
        const current = self.text();
        if (current.len == 0 or std.mem.eql(u8, current, "-")) self.setText("0");
    }

    fn negate(self: *Calculator) void {
        // Straight after an operator, ± starts the next number as negative.
        if (self.fresh and self.pending != null and !self.operand_ready) {
            self.setText("-0");
            self.fresh = false;
            self.operand_ready = true;
            return;
        }
        const current = self.text();
        if (current[0] == '-') {
            var unsigned: [40]u8 = undefined;
            @memcpy(unsigned[0 .. current.len - 1], current[1..]);
            self.setText(unsigned[0 .. current.len - 1]);
        } else if (!(self.fresh and std.mem.eql(u8, current, "0"))) {
            var signed: [40]u8 = undefined;
            signed[0] = '-';
            @memcpy(signed[1 .. current.len + 1], current);
            self.setText(signed[0 .. current.len + 1]);
        }
    }

    fn percent(self: *Calculator) void {
        self.show(self.value() / 100);
        self.fresh = true;
        self.operand_ready = true;
    }

    fn chooseOp(self: *Calculator, op: Op) void {
        if (self.pending != null and self.operand_ready) {
            self.evaluate();
            if (self.failed) return;
        } else if (self.pending == null) {
            self.accumulator = self.value();
        }
        // Otherwise an operator was pressed twice in a row: the new one wins.
        self.pending = op;
        self.fresh = true;
        self.operand_ready = false;
    }

    fn equals(self: *Calculator) void {
        if (self.pending == null) return;
        self.evaluate();
        self.pending = null;
        self.fresh = true;
        self.operand_ready = false;
    }

    /// Applies the pending operation to the accumulator and the display.
    fn evaluate(self: *Calculator) void {
        const rhs = self.value();
        const result = switch (self.pending.?) {
            .add => self.accumulator + rhs,
            .subtract => self.accumulator - rhs,
            .multiply => self.accumulator * rhs,
            .divide => if (rhs == 0) std.math.nan(f64) else self.accumulator / rhs,
        };
        self.show(result);
        // Carry on from the rounded number on screen, not the exact result,
        // so 0.1 + 0.2 - 0.3 comes out as 0.
        self.accumulator = self.value();
    }

    /// Shows a number to about ten significant digits.
    fn show(self: *Calculator, x: f64) void {
        if (!std.math.isFinite(x)) {
            self.setText("Error");
            self.failed = true;
            return;
        }
        var buf: [40]u8 = undefined;
        const magnitude = @abs(x);
        if (magnitude == 0) {
            self.setText("0");
        } else if (magnitude >= 1e10 or magnitude < 1e-7) {
            // Scientific notation: trim zeros from the mantissa, 1.50000000e-9 -> 1.5e-9.
            const formatted = std.fmt.bufPrint(&buf, "{e:.8}", .{x}) catch unreachable;
            const e = std.mem.indexOfScalar(u8, formatted, 'e').?;
            const mantissa = trimZeros(formatted[0..e]);
            var joined: [40]u8 = undefined;
            const out = std.fmt.bufPrint(&joined, "{s}{s}", .{ mantissa, formatted[e..] }) catch unreachable;
            self.setText(out);
        } else {
            const decimals: usize = @intFromFloat(std.math.clamp(9 - @floor(std.math.log10(magnitude)), 0, 16));
            const formatted = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ x, decimals }) catch unreachable;
            const trimmed = trimZeros(formatted);
            self.setText(if (std.mem.eql(u8, trimmed, "-0")) "0" else trimmed);
        }
    }

    fn setText(self: *Calculator, new_text: []const u8) void {
        @memcpy(self.text_buf[0..new_text.len], new_text);
        self.text_len = new_text.len;
        self.text_buf[self.text_len] = 0;
    }

    fn append(self: *Calculator, char: u8) void {
        self.text_buf[self.text_len] = char;
        self.text_len += 1;
        self.text_buf[self.text_len] = 0;
    }
};

fn countDigits(s: []const u8) usize {
    var n: usize = 0;
    for (s) |c| {
        if (std.ascii.isDigit(c)) n += 1;
    }
    return n;
}

/// "2.500" -> "2.5", "3.000" -> "3". Leaves numbers without a point alone.
fn trimZeros(s: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, s, '.') == null) return s;
    const no_zeros = std.mem.trimEnd(u8, s, "0");
    return std.mem.trimEnd(u8, no_zeros, ".");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Presses each key named in `keys`, e.g. "12+3=", and returns the display.
/// `n` is ±, `%` is percent, `<` is backspace and `c` is clear.
fn run(calc: *Calculator, keys: []const u8) []const u8 {
    for (keys) |k| {
        calc.press(switch (k) {
            '0'...'9' => @enumFromInt(k - '0'),
            '.' => .decimal,
            '+' => .add,
            '-' => .subtract,
            '*' => .multiply,
            '/' => .divide,
            '=' => .equals,
            'c' => .clear,
            'n' => .negate,
            '%' => .percent,
            '<' => .backspace,
            else => unreachable,
        });
    }
    return calc.text();
}

fn expectDisplay(keys: []const u8, expected: []const u8) !void {
    var calc: Calculator = .{};
    try std.testing.expectEqualStrings(expected, run(&calc, keys));
}

test "starts at zero" {
    try expectDisplay("", "0");
}

test "typing numbers" {
    try expectDisplay("0012", "12");
    try expectDisplay("3.14", "3.14");
    try expectDisplay(".5", "0.5");
    try expectDisplay("1..2", "1.2");
    try expectDisplay("1234567890", "123456789");
}

test "basic operations" {
    try expectDisplay("12+30=", "42");
    try expectDisplay("5-8=", "-3");
    try expectDisplay("6*7=", "42");
    try expectDisplay("1/4=", "0.25");
}

test "operations run in the order entered" {
    try expectDisplay("2+3*4=", "20");
    // The running total shows as soon as the next operator is pressed.
    try expectDisplay("2+3*", "5");
}

test "pressing a second operator replaces the first" {
    try expectDisplay("9+-2=", "7");
}

test "results are rounded for display" {
    try expectDisplay("1/3=", "0.3333333333");
    try expectDisplay("2/3=", "0.6666666667");
    try expectDisplay(".1+.2=", "0.3");
    try expectDisplay(".1+.2-.3=", "0");
}

test "large and tiny results use scientific notation" {
    try expectDisplay("999999999*999999999=", "9.99999998e17");
    try expectDisplay("1/100000000/100=", "1e-10");
}

test "division by zero shows an error until the next number" {
    var calc: Calculator = .{};
    try std.testing.expectEqualStrings("Error", run(&calc, "5/0="));
    try std.testing.expectEqualStrings("Error", run(&calc, "+"));
    try std.testing.expectEqualStrings("7", run(&calc, "7"));
}

test "a result can be used in the next calculation" {
    try expectDisplay("2+3=*10=", "50");
    try expectDisplay("2+3=7", "7");
}

test "negate" {
    try expectDisplay("5n", "-5");
    try expectDisplay("5nn", "5");
    try expectDisplay("n", "0");
    try expectDisplay("10-n4=", "14");
    try expectDisplay("3=n", "-3");
}

test "percent" {
    try expectDisplay("50%", "0.5");
    try expectDisplay("200*10%=", "20");
}

test "backspace" {
    try expectDisplay("123<", "12");
    try expectDisplay("5<", "0");
    try expectDisplay("5n<", "0");
    // A result can't be edited.
    try expectDisplay("2+3=<", "5");
}

test "clear" {
    try expectDisplay("12+3c", "0");
    try expectDisplay("12+3c4=", "4");
}

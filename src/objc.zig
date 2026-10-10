//! The Objective-C runtime (libobjc), declared by hand.
//!
//! UIKit is an Objective-C framework, so every call into it goes through this
//! plain C library: look a class up by name, then send it messages with
//! `objc_msgSend`.

/// Any Objective-C object, including a class. Null is Objective-C's `nil`.
pub const Id = ?*opaque {};
/// A method name ("selector") registered with the runtime.
pub const Sel = ?*opaque {};
pub const Protocol = opaque {};
/// A method implementation, type-erased.
pub const Imp = *const fn () callconv(.c) void;

pub extern fn objc_getClass(name: [*:0]const u8) Id;
pub extern fn objc_getProtocol(name: [*:0]const u8) ?*Protocol;
pub extern fn sel_registerName(name: [*:0]const u8) Sel;
pub extern fn objc_allocateClassPair(superclass: Id, name: [*:0]const u8, extra_bytes: usize) Id;
pub extern fn objc_registerClassPair(class: Id) void;
pub extern fn class_addMethod(class: Id, name: Sel, imp: Imp, types: [*:0]const u8) bool;
pub extern fn class_addProtocol(class: Id, protocol: ?*Protocol) bool;

/// Declared with no signature because it has none of its own: it must be cast
/// to the signature of the method being called. See `send`.
extern fn objc_msgSend() void;

/// Sends `selector` to `target`: Objective-C's `[target selector:arg ...]`.
///
/// Nothing here is checked at compile time. A misspelt selector, or an
/// argument of the wrong type, compiles and then crashes at runtime, so pass
/// arguments with explicit types (`@as(isize, 1)`, not `1`).
pub fn send(comptime Ret: type, target: Id, selector: [*:0]const u8, args: anytype) Ret {
    const A = @TypeOf(args);
    const Fn = switch (args.len) {
        0 => fn (Id, Sel) callconv(.c) Ret,
        1 => fn (Id, Sel, @TypeOf(args[0])) callconv(.c) Ret,
        2 => fn (Id, Sel, @TypeOf(args[0]), @TypeOf(args[1])) callconv(.c) Ret,
        3 => fn (Id, Sel, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2])) callconv(.c) Ret,
        else => @compileError("send: add a case for " ++ @typeName(A)),
    };
    const typed: *const Fn = @ptrCast(&objc_msgSend);
    return @call(.auto, typed, .{ target, sel_registerName(selector) } ++ args);
}

pub fn class(name: [*:0]const u8) Id {
    return objc_getClass(name);
}

/// `[[ClassName alloc] init]`
pub fn new(class_name: [*:0]const u8) Id {
    return send(Id, send(Id, class(class_name), "alloc", .{}), "init", .{});
}

/// Makes an `NSString` from a null-terminated UTF-8 string.
pub fn nsString(text: [*:0]const u8) Id {
    return send(Id, class("NSString"), "stringWithUTF8String:", .{text});
}

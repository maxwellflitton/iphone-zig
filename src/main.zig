//! Hello world for iPhone in pure Zig.
//!
//! There is no Swift, Objective-C or C source here. UIKit is an Objective-C
//! framework, so every call goes through the Objective-C runtime, which is a
//! plain C library: look a class up by name, then send it messages with
//! `objc_msgSend`.

// ---------------------------------------------------------------------------
// MARK:- The Objective-C runtime (libobjc), declared by hand.
// ---------------------------------------------------------------------------

/// Any Objective-C object, including a class. Null is Objective-C's `nil`.
const Id = ?*opaque {};
/// A method name ("selector") registered with the runtime.
const Sel = ?*opaque {};
const Protocol = opaque {};
/// A method implementation, type-erased.
const Imp = *const fn () callconv(.c) void;

extern fn objc_getClass(name: [*:0]const u8) Id;
extern fn objc_getProtocol(name: [*:0]const u8) ?*Protocol;
extern fn sel_registerName(name: [*:0]const u8) Sel;
extern fn objc_allocateClassPair(superclass: Id, name: [*:0]const u8, extra_bytes: usize) Id;
extern fn objc_registerClassPair(class: Id) void;
extern fn class_addMethod(class: Id, name: Sel, imp: Imp, types: [*:0]const u8) bool;
extern fn class_addProtocol(class: Id, protocol: ?*Protocol) bool;

/// Declared with no signature because it has none of its own: it must be cast
/// to the signature of the method being called. See `send`.
extern fn objc_msgSend() void;

/// UIKit's entry point. Starts the run loop and never returns.
extern fn UIApplicationMain(
    argc: c_int,
    argv: [*c][*c]u8,
    principal_class_name: Id,
    delegate_class_name: Id,
) c_int;

/// Sends `selector` to `target`: Objective-C's `[target selector:arg ...]`.
///
/// Nothing here is checked at compile time. A misspelt selector, or an
/// argument of the wrong type, compiles and then crashes at runtime, so pass
/// arguments with explicit types (`@as(isize, 1)`, not `1`).
fn send(comptime Ret: type, target: Id, selector: [*:0]const u8, args: anytype) Ret {
    const A = @TypeOf(args);
    const Fn = switch (args.len) {
        0 => fn (Id, Sel) callconv(.c) Ret,
        1 => fn (Id, Sel, @TypeOf(args[0])) callconv(.c) Ret,
        2 => fn (Id, Sel, @TypeOf(args[0]), @TypeOf(args[1])) callconv(.c) Ret,
        else => @compileError("send: add a case for " ++ @typeName(A)),
    };
    const typed: *const Fn = @ptrCast(&objc_msgSend);
    return @call(.auto, typed, .{ target, sel_registerName(selector) } ++ args);
}

fn class(name: [*:0]const u8) Id {
    return objc_getClass(name);
}

/// Makes an `NSString` from a Zig string literal.
fn nsString(text: [*:0]const u8) Id {
    return send(Id, class("NSString"), "stringWithUTF8String:", .{text});
}

// ---------------------------------------------------------------------------
// MARK:- The app.
// ---------------------------------------------------------------------------

/// UIKit does not keep the window alive for us, so we hold it here.
var window: Id = null;

/// `-[AppDelegate application:didFinishLaunchingWithOptions:]`
fn didFinishLaunching(_: Id, _: Sel, _: Id, _: Id) callconv(.c) bool {
    return true;
}

/// `-[SceneDelegate scene:willConnectToSession:options:]`
///
/// iOS calls this when it has a screen ("scene") ready for us to fill.
fn sceneWillConnect(_: Id, _: Sel, scene: Id, _: Id, _: Id) callconv(.c) void {
    const label = send(Id, send(Id, class("UILabel"), "alloc", .{}), "init", .{});
    send(void, label, "setText:", .{nsString("Hello, world!")});
    send(void, label, "setTextAlignment:", .{@as(isize, 1)}); // NSTextAlignmentCenter
    send(void, label, "setFont:", .{
        send(Id, class("UIFont"), "boldSystemFontOfSize:", .{@as(f64, 34)}),
    });
    // A dynamic colour, so the default label text stays readable in dark mode.
    send(void, label, "setBackgroundColor:", .{
        send(Id, class("UIColor"), "systemBackgroundColor", .{}),
    });

    // Making the label the controller's root view stretches it to fill the
    // screen, which saves doing any layout.
    const controller = send(Id, send(Id, class("UIViewController"), "alloc", .{}), "init", .{});
    send(void, controller, "setView:", .{label});

    window = send(Id, send(Id, class("UIWindow"), "alloc", .{}), "initWithWindowScene:", .{scene});
    send(void, window, "setRootViewController:", .{controller});
    send(void, window, "makeKeyAndVisible", .{});
}

/// Creates the two Objective-C classes iOS expects to find, at runtime.
/// Info.plist names `SceneDelegate`; `main` names `AppDelegate`.
fn registerClasses() void {
    const responder = class("UIResponder");

    // The last argument to `class_addMethod` is the method's type encoding:
    // return type, then self (`@`), the selector (`:`), then the arguments.
    // `B` is BOOL, `v` is void, `@` is an object.
    const app_delegate = objc_allocateClassPair(responder, "AppDelegate", 0);
    _ = class_addProtocol(app_delegate, objc_getProtocol("UIApplicationDelegate"));
    _ = class_addMethod(
        app_delegate,
        sel_registerName("application:didFinishLaunchingWithOptions:"),
        @ptrCast(&didFinishLaunching),
        "B@:@@",
    );
    objc_registerClassPair(app_delegate);

    const scene_delegate = objc_allocateClassPair(responder, "SceneDelegate", 0);
    _ = class_addProtocol(scene_delegate, objc_getProtocol("UIWindowSceneDelegate"));
    _ = class_addMethod(
        scene_delegate,
        sel_registerName("scene:willConnectToSession:options:"),
        @ptrCast(&sceneWillConnect),
        "v@:@@@",
    );
    objc_registerClassPair(scene_delegate);
}

/// Exporting a C `main` replaces Zig's own start-up code, which is what iOS
/// wants: it gives us `argc` and `argv` to hand straight to UIKit.
pub export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    registerClasses();
    return UIApplicationMain(argc, argv, null, nsString("AppDelegate"));
}

//! A calculator for iPhone in pure Zig.
//!
//! There is no Swift, Objective-C or C source here. UIKit is an Objective-C
//! framework, so every call goes through the Objective-C runtime (objc.zig).
//!
//! - calc_mechanics.zig: the calculator logic, free of any UIKit code.
//! - calc_ui.zig: the screen, which drives the logic.
//! - this file: starts UIKit and mounts the calculator screen in a window.

const std = @import("std");
const objc = @import("objc.zig");
const calc_ui = @import("calc_ui.zig");

/// Zig's stack traces look up loaded images with a dyld function the iOS SDK
/// does not provide, so linking fails with them on. Panics still print their
/// message, just without a trace.
pub const std_options: std.Options = .{ .allow_stack_tracing = false };

const Id = objc.Id;
const Sel = objc.Sel;
const send = objc.send;
const class = objc.class;

/// UIKit's entry point. Starts the run loop and never returns.
extern fn UIApplicationMain(
    argc: c_int,
    argv: [*c][*c]u8,
    principal_class_name: Id,
    delegate_class_name: Id,
) c_int;

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
    window = send(Id, send(Id, class("UIWindow"), "alloc", .{}), "initWithWindowScene:", .{scene});
    send(void, window, "setRootViewController:", .{calc_ui.makeViewController()});
    send(void, window, "makeKeyAndVisible", .{});
}

/// Creates the Objective-C classes iOS expects to find, at runtime.
/// Info.plist names `SceneDelegate`; `main` names `AppDelegate`.
fn registerClasses() void {
    const responder = class("UIResponder");

    // The last argument to `class_addMethod` is the method's type encoding:
    // return type, then self (`@`), the selector (`:`), then the arguments.
    // `B` is BOOL, `v` is void, `@` is an object.
    const app_delegate = objc.objc_allocateClassPair(responder, "AppDelegate", 0);
    _ = objc.class_addProtocol(app_delegate, objc.objc_getProtocol("UIApplicationDelegate"));
    _ = objc.class_addMethod(
        app_delegate,
        objc.sel_registerName("application:didFinishLaunchingWithOptions:"),
        @ptrCast(&didFinishLaunching),
        "B@:@@",
    );
    objc.objc_registerClassPair(app_delegate);

    const scene_delegate = objc.objc_allocateClassPair(responder, "SceneDelegate", 0);
    _ = objc.class_addProtocol(scene_delegate, objc.objc_getProtocol("UIWindowSceneDelegate"));
    _ = objc.class_addMethod(
        scene_delegate,
        objc.sel_registerName("scene:willConnectToSession:options:"),
        @ptrCast(&sceneWillConnect),
        "v@:@@@",
    );
    objc.objc_registerClassPair(scene_delegate);

    calc_ui.registerClasses();
}

/// Exporting a C `main` replaces Zig's own start-up code, which is what iOS
/// wants: it gives us `argc` and `argv` to hand straight to UIKit.
pub export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    registerClasses();
    return UIApplicationMain(argc, argv, null, objc.nsString("AppDelegate"));
}

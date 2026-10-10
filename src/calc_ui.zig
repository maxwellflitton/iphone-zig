//! The calculator screen: a display and a 4×5 grid of buttons, built with
//! UIKit through the Objective-C runtime. In portrait the display sits above
//! the buttons; in landscape it sits to their left.
//!
//! Layout uses stack views and Auto Layout anchors rather than frames, so
//! every message takes objects and plain numbers, never structs like CGRect.

const objc = @import("objc.zig");
const mechanics = @import("calc_mechanics.zig");

const Id = objc.Id;
const Sel = objc.Sel;
const Key = mechanics.Key;
const send = objc.send;
const class = objc.class;
const new = objc.new;
const nsString = objc.nsString;

// ---------------------------------------------------------------------------
// MARK:- Buttons.
// ---------------------------------------------------------------------------

const Style = enum { function, digit, operator };

const Button = struct {
    title: [*:0]const u8,
    key: Key,
    style: Style,
};

const rows = [_][4]Button{
    .{ .{ .title = "AC", .key = .clear, .style = .function }, .{ .title = "±", .key = .negate, .style = .function }, .{ .title = "%", .key = .percent, .style = .function }, .{ .title = "÷", .key = .divide, .style = .operator } },
    .{ .{ .title = "7", .key = .digit_7, .style = .digit }, .{ .title = "8", .key = .digit_8, .style = .digit }, .{ .title = "9", .key = .digit_9, .style = .digit }, .{ .title = "×", .key = .multiply, .style = .operator } },
    .{ .{ .title = "4", .key = .digit_4, .style = .digit }, .{ .title = "5", .key = .digit_5, .style = .digit }, .{ .title = "6", .key = .digit_6, .style = .digit }, .{ .title = "−", .key = .subtract, .style = .operator } },
    .{ .{ .title = "1", .key = .digit_1, .style = .digit }, .{ .title = "2", .key = .digit_2, .style = .digit }, .{ .title = "3", .key = .digit_3, .style = .digit }, .{ .title = "+", .key = .add, .style = .operator } },
    .{ .{ .title = "⌫", .key = .backspace, .style = .function }, .{ .title = "0", .key = .digit_0, .style = .digit }, .{ .title = ".", .key = .decimal, .style = .digit }, .{ .title = "=", .key = .equals, .style = .operator } },
};

/// Gap between buttons, in points.
const spacing: f64 = 12;
/// Distance from the screen edges, in points.
const margin: f64 = 16;

// UIKit constants.
const ns_text_alignment_right: isize = 2;
const ui_control_state_normal: usize = 0;
const ui_control_state_highlighted: usize = 1;
const ui_control_event_touch_up_inside: usize = 1 << 6;
const ui_layout_axis_horizontal: isize = 0;
const ui_layout_axis_vertical: isize = 1;
const ui_stack_view_alignment_fill: isize = 0;
const ui_stack_view_alignment_bottom: isize = 4;
const ui_stack_view_distribution_fill_equally: isize = 1;
const ui_user_interface_size_class_compact: isize = 1;
const ui_font_weight_light: f64 = -0.4;
const ui_font_weight_regular: f64 = 0;

// ---------------------------------------------------------------------------
// MARK:- State.
// ---------------------------------------------------------------------------

var calculator: mechanics.Calculator = .{};
/// The label showing the current number.
var display: Id = null;
/// Receives every button tap. UIKit does not retain action targets, so it
/// lives here for the life of the app.
var button_target: Id = null;

const Orientation = enum { portrait, landscape };

/// Holds the display and the grid: a column in portrait, a row in landscape.
var body: Id = null;
/// Constraints that only apply in one orientation. Built once, then switched
/// on and off by `applyLayout`.
var portrait_constraints: [2]Id = undefined;
var landscape_constraints: [3]Id = undefined;
/// The layout currently applied, or null before the first layout pass.
var current_orientation: ?Orientation = null;

/// `-[CalcButtonTarget keyPressed:]`. Each button's tag holds its `Key`.
fn keyPressed(_: Id, _: Sel, sender: Id) callconv(.c) void {
    const tag = send(isize, sender, "tag", .{});
    calculator.press(@enumFromInt(@as(u8, @intCast(tag))));
    send(void, display, "setText:", .{nsString(calculator.text())});
}

/// `-[CalcViewController viewWillLayoutSubviews]`
///
/// UIKit calls this before every layout pass, including after a rotation.
/// An iPhone in landscape has a compact vertical size class.
fn viewWillLayoutSubviews(self: Id, _: Sel) callconv(.c) void {
    const traits = send(Id, self, "traitCollection", .{});
    const compact = send(isize, traits, "verticalSizeClass", .{}) == ui_user_interface_size_class_compact;
    applyLayout(if (compact) .landscape else .portrait);
}

/// Creates the Objective-C classes the screen needs. Call before
/// `makeViewController`.
pub fn registerClasses() void {
    const target_class = objc.objc_allocateClassPair(class("NSObject"), "CalcButtonTarget", 0);
    _ = objc.class_addMethod(
        target_class,
        objc.sel_registerName("keyPressed:"),
        @ptrCast(&keyPressed),
        "v@:@",
    );
    objc.objc_registerClassPair(target_class);

    // UIViewController's own viewWillLayoutSubviews does nothing, so this
    // override doesn't need to call it.
    const controller_class = objc.objc_allocateClassPair(class("UIViewController"), "CalcViewController", 0);
    _ = objc.class_addMethod(
        controller_class,
        objc.sel_registerName("viewWillLayoutSubviews"),
        @ptrCast(&viewWillLayoutSubviews),
        "v@:",
    );
    objc.objc_registerClassPair(controller_class);
}

// ---------------------------------------------------------------------------
// MARK:- Building the screen.
// ---------------------------------------------------------------------------

/// Builds the calculator screen and returns its `UIViewController`.
pub fn makeViewController() Id {
    button_target = new("CalcButtonTarget");

    const view = new("UIView");
    send(void, view, "setBackgroundColor:", .{color("systemBackgroundColor")});

    display = new("UILabel");
    send(void, display, "setText:", .{nsString(calculator.text())});
    send(void, display, "setTextAlignment:", .{ns_text_alignment_right});
    send(void, display, "setFont:", .{
        send(Id, class("UIFont"), "monospacedDigitSystemFontOfSize:weight:", .{ @as(f64, 80), ui_font_weight_light }),
    });
    // Long numbers shrink to fit instead of being cut off.
    send(void, display, "setAdjustsFontSizeToFitWidth:", .{true});
    send(void, display, "setMinimumScaleFactor:", .{@as(f64, 0.3)});

    const grid = stack(ui_layout_axis_vertical);
    for (rows) |row| {
        const row_view = stack(ui_layout_axis_horizontal);
        for (row) |button| {
            send(void, row_view, "addArrangedSubview:", .{makeButton(button)});
        }
        send(void, grid, "addArrangedSubview:", .{row_view});
    }

    body = new("UIStackView");
    send(void, body, "setSpacing:", .{margin});
    send(void, body, "addArrangedSubview:", .{display});
    send(void, body, "addArrangedSubview:", .{grid});
    send(void, body, "setTranslatesAutoresizingMaskIntoConstraints:", .{false});
    send(void, view, "addSubview:", .{body});

    // In both orientations the body hugs the bottom and sides of the safe area.
    const guide = send(Id, view, "safeAreaLayoutGuide", .{});
    activate(constraint(body, "leadingAnchor", "constraintEqualToAnchor:constant:", guide, "leadingAnchor", margin));
    activate(constraint(body, "trailingAnchor", "constraintEqualToAnchor:constant:", guide, "trailingAnchor", -margin));
    activate(constraint(body, "bottomAnchor", "constraintEqualToAnchor:constant:", guide, "bottomAnchor", -margin));

    // The buttons stay square: 5 rows of 4, with 3 gaps across and 4 down.
    // In portrait the screen's width sets their size, and the display sits on
    // top of the grid, wherever that ends up.
    const grid_height = send(Id, grid, "heightAnchor", .{});
    const grid_width = send(Id, grid, "widthAnchor", .{});
    portrait_constraints = .{
        constraint(body, "topAnchor", "constraintGreaterThanOrEqualToAnchor:constant:", guide, "topAnchor", margin),
        send(Id, grid_height, "constraintEqualToAnchor:multiplier:constant:", .{
            grid_width,
            @as(f64, 5.0 / 4.0),
            4 * spacing - (5.0 / 4.0) * 3 * spacing,
        }),
    };
    // In landscape the screen's height sets their size, the grid fills it,
    // and the display takes the space to the left.
    landscape_constraints = .{
        constraint(body, "topAnchor", "constraintEqualToAnchor:constant:", guide, "topAnchor", margin),
        constraint(grid, "topAnchor", "constraintEqualToAnchor:constant:", body, "topAnchor", 0),
        send(Id, grid_width, "constraintEqualToAnchor:multiplier:constant:", .{
            grid_height,
            @as(f64, 4.0 / 5.0),
            3 * spacing - (4.0 / 5.0) * 4 * spacing,
        }),
    };

    // Inactive constraints are not held by any view, so keep our own
    // reference to each one or it is freed before it is needed.
    for (portrait_constraints) |c| retain(c);
    for (landscape_constraints) |c| retain(c);

    // The layout itself is applied by `viewWillLayoutSubviews`, once UIKit
    // knows which way up the phone is.
    const controller = new("CalcViewController");
    send(void, controller, "setView:", .{view});
    return controller;
}

/// Switches the body and constraints to suit `orientation`.
fn applyLayout(orientation: Orientation) void {
    if (current_orientation == orientation) return;
    current_orientation = orientation;

    // Deactivate the old set first, so the two never conflict.
    switch (orientation) {
        .portrait => {
            for (landscape_constraints) |c| deactivate(c);
            send(void, body, "setAxis:", .{ui_layout_axis_vertical});
            send(void, body, "setAlignment:", .{ui_stack_view_alignment_fill});
            for (portrait_constraints) |c| activate(c);
        },
        .landscape => {
            for (portrait_constraints) |c| deactivate(c);
            send(void, body, "setAxis:", .{ui_layout_axis_horizontal});
            // Keeps the display at the bottom, level with the last row.
            send(void, body, "setAlignment:", .{ui_stack_view_alignment_bottom});
            for (landscape_constraints) |c| activate(c);
        },
    }
}

fn makeButton(spec: Button) Id {
    const background, const foreground = switch (spec.style) {
        .function => .{ color("systemGray4Color"), color("labelColor") },
        .digit => .{ color("systemGray6Color"), color("labelColor") },
        .operator => .{ color("systemOrangeColor"), color("whiteColor") },
    };

    const button = send(Id, class("UIButton"), "buttonWithType:", .{@as(isize, 0)}); // UIButtonTypeCustom
    send(void, button, "setTitle:forState:", .{ nsString(spec.title), ui_control_state_normal });
    send(void, button, "setTitleColor:forState:", .{ foreground, ui_control_state_normal });
    send(void, button, "setTitleColor:forState:", .{ color("tertiaryLabelColor"), ui_control_state_highlighted });
    send(void, send(Id, button, "titleLabel", .{}), "setFont:", .{
        send(Id, class("UIFont"), "systemFontOfSize:weight:", .{ @as(f64, 32), ui_font_weight_regular }),
    });
    send(void, button, "setBackgroundColor:", .{background});
    send(void, send(Id, button, "layer", .{}), "setCornerRadius:", .{@as(f64, 16)});

    send(void, button, "setTag:", .{@as(isize, @intFromEnum(spec.key))});
    send(void, button, "addTarget:action:forControlEvents:", .{
        button_target,
        objc.sel_registerName("keyPressed:"),
        ui_control_event_touch_up_inside,
    });
    return button;
}

/// A stack view whose children share its length equally.
fn stack(axis: isize) Id {
    const view = new("UIStackView");
    send(void, view, "setAxis:", .{axis});
    send(void, view, "setDistribution:", .{ui_stack_view_distribution_fill_equally});
    send(void, view, "setSpacing:", .{spacing});
    return view;
}

/// `view.<anchor> <relation> other.<other_anchor> + constant`, not yet active.
fn constraint(
    view: Id,
    anchor: [*:0]const u8,
    relation: [*:0]const u8,
    other: Id,
    other_anchor: [*:0]const u8,
    constant: f64,
) Id {
    const from = send(Id, view, anchor, .{});
    const to = send(Id, other, other_anchor, .{});
    return send(Id, from, relation, .{ to, constant });
}

fn activate(c: Id) void {
    send(void, c, "setActive:", .{true});
}

fn deactivate(c: Id) void {
    send(void, c, "setActive:", .{false});
}

fn retain(object: Id) void {
    _ = send(Id, object, "retain", .{});
}

/// One of `UIColor`'s named colours, e.g. "systemOrangeColor". The system
/// colours adapt to dark mode on their own.
fn color(name: [*:0]const u8) Id {
    return send(Id, class("UIColor"), name, .{});
}

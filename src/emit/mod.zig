const std = @import("std");

pub const Repository = @import("../repository.zig").Repository;

pub const Arg = @import("arg.zig").Arg;
pub const Callable = @import("callable.zig").Callable;
pub const Field = @import("field.zig").Field;
pub const GirFile = @import("gir.zig").GirFile;
pub const ObjectsSubdir = @import("object.zig").ObjectsSubdir;
pub const Type = @import("type.zig").Type;

pub const utils = @import("utils.zig");

pub const PAD = " " ** 4;

pub const Dependencies = std.StringHashMap(void);

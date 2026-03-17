const std = @import("std");
const types = @import("types.zig");
const Category = types.Category;

pub const mountains = [_][]const u8{
    "denali", "rainier", "shasta",  "whitney",  "hood",
    "elbert", "massive", "harvard", "blanca",   "lincoln",
    "evans",  "longs",   "pikes",   "quandary", "bierstadt",
};

pub const rivers = [_][]const u8{
    "columbia", "colorado", "missouri", "yukon",  "rio",
    "snake",    "platte",   "arkansas", "pecos",  "gila",
    "brazos",   "trinity",  "sabine",   "neches", "nueces",
};

pub const deserts = [_][]const u8{
    "mojave",   "sonoran", "chihuahua", "painted", "alvord",
    "amargosa", "borrego", "escalante", "jornada", "vizcaino",
    "tabernas", "karakum", "tanami",    "namib",   "sahel",
};

pub const canyons = [_][]const u8{
    "bryce", "zion",     "antelope", "marble",    "havasu",
    "paria", "buckskin", "canyon",   "escalante", "fern",
    "tonto", "walnut",   "oak",      "sedona",    "verde",
};

pub const islands = [_][]const u8{
    "catalina",  "alcatraz", "coronado", "padre",  "sanibel",
    "nantucket", "block",    "kiawah",   "hilton", "amelia",
    "kodiak",    "adak",     "unalaska", "sitka",  "juneau",
};

pub const passes = [_][]const u8{
    "donner", "loveland", "berthoud", "monarch", "vail",
    "wolf",   "teton",    "chinook",  "logan",   "glacier",
    "tioga",  "sonora",   "kenosha",  "hoosier", "fremont",
};

pub const moons_list = [_][]const u8{
    "europa",    "titan",  "ganymede", "callisto", "io",
    "enceladus", "triton", "oberon",   "miranda",  "ariel",
    "phobos",    "deimos", "charon",   "hyperion", "rhea",
};

pub const raptors = [_][]const u8{
    "falcon", "hawk",    "eagle",    "osprey", "kestrel",
    "merlin", "harrier", "goshawk",  "condor", "vulture",
    "kite",   "buzzard", "caracara", "hobby",  "sparrow",
};

pub const minerals = [_][]const u8{
    "quartz",  "feldspar", "mica",    "olivine", "garnet",
    "topaz",   "beryl",    "apatite", "zircon",  "pyrite",
    "calcite", "gypsum",   "talc",    "galena",  "barite",
};

pub const norse = [_][]const u8{
    "odin",   "thor",     "freya",   "loki",  "tyr",
    "baldur", "heimdall", "frigg",   "bragi", "idun",
    "vidar",  "vali",     "forseti", "njord", "skadi",
};

pub const adjectives = [_][]const u8{
    "swift",  "bold",  "calm",   "dark",  "keen",
    "warm",   "cool",  "vast",   "wild",  "pure",
    "bright", "deep",  "high",   "soft",  "firm",
    "quick",  "sharp", "strong", "clear", "silent",
};

pub const nouns = [_][]const u8{
    "stone",  "creek", "ridge", "vale",  "grove",
    "peak",   "drift", "shade", "bloom", "forge",
    "hearth", "trail", "haven", "crest", "glen",
    "brook",  "cliff", "marsh", "dune",  "ledge",
};

pub const verbs = [_][]const u8{
    "run",   "climb", "drift", "forge",  "spark",
    "flow",  "soar",  "dash",  "stride", "roam",
    "blaze", "surge", "glide", "leap",   "wade",
    "trek",  "scout", "march", "quest",  "hunt",
};

pub fn getWordList(category: Category) []const []const u8 {
    return switch (category) {
        .mountains => &mountains,
        .rivers => &rivers,
        .deserts => &deserts,
        .canyons => &canyons,
        .islands => &islands,
        .passes => &passes,
        .moons => &moons_list,
        .raptors => &raptors,
        .minerals => &minerals,
        .norse => &norse,
    };
}

fn validateWord(word: []const u8) bool {
    if (word.len == 0 or word.len > 12) return false;
    for (word) |c| {
        if (c < 'a' or c > 'z') return false;
    }
    return true;
}

test "all words are valid" {
    const categories = comptime std.enums.values(Category);
    inline for (categories) |cat| {
        const list = getWordList(cat);
        try std.testing.expect(list.len >= 10);
        for (list) |word| {
            if (!validateWord(word)) {
                std.debug.print("invalid word in {s}: '{s}'\n", .{ @tagName(cat), word });
                try std.testing.expect(false);
            }
        }
    }
}

test "adjectives are valid" {
    for (&adjectives) |word| {
        try std.testing.expect(validateWord(word));
    }
}

test "nouns are valid" {
    for (&nouns) |word| {
        try std.testing.expect(validateWord(word));
    }
}

test "verbs are valid" {
    for (&verbs) |word| {
        try std.testing.expect(validateWord(word));
    }
}

test "getWordList returns correct list" {
    const list = getWordList(.mountains);
    try std.testing.expectEqualStrings("denali", list[0]);
}

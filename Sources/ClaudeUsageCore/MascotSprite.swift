import Foundation

/// Pixel-art sprite data for each evolution stage. Lives in Core so both the live mascot
/// view (AppKit-side) and the README asset renderer can share the same source of truth.
///
/// Cell legend:
///   `.`  transparent
///   `X`  body orange
///   `o`  eye cream (closes during blink in live view)
///   `c`  crystal cream (always-on, does not blink)
///   `W`  eggshell cream-white (egg only)
///   `s`  orange speckle on the egg (same color as body X)
///   `g`  dark grey wand shaft (ultimate only)
public enum MascotSprite {
    public static let canvasCols = 16
    public static let canvasRows = 12

    public static func sprite(for stage: EvolutionStage) -> [String] {
        sprites[stage] ?? sprites[.egg]!
    }

    private static let sprites: [EvolutionStage: [String]] = [
        .egg: [
            "................",
            "......WWWW......",
            ".....WWWWWW.....",
            "....WWWWWssW....", // 2-cell speckle, upper right
            "....WWssWWsW....", // 2x2 blob (left, row 1) + L tail (right)
            "....WWssWWWW....", // 2x2 blob (left, row 2)
            "....WWWWWWWW....",
            "....ssWWWWWW....", // 2x2 blob anchored to the left edge, row 1
            "....ssWWWssW....", // 2x2 blob row 2 + 2x2 blob (right, row 1)
            "....WWWWWssW....", // 2x2 blob (right, row 2)
            ".....WWWWWW.....",
            "......WWWW......"
        ],
        .baby: [
            "................",
            "................",
            "................",
            "................",
            ".....XXXXXX.....",
            "....XXXXXXXX....",
            "....XoXXXXoX....",
            "....XoXXXXoX....",
            "....XXXXXXXX....",
            ".....XXXXXX.....",
            "......X..X......",
            "......X..X......"
        ],
        .growth: [
            "................",
            "................",
            "....XXXXXXXX....", // narrow top (8 wide)
            "...XXXXXXXXXX...", // widening (10 wide)
            "..XXXXXXXXXXXX..", // widest (12 wide)
            "..XXoXXXXXXoXX..", // eyes (cols 4, 11)
            "..XXoXXXXXXoXX..",
            "..XXXXXXXXXXXX..",
            "...XXXXXXXXXX...", // taper
            "....XXXXXXXX....", // bottom 8 wide
            "....X.X..X.X....", // 4 short legs (cols 4, 6, 9, 11)
            "....X.X..X.X...."
        ],
        .mature: [
            "................",
            ".....X....X.....", // horns rise from inside the narrow head top
            ".....X....X.....", // so they sit directly on the body — not floating
            "....XXXXXXXX....", // narrow top (8 wide) — cols 5 and 10 catch the horns
            "..XXXXXXXXXXXX..", // shoulders (12 wide)
            ".XXXXXXXXXXXXXX.", // widest (14 wide)
            ".XXXoXXXXXXoXXX.", // eyes (cols 4, 11)
            ".XXXoXXXXXXoXXX.",
            ".XXXXXXXXXXXXXX.",
            ".XXXXXXXXXXXXXX.",
            "...X.X....X.X...", // 4 legs (cols 3, 5, 10, 12)
            "...X.X....X.X..."
        ],
        .perfect: [
            "................",
            "..XXXXXXXXXXXX..", // extra crown row on top of the head
            "..XXXXXXXXXXXX..",
            "..XXoXXXXXXoXX..",
            "..XXoXXXXXXoXX..",
            "..XXXXXXXXXXXX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..X.X......X.X..",
            "..X.X......X.X..",
            "................"
        ],
        .ultimate: [
            ".X.X........X.Xc", // 4 horns (cols 1, 3, 12, 14) + crystal at col 15
            ".X.X........X.Xc",
            "..XXXXXXXXXXXX.g", // body 12 wide + thin wand shaft on col 15
            "..XXoXXXXXXoXX.g", // eyes (same positions as perfect)
            "..XXoXXXXXXoXX.g",
            "..XXXXXXXXXXXX.g",
            "..XXXXXXXXXXXX.g", // shaft continues down to the right hand
            "XXXXXXXXXXXXXXXX", // arm band (kept from perfect — right hand grips the wand)
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..X.X......X.X..", // 4 legs — matches perfect exactly
            "..X.X......X.X.."
        ]
    ]
}

import AppKit

/// A menu of the common GitHub emoji, by category, for inserting while editing. An item inserts
/// the shortcode, such as `:smile:`, which the preview and GitHub both show as the emoji; with ⌥
/// held it inserts the emoji itself. The ones used lately come first.
enum EmojiMenu {
    private static let categories: [(zh: String, en: String, names: [String])] = [
        ("表情", "Smileys", [
            "smile", "smiley", "grinning", "laughing", "joy", "rofl", "sweat_smile", "wink", "blush", "innocent",
            "heart_eyes", "kissing_heart", "yum", "sunglasses", "nerd_face", "thinking", "neutral_face",
            "expressionless", "unamused", "roll_eyes", "smirk", "grimacing", "relieved", "pensive", "sleepy",
            "sleeping", "mask", "exploding_head", "partying_face", "confused", "worried", "open_mouth",
            "astonished", "flushed", "pleading_face", "cry", "sob", "scream", "weary", "triumph", "rage", "angry",
            "skull", "poop", "ghost", "robot", "see_no_evil",
        ]),
        ("手勢", "Gestures", [
            "wave", "ok_hand", "v", "crossed_fingers", "point_left", "point_right", "point_up", "point_down",
            "+1", "-1", "fist", "punch", "clap", "raised_hands", "pray", "handshake", "muscle", "writing_hand",
            "eyes", "brain",
        ]),
        ("愛心與符號", "Hearts & Symbols", [
            "heart", "orange_heart", "yellow_heart", "green_heart", "blue_heart", "purple_heart", "black_heart",
            "broken_heart", "sparkling_heart", "two_hearts", "100", "boom", "dizzy", "zzz", "sparkles", "star",
            "star2", "fire", "warning", "no_entry", "x", "o", "heavy_check_mark", "white_check_mark",
            "ballot_box_with_check", "question", "exclamation", "bangbang", "information_source", "arrow_up",
            "arrow_down", "arrow_left", "arrow_right", "arrows_counterclockwise", "new", "free", "up", "cool",
            "ok", "sos", "red_circle", "large_blue_circle", "green_circle", "yellow_circle", "recycle",
        ]),
        ("物品", "Objects", [
            "computer", "keyboard", "iphone", "phone", "battery", "bulb", "wrench", "hammer", "gear", "link",
            "lock", "unlock", "key", "bell", "mag", "book", "books", "notebook", "memo", "pencil2", "paperclip",
            "pushpin", "scissors", "file_folder", "page_facing_up", "calendar", "date", "clipboard",
            "chart_with_upwards_trend", "chart_with_downwards_trend", "bar_chart", "email", "package",
            "moneybag", "gem", "hourglass", "alarm_clock", "camera", "headphones", "gift",
        ]),
        ("自然", "Nature", [
            "sunny", "cloud", "umbrella", "snowflake", "zap", "droplet", "ocean", "rainbow", "crescent_moon",
            "rose", "sunflower", "cherry_blossom", "seedling", "deciduous_tree", "four_leaf_clover", "maple_leaf",
            "cat", "dog", "rabbit", "fox_face", "bear", "panda_face", "unicorn", "bee", "bug", "butterfly",
            "turtle", "whale",
        ]),
        ("食物", "Food", [
            "apple", "banana", "grapes", "watermelon", "strawberry", "peach", "lemon", "avocado", "bread",
            "cheese", "egg", "hamburger", "fries", "pizza", "ramen", "sushi", "rice", "dumpling", "icecream",
            "cake", "birthday", "cookie", "coffee", "tea", "beer", "wine_glass",
        ]),
        ("活動與旅行", "Activities & Travel", [
            "tada", "confetti_ball", "balloon", "christmas_tree", "trophy", "1st_place_medal", "soccer",
            "basketball", "video_game", "dart", "art", "musical_note", "microphone", "guitar", "house", "office",
            "school", "car", "bus", "train", "bike", "airplane", "rocket", "ship", "construction",
            "checkered_flag", "triangular_flag_on_post",
        ]),
    ]

    private static let recentKey = "menunote.recentEmoji"
    private static let recentCount = 10

    /// Shortcodes inserted lately, newest first.
    private static var recent: [String] {
        get { (UserDefaults.standard.stringArray(forKey: recentKey) ?? []).filter { HackMD.emoji[$0] != nil } }
        set { UserDefaults.standard.set(Array(newValue.prefix(recentCount)), forKey: recentKey) }
    }

    /// What a chosen item inserts, kept in its `representedObject`.
    struct Choice {
        let name: String
        let text: String
    }

    /// Notes that `name` was used, so it comes first next time.
    static func used(_ name: String) {
        recent = [name] + recent.filter { $0 != name }
    }

    /// The menu's items; each sends `action` to `target` with a `Choice`. `palette` opens the
    /// system's full emoji picker.
    static func items(target: AnyObject, action: Selector, palette: Selector) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let recent = recent
        if !recent.isEmpty {
            items.append(header(tr("最近使用", "Recently Used")))
            for name in recent { items += pair(name, target: target, action: action) }
            items.append(.separator())
        }
        for category in categories {
            let menu = NSMenu()
            for name in category.names { pair(name, target: target, action: action).forEach(menu.addItem) }
            let item = NSMenuItem(title: tr(category.zh, category.en), action: nil, keyEquivalent: "")
            item.submenu = menu
            items.append(item)
        }
        items.append(.separator())
        items.append(header(tr("按住 ⌥ 插入 emoji 本身，而不是代碼", "Hold ⌥ to insert the emoji itself, not its code")))
        let more = NSMenuItem(title: tr("顯示所有 Emoji 與符號…", "Show All Emoji & Symbols…"), action: palette, keyEquivalent: "")
        more.target = target
        items.append(more)
        return items
    }

    private static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// An item inserting the shortcode, and its ⌥ alternate inserting the emoji.
    private static func pair(_ name: String, target: AnyObject, action: Selector) -> [NSMenuItem] {
        guard let emoji = HackMD.emoji[name] else { return [] }
        let code = NSMenuItem(title: "\(emoji)  :\(name):", action: action, keyEquivalent: "")
        code.representedObject = Choice(name: name, text: ":\(name):")
        let character = NSMenuItem(title: "\(emoji)  " + tr("插入 \(emoji)", "Insert \(emoji)"), action: action, keyEquivalent: "")
        character.representedObject = Choice(name: name, text: emoji)
        character.keyEquivalentModifierMask = .option
        character.isAlternate = true
        for item in [code, character] { item.target = target }
        return [code, character]
    }
}

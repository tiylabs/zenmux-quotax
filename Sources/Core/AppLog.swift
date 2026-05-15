import OSLog

public enum AppLog {
    private static let subsystem = "com.zenmux.quotax"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let refresh = Logger(subsystem: subsystem, category: "refresh")
    public static let decode = Logger(subsystem: subsystem, category: "decode")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
}

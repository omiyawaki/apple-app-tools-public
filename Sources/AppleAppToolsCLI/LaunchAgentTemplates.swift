import Foundation

enum LaunchAgentTemplates {
    static func listenPlist(label: String, toolPath: String, bindAddress: String, port: Int, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(toolPath)</string>
            <string>auto-deploy</string>
            <string>serve</string>
            <string>--bind</string>
            <string>\(bindAddress)</string>
            <string>--port</string>
            <string>\(port)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>ThrottleInterval</key>
          <integer>10</integer>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    static func catchUpPlist(label: String, toolPath: String, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(toolPath)</string>
            <string>auto-deploy</string>
            <string>catch-up</string>
          </array>
          <key>LaunchEvents</key>
          <dict>
            <key>com.apple.notifyd.matching</key>
            <dict>
              <key>com.apple.system.config.network_change</key>
              <dict>
                <key>Notification</key>
                <string>com.apple.system.config.network_change</string>
              </dict>
            </dict>
          </dict>
          <key>ThrottleInterval</key>
          <integer>300</integer>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    static func dailyPlist(label: String, toolPath: String, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(toolPath)</string>
            <string>auto-deploy</string>
            <string>catch-up</string>
          </array>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Hour</key>
            <integer>4</integer>
            <key>Minute</key>
            <integer>0</integer>
          </dict>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }
}

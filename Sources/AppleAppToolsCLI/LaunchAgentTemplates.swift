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
          </array>
          <key>Sockets</key>
          <dict>
            <key>Listener</key>
            <dict>
              <key>SockNodeName</key>
              <string>\(bindAddress)</string>
              <key>SockServiceName</key>
              <string>\(port)</string>
              <key>SockType</key>
              <string>stream</string>
            </dict>
          </dict>
          <key>inetdCompatibility</key>
          <dict>
            <key>Wait</key>
            <false/>
          </dict>
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
            <key>com.apple.iokit.matching</key>
            <dict>
              <key>com.apple.iokit.power-state</key>
              <dict>
                <key>IOMatchLaunchStream</key>
                <true/>
                <key>IOProviderClass</key>
                <string>IOPMrootDomain</string>
              </dict>
            </dict>
          </dict>
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

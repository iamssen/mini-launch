on run arguments
    with timeout of 30 seconds
        tell application id "com.googlecode.iterm2"
            set commandWindow to create window with default profile
            tell current session of commandWindow to write text (item 1 of arguments)
            activate
        end tell
    end timeout
end run

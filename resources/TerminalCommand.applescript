on run arguments
    with timeout of 30 seconds
        tell application id "com.apple.Terminal"
            do script (item 1 of arguments)
            activate
        end tell
    end timeout
end run

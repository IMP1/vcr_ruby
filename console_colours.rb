module ConsoleColour

    RESET = "\033[0m"

    def self.bold(text)
        return "\33[1m" + text + "\33[22m"
    end

    def self.black(text)
        return "\u001b[30m" + text + RESET
    end

    def self.red(text)
        return "\u001b[31m" + text + RESET
    end

    def self.green(text)
        return "\u001b[32m" + text + RESET
    end

    def self.yellow(text)
        return "\u001b[33m" + text + RESET
    end

    def self.blue(text)
        return "\u001b[34m" + text + RESET
    end

    def self.magenta(text)
        return "\u001b[35m" + text + RESET
    end

    def self.cyan(text)
        return "\u001b[36m" + text + RESET
    end

    def self.white(text)
        return "\u001b[37m" + text + RESET
    end

    def self.default(text)
        return "\u001b[39m" + text + RESET
    end
    
end
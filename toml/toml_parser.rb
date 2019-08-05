# TOML Spec
# https://github.com/toml-lang/toml#user-content-spec

module Toml

    def self.load(filename)
        parse(File.read(filename))
    end

    def self.parse(text)
        parser = TomlParser.new(text)
        ruby_obj = parser.parse
        return ruby_obj
    end

    def self.dump(table)

    end

end

class TomlParser

    IDENTIFIER_REGEX = /[A-Za-z0-9_\-]/
    
    def initialize(string, filename="")
        @filename = filename
        @source   = string
        @root     = {}
        @start    = 0
        @current  = 0
        @line     = 1
        @column   = 1
    end

    def eof?
        return @current >= @source.length
    end

    def newline
        @line += 1
        @column = 1
    end

    def advance
        @current += 1
        @column  += 1
        return @source[@current - 1]
    end

    def check(regex)
        return @source[@current..-1].start_with?(regex)
    end

    def consume(expected)
        return advance if check(expected)
        raise "Invalid TOML. Expected '#{expected}', but got '#{peek}'."
    end

    def consume_whitespace
        while check(/\s\r\t/)
            advance
        end
    end

    def advance_if(expected)
        return false if eof?
        return false if @source[@current] != expected

        advance
        return true
    end

    def previous
        return @source[@current - 1]
    end

    def peek
        return nil if eof?
        return @source[@current]
    end

    def peek_next
        return nil if @current >= @source.length
        return nil if @current + 1 >= @source.length
        return @source[@current + 1]
    end

    def parse(block)
        thread = Thread.start do 
            parse_toml
        end
        thread.join if block
    end

    def parse_toml
        consume_whitespace
        while !eof?
            key = []
            loop do
                key.push(parse_key)
                consume_whitespace
                break if peek != "."
                advance # consume '.'
                consume_whitespace
            end
            value = parse_value
            if @root[key]
                raise "Invalid TOML. '#{key}' is reassigned."
            end
            @root[key] = value
        end
    end

    def parse_key
        c = advance
        case c
        when "\""
            basic_string
        when "'"
            literal_string
        when IDENTIFIER_REGEX
            identifier
        when "["
            if peek == "["
                table_array_name
            else
                table_name
            end
        else
            raise "Invalid TOML. '#{key}' is not a valid key."
        end
    end

    def parse_value
        c = advance
        case c

        # Strings
        when "\""
            if check(/""/)
                multiline_basic_string
            else
                basic_string
            end

        when "'"
            if check(/""/)
                multiline_literal_string
            else
                literal_string
            end

        # Numerics (integers, floats, dates)
        when "0"
            if peek == "x"
                advance
                integer(16)
            elsif peek == "o"
                advance
                integer(8)
            elsif peek == "b"
                advance
                integer(2)
            else
                number
            end

        when /[\d\+\-]/
            number

        when "t"
            if check("rue")
                true
            else

        when "f"
            if check("alse")
                false
            else

        # Arrays
        when "["
            array

        # Inline Tables
        when "{" 
            inline_table

        else
            if 

        end
    end

    def basic_string
        # TODO: escape certain characters
        while !eof? && !(peek == "\"" && previous != "\\")
            newline if peek == "\n"
            advance
        end

        if eof?
            report_error("Invalid TOML. Unterminated string, starting on line #{@line}.")
            return
        end
        
        advance # The closing ".

        # Trim the surrounding quotes.
        value = @source[@start + 1...@current - 1]
        return value
    end

    def literal_string
        # TODO: don't escape any characters
        while !eof? && !(peek == "'" && previous != "\\")
            newline if peek == "\n"
            advance
        end

        if eof?
            report_error("Invalid TOML. Unterminated string, starting on line #{@line}.")
            return
        end
        
        advance # The closing ".

        # Trim the surrounding quotes.
        value = @source[@start + 1...@current - 1]
        return value
    end

    def multiline_basic_string
    end

    def multiline_literal_string
    end

    def integer(base=10)

    end

    def number
        # could be integer
        # could be float
        # could be date
    end

    def table_name

    end

    def table_array_name

    end

    def identifier
        advance while peek =~ IDENTIFIER_REGEX

        return @source[@start...@current]
    end

end
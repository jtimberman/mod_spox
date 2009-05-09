require 'mod_spox/handlers/Handler'
module ModSpox
    module Handlers
        class Ping < Handler
            def initialize(handlers)
                handlers[:PING] = self
            end
            def process(string)
                orig = string.dup
                begin
                    string.slice!(0) if string[0] == ':'
                    server = string[0..string.index(' ')-1]
                    message = string[string.index(':')+1..string.size]
                    server = message.dup if server == 'PING'
                    return Messages::Incoming::Ping.new(orig, server, message)
                rescue Object
                    Logger.error("Failed to parse PING message: #{string}")
                end
            end
        end
    end
end
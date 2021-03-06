require 'mod_spox/handlers/Handler'
require 'mod_spox/messages/incoming/Pong'
module ModSpox
    module Handlers
        class Pong < Handler
            def initialize(handlers)
                handlers[:PONG] = self
            end
            def process(string)
                orig = string.dup
                string = string.dup
                begin
                    a = string.slice!(string.rindex(':')+1, string.size)
                    string.slice!(-2..string.size)
                    return Messages::Incoming::Pong.new(orig, string.slice(string.rindex(' ')+1..string.size), a)
                rescue Object => boom
                    Logger.error("Failed to parse PONG message: #{orig}")
                    raise Exceptions::GeneralException.new(boom)
                end
            end
        end
    end
end
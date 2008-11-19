require 'mod_spox/handlers/Handler'
module ModSpox
    module Handlers
        class LuserOp < Handler
            def initialize(handlers)
                handlers[RPL_LUSEROP] = self
            end
            def process(string)
                if(string =~ /(\d+) :.*?\s*[oO]perators/)
                    return Messages::Incoming::LuserOp.new(string, $1.to_i)
                else
                    Logger.warn('Failed to match RPL_LUSEROP message')
                    return nil
                end
            end
        end
    end
end
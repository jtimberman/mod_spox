module ModSpox
    module Models
        # Attributes provided by model:
        # trigger:: trigger to match
        # active:: trigger is active
        class Trigger < Sequel::Model(:triggers)
        end
    end
end
module ModSpox
    module Migrators
        class CreateNickModes < Sequel::Migration
            def up
                Models::NickMode.create_table unless Models::NickMode.table_exists?
            end
            
            def down
                Models::NickMode.drop_table if Models::NickMode.table_exists?
            end
        end
    end
end
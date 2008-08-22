module ModSpox
    module Migrators
        class CreateConfigs < Sequel::Migration
            def up
                Models::Config.create_table unless Models::Config.table_exists?
            end
            
            def down
                Models::Config.drop_table if Models::Config.table_exists?
            end
        end
    end
end
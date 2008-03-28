module ModSpox
    module Migrators
        class CreateChannelModes < Sequel::Migration
            def up
                Models::ChannelMode.create_table unless Models::ChannelMode.table_exists?
            end
            
            def down
                Models::ChannelMode.drop_table
            end
        end
    end
end
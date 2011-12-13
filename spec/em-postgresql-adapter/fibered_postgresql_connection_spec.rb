require 'spec_helper'

describe EM::DB::FiberedPostgresConnection, 'plain integration into active_record' do

  before :each do
    ActiveRecord::Base.establish_connection(database_connection_config)
  end

  it "is a sane database.yml file" do
    database_connection_config['adapter'].should == 'em_postgresql'
  end

  it "uses an identifiable driver" do
    ActiveRecord::Base.connection.should be_instance_of(ActiveRecord::ConnectionAdapters::EMPostgreSQLAdapter)
  end

  it "can connect outside of eventmachine" do
    result = ActiveRecord::Base.connection.execute('select 42')
    result.values.should == [['42']]
  end

end

$LOAD_PATH << File.expand_path(File.dirname(__FILE__) + "/../../lib")
$LOAD_PATH << File.expand_path(File.dirname(__FILE__) + "/..")

require 'neo4j'
require 'spec'

require 'spec/interop/test'
require 'sinatra/test'

# TODO refactor, duplicated code in spec_helper

require 'fileutils'
require 'tmpdir'

# suppress all warnings
$NEO_LOGGER.level = Logger::ERROR
NEO_STORAGE = Dir::tmpdir + "/neo_storage"
LUCENE_INDEX_LOCATION = Dir::tmpdir + "/lucene"
Lucene::Config[:storage_path] = LUCENE_INDEX_LOCATION
Lucene::Config[:store_on_file] = false
Neo4j::Config[:storage_path] = NEO_STORAGE


Sinatra::Application.set :environment, :test

class Person
  include Neo4j::NodeMixin
  # by includeing the following mixin we will expose this node as a RESTful resource
  include RestMixin
  property :name
  has_n :friends
end

describe 'Restful' do
  include Sinatra::Test

  after(:each) do
    Neo4j.stop
    FileUtils.rm_rf Neo4j::Config[:storage_path]  # NEO_STORAGE
    FileUtils.rm_rf Lucene::Config[:storage_path] unless Lucene::Config[:storage_path].nil?
  end

  it "should know the URI of a Person instance" do
    person = Person.new
    port = Sinatra::Application.port # we do not know it since we have not started it - mocked
    person._uri.should == "http://0.0.0.0:#{port}/Person/#{person.neo_node_id}"
  end

  it "should be possible to traverse a relationship on GET /Person/<id>/traverse?relation=friends&depth=1" do
    adam = Person.new
    adam.name = 'adam'

    bertil = Person.new
    bertil.name = 'bertil'

    carl = Person.new

    adam.friends << bertil << carl

    # when
    get "/Person/#{adam.neo_node_id}/traverse?relation=friends&depth=1"

    # then
    status.should == 200
    body = JSON.parse(response.body)
    body['uri_list'].should_not be_nil
    body['uri_list'][0].should == 'http://0.0.0.0:4567/Person/2'
    body['uri_list'][1].should == 'http://0.0.0.0:4567/Person/3'
    body['uri_list'].size.should == 2
  end
  
  it "should create a relationship on POST /Person/friends" do
    adam = Person.new
    adam.name = 'adam'

    bertil = Person.new
    bertil.name = 'bertil'


    # when
    post "/Person/#{adam.neo_node_id}/friends", { :uri => bertil._uri }.to_json

    # then
    status.should == 201
    response.location.should == "/Relations/2"
    adam.friends.should include(bertil)
  end

  it "should be possible to load a relationship on GET /Relations/<id>" do
    adam = Person.new
    bertil = Person.new
    rel = adam.friends.new(bertil)
    rel.foo = "bar"
    # when
    get "/Relations/#{rel.neo_relation_id}"

    # then
    status.should == 200
    body = JSON.parse(response.body)
    body['foo'].should == 'bar'
  end


  it "should create a new Person on POST /Person" do
    data = { :name => 'kalle'}

    # when
    post '/Person', data.to_json

    # then
    status.should == 201
    response.location.should == "/Person/1"
  end

  it "should be possible to follow the location HTTP header when creating a new Person" do
    data = { :name => 'kalle'}

    # when
    post '/Person', data.to_json
    follow!

    # then
    status.should == 200
    body = JSON.parse(response.body)
    body['name'].should == 'kalle'
  end

  it "should find a Person on GET /Person/neo_node_id" do
    # given
    p = Person.new
    p.name = 'sune'

    # when
    get "/Person/#{p.neo_node_id}"

    # then
    status.should == 200
    data = JSON.parse(response.body)
    data.should include("name")
    data['name'].should == 'sune'
  end

  it "should return a 404 if it can't find the node" do
    get "/Person/742421"

    # then
    status.should == 404
  end

  it "should be possible to get a property on GET /Person/[node_id]/[property_name]" do
    # given
    p = Person.new
    p.name = 'sune123'

    # when
    get "/Person/#{p.neo_node_id}/name"

    # then
    status.should == 200
    data = JSON.parse(response.body)
    data['name'].should == 'sune123'
  end

  it "should be possible to set a property on PUT /Person/[node_id]/[property_name]" do
    # given
    p = Person.new
    p.name = 'sune123'

    # when
    data = { :name => 'new-name'}
    put "/Person/#{p.neo_node_id}/name", data.to_json

    # then
    status.should == 200
    p.name.should == 'new-name'
  end

end
libdir = File.dirname(__FILE__)+'/../lib'
$LOAD_PATH.unshift libdir unless $LOAD_PATH.include?(libdir)
require 'sinatra/async'
require 'rack/test'
require 'spec/interop/test'
require 'rack/async2sync'
Test::Unit::TestCase.send :include, Rack::Test::Methods

Spec::Runner.configure do |config|
  
end

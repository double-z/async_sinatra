require File.dirname(__FILE__)+'/spec_helper'
require 'em-http'

def server(base=Sinatra::Base, &block)
  Rack::Async2Sync.new Sinatra.new(base, &block)
end

def app
  @app
end


describe "Asynchronous routes" do
  it "should still work as usual" do
    @app = server do
      register Sinatra::Async
      disable :raise_errors, :show_exceptions

      aget '/' do
        body "hello async"
      end      
    end
    get '/'
    last_response.status.should == 200
    last_response.body.should == "hello async"
  end
  
  it "should correctly deal with raised exceptions" do
    @app = server do
      register Sinatra::Async
      disable :raise_errors, :show_exceptions
      aget '/' do
        raise "boom"
        body "hello async"
      end
      error Exception do
        e = request.env['sinatra.error']
        "problem: #{e.class.name} #{e.message}"
      end
    end
    get '/'
    last_response.status.should == 500
    last_response.body.should == "problem: RuntimeError boom"
  end
  
  it "should correctly deal with halts" do
    @app = server do
      register Sinatra::Async
      disable :raise_errors, :show_exceptions
      aget '/' do
        halt 406, "Format not supported"
        body "never called"
      end
    end

    get '/'
    last_response.status.should == 406
    last_response.body.should == "Format not supported"
  end
  
  it "should correctly deal with halts and pass it to the defined error blocks if any" do
    @app = server do
      register Sinatra::Async
      disable :raise_errors, :show_exceptions
      aget '/' do
        halt 406, "Format not supported"
        body "never called"
      end
      error 406 do
        response['Content-Type'] = "text/plain"
        "problem: #{response.body.to_s}"
      end
    end
    get '/'
    last_response.status.should == 406
    last_response.headers['Content-Type'].should == "text/plain"
    last_response.body.should == "problem: Format not supported"
  end
  
  describe "using EM libraries inside route block" do
    it "should still work as usual" do
      @app = server do
        register Sinatra::Async
        disable :raise_errors, :show_exceptions
        aget '/' do
          url = "http://ruby.activeventure.com/programmingruby/book/tut_exceptions.html"
          http = EM::HttpRequest.new(url).get
          http.callback {
            status http.response_header.status
            body "ok"
          }
          http.errback {
            body "nok"
          }
        end
      end
      get '/'
      last_response.status.should == 200
      last_response.body.should == "ok"
    end

    it "should correctly deal with exceptions raised from within EM callbacks" do
      @app = server do
        register Sinatra::Async
        disable :raise_errors, :show_exceptions
        aget '/' do
          url = "http://doesnotexist.local/whatever"
          http = EM::HttpRequest.new(url).get
          http.callback {
            status http.response_header.status
            body "ok"
          }
          http.errback {
            raise "boom"
          }
        end
        error Exception do
          e = request.env['sinatra.error']
          "#{e.class.name}: #{e.message}"
        end
      end
      get '/'
      last_response.status.should == 500
      last_response.body.should == "RuntimeError: boom"
    end

    it "should correctly deal with halts thrown from within EM callbacks" do
      @app = server do
        register Sinatra::Async
        disable :raise_errors, :show_exceptions
        aget '/' do
          url = "http://doesnotexist.local/whatever"
          http = EM::HttpRequest.new(url).get
          http.callback {
            status http.response_header.status
            body "ok"
          }
          http.errback {
            halt 503, "error: #{http.errors.inspect}"
          }
        end
        error 503 do
          "503: #{response.body.to_s}"
        end
      end
      get '/'
      last_response.status.should == 503
      last_response.body.should == "503: error: \"unable to resolve server address\""
    end
  end
end

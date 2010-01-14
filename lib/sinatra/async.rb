require 'sinatra/base'

module Sinatra #:nodoc:

  # Normally Sinatra expects that the completion of a request is # determined
  # by the block exiting, and returning a value for the body.
  #
  # In an async environment, we want to tell the webserver that we're not going
  # to provide a response now, but some time in the future.
  #
  # The a* methods provide a method for doing this, by informing the server of
  # our asynchronous intent, and then scheduling our action code (your block)
  # as the next thing to be invoked by the server.
  #
  # This code can then do a number of things, including waiting (asynchronously)
  # for external servers, services, and whatnot to complete. When ready to send
  # the real response, simply setup your environment as you normally would for 
  # sinatra (using #content_type, #headers, etc). Finally, you complete your
  # response body by calling the #body method. This will push your body into the
  # response object, and call out to the server to actually send that data.
  #
  # == Example
  #  require 'sinatra/async'
  #  
  #  class AsyncTest < Sinatra::Base
  #    register Sinatra::Async
  #  
  #    aget '/' do
  #      body "hello async"
  #    end
  #  
  #    aget '/delay/:n' do |n|
  #      EM.add_timer(n.to_i) { body { "delayed for #{n} seconds" } }
  #    end
  #  
  #  end
  module Async
    # Similar to Sinatra::Base#get, but the block will be scheduled to run
    # during the next tick of the EventMachine reactor. In the meantime,
    # Thin will hold onto the client connection, awaiting a call to 
    # Async#body with the response.
    def aget(path, opts={}, &block)
      conditions = @conditions.dup
      aroute('GET', path, opts, &block)

      @conditions = conditions
      aroute('HEAD', path, opts, &block)
    end

    # See #aget.
    def aput(path, opts={}, &bk); aroute 'PUT', path, opts, &bk; end
    # See #aget.
    def apost(path, opts={}, &bk); aroute 'POST', path, opts, &bk; end
    # See #aget.
    def adelete(path, opts={}, &bk); aroute 'DELETE', path, opts, &bk; end
    # See #aget.
    def ahead(path, opts={}, &bk); aroute 'HEAD', path, opts, &bk; end

    private
    def aroute(verb, path, opts = {}, &block) #:nodoc:
      route(verb, path, opts) do |*bargs|
        method = "A#{verb} #{path}".to_sym

        mc = class << self; self; end
        mc.send :define_method, method, &block
        mc.send :alias_method, :__async_callback, method

        EM.next_tick {
          begin
            res = catch(:halt) do
              send(:__async_callback, *bargs)
              nil
            end
            # res is non-nil (contains a rack-esque array or string) only if a :halt is thrown
            handle_failure(res) unless res.nil?
          rescue ::Exception => boom
            if options.show_exceptions?
              # HACK: handle_exception! re-raises the exception if show_exceptions?,
              # so we ignore any errors and instead create a ShowExceptions page manually
              handle_exception!(boom) rescue nil
              s, h, b = Sinatra::ShowExceptions.new(proc{ raise boom }).call(request.env)
              response.status = s
              response.headers.replace(h)
              body(b)
            else
              body(handle_exception!(boom))
            end
          end
        }

        throw :async      
      end
    end

    module Helpers
      # Send the given body or block as the final response to the asynchronous 
      # request.
      def body(*args, &blk)
        super
        request.env['async.callback'][
          [response.status, response.headers, response.body]
        ] if respond_to?(:__async_callback)
      end
      
      # taken from Sinatra::Base#invoke, cannot reuse the existing <tt>#invoke</tt> method since it contains a <tt>return</tt> clause.
      def handle_failure(res)
        case
        when res.respond_to?(:to_str)
          @response.body = [res]
        when res.respond_to?(:to_ary)
          res = res.to_ary
          if Fixnum === res.first
            if res.length == 3
              @response.status, headers, body = res
              @response.body = body if body
              headers.each { |k, v| @response.headers[k] = v } if headers
            elsif res.length == 2
              @response.status = res.first
              @response.body   = res.last
            else
              raise TypeError, "#{res.inspect} not supported"
            end
          else
            @response.body = res
          end
        when res.respond_to?(:each)
          @response.body = res
        when (100...599) === res
          @response.status = res
        end

        if (new_body = error_block!(@response.status))
          @response.body = new_body
        end
        body @response.body
      end
    end

    def self.registered(app) #:nodoc:
      app.helpers Helpers
    end
  end
end
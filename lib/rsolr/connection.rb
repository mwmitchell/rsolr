require 'net/http'
require 'net/https'

# The default/Net::Http adapter for RSolr.
class RSolr::Connection
  
  # using the request_context hash,
  # send a request,
  # then return the standard rsolr response hash {:status, :body, :headers}
  def execute client, request_context
    http_request = http(request_context[:uri], request_context[:proxy])
    request      = setup_raw_request(request_context)
    request.body = request_context[:data] if request_context[:method] == :post and request_context[:data]

    begin
      response = http_request.request(request)

      { :status => response.code.to_i, :headers => response.to_hash, :body => response.body }
    rescue Exception => e # catch the undefined closed? exception -- this is a confirmed ruby bug
      if client.raise_connection_exceptions
        if e.message == "undefined method `closed?' for nil:NilClass"
          raise(e)
        else
          raise(Errno::ECONNREFUSED.new)
        end
      end

      stubbed_empty_response
    end
  end
  
  def self.valid_methods
    [:get, :post, :head]
  end

  protected
  
  def stubbed_empty_response
    { :status => 500, :headers => {}, :body => "{'response'=>{'start'=>0, 'docs'=>[], 'numFound'=>0}, 'responseHeader'=>{'QTime'=>0, 'params'=>{'facet'=>'true', 'q'=>'', 'wt'=>'ruby', 'rows'=>'0'}, 'status'=>0}, 'facet_counts'=>{'facet_fields'=>{'section'=>[]}, 'facet_dates'=>{}, 'facet_queries'=>{}}}" }
  end

  # This returns a singleton of a Net::HTTP or Net::HTTP.Proxy request object.
  def http uri, proxy = nil
    @http ||= (
      http = if proxy
        proxy_user, proxy_pass = proxy.userinfo.split(/:/) if proxy.userinfo
        Net::HTTP.Proxy(proxy.host, proxy.port, proxy_user, proxy_pass).new uri.host, uri.port
      else
        Net::HTTP.new uri.host, uri.port
      end
      http.use_ssl = uri.port == 443 || uri.instance_of?(URI::HTTPS)      
      http
    )
  end
  
  # 
  def setup_raw_request request_context
    http_method = case request_context[:method]
    when :get
      Net::HTTP::Get
    when :post
      #require 'net/http/post/multipart'
      #File === request_context[:data] ? Net::HTTP::Post::Multipart : Net::HTTP::Post
      Net::HTTP::Post
    when :head
      Net::HTTP::Head
    else
      raise "Only :get, :post and :head http method types are allowed."
    end
    headers = request_context[:headers] || {}
    # if http_method.to_s == "Net::HTTP::Post::Multipart"
    #   io = request_context[:data]
    #   UploadIO.convert! io, request_context[:headers]["Content-Type"], io.path, io.path
    #   raw_request =
    #     Net::HTTP::Post::Multipart.new(
    #       request_context[:path],
    #       :file => io)
    # else
      raw_request = http_method.new request_context[:uri].to_s
    # end
    raw_request.initialize_http_header headers
    raw_request
  end
  
end
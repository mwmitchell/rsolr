require 'net/http'
require 'net/https'

# The default/Net::Http adapter for RSolr.
class RSolr::Connection

  # using the request_context hash,
  # send a request,
  # then return the standard rsolr response hash {:status, :body, :headers}
  def execute client, request_context
    h = http request_context[:uri], request_context[:proxy], request_context[:read_timeout], request_context[:open_timeout]
    request = setup_raw_request request_context
    request.body = request_context[:data] if request_context[:method] == :post and request_context[:data]
    begin
      response = h.request request

      { :status => response.code.to_i,
        :headers => response.to_hash,
        :body => force_charset(response.body, response.type_params["charset"]) }
    rescue Errno::ECONNREFUSED
      self.retry(RSolr::Error::ConnectionRefused, client, request_context)
    rescue Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout => e
      self.retry(e, client, request_context)
    # catch the undefined closed? exception -- this is a confirmed ruby bug
    rescue NoMethodError => e
      e.message == "undefined method `closed?' for nil:NilClass" ?
        self.retry(RSolr::Error::ConnectionRefused, client, request_context) :
        raise(e)
    end
  end

  protected

  # This returns a singleton of a Net::HTTP or Net::HTTP.Proxy request object.
  def http(uri, proxy = nil, read_timeout = nil, open_timeout = nil)
    if @http and (@http.address != uri.host or @http.port != uri.port)
      @http = nil
    end

    @http ||= begin
      http = if proxy
        proxy_user, proxy_pass = proxy.userinfo && proxy.userinfo.split(/:/)
        Net::HTTP.Proxy(proxy.host, proxy.port, proxy_user, proxy_pass).new uri.host, uri.port
      elsif proxy == false
        # If explicitly passing in false, make sure we set proxy_addr to nil
        # to tell Net::HTTP to *not* use the environment proxy variables.
        Net::HTTP.new uri.host, uri.port, nil
      else
        Net::HTTP.new uri.host, uri.port
      end
      http.use_ssl = uri.port == 443 || uri.instance_of?(URI::HTTPS)
      http.read_timeout = read_timeout if read_timeout
      http.open_timeout = open_timeout if open_timeout
      http
    end
  end

  #
  def setup_raw_request request_context
    http_method = case request_context[:method]
    when :get
      Net::HTTP::Get
    when :post
      Net::HTTP::Post
    when :head
      Net::HTTP::Head
    else
      raise "Only :get, :post and :head http method types are allowed."
    end
    headers = request_context[:headers] || {}
    raw_request = http_method.new request_context[:uri].request_uri
    raw_request.initialize_http_header headers
    raw_request.basic_auth(request_context[:uri].user, request_context[:uri].password) if request_context[:uri].user && request_context[:uri].password
    raw_request
  end

  def retry(e, client, request_context)
    unless client.try_another_node?(request_context)
      raise(e, request_context.inspect)
    end

    execute(client, request_context)
  end

  private

  def force_charset body, charset
    return body unless charset and body.respond_to?(:force_encoding)
    body.force_encoding(charset)
  end

end

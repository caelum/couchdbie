require 'simple_couch'
require 'rubygems'
require 'ruby_debug'
require 'sinatra'
require 'json'
require 'rack/conneg'
require 'activesupport'

use(Rack::Conneg) do |conneg|
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.provide([:xml, :json, :html])
end

before do
  content_type negotiated_type
end

get "/:db/:uri" do
  db = params[:db]
  uri = params[:uri]
  server = Couch::Server.new("localhost", "5984")
  links = []
  rev = params[:rev]
  
  # supporting RFC-5829
  unless rev
    JSON.parse(server.get("/#{db}/#{uri}?revs_info=true").body)["_revs_info"].each do |r|
      puts "found #{r['rev']}"
      links << {:href => "http://localhost:5984/#{db}/#{uri}?rev=#{r['rev']}", :rel => "revision"}
    end
  end

  grab = "/#{db}/#{uri}"
  grab << "?rev=#{rev}" if rev
  res = server.get(grab)
  response = JSON.parse(res.body)
  response.keys.each do |k|
    new_uri = URI.escape(response[k])
    temp = Net::HTTP.start("localhost", "5984") { |http|http.request(Net::HTTP::Get.new("/#{db}/#{new_uri}")) }
    found = temp.code=="200"
    if found
      if k=="_id"
        links << {:href => "http://localhost:5984/#{db}/#{new_uri}", :rel => "self"}
      else
        links << {:href => "http://localhost:5984/#{db}/#{new_uri}", :rel => k}
      end
    end
  end
  response["links"] = links
  # http://localhost:5984/foo/_design/application/_view/docs
  
  link_header = ""
  links.each do |l|
    link_header << "," unless link_header.empty?
    link_header << "<#{l[:href]}>; rel=\"#{l[:rel]}\""
  end

  # r = Rack::Response.new(content, 200)
  # r.header["Content-type"] = "text/plain"
  # r.header["Content-type"] = "application/json"
  respond_to do |wants|
    wants.html {
      r = Rack::Response.new(response.to_s, 200)
      r.header["Link"] = link_header
      r.finish
    }
    wants.json {
      r = Rack::Response.new(response.to_json, 200)
      r.header["Link"] = link_header
      r.finish
    }
    wants.xml {
      r = Rack::Response.new(response.to_xml, 200)
      r.header["Link"] = link_header
      r.finish
    }
  end

end
